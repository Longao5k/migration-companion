import time
from dataclasses import dataclass
from urllib.error import HTTPError
from urllib.request import Request, build_opener
from urllib.robotparser import RobotFileParser
from urllib.parse import urljoin

from .models import FetchResult, Source
from .security import validate_url

MAX_BODY_BYTES = 5 * 1024 * 1024

# 站点没有声明 Crawl-delay 时的最小请求间隔。新闻发现会对同一主机连续取
# 列表页加多篇文章，没有节流就是一次突发。
DEFAULT_CRAWL_DELAY_SECONDS = 2.0
# 站点声明的 Crawl-delay 再长也照单全收，但设一个上限避免配置错误把抓取卡死。
MAX_CRAWL_DELAY_SECONDS = 30.0


class FetchRejected(RuntimeError):
    pass


@dataclass
class ConditionalHeaders:
    etag: str | None = None
    last_modified: str | None = None


class OfficialFetcher:
    def __init__(self, user_agent: str, approved_hosts: set[str]) -> None:
        if "example.invalid" in user_agent or "+http" not in user_agent:
            raise FetchRejected("crawler user agent must contain a truthful contact URL")
        self.user_agent = user_agent
        self.approved_hosts = approved_hosts
        self.opener = build_opener()
        # 每个主机上一次请求的时间，用于遵守 Crawl-delay。
        self._last_request_at: dict[str, float] = {}

    def fetch(self, source: Source, conditional: ConditionalHeaders) -> FetchResult:
        host = validate_url(source.url, self.approved_hosts)
        robots_url = urljoin(source.url, "/robots.txt")
        robots = RobotFileParser(robots_url)
        robots.set_url(robots_url)
        try:
            robots.read()
        except OSError as exc:
            raise FetchRejected(f"robots rules could not be verified for {host}") from exc
        if not robots.can_fetch(self.user_agent, source.url):
            raise FetchRejected("robots rules do not permit this URL")
        self._respect_crawl_delay(host, robots)

        headers = {
            "User-Agent": self.user_agent,
            "Accept": "text/html,application/xhtml+xml,application/pdf;q=0.8",
            "Accept-Encoding": "identity",
        }
        if conditional.etag:
            headers["If-None-Match"] = conditional.etag
        if conditional.last_modified:
            headers["If-Modified-Since"] = conditional.last_modified

        self._last_request_at[host] = time.monotonic()
        try:
            response = self.opener.open(Request(source.url, headers=headers), timeout=25)
        except HTTPError as exc:
            if exc.code == 304:
                return FetchResult(304, b"", "", conditional.etag, conditional.last_modified)
            raise FetchRejected(f"source returned HTTP {exc.code}") from exc

        final_host = validate_url(response.geturl(), self.approved_hosts)
        if final_host not in self.approved_hosts:
            raise FetchRejected("redirect left the approved host set")
        length = response.headers.get("Content-Length")
        if length and int(length) > MAX_BODY_BYTES:
            raise FetchRejected("source response exceeds the evidence size limit")
        body = response.read(MAX_BODY_BYTES + 1)
        if len(body) > MAX_BODY_BYTES:
            raise FetchRejected("source response exceeds the evidence size limit")
        content_type = response.headers.get_content_type()
        if content_type not in {"text/html", "application/xhtml+xml", "application/pdf"}:
            raise FetchRejected(f"unsupported content type: {content_type}")
        return FetchResult(
            status=response.status,
            body=body,
            content_type=content_type,
            etag=response.headers.get("ETag"),
            last_modified=response.headers.get("Last-Modified"),
        )

    def _respect_crawl_delay(self, host: str, robots: RobotFileParser) -> None:
        """按站点声明的 Crawl-delay 等待，未声明时用默认最小间隔。

        legislation.gov.au 声明了 Crawl-delay: 10，此前我们完全没遵守——
        站点明确表达了节奏要求而我们无视，属于不当抓取。
        """
        declared = None
        try:
            declared = robots.crawl_delay(self.user_agent)
        except Exception:
            # 不同 Python 版本对畸形 robots 的行为不一致；拿不到就退回默认值。
            declared = None
        delay = min(
            MAX_CRAWL_DELAY_SECONDS,
            max(DEFAULT_CRAWL_DELAY_SECONDS, float(declared or 0)),
        )
        previous = self._last_request_at.get(host)
        if previous is None:
            return
        elapsed = time.monotonic() - previous
        if elapsed < delay:
            time.sleep(delay - elapsed)
