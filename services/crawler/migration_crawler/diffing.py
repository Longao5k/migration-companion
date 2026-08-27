import difflib
import re
from .models import ChangeCandidate, Importance

MAJOR_TERMS = re.compile(r"\b(?:closed|suspended|ceased|withdrawn|abolished|not accepting)\b", re.I)
IMPORTANT_TERMS = re.compile(
    r"\b(?:eligibility|requirement|occupation|invitation|nomination|fee|deadline|points?|income|age|English)\b",
    re.I,
)


def classify(changed_text: str) -> Importance:
    if MAJOR_TERMS.search(changed_text):
        return "MAJOR"
    if IMPORTANT_TERMS.search(changed_text):
        return "IMPORTANT"
    return "GENERAL"


def make_candidate(old: str, new: str, source_name: str) -> ChangeCandidate | None:
    if old == new:
        return None
    removed: list[str] = []
    added: list[str] = []
    for line in difflib.ndiff(old.splitlines(), new.splitlines()):
        if line.startswith("- "):
            removed.append(line[2:])
        elif line.startswith("+ "):
            added.append(line[2:])
    old_excerpt = "\n".join(removed)[:2000]
    new_excerpt = "\n".join(added)[:2000]
    combined = f"{old_excerpt}\n{new_excerpt}"
    return ChangeCandidate(
        title_zh=f"{source_name} 检测到页面变化",
        old_excerpt=old_excerpt,
        new_excerpt=new_excerpt,
        context="自动差异候选；必须回到官方页面判断真实含义。",
        importance=classify(combined),
    )

