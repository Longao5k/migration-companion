"""把南澳官方新闻的历史条目一次性补进待审队列。

日常发现只看列表页第一屏，而且有条数上限——它的职责是「今天有没有新东西」，
不是「把过去两年补齐」。回填是另一件事，所以单独一个入口，手动跑，不进定时任务。

**能回溯到哪里，是站点决定的，不是我们决定的：**

- `/news` 列表页只给 18 条，最早 2025-10 月。`?page=2` 参数被忽略，返回同一批。
- 但**分类视图会露出更老的条目**：`?category=other-news` 能回到 2024-07。
  三个视图取并集是目前能拿到的最全的一份（实测 31 篇，2024-07 → 2026-07）。
- `sitemap.xml` 里有 43 篇，比并集多 12 篇，但多出来的全是活动与招聘推广
  （Careers Made in SA、Welcome to SA 之类），不是政策，且 sitemap 的 `lastmod`
  是 CMS 记录改动时间不是发布时间，拿不到真实日期。所以走列表而不是 sitemap。

回填出来的全部是**草稿**，`titleZh`/`summaryZh` 需要人工写中文编辑稿之后才能发布。
这条人工闸门是冻结规则，回填不绕过它。
"""

import time
from dataclasses import replace

from .api import submit_news_draft
from .fetcher import ConditionalHeaders, OfficialFetcher
from .models import DiscoveredNews, Source
from .news_discovery import discover_sa_news, extract_article_excerpt

# 同一个列表，三种筛选。分类视图会露出主列表上没有的旧条目。
SA_NEWS_VIEWS = (
    "https://migration.sa.gov.au/news",
    "https://migration.sa.gov.au/news?category=other-news",
    "https://migration.sa.gov.au/news?category=invitations-issued",
)

# 正文太短的多半是活动通知或跳转页，没有可摘要的内容。
MIN_EXCERPT_CHARS = 40


def collect_sa_news_archive(
    source: Source, fetcher: OfficialFetcher
) -> list[DiscoveredNews]:
    """把三个列表视图合并成一份去重、按时间升序的历史条目。

    `discover_sa_news` 的 limit 在这里给一个大数：列表页本身只有几十条，
    真正的上限是站点给多少。
    """
    merged: dict[str, DiscoveredNews] = {}
    for view in SA_NEWS_VIEWS:
        listing_source = replace(source, url=view, discovery_url=None)
        listing = fetcher.fetch(listing_source, ConditionalHeaders())
        for item in discover_sa_news(listing.body, limit=500):
            merged.setdefault(item.url, item)
    return sorted(merged.values(), key=lambda item: item.published_at)


def backfill_sa_news(
    source: Source,
    fetcher: OfficialFetcher,
    api_url: str,
    worker_key: str,
    *,
    dry_run: bool = False,
    delay_seconds: float = 2.0,
) -> list[tuple[str, str, str]]:
    """逐篇取正文摘录并提交草稿。返回 (日期, 标题, 结果) 便于核对。

    每篇之间留间隔。一次补两年的量是几十个请求，对方站点没有声明 Crawl-delay，
    但连续打几十下不合适——`OfficialFetcher` 本身已按主机节流，这里再留一道。
    """
    archive = collect_sa_news_archive(source, fetcher)
    results: list[tuple[str, str, str]] = []

    for index, item in enumerate(archive):
        if index:
            time.sleep(delay_seconds)
        article_source = replace(source, url=item.url, discovery_url=None)
        try:
            article = fetcher.fetch(article_source, ConditionalHeaders())
        except Exception as exc:  # noqa: BLE001
            results.append((item.published_at[:10], item.title, f"取不到：{exc}"))
            continue

        excerpt = extract_article_excerpt(article.body, item.title)
        if len(excerpt) < MIN_EXCERPT_CHARS:
            results.append((item.published_at[:10], item.title, "正文过短，跳过"))
            continue

        complete = replace(item, excerpt=excerpt)
        if dry_run:
            results.append((item.published_at[:10], item.title, "试运行"))
            continue

        try:
            submit_news_draft(api_url, worker_key, source, complete)
        except Exception as exc:  # noqa: BLE001
            results.append((item.published_at[:10], item.title, f"提交失败：{exc}"))
            continue
        results.append((item.published_at[:10], item.title, "已建草稿"))

    return results
