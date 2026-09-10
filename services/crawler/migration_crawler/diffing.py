import difflib
import re
from .models import ChangeCandidate, Importance

# 引用配额必须与 services/api/src/content/excerpt-quota.ts 保持一致。
# 采集器如果按更宽的配额产出，API 会以 HTTP 400 拒绝，该来源本轮直接失败——
# 也就是说真实政策变更会被我们自己的规则吃掉，而且只有在真的变更时才暴露。
EXCERPT_PER_FIELD = 600
EXCERPT_COMBINED = 1200
EXCERPT_BODY_RATIO = 0.2

MAJOR_TERMS = re.compile(r"\b(?:closed|suspended|ceased|withdrawn|abolished|not accepting)\b", re.I)
IMPORTANT_TERMS = re.compile(
    r"\b(?:eligibility|requirement|occupation|invitation|nomination|fee|deadline|points?|income|age|English)\b",
    re.I,
)

TIMESTAMP_ONLY = re.compile(
    r"^(?:lastmod\s*[:=]?\s*)?\d{4}-\d{2}-\d{2}(?:[T\s]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?$",
    re.I,
)
MAINTENANCE_NOISE = re.compile(
    r"(?:scheduled maintenance|temporarily unavailable due to maintenance|online services? (?:will be|are) unavailable)",
    re.I,
)


def classify(changed_text: str) -> Importance:
    if MAJOR_TERMS.search(changed_text):
        return "MAJOR"
    if IMPORTANT_TERMS.search(changed_text):
        return "IMPORTANT"
    return "GENERAL"


def excerpt_budget(body_chars: int) -> int:
    """本次候选可以引用的官方原文总字符数。

    固定上限挡长页面，比例上限挡短页面：只有固定上限时，两千多字的短页面
    仍然可能被整页引用。
    """
    if body_chars > 0:
        return max(0, min(EXCERPT_COMBINED, int(body_chars * EXCERPT_BODY_RATIO)))
    return EXCERPT_COMBINED


CANDIDATE_CONTEXT = "官方页面内容更新候选；发布前须核对完整页面与上下文。"


def _noise_only(changed_lines: list[str]) -> bool:
    meaningful = [
        re.sub(r"<[^>]+>", "", line).strip(" \t-+")
        for line in changed_lines
        if line.strip(" \t-+")
    ]
    if not meaningful:
        return True
    return all(
        TIMESTAMP_ONLY.fullmatch(line) is not None
        or MAINTENANCE_NOISE.search(line) is not None
        for line in meaningful
    )


def _contextual_excerpts(old: str, new: str) -> tuple[str, str, list[str]]:
    """Produce a compact, git-like comparison with unchanged lines for context."""
    old_lines = old.splitlines()
    new_lines = new.splitlines()
    matcher = difflib.SequenceMatcher(None, old_lines, new_lines, autojunk=False)
    old_output: list[str] = []
    new_output: list[str] = []
    changed: list[str] = []
    groups = list(matcher.get_grouped_opcodes(n=3))
    for group_index, group in enumerate(groups):
        if group_index:
            old_output.append("  …")
            new_output.append("  …")
        for tag, i1, i2, j1, j2 in group:
            if tag == "equal":
                old_output.extend(f"  {line}" for line in old_lines[i1:i2])
                new_output.extend(f"  {line}" for line in new_lines[j1:j2])
            elif tag == "delete":
                old_output.extend(f"- {line}" for line in old_lines[i1:i2])
                changed.extend(old_lines[i1:i2])
            elif tag == "insert":
                new_output.extend(f"+ {line}" for line in new_lines[j1:j2])
                changed.extend(new_lines[j1:j2])
            else:
                old_output.extend(f"- {line}" for line in old_lines[i1:i2])
                new_output.extend(f"+ {line}" for line in new_lines[j1:j2])
                changed.extend(old_lines[i1:i2])
                changed.extend(new_lines[j1:j2])
    return "\n".join(old_output), "\n".join(new_output), changed


def make_candidate(
    old: str, new: str, source_name: str, body_chars: int = 0
) -> ChangeCandidate | None:
    if old == new:
        return None
    old_context, new_context, changed = _contextual_excerpts(old, new)
    if _noise_only(changed):
        return None

    # 服务端按 old + new + context 合计计算，所以 context 必须先从预算里扣掉。
    # 不扣的话，长页面上 600 + 600 + len(context) = 1222 会越过 1200 的合计上限，
    # 真实政策变更会被我们自己的 API 以 400 拒绝——正是这段配额想避免的事。
    # 预算在改前/改后之间平分，各自再受单字段上限约束。
    budget = max(0, excerpt_budget(body_chars) - len(CANDIDATE_CONTEXT))
    per_field = min(EXCERPT_PER_FIELD, max(0, budget // 2))
    old_excerpt = old_context[:per_field]
    new_excerpt = new_context[:per_field]
    combined = f"{old_excerpt}\n{new_excerpt}"
    return ChangeCandidate(
        title_zh=f"{source_name} 页面内容更新",
        title_en=f"{source_name} content update",
        old_excerpt=old_excerpt,
        new_excerpt=new_excerpt,
        context=CANDIDATE_CONTEXT,
        importance=classify("\n".join(changed)),
    )
