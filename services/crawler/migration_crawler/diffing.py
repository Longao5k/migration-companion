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


CANDIDATE_CONTEXT = "自动差异候选；必须回到官方页面判断真实含义。"


def make_candidate(
    old: str, new: str, source_name: str, body_chars: int = 0
) -> ChangeCandidate | None:
    if old == new:
        return None
    removed: list[str] = []
    added: list[str] = []
    for line in difflib.ndiff(old.splitlines(), new.splitlines()):
        if line.startswith("- "):
            removed.append(line[2:])
        elif line.startswith("+ "):
            added.append(line[2:])

    # 服务端按 old + new + context 合计计算，所以 context 必须先从预算里扣掉。
    # 不扣的话，长页面上 600 + 600 + len(context) = 1222 会越过 1200 的合计上限，
    # 真实政策变更会被我们自己的 API 以 400 拒绝——正是这段配额想避免的事。
    # 预算在改前/改后之间平分，各自再受单字段上限约束。
    budget = max(0, excerpt_budget(body_chars) - len(CANDIDATE_CONTEXT))
    per_field = min(EXCERPT_PER_FIELD, max(0, budget // 2))
    old_excerpt = "\n".join(removed)[:per_field]
    new_excerpt = "\n".join(added)[:per_field]
    combined = f"{old_excerpt}\n{new_excerpt}"
    return ChangeCandidate(
        title_zh=f"{source_name} 检测到页面变化",
        old_excerpt=old_excerpt,
        new_excerpt=new_excerpt,
        context="自动差异候选；必须回到官方页面判断真实含义。",
        importance=classify(combined),
    )

