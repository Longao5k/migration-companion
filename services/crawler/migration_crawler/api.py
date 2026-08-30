import json
from dataclasses import asdict
from datetime import datetime, timezone
from urllib.request import Request, urlopen

from .jurisdictions import label_for
from .models import ChangeCandidate, DiscoveredNews, Source


def submit_news_draft(
    api_url: str, worker_key: str, source: Source, item: DiscoveredNews
) -> None:
    # 辖区标签必须来自来源的 jurisdiction。这里曾经写死 "南澳"，
    # 接入其它州之后 47 条内容全部错标——昆士兰的提名政策显示成南澳的。
    tags = [label_for(source.jurisdiction)]
    searchable = f"{item.title} {item.excerpt}".lower()
    if "190" in searchable:
        tags.append("190")
    if "491" in searchable:
        tags.append("491")
    if item.category:
        tags.append(item.category)
    payload = {
        "sourceRegistryUrl": source.url,
        "sourceUrl": item.url,
        "sourceTitle": item.title,
        "sourceExcerpt": item.excerpt,
        "tags": tags,
        "publishedAt": item.published_at,
    }
    request = Request(
        f"{api_url.rstrip('/')}/v1/content/worker/news",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Worker-Key": worker_key},
        method="POST",
    )
    with urlopen(request, timeout=15) as response:
        if response.status >= 300:
            raise RuntimeError(f"review API returned HTTP {response.status}")


def submit_candidate(
    api_url: str,
    worker_key: str,
    source: Source,
    candidate: ChangeCandidate,
    body_chars: int = 0,
) -> None:
    # 同上：非南澳即联邦是接入其它州之前的假设，现在会把昆士兰的变更标成联邦。
    tags = [label_for(source.jurisdiction)]
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
        # 让服务端的「引用不超过正文 20%」真正生效：没有这个值时
        # 服务端只能退回固定上限，短页面仍可能被整页引用。
        "sourceBodyChars": body_chars or None,
    }
    payload = {key: value for key, value in payload.items() if value is not None}
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
