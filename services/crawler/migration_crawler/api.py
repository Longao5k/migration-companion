import json
from dataclasses import asdict
from datetime import datetime, timezone
from urllib.request import Request, urlopen

from .models import ChangeCandidate, Source


def submit_candidate(api_url: str, worker_key: str, source: Source, candidate: ChangeCandidate) -> None:
    payload = {
        "sourceUrl": source.url,
        "sourceName": source.name,
        "titleZh": candidate.title_zh,
        "oldExcerpt": candidate.old_excerpt,
        "newExcerpt": candidate.new_excerpt,
        "context": candidate.context,
        "importance": candidate.importance,
        "discoveredAt": datetime.now(timezone.utc).isoformat(),
    }
    request = Request(
        f"{api_url.rstrip('/')}/v1/content/worker/changes",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Worker-Key": worker_key},
        method="POST",
    )
    with urlopen(request, timeout=15) as response:
        if response.status >= 300:
            raise RuntimeError(f"review API returned HTTP {response.status}")

