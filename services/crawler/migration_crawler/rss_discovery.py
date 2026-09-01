"""Discover official articles from an allowlisted RSS feed.

The Home Affairs ministerial site exposes a stable RSS endpoint even though its
SharePoint listing is rendered client-side.  The feed is used only to discover
same-host article URLs, titles and publication dates; the article itself is
still fetched through :class:`OfficialFetcher` and stored as evidence by the
normal crawler path.
"""

import html
import re
import xml.etree.ElementTree as ET
from dataclasses import replace
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urlparse

from .fetcher import ConditionalHeaders
from .models import DiscoveredNews, Source


def discover_rss_articles(source: Source, fetcher, limit: int = 12) -> list[DiscoveredNews]:
    feed_url = source.discovery_url or source.url
    feed = fetcher.fetch(
        replace(source, url=feed_url, discovery_url=None), ConditionalHeaders()
    )
    root = ET.fromstring(feed.body)
    origin = urlparse(source.url)
    path_rule = re.compile(source.article_pattern or r"^/.*$")
    relevance = re.compile(source.relevance_pattern, re.I) if source.relevance_pattern else None
    current = datetime.now(timezone.utc)

    items: list[DiscoveredNews] = []
    seen: set[str] = set()
    for node in root.findall("./channel/item"):
        title = _text(node, "title")
        link = _text(node, "link").split("#", 1)[0].split("?", 1)[0]
        description = _plain(_text(node, "description"))
        published = _published(_text(node, "pubDate"))
        parsed = urlparse(link)

        if not title or not published or published > current:
            continue
        if parsed.scheme != "https" or parsed.hostname != origin.hostname:
            continue
        if not path_rule.fullmatch(parsed.path):
            continue
        if relevance and not relevance.search(f"{title}\n{description}"):
            continue
        if link in seen:
            continue
        seen.add(link)
        items.append(
            DiscoveredNews(
                title=title,
                url=link,
                category="",
                published_at=published.isoformat(),
            )
        )
        if len(items) >= limit:
            break
    return sorted(items, key=lambda item: item.published_at)


def _text(node: ET.Element, name: str) -> str:
    child = node.find(name)
    return "" if child is None or child.text is None else child.text.strip()


def _plain(value: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", value))).strip()


def _published(value: str) -> datetime | None:
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)
