import json
import os
from pathlib import Path

from .api import submit_candidate
from .diffing import make_candidate
from .fetcher import ConditionalHeaders, OfficialFetcher
from .models import Source
from .normalizer import normalize_html
from .storage import LocalEvidenceStore


def load_sources(path: Path) -> list[Source]:
    return [Source(**record) for record in json.loads(path.read_text(encoding="utf-8"))]


def run_source(source: Source, sources: list[Source], state_dir: Path) -> str:
    user_agent = os.environ.get("CRAWLER_USER_AGENT", "")
    fetcher = OfficialFetcher(user_agent, {item.url.split('/')[2].lower() for item in sources})
    store = LocalEvidenceStore(state_dir)
    previous = store.load(source.id)
    result = fetcher.fetch(source, ConditionalHeaders(previous.etag, previous.last_modified))
    if result.status == 304:
        return "not-modified"
    if result.content_type == "application/pdf":
        normalized = f"PDF SHA256 evidence only: {__import__('hashlib').sha256(result.body).hexdigest()}"
    else:
        normalized = normalize_html(result.body)
    if len(normalized) < 80:
        raise RuntimeError("normalised page is unexpectedly empty; hold for source health review")
    store.save(source.id, result.body, normalized, result.etag, result.last_modified)
    if not previous.content_hash:
        return "baseline-created"
    candidate = make_candidate(previous.normalized_text, normalized, source.name)
    if not candidate:
        return "unchanged"

    api_url = os.environ.get("REVIEW_API_URL")
    worker_key = os.environ.get("WORKER_API_KEY")
    if api_url and worker_key:
        submit_candidate(api_url, worker_key, source, candidate)
        return f"candidate-submitted:{candidate.importance}"
    output = state_dir / source.id / "pending-candidate.json"
    output.write_text(json.dumps(candidate.__dict__, ensure_ascii=False, indent=2), encoding="utf-8")
    return f"candidate-staged:{candidate.importance}"

