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
_LD_DATE = re.compile(r'"datePublished"\s*:\s*"([^"]+)"')
_META_DATE = re.compile(
    r'<meta[^>]+(?:property|name)="(?:article:published_time|dcterms\.date|date)"'
    r'[^>]+content="([^"]+)"',
    re.I,
)
_VISIBLE_DATE = re.compile(
    r"\b(\d{1,2})(?:st|nd|rd|th)?\s+"
    r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(20\d\d)\b"
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


def extract_published_at(body: bytes) -> str:
    """发布时间，ISO 8601。取不到返回空串——宁可跳过，也不要编一个日期。"""
    text = body.decode("utf-8", "replace")

    for pattern in (_LD_DATE, _META_DATE):
        match = pattern.search(text)
        if match:
            raw = match.group(1).strip()
            try:
                return datetime.fromisoformat(raw.replace("Z", "+00:00")).isoformat()
            except ValueError:
                pass

    match = _VISIBLE_DATE.search(text)
    if match:
        day, month, year = match.groups()
        # 站点只给日历日期，用正午 UTC，这样在澳洲各时区里日期都不会漂。
        return datetime(
            int(year), _MONTHS[month], int(day), 12, tzinfo=timezone.utc
        ).isoformat()
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
    links = extract_links(listing.body, listing_url, article_pattern)[:limit]

    items: list[DiscoveredNews] = []
    for link in links:
        article = fetcher.fetch(
            replace(source, url=link, discovery_url=None), ConditionalHeaders()
        )
        title = extract_title(article.body)
        published_at = extract_published_at(article.body)
        if not title or not published_at:
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
