import json
import os
from pathlib import Path

from dataclasses import replace

from .api import report_source_check, submit_candidate, submit_news_draft
from .diffing import make_candidate
from .fetcher import ConditionalHeaders, OfficialFetcher
from .models import Source
from .generic_discovery import discover_articles
from .news_discovery import discover_sa_news, extract_article_excerpt
from .normalizer import normalize_html
from .storage import LocalEvidenceStore


def load_sources(path: Path) -> list[Source]:
    return [Source(**record) for record in json.loads(path.read_text(encoding="utf-8"))]


def run_source(source: Source, sources: list[Source], state_dir: Path) -> str:
    user_agent = os.environ.get("CRAWLER_USER_AGENT", "")
    fetcher = OfficialFetcher(user_agent, {item.url.split('/')[2].lower() for item in sources})
    store = LocalEvidenceStore(state_dir)
    previous = store.load(source.id)
    api_url = os.environ.get("REVIEW_API_URL")
    worker_key = os.environ.get("WORKER_API_KEY")

    def report(status: str, **details: object) -> None:
        if api_url and worker_key:
            report_source_check(api_url, worker_key, source, status, **details)

    try:
        result = fetcher.fetch(source, ConditionalHeaders(previous.etag, previous.last_modified))
        if result.status == 304:
            report("NOT_MODIFIED", http_status=304)
            return "not-modified"
        if result.content_type == "application/pdf":
            normalized = f"PDF SHA256 evidence only: {__import__('hashlib').sha256(result.body).hexdigest()}"
        else:
            normalized = normalize_html(result.body)
        if len(normalized) < 80:
            raise RuntimeError("normalised page is unexpectedly empty; hold for source health review")
        digest = store.save(source.id, result.body, normalized, result.etag, result.last_modified)
        report(
            "SUCCESS",
            content_hash=digest,
            snapshot_key=f"{source.id}/{digest}",
            http_status=result.status,
            etag=result.etag,
            last_modified=result.last_modified,
        )
        news_result = _discover_news(source, fetcher, state_dir, api_url, worker_key)
        if not previous.content_hash:
            return _with_news("baseline-created", news_result)
        candidate = make_candidate(
            previous.normalized_text, normalized, source.name, len(normalized)
        )
        if not candidate:
            return _with_news("unchanged", news_result)

        if api_url and worker_key:
            submit_candidate(api_url, worker_key, source, candidate, len(normalized))
            return _with_news(f"candidate-submitted:{candidate.importance}", news_result)
        output = state_dir / source.id / "pending-candidate.json"
        output.write_text(json.dumps(candidate.__dict__, ensure_ascii=False, indent=2), encoding="utf-8")
        return _with_news(f"candidate-staged:{candidate.importance}", news_result)
    except Exception as error:
        try:
            report("ERROR", error_code=type(error).__name__)
        except Exception:
            # Health reporting must never hide the original fetch/normalisation failure.
            pass
        raise


def _with_news(status: str, discovered: int) -> str:
    return f"{status};news-drafts:{discovered}" if discovered else status


def _discover_news(
    source: Source,
    fetcher: OfficialFetcher,
    state_dir: Path,
    api_url: str | None,
    worker_key: str | None,
) -> int:
    if not source.discovery_url:
        return 0

    limit = max(1, min(int(os.environ.get("NEWS_DISCOVERY_LIMIT", "6")), 12))
    if source.article_pattern:
        # 通用路径：列表页只用来发现链接，标题和日期到文章页里取。
        # 各州 DOM 各不相同，但 h1 和 JSON-LD 是通用的。
        discovered = discover_articles(
            source, fetcher, source.article_pattern, limit=limit
        )
    else:
        # 南澳沿用按其 DOM 写死的解析：它的列表页直接给全标题和日期，
        # 少一轮逐篇请求，没必要改。
        listing_source = replace(source, url=source.discovery_url, discovery_url=None)
        listing = fetcher.fetch(listing_source, ConditionalHeaders())
        discovered = discover_sa_news(listing.body, limit)
    complete = []
    for item in discovered:
        article_source = replace(source, url=item.url, discovery_url=None)
        article = fetcher.fetch(article_source, ConditionalHeaders())
        excerpt = extract_article_excerpt(article.body, item.title)
        if len(excerpt) < 40:
            continue
        complete_item = replace(item, excerpt=excerpt)
        complete.append(complete_item)
        if api_url and worker_key:
            submit_news_draft(api_url, worker_key, source, complete_item)
    if complete and not (api_url and worker_key):
        output = state_dir / source.id / "pending-news.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            json.dumps([item.__dict__ for item in complete], ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    return len(complete)
