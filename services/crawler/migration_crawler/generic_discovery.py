"""按配置从任意州的新闻列表页发现文章，不为每个站单独写解析器。

南澳那套（`news_discovery.py`）是照它的 DOM 写死的：`xl:col-span-6` 容器、`h3` 标题、
特定格式的日期文本。再来三个州就是三份这样的代码，每次对方改版都得重写一遍。

这里换个思路：**列表页只用来发现链接，标题和日期到文章页里取。**
文章页的 `<h1>` 和 JSON-LD 的 `datePublished` 比列表卡片的 class 名稳定得多——
前者是语义结构，后者是 Tailwind 生成的样式类，改版必变。

每个来源在 `sources.json` 里配一个 `article_pattern`，其余通用。
"""

import html as htmllib
import json
import re
from dataclasses import replace
from datetime import datetime, timezone

from .models import DiscoveredNews, Source

# 文章页里找发布日期的顺序。JSON-LD 最可靠，其次是标准 meta，最后才退回可见文本。
_TIME_ELEMENT = re.compile(r'<time[^>]+datetime="([^"]+)"', re.I)
_LD_DATE = re.compile(r'"datePublished"\s*:\s*"([^"]+)"')
_META_DATE = re.compile(
    r'<meta[^>]+(?:property|name)="(?:article:published_time|dcterms\.date|date)"'
    r'[^>]+content="([^"]+)"',
    re.I,
)

_DATE_TEXT = (
    r"(\d{1,2})(?:st|nd|rd|th)?\s+"
    r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(20\d\d)"
)
# 可见日期只在紧跟「发布/更新」字样时才认。
# 词表里原先还有一个裸的 `date`，于是 closing date、commencement date、
# effective date、expiry date 全都会被当成发布日期——而未来日期守卫挡不住它们，
# 因为这些通常是过去的日期。
#
# 起因：WA 有一篇标题是「…continue to access the Goldfields DAMA until 31 December
# 2026」，页面上第一个日期就是标题里的**截止日期**。当时的兜底把它当成发布日期，
# 于是一条 2025 年的公告被标成 2026-12-31——排到资讯页最顶上，还是个未来日期。
# 「页面上第一个日期」这个启发式在政策网站上就是错的：这类页面遍地是生效日、
# 截止日、财年区间。
_LABELLED_DATE = re.compile(
    r"(?:published|posted|released|last\s+updated)\b[^<]{0,40}?" + _DATE_TEXT,
    re.I,
)

_MONTHS = {
    m: i + 1
    for i, m in enumerate(
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    )
}


def extract_links(body: bytes, base_url: str, pattern: str) -> list[str]:
    """从列表页取出符合模式的文章链接，去重并补全为绝对地址。"""
    text = body.decode("utf-8", "replace")
    origin = re.match(r"https?://[^/]+", base_url)
    if not origin:
        return []
    prefix = origin.group(0)
    compiled = re.compile(pattern)

    found: dict[str, None] = {}
    for href in re.findall(r'href="([^"]+)"', text):
        href = htmllib.unescape(href).split("#")[0].split("?")[0].rstrip("/")
        if not href:
            continue
        path = href[len(prefix):] if href.startswith(prefix) else href
        if not path.startswith("/"):
            continue
        if compiled.match(path):
            found.setdefault(prefix + path, None)
    return list(found)


def extract_title(body: bytes) -> str:
    """文章标题。优先 h1；h1 是栏目名时退回 og:title。

    不用 `<title>`：多数 CMS 会把它截断成「South Australia's 2024-2025 General Skilled…」。
    """
    text = body.decode("utf-8", "replace")
    candidates: list[str] = []
    for match in re.findall(r"<h1[^>]*>(.*?)</h1>", text, re.S):
        cleaned = re.sub(r"\s+", " ", htmllib.unescape(re.sub(r"<[^>]+>", " ", match))).strip()
        if cleaned:
            candidates.append(cleaned)

    og = re.search(r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"', text, re.I)
    if og:
        candidates.append(re.sub(r"\s+", " ", htmllib.unescape(og.group(1))).strip())

    # 「News」「Home」这类栏目名不是文章标题。
    generic = {"news", "home", "media", "updates", "news and updates"}
    for candidate in candidates:
        if candidate.lower() not in generic and len(candidate) > 4:
            return candidate
    return candidates[0] if candidates else ""


def extract_published_at(body: bytes, *, now: datetime | None = None) -> str:
    """发布时间，ISO 8601。取不到返回空串——宁可跳过整篇，也不要编一个日期。

    顺序是按可靠性排的：`<time datetime>` 和 JSON-LD 是语义标注，meta 次之，
    带「published」字样的可见文本最后。没有标注就放弃。
    """
    text = body.decode("utf-8", "replace")
    current = now or datetime.now(timezone.utc)

    def accept(value: datetime) -> str:
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        # 未来日期一定是取错了——政策网站上满是生效日和截止日。
        # 放进去会让这条永远置顶在资讯页。
        if value > current:
            return ""
        return value.isoformat()

    for pattern in (_TIME_ELEMENT, _LD_DATE, _META_DATE):
        for raw in pattern.findall(text):
            try:
                parsed = datetime.fromisoformat(raw.strip().replace("Z", "+00:00"))
            except ValueError:
                continue
            result = accept(parsed)
            if result:
                return result

    match = _LABELLED_DATE.search(text)
    if match:
        day, month, year = match.groups()
        # 站点只给日历日期，用正午 UTC，这样在澳洲各时区里日期都不会漂。
        return accept(
            datetime(int(year), _MONTHS[month], int(day), 12, tzinfo=timezone.utc)
        )
    return ""


def discover_articles(
    source: Source, fetcher, article_pattern: str, limit: int = 200
) -> list[DiscoveredNews]:
    """列表页发现链接，逐篇取标题与日期。取不到日期的直接丢弃。"""
    from .fetcher import ConditionalHeaders  # 局部导入避免循环依赖

    listing_url = source.discovery_url or source.url
    listing = fetcher.fetch(
        replace(source, url=listing_url, discovery_url=None), ConditionalHeaders()
    )
    relevance = re.compile(source.relevance_pattern, re.I) if source.relevance_pattern else None
    links = extract_links(listing.body, listing_url, article_pattern)
    if relevance:
        # Whole-of-government newsrooms can publish dozens of unrelated stories a day.
        # Filter their descriptive URL slugs before fetching article bodies; otherwise
        # the first N health/roads releases consume the entire polite request budget.
        links = [link for link in links if relevance.search(link.replace("-", " "))]
    links = links[:limit]

    items: list[DiscoveredNews] = []
    for link in links:
        article = fetcher.fetch(
            replace(source, url=link, discovery_url=None), ConditionalHeaders()
        )
        title = extract_title(article.body)
        published_at = extract_published_at(article.body)
        if not title or not published_at:
            continue
        if relevance and not relevance.search(title):
            continue
        items.append(
            DiscoveredNews(
                title=title,
                url=link,
                category="",
                published_at=published_at,
            )
        )
    return sorted(items, key=lambda item: item.published_at)
