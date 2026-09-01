"""Discover recent relevant releases through an allowlisted official sitemap."""

import os
import re
import xml.etree.ElementTree as ET
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

from .fetcher import ConditionalHeaders
from .generic_discovery import extract_published_at, extract_title
from .models import DiscoveredNews, Source


def discover_sitemap_articles(source: Source, fetcher, limit: int = 12) -> list[DiscoveredNews]:
    root_url = source.discovery_url or source.url
    root = fetcher.fetch(
        replace(source, url=root_url, discovery_url=None), ConditionalHeaders()
    )
    parsed_root = ET.fromstring(root.body)
    origin = urlparse(source.url)

    sitemap_urls = [_text(node) for node in parsed_root.findall(".//{*}sitemap/{*}loc")]
    if sitemap_urls:
        max_pages = max(1, min(int(os.getenv("SITEMAP_RECENT_PAGES", "2")), 4))
        sitemap_urls = [
            url
            for url in sitemap_urls
            if _same_host(url, origin.hostname) and urlparse(url).path == urlparse(root_url).path
        ][-max_pages:]
    else:
        sitemap_urls = [root_url]

    relevance = re.compile(source.relevance_pattern, re.I) if source.relevance_pattern else None
    now = datetime.now(timezone.utc)
    lookback = now - timedelta(days=max(30, int(os.getenv("SITEMAP_LOOKBACK_DAYS", "450"))))
    candidates: dict[str, datetime] = {}
    for sitemap_url in sitemap_urls:
        document = (
            root
            if sitemap_url == root_url
            else fetcher.fetch(
                replace(source, url=sitemap_url, discovery_url=None), ConditionalHeaders()
            )
        )
        page = ET.fromstring(document.body)
        for node in page.findall(".//{*}url"):
            url = _text(node.find("{*}loc"))
            modified = _date(_text(node.find("{*}lastmod")))
            searchable = url.replace("-", " ")
            if not url or not modified or modified < lookback or modified > now:
                continue
            if not _same_host(url, origin.hostname):
                continue
            if relevance and not relevance.search(searchable):
                continue
            candidates[url] = modified

    items: list[DiscoveredNews] = []
    for url, _ in sorted(candidates.items(), key=lambda row: row[1], reverse=True)[:limit]:
        article = fetcher.fetch(
            replace(source, url=url, discovery_url=None), ConditionalHeaders()
        )
        title = extract_title(article.body)
        published_at = extract_published_at(article.body)
        if not title or not published_at:
            continue
        if relevance and not relevance.search(f"{title}\n{url.replace('-', ' ')}"):
            continue
        items.append(
            DiscoveredNews(
                title=title,
                url=url,
                category="",
                published_at=published_at,
            )
        )
    return sorted(items, key=lambda item: item.published_at)


def _text(node: ET.Element | None) -> str:
    return "" if node is None or node.text is None else node.text.strip()


def _date(value: str) -> datetime | None:
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if result.tzinfo is None:
        result = result.replace(tzinfo=timezone.utc)
    return result.astimezone(timezone.utc)


def _same_host(url: str, host: str | None) -> bool:
    parsed = urlparse(url)
    return parsed.scheme == "https" and parsed.hostname == host
