"""Run a user-directed Agent final review over the human editorial queue.

Generation is read-only and writes a local JSON report. Applying that report is
an explicit second command with an item-by-item approval file. A plain id may
only approve a clean report row. A row with a model disagreement requires an
Agent decision note and explicit corrected fields. The API re-checks the
evidence digest and all deterministic content guards before publishing.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import time
from datetime import datetime, timezone

import editorial_worker as ew
import summarize_drafts as sd


def fresh_draft(item: dict, pool: sd.ModelPool, previous: dict | None = None,
                findings: list[str] | None = None) -> tuple[dict, str]:
    """Generate from the official excerpt, switching models on failure."""
    while True:
        model = pool.current
        last: Exception | None = None
        candidate = previous
        feedback = findings
        for _ in range(2):
            try:
                draft = sd.summarise(
                    item["sourceTitle"],
                    item["sourceExcerpt"].strip(),
                    model,
                    previous_draft=candidate,
                    review_findings=feedback,
                )
                problems = sd.validate(
                    draft,
                    item["sourceExcerpt"].strip(),
                    item["publishedAt"][:4],
                    item["sourceTitle"],
                )
                if not problems:
                    return draft, model
                last = RuntimeError("；".join(problems))
                candidate = draft
                feedback = problems
            except Exception as exc:  # noqa: BLE001
                last = exc
                if sd.is_quota_error(exc):
                    break
        if last is not None:
            if pool.retire_current():
                reason = "额度耗尽" if sd.is_quota_error(last) else "两次调用或内容校验失败"
                print(f"起草模型{reason}，切换到 {pool.current}", flush=True)
                continue
            raise last


def review_once(item: dict, draft: dict, draft_model: str,
                pool: sd.ModelPool, runs: int) -> tuple[list[dict], str]:
    return ew.review_draft(item, draft, draft_model, pool, runs)


def review_lines(findings: list[dict], runs: int) -> tuple[list[str], list[str]]:
    lines = [ew.finding_text(finding, runs) for finding in findings]
    blocking = [
        ew.finding_text(finding, runs)
        for finding in findings
        if finding.get("severity") == "high" or int(finding.get("votes") or 1) >= 2
    ]
    return lines, blocking


def make_body(item: dict, draft: dict, draft_model: str, review_model: str,
              runs: int, findings: list[str], blocking: list[str]) -> dict:
    excerpt = item["sourceExcerpt"].strip()
    digest = hashlib.sha256(
        f"{item['sourceTitle']}\n{item['sourceExcerpt']}".encode("utf-8")
    ).hexdigest()
    checks = [
        line
        for line in sd.checks_performed(draft, excerpt, item["sourceTitle"])
        if not line.startswith("以下未经机器核对")
    ]
    checks.append(f"Agent 最终复核：独立模型完成 {runs} 轮完整原文对照")
    return {
        "sourceDigest": digest,
        "titleZh": draft["title"],
        "summaryZh": draft["summary"],
        "titleEn": draft["titleEn"],
        "summaryEn": draft["summaryEn"],
        "draftModel": draft_model,
        "reviewModel": review_model,
        "reviewRuns": runs,
        "checks": checks,
        "findings": findings,
        "blockingFindings": blocking,
    }


def generate(path: str, limit: int, runs: int, selected_ids: set[str] | None = None) -> None:
    items = ew.worker_request("/content/worker/agent-review-queue") or []
    if selected_ids is not None:
        items = [item for item in items if item["id"] in selected_ids]
    if limit:
        items = items[:limit]
    draft_pool = sd.ModelPool(
        os.environ.get("EDITORIAL_DRAFT_MODELS", sd.DEFAULT_MODEL).split(",")
    )
    review_pool = sd.ModelPool(
        os.environ.get("EDITORIAL_REVIEW_MODELS", ew.cc.DEFAULT_MODEL).split(",")
    )
    report: list[dict] = []
    failed = 0
    print(f"Agent 最终复核队列 {len(items)} 条", flush=True)

    def save_progress() -> None:
        with io.open(path, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)

    for index, item in enumerate(items, 1):
        label = (item.get("titleZh") or item.get("sourceTitle") or item["id"])[:54]
        print(f"[{index}/{len(items)}] {label}", flush=True)
        try:
            draft, draft_model = fresh_draft(item, draft_pool)
            findings, review_model = review_once(
                item, draft, draft_model, review_pool, runs
            )
            finding_texts, blocking = review_lines(findings, runs)
            revised = False
            # One source-bound rewrite is useful when the reviewer finds a real
            # discrepancy. The second review starts fresh and must return clean;
            # old findings are retained in the report, not carried as current facts.
            first_findings = list(finding_texts)
            if finding_texts:
                revised = True
                draft, draft_model = fresh_draft(
                    item, draft_pool, previous=draft, findings=finding_texts
                )
                findings, review_model = review_once(
                    item, draft, draft_model, review_pool, runs
                )
                finding_texts, blocking = review_lines(findings, runs)

            body = make_body(
                item, draft, draft_model, review_model, runs, finding_texts, blocking
            )
            report.append({
                "id": item["id"],
                "title": item.get("titleZh") or item["sourceTitle"],
                "sourceTitle": item["sourceTitle"],
                "sourceUrl": item["sourceUrl"],
                "sourceExcerpt": item["sourceExcerpt"],
                "riskReasons": item.get("editorialRiskReasons") or [],
                "previousFindings": item.get("editorialFindings") or [],
                "firstPassFindings": first_findings,
                "revised": revised,
                "ready": not finding_texts,
                "body": body,
            })
            save_progress()
            print(
                "  可发布" if not finding_texts else f"  仍有 {len(finding_texts)} 项分歧",
                flush=True,
            )
        except Exception as exc:  # noqa: BLE001
            failed += 1
            report.append({"id": item["id"], "title": label, "ready": False, "error": str(exc)})
            save_progress()
            print(f"  失败：{exc}", flush=True)
        time.sleep(1)

    save_progress()
    ready = sum(1 for row in report if row.get("ready"))
    print(f"完成：可发布 {ready}，仍需处理 {len(report) - ready - failed}，失败 {failed}")
    print(f"报告：{path}")


COPY_FIELDS = {"titleZh", "summaryZh", "titleEn", "summaryEn"}


def approved_body(row: dict, approval: str | dict) -> dict:
    """Build a publish body without silently discarding reviewer findings."""
    body = dict(row.get("body") or {})
    if isinstance(approval, str):
        if not row.get("ready") or body.get("findings"):
            raise ValueError(f"{approval} 仍有分歧，必须提供逐条裁决和修正文案")
        return {**body, "finalAgentReview": True}
    if not isinstance(approval, dict) or approval.get("id") != row.get("id"):
        raise ValueError("批准项必须是 id 字符串，或带相同 id 的裁决对象")
    unknown_approval = set(approval) - {"id", "note", "overrides", "disposition"}
    if unknown_approval:
        raise ValueError(
            f"{row['id']} 含未知裁决字段：{', '.join(sorted(unknown_approval))}"
        )
    note = str(approval.get("note") or "").strip()
    overrides = approval.get("overrides") or {}
    disposition = approval.get("disposition") or "publish"
    if not note:
        raise ValueError(f"{row['id']} 的 Agent 裁决缺少说明")
    if disposition not in {"publish", "reference_only"}:
        raise ValueError(f"{row['id']} 的 Agent 处置必须是 publish 或 reference_only")
    if disposition == "publish" and (not isinstance(overrides, dict) or not overrides):
        raise ValueError(f"{row['id']} 的 Agent 裁决必须显式提供修正文案")
    if disposition == "reference_only" and not isinstance(overrides, dict):
        raise ValueError(f"{row['id']} 的修正文案必须是对象")
    unknown = set(overrides) - COPY_FIELDS
    if unknown:
        raise ValueError(f"{row['id']} 含不允许覆盖的字段：{', '.join(sorted(unknown))}")
    missing = COPY_FIELDS - set(overrides)
    if overrides and missing:
        raise ValueError(f"{row['id']} 必须完整提供双语标题和摘要")
    if len(note) > 250:
        raise ValueError(f"{row['id']} 的 Agent 裁决说明超过 250 字符")
    checks = list(body.get("checks") or [])
    checks.append(f"Agent 最终裁决：{note}")
    return {
        **body,
        **{field: str(overrides[field]).strip() for field in COPY_FIELDS if field in overrides},
        "checks": checks,
        "findings": [],
        "blockingFindings": [],
        "finalAgentReview": True,
        "finalAgentDisposition": disposition,
        "finalAgentReason": note,
    }


def apply_report(path: str, ids_path: str) -> None:
    rows = []
    for report_path in path.split(","):
        rows.extend(json.load(io.open(report_path.strip(), encoding="utf-8")))
    approved = json.load(io.open(ids_path, encoding="utf-8"))
    if not isinstance(approved, list) or not approved:
        raise SystemExit("批准文件必须是非空 JSON 数组")
    indexed = {row["id"]: row for row in rows}
    approval_ids = [entry if isinstance(entry, str) else entry.get("id") for entry in approved]
    if len(approval_ids) != len(set(approval_ids)):
        raise SystemExit("批准文件含重复 id")
    missing = set(approval_ids) - indexed.keys()
    if missing:
        raise SystemExit(f"批准列表里有 {len(missing)} 个报告中不存在的 id")

    # 先完整验证，再改第一条生产数据，避免第 N 条格式错误造成半批发布。
    prepared = []
    try:
        for approval in approved:
            item_id = approval if isinstance(approval, str) else approval.get("id")
            row = indexed[item_id]
            prepared.append((row, approved_body(row, approval)))
    except (KeyError, TypeError, ValueError) as exc:
        raise SystemExit(str(exc)) from None

    current = {
        item["id"]: item
        for item in (ew.worker_request("/content/worker/agent-review-queue") or [])
    }
    preflight_errors = []
    for row, body in prepared:
        item = current.get(row["id"])
        if item is None:
            preflight_errors.append(f"{row['id']} 已不在待复核队列")
            continue
        current_digest = hashlib.sha256(
            f"{item['sourceTitle']}\n{item['sourceExcerpt']}".encode("utf-8")
        ).hexdigest()
        if body.get("sourceDigest") != current_digest:
            preflight_errors.append(f"{row['id']} 的官方证据已更新，必须重新生成报告")
            continue
        draft = {
            "title": body["titleZh"],
            "summary": body["summaryZh"],
            "titleEn": body["titleEn"],
            "summaryEn": body["summaryEn"],
        }
        problems = sd.validate(
            draft,
            item["sourceExcerpt"].strip(),
            item["publishedAt"][:4],
            item["sourceTitle"],
        )
        if problems:
            preflight_errors.append(f"{row['id']}：{'；'.join(problems)}")
    if preflight_errors:
        raise SystemExit("批准文件预检失败，尚未发布任何内容：\n" + "\n".join(preflight_errors))

    done = 0
    for row, body in prepared:
        item_id = row["id"]
        result = ew.worker_request(
            f"/content/worker/news/{item_id}/editorial-review",
            method="PATCH",
            body=body,
        )
        expected_reference = body.get("finalAgentDisposition") == "reference_only"
        if expected_reference:
            if result.get("editorialReviewStatus") != "REFERENCE_ONLY" or result.get("isPublished"):
                raise RuntimeError(f"{item_id} 未进入 REFERENCE_ONLY")
        elif result.get("editorialReviewStatus") != "AUTO_APPROVED" or not result.get("isPublished"):
            raise RuntimeError(f"{item_id} 未进入 AUTO_APPROVED")
        done += 1
        action = "已归档" if expected_reference else "已发布"
        print(f"[{done}/{len(prepared)}] {action} {row['title'][:50]}", flush=True)
        time.sleep(0.5)
    print(f"已应用 {done} 条最终处置")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="agent-final-review.json")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--apply", default="", help="应用已有报告，不重新调用模型")
    parser.add_argument(
        "--ids",
        default="",
        help="逐条批准的 JSON 数组（干净稿用 id，修正稿用裁决对象）；与 --apply 同用",
    )
    parser.add_argument("--select", default="", help="生成时只复核这个 JSON id 数组")
    args = parser.parse_args()
    if not 3 <= args.runs <= 5:
        raise SystemExit("runs 必须在 3 到 5 之间")
    if args.apply:
        if not args.ids:
            raise SystemExit("--apply 必须同时提供 --ids，不能默认批准整份报告")
        apply_report(args.apply, args.ids)
        return
    selected_ids = None
    if args.select:
        selected_ids = set(json.load(io.open(args.select, encoding="utf-8")))
    generate(args.out, args.limit, args.runs, selected_ids)


if __name__ == "__main__":
    main()
