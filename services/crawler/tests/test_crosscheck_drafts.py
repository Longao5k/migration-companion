"""Regression tests for evidence-bound editorial cross-checking."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))

import crosscheck_drafts as cc  # noqa: E402


def test_final_comparison_receives_original_excerpt_when_fact_index_omits_claim(
    monkeypatch,
) -> None:
    """A lossy fact index must never become the final source of truth."""
    item = {
        "sourceTitle": "Move to South Australia Roadshow",
        "sourceExcerpt": (
            "This government-led initiative helps employers access talent "
            "that can be difficult to source locally."
        ),
        "sourceUrl": "https://migration.sa.gov.au/news/roadshow",
        "source": {"name": "Move to South Australia", "jurisdiction": "AU-SA"},
        "titleZh": "南澳赴英爱路演",
        "summaryZh": "该项目帮助雇主接触本地难以招聘的人才。",
        "titleEn": "South Australia roadshow",
        "summaryEn": "The initiative helps employers reach hard-to-source talent.",
    }
    calls: list[str] = []

    def fake_raw(model: str, system: str, user: str, attempts_left: int = 2) -> dict:
        del model, attempts_left
        calls.append(user)
        if system == cc.EXTRACT_PROMPT:
            # Reproduce the production false positive: extraction omitted the
            # sentence even though it is plainly present in the source excerpt.
            return {"dates": [], "numbers": [], "who": [], "conditions": [], "status": "路演"}

        assert "A. 官方原文摘录" in user
        assert "difficult to source locally" in user
        assert "B. 从官方原文独立提取的事实索引" in user
        assert "C. 我们写的摘要" in user
        return {"findings": []}

    monkeypatch.setattr(cc, "_raw", fake_raw)

    assert cc.crosscheck(item, "review-model", "2026-09-06") == []
    assert len(calls) == 2


def test_repeated_review_extracts_facts_once(monkeypatch) -> None:
    item = {
        "sourceTitle": "Official update",
        "sourceExcerpt": "Official fact.",
        "sourceUrl": "https://example.gov.au/update",
        "source": {"name": "Official source", "jurisdiction": "AU-FED"},
        "titleZh": "官方更新",
        "summaryZh": "官方公布更新。",
        "titleEn": "Official update",
        "summaryEn": "The authority published an update.",
    }
    extracted = 0
    compared = 0

    def fake_extract(candidate: dict, model: str) -> dict:
        nonlocal extracted
        del candidate, model
        extracted += 1
        return {"status": "update"}

    def fake_compare(candidate: dict, facts: dict, model: str, today: str) -> list[dict]:
        nonlocal compared
        del candidate, facts, model, today
        compared += 1
        return []

    monkeypatch.setattr(cc, "extract_facts", fake_extract)
    monkeypatch.setattr(cc, "compare_draft", fake_compare)
    monkeypatch.setattr(cc.time, "sleep", lambda _: None)

    assert cc.crosscheck_repeated(item, "review-model", "2026-09-06", 3) == []
    assert extracted == 1
    assert compared == 3


def test_repeated_review_never_counts_more_than_one_vote_per_run(monkeypatch) -> None:
    item = {
        "source": {"name": "Official", "jurisdiction": "AU-SA"},
        "sourceUrl": "https://example.gov.au/news/item",
        "sourceTitle": "Invitation table",
        "sourceExcerpt": "A table with multiple rows.",
        "titleZh": "标题",
        "summaryZh": "摘要",
        "titleEn": "Title",
        "summaryEn": "Summary",
    }
    monkeypatch.setattr(cc, "extract_facts", lambda *_: {})
    monkeypatch.setattr(
        cc,
        "compare_draft",
        lambda *_: [
            {"kind": "number", "severity": "high", "detail": "表格数字不符：A 行写成 17"},
            {"kind": "number", "severity": "high", "detail": "表格数字不符：B 行写成 18"},
        ],
    )
    monkeypatch.setattr(cc.time, "sleep", lambda *_: None)

    findings = cc.crosscheck_repeated(item, "review-model", "2026-09-06", 3)

    assert findings
    assert max(finding["votes"] for finding in findings) <= 3
