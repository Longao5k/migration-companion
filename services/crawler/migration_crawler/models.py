from dataclasses import dataclass
from typing import Literal

Importance = Literal["GENERAL", "IMPORTANT", "MAJOR"]


@dataclass(frozen=True)
class Source:
    id: str
    name: str
    url: str
    jurisdiction: str
    license_note: str
    enabled: bool
    discovery_url: str | None = None
    # 配了这个就走通用发现（generic_discovery），不配就走南澳那套写死的解析。
    # 值是文章路径的正则，例如 r"^/news/[a-z0-9][a-z0-9\-]+$"。
    article_pattern: str | None = None


@dataclass(frozen=True)
class FetchResult:
    status: int
    body: bytes
    content_type: str
    etag: str | None
    last_modified: str | None


@dataclass(frozen=True)
class ChangeCandidate:
    title_zh: str
    old_excerpt: str
    new_excerpt: str
    context: str
    importance: Importance


@dataclass(frozen=True)
class DiscoveredNews:
    title: str
    url: str
    category: str
    published_at: str
    excerpt: str = ""
