"""Continuously draft, independently review, and submit official news.

The worker cannot decide what is safe to publish. It submits evidence-bound
results to the API; server-side policy makes the final auto/human decision.
Secrets are read only from environment variables.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import crosscheck_drafts as cc
import summarize_drafts as sd


def require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"缺少环境变量 {name}")
    return value


def worker_request(path: str, *, method: str = "GET", body: dict | None = None):
    base = require("EDITORIAL_API_URL").rstrip("/")
    payload = json.dumps(body, ensure_ascii=False).encode("utf-8") if body else None
    request = Request(
        f"{base}/v1{path}",
        data=payload,
        method=method,
        headers={
            "x-worker-key": require("WORKER_API_KEY"),
            **({"content-type": "application/json"} if payload else {}),
        },
    )
    try:
        with urlopen(request, timeout=90) as response:
            raw = response.read().decode("utf-8")
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"API HTTP {exc.code}: {detail}") from None
    except URLError as exc:
        raise RuntimeError(f"API 连接失败: {exc.reason}") from exc
    return json.loads(raw) if raw else None


def model_family(model: str) -> str:
    lowered = model.lower()
    for family in ("deepseek", "qwen", "kimi", "glm"):
        if family in lowered:
            return family
    return lowered.split("-")[0]


def choose_review_model(pool: sd.ModelPool, draft_model: str) -> str:
    """Select a model family independent from the drafting model."""
    start = pool.index
    for index in range(start, len(pool.models)):
        candidate = pool.models[index]
        if candidate != draft_model and model_family(candidate) != model_family(draft_model):
            pool.index = index
            return candidate
    raise RuntimeError("没有与起草模型不同家族的复核模型")


def create_draft(item: dict, pool: sd.ModelPool) -> tuple[dict, str]:
    existing = {
        "title": (item.get("titleZh") or "").strip(),
        "summary": (item.get("summaryZh") or "").strip(),
        "titleEn": (item.get("titleEn") or "").strip(),
        "summaryEn": (item.get("summaryEn") or "").strip(),
    }
    excerpt = item["sourceExcerpt"].strip()
    if item.get("draftAuthor") == "model" and all(existing.values()):
        problems = sd.validate(
            existing,
            excerpt,
            item["publishedAt"][:4],
            item["sourceTitle"],
        )
        # Historical drafts may come from the family now reserved for review.
        # Reusing one would either make the reviewer check its own family or leave
        # the item permanently pending. Re-draft those with the active draft family.
        if (
            not problems
            and item.get("draftModel")
            and model_family(item["draftModel"]) == model_family(pool.current)
        ):
            return existing, item["draftModel"]

    while True:
        try:
            result = sd.summarise(item["sourceTitle"], excerpt, pool.current)
            problems = sd.validate(
                result,
                excerpt,
                item["publishedAt"][:4],
                item["sourceTitle"],
            )
            if problems:
                raise RuntimeError("；".join(problems))
            return result, pool.current
        except Exception as exc:  # noqa: BLE001
            if pool.retire_current():
                reason = "额度耗尽" if sd.is_quota_error(exc) else "调用或内容校验失败"
                print(f"起草模型{reason}，切换到 {pool.current}", flush=True)
                continue
            raise


def review_draft(
    item: dict,
    draft: dict,
    draft_model: str,
    pool: sd.ModelPool,
    runs: int,
) -> tuple[list[dict], str]:
    candidate = {
        **item,
        "titleZh": draft["title"],
        "summaryZh": draft["summary"],
        "titleEn": draft["titleEn"],
        "summaryEn": draft["summaryEn"],
    }
    while True:
        model = choose_review_model(pool, draft_model)
        try:
            findings = cc.crosscheck_repeated(
                candidate,
                model,
                datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                runs,
            )
            return findings, model
        except Exception as exc:  # noqa: BLE001
            if pool.retire_current():
                reason = "额度耗尽" if sd.is_quota_error(exc) else "调用或结果校验失败"
                print(f"复核模型{reason}，切换到 {pool.current}", flush=True)
                continue
            raise


def finding_text(finding: dict, runs: int) -> str:
    votes = int(finding.get("votes") or 1)
    severity = "高" if finding.get("severity") == "high" else "低"
    kind = cc.KIND_LABEL.get(finding.get("kind", ""), finding.get("kind", "分歧"))
    return f"[{votes}/{runs}轮][{severity}风险]{kind}：{finding['detail']}"[:300]


def process_batch(limit: int, review_runs: int) -> tuple[int, int]:
    items = worker_request("/content/worker/editorial-queue") or []
    items = items[:limit]
    if not items:
        return 0, 0

    draft_pool = sd.ModelPool(
        os.environ.get("EDITORIAL_DRAFT_MODELS", sd.DEFAULT_MODEL).split(",")
    )
    review_pool = sd.ModelPool(
        os.environ.get("EDITORIAL_REVIEW_MODELS", cc.DEFAULT_MODEL).split(",")
    )
    succeeded = failed = 0
    for index, item in enumerate(items, 1):
        label = (item.get("sourceTitle") or item["id"])[:70]
        print(f"[{index}/{len(items)}] {label}", flush=True)
        try:
            draft, draft_model = create_draft(item, draft_pool)
            findings, review_model = review_draft(
                item, draft, draft_model, review_pool, review_runs
            )
            finding_lines = [finding_text(finding, review_runs) for finding in findings]
            blocking = [
                finding_text(finding, review_runs)
                for finding in findings
                if finding.get("severity") == "high"
                or int(finding.get("votes") or 1) >= 2
            ]
            excerpt = item["sourceExcerpt"].strip()
            checks = [
                line
                for line in sd.checks_performed(draft, excerpt, item["sourceTitle"])
                if not line.startswith("以下未经机器核对")
            ]
            checks.append(f"独立模型完成 {review_runs} 轮事实与中英文一致性复核")
            # Hash the exact stored evidence, not the trimmed prompt copy. This is an
            # optimistic lock: even whitespace changes force a fresh review.
            digest = hashlib.sha256(
                f"{item['sourceTitle']}\n{item['sourceExcerpt']}".encode("utf-8")
            ).hexdigest()
            result = worker_request(
                f"/content/worker/news/{item['id']}/editorial-review",
                method="PATCH",
                body={
                    "sourceDigest": digest,
                    "titleZh": draft["title"],
                    "summaryZh": draft["summary"],
                    "titleEn": draft["titleEn"],
                    "summaryEn": draft["summaryEn"],
                    "draftModel": draft_model,
                    "reviewModel": review_model,
                    "reviewRuns": review_runs,
                    "checks": checks,
                    "findings": finding_lines,
                    "blockingFindings": blocking,
                },
            )
            state = result.get("editorialReviewStatus", "UNKNOWN")
            print(f"  完成：{state}", flush=True)
            succeeded += 1
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"  失败：{exc}", file=sys.stderr, flush=True)
        time.sleep(1)
    return succeeded, failed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--loop", action="store_true")
    parser.add_argument("--limit", type=int, default=int(os.getenv("EDITORIAL_BATCH_LIMIT", "5")))
    parser.add_argument(
        "--review-runs", type=int, default=int(os.getenv("EDITORIAL_REVIEW_RUNS", "3"))
    )
    args = parser.parse_args()
    if not 3 <= args.review_runs <= 5:
        raise SystemExit("review-runs 必须在 3 到 5 之间")

    interval = int(os.getenv("EDITORIAL_INTERVAL_SECONDS", "900"))
    while True:
        missing = [
            name
            for name in (
                "EDITORIAL_API_URL",
                "WORKER_API_KEY",
                "SUMMARIZER_BASE_URL",
                "SUMMARIZER_API_KEY",
            )
            if not os.getenv(name, "").strip()
        ]
        if missing:
            message = "自动编辑暂停，缺少环境变量：" + "、".join(missing)
            if not args.loop:
                raise SystemExit(message)
            print(message, flush=True)
        else:
            try:
                succeeded, failed = process_batch(args.limit, args.review_runs)
                print(f"本轮完成 {succeeded}，失败 {failed}", flush=True)
            except Exception as exc:  # noqa: BLE001
                if not args.loop:
                    raise
                print(f"本轮失败：{exc}", file=sys.stderr, flush=True)
        if not args.loop:
            break
        time.sleep(interval)


if __name__ == "__main__":
    main()
