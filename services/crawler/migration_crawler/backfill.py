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


def backfill_excerpts(
    source: Source,
    fetcher: OfficialFetcher,
    api_url: str,
    worker_key: str,
    entries: list[dict],
    *,
    dry_run: bool = False,
    delay_seconds: float = 2.0,
) -> list[tuple[str, str, str]]:
    """给已入库但缺 sourceExcerpt 的条目补上官方原文摘录。

    为什么需要它：后台审核靠原文与译稿左右对照，没有摘录的条目在界面上
    只剩一句「原文摘录已丢失，请打开官方页面核对」——等于这条没法在后台审。
    线上实测有 12 条这种情况（11 条昆士兰 + 1 条联邦法规）。

    更糟的是摘要工具当时会退回拿已有中文摘要当「原文」再摘一次，于是产出是
    摘要的摘要，而「数字必须在原文中出现」那道校验比对的也是上一版摘要——
    它只能证明前后两版一致，证明不了与官方一致。

    与 `backfill_sa_news` 的区别：那个是从列表页发现新条目并建草稿；
    这个针对**已知 URL 的已有条目**，走同一个 upsert 入口。
    `ingestNews` 的 update 分支只写 publishedAt / sourceTitle / sourceExcerpt，
    不碰 titleZh / summaryZh / tags，所以重新提交不会覆盖任何人写的东西。

    publishedAt 必须由调用方从库里带过来。让抓取端重新推断日期，
    等于给每条内容一次改错日期的机会——西澳那次就是把标题里的
    「until 31 December 2026」当成了发布日期。
    """
    results: list[tuple[str, str, str]] = []

    for index, entry in enumerate(entries):
        if index:
            time.sleep(delay_seconds)
        url = entry["url"]
        title = entry["title"]
        article_source = replace(source, url=url, discovery_url=None)
        try:
            article = fetcher.fetch(article_source, ConditionalHeaders())
        except Exception as exc:  # noqa: BLE001
            results.append((entry["publishedAt"][:10], title, f"取不到：{exc}"))
            continue

        excerpt = extract_article_excerpt(article.body, title)
        if len(excerpt) < MIN_EXCERPT_CHARS:
            results.append((entry["publishedAt"][:10], title, "正文过短，跳过"))
            continue

        item = DiscoveredNews(
            title=title,
            url=url,
            category=entry.get("category", ""),
            published_at=entry["publishedAt"],
            excerpt=excerpt,
        )
        if dry_run:
            results.append(
                (entry["publishedAt"][:10], title, f"试运行（摘录 {len(excerpt)} 字符）")
            )
            continue

        try:
            submit_news_draft(api_url, worker_key, source, item)
        except Exception as exc:  # noqa: BLE001
            results.append((entry["publishedAt"][:10], title, f"提交失败：{exc}"))
            continue
        results.append((entry["publishedAt"][:10], title, f"已补摘录 {len(excerpt)} 字符"))

    return results
