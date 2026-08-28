import json
from dataclasses import asdict
from datetime import datetime, timezone
from urllib.request import Request, urlopen

from .models import ChangeCandidate, Source


def submit_candidate(api_url: str, worker_key: str, source: Source, candidate: ChangeCandidate) -> None:
    tags = ["SA" if source.jurisdiction == "AU-SA" else "联邦"]
    if "190" in source.url:
        tags.append("190")
    if "491" in source.url:
        tags.append("491")
    payload = {
        "sourceUrl": source.url,
        "sourceName": source.name,
        "titleZh": candidate.title_zh,
        "oldExcerpt": candidate.old_excerpt,
        "newExcerpt": candidate.new_excerpt,
        "context": candidate.context,
        "importance": candidate.importance,
        "discoveredAt": datetime.now(timezone.utc).isoformat(),
        "tags": tags,
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


def report_source_check(
    api_url: str,
    worker_key: str,
    source: Source,
    status: str,
    *,
    content_hash: str | None = None,
    snapshot_key: str | None = None,
    http_status: int | None = None,
    etag: str | None = None,
    last_modified: str | None = None,
    error_code: str | None = None,
) -> None:
    payload = {
        "sourceUrl": source.url,
        "sourceName": source.name,
        "jurisdiction": source.jurisdiction,
        "status": status,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        **({"contentHash": content_hash} if content_hash else {}),
        **({"snapshotKey": snapshot_key} if snapshot_key else {}),
        **({"httpStatus": http_status} if http_status else {}),
        **({"etag": etag} if etag else {}),
        **({"lastModified": last_modified} if last_modified else {}),
        **({"errorCode": error_code} if error_code else {}),
    }
    request = Request(
        f"{api_url.rstrip('/')}/v1/content/worker/source-checks",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Worker-Key": worker_key},
        method="POST",
    )
    with urlopen(request, timeout=15) as response:
        if response.status >= 300:
            raise RuntimeError(f"source health API returned HTTP {response.status}")
