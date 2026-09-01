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
    # `html` 从列表页发现链接；`rss` 从官方 RSS；`sitemap` 从允许访问的官方
    # sitemap 发现链接（用于正文列表被 WAF 拦截、但 sitemap 明确开放的站点）。
    # RSS 是联邦部长媒体中心提供的正式接口，比抓 SharePoint 动态列表稳定。
    discovery_format: str = "html"
    # 一个来源可能同时发布网络安全、文化、边境执法等内容。只在标题与 RSS
    # description 命中这个显式登记的规则时，才把它当作移民资讯。
    relevance_pattern: str | None = None
    # 该来源发现的条目默认带上的主题标签。
    # 从来源推导比从标题猜可靠：接一个新的职业清单页时，主题是先验已知的。
    topics: tuple[str, ...] = ()


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
