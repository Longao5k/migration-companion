"""标签抽取。三个轴，各自独立。

**辖区不在标签里。** 它已经是一等字段（`source.jurisdiction`，接口也下发了）。
在 tags 里再留一份是双份真相，而且正是它把签证和主题标签挤没了——修完辖区标签之后，
筛选栏一度变成纯地理的，签证这个轴在界面上完全消失。

所以 tags 只承载两个轴：

- **签证类别**：封闭词表，只收与技术移民相关的类别。
- **主题**：封闭词表，主要由来源推导（`sources.json` 的 `topics`），标题关键词只作补充。

两个都是封闭词表：服务端拒绝表外的值。开放词表会让运营敲出 `SA`、`南澳`、`sa` 三种写法，
用户订阅其中一种就漏掉另外两种。
"""

import re

# 与技术移民相关的签证类别。用纯数字代码——申请人本来就用数字交流
# （「我走 190」「491 偏远」），加中文名反而不认。
#
# 不收：配偶签证（第一阶段不做，给了标签会造出「你们做配偶签证」的预期）、
# 已废止的 132/489（只出现在历史条目里，用「法规」主题标即可）。
VISA_SUBCLASSES = (
    "189", "190", "491", "494", "186", "482", "485", "462", "188", "888", "858",
)

# 必须有签证词邻接才认。
#
# 原先是 `if "190" in text` 这种子串判断，会命中日期、金额、条目编号。
# 宁可漏，不可错：漏了运营在后台补一下；错了就是把 482 的政策推给 491 的用户。
_VISA = re.compile(
    r"(?:subclass|sc\.?|visa|签证|类别)\s*[（(]?\s*(" + "|".join(VISA_SUBCLASSES) + r")\b"
    r"|\b(" + "|".join(VISA_SUBCLASSES) + r")\s*(?:visa|subclass|签证|类)",
    re.I,
)

TOPICS = (
    "职业清单", "邀请轮次", "提名条件", "申请材料", "审理时间",
    "打分规则", "英语要求", "费用", "法规", "项目开关", "活动",
)

# 标题关键词只作补充：主题的主要来源是 sources.json 里每个来源登记的 topics。
# 从来源推导比从标题猜可靠得多，而且接一个新来源时主题是先验已知的。
_TOPIC_HINTS = {
    "职业清单": re.compile(r"occupation list|skilled occupation|ANZSCO|occupations for", re.I),
    "邀请轮次": re.compile(r"invitation(?:s)? (?:issued|round)|invitations in", re.I),
    "提名条件": re.compile(r"eligibility|nomination requirement|nomination criteria", re.I),
    "申请材料": re.compile(r"document(?:s|ation) (?:required|checklist)|evidence required", re.I),
    "审理时间": re.compile(r"processing time|processing period", re.I),
    "打分规则": re.compile(r"points test|pass mark|pool mark", re.I),
    "英语要求": re.compile(r"english language|language test|IELTS|PTE\b", re.I),
    "费用": re.compile(r"application fee|nomination fee|\bcharge\b|VAC\b", re.I),
    "法规": re.compile(r"instrument|regulation|determination|\bact\b", re.I),
    "项目开关": re.compile(
        r"now open|has closed|closing|paused|allocation|places available|quota", re.I
    ),
    "活动": re.compile(r"roadshow|workshop|webinar|welcome to|career compass|event:", re.I),
}


def extract_tags(text: str, source_topics: tuple[str, ...] = ()) -> list[str]:
    """签证类别 + 主题。不含辖区——辖区是字段，不是标签。

    抽不出来就返回空列表。猜一个标签比不打标签糟：用户会因此收到不相关的提醒。
    """
    tags: list[str] = []

    for pair in _VISA.findall(text):
        code = pair[0] or pair[1]
        if code and code not in tags:
            tags.append(code)

    for topic in source_topics:
        if topic in TOPICS and topic not in tags:
            tags.append(topic)

    for topic, pattern in _TOPIC_HINTS.items():
        if topic not in tags and pattern.search(text):
            tags.append(topic)

    return tags
