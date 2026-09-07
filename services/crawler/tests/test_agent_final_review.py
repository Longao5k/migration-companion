"""Safety tests for explicit Agent approval files."""

from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))

import agent_final_review as agent_review  # noqa: E402


def row(ready=False):
    return {
        "id": "news-1",
        "ready": ready,
        "body": {
            "titleZh": "旧标题",
            "summaryZh": "旧摘要",
            "titleEn": "Old title",
            "summaryEn": "Old summary",
            "checks": ["三轮复核"],
            "findings": [] if ready else ["数字错误"],
            "blockingFindings": [] if ready else ["数字错误"],
        },
    }


def test_plain_id_only_approves_clean_row():
    body = agent_review.approved_body(row(ready=True), "news-1")
    assert body["finalAgentReview"] is True

    with pytest.raises(ValueError, match="必须提供逐条裁决"):
        agent_review.approved_body(row(), "news-1")


def test_agent_decision_requires_complete_corrected_bilingual_copy():
    with pytest.raises(ValueError, match="完整提供"):
        agent_review.approved_body(
            row(),
            {"id": "news-1", "note": "已核对", "overrides": {"titleZh": "新标题"}},
        )


def test_agent_decision_retains_audit_note_and_clears_resolved_findings():
    approval = {
        "id": "news-1",
        "note": "对照官方表格修正了本轮与累计列",
        "overrides": {
            "titleZh": "新标题",
            "summaryZh": "新摘要",
            "titleEn": "New title",
            "summaryEn": "New summary",
        },
    }
    body = agent_review.approved_body(row(), approval)
    assert body["titleZh"] == "新标题"
    assert body["findings"] == []
    assert body["blockingFindings"] == []
    assert body["checks"][-1].startswith("Agent 最终裁决：")
    assert body["finalAgentReview"] is True


def test_reference_only_decision_does_not_require_copy_override():
    body = agent_review.approved_body(
        row(),
        {
            "id": "news-1",
            "disposition": "reference_only",
            "note": "与已发布的官方联合新闻稿重复",
        },
    )
    assert body["finalAgentDisposition"] == "reference_only"
    assert body["finalAgentReason"] == "与已发布的官方联合新闻稿重复"
