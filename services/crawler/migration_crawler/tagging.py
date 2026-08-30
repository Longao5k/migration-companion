"""从标题与正文摘录里抽取标签。

原先是两行硬编码子串判断：

    if "190" in searchable: tags.append("190")
    if "491" in searchable: tags.append("491")

于是 78 条内容里只有 190/491 有签证标签，而联邦法规里的「Subclass 485 英语要求」
「Subclass 494 职业清单」「Subclass 417 工作豁免」一个标签都没有——用户订阅 485
收不到任何东西，App 里也筛不出来。

这里按**已知的签证类别白名单 + 词边界**抽取，不做开放式的三位数匹配：
「2000 places」「3,000 nomination places」这类数字不是签证类别，收进去会让用户
以为某条名额公告和某个签证有关。
"""

import re

# 与技术移民相关的签证类别。不求覆盖澳洲全部签证——收进无关的类别，
# 等于告诉用户这条内容和他的签证有关。
VISA_SUBCLASSES = {
    # 技术移民主线
    "189": "189",
    "190": "190",
    "191": "191",
    "491": "491",
    "494": "494",
    "489": "489",
    # 雇主担保
    "482": "482",
    "186": "186",
    "187": "187",
    "407": "407",
    # 毕业生与学生
    "485": "485",
    "500": "500",
    "476": "476",
    # 打工度假（州担保页面常一起公布）
    "417": "417",
    "462": "462",
    # 商业与投资
    "188": "188",
    "888": "888",
    "132": "132",
    # 国家创新签证
    "858": "858",
}

_SUBCLASS = re.compile(r"\b(" + "|".join(sorted(VISA_SUBCLASSES)) + r")\b")

# 主题标签。命中即打，用于「关注 DAMA」「关注职业清单」这类订阅。
TOPIC_PATTERNS = {
    "职业清单": re.compile(r"occupation list|skilled occupation|ANZSCO|occupations for", re.I),
    "名额": re.compile(r"\ballocation|nomination places|places available|quota\b", re.I),
    "邀请数据": re.compile(r"invitation(?:s)? (?:issued|round)|invitations in", re.I),
    "ROI": re.compile(r"registration of interest|\bROI\b", re.I),
    "DAMA": re.compile(r"\bDAMA\b|designated area migration agreement", re.I),
    "英语要求": re.compile(r"english language|language test|IELTS|PTE\b", re.I),
    "薪资门槛": re.compile(r"\bTSMIT\b|income threshold|salary threshold", re.I),
    "职业评估": re.compile(r"assessing authorit|skills assessment", re.I),
    "雇主担保": re.compile(r"employer sponsor|employer nomination|sponsorship", re.I),
    "审理进度": re.compile(r"processing time|processing period", re.I),
}


def extract_tags(jurisdiction_label: str, text: str, category: str = "") -> list[str]:
    """辖区标签在前，其后是签证类别与主题标签。去重并保持稳定顺序。

    辖区一定有；签证类别和主题可能一个都没有——那说明这条内容是通用公告，
    宁可不打标签，也不要猜一个让用户误订阅。
    """
    tags = [jurisdiction_label]

    for number in _SUBCLASS.findall(text):
        label = VISA_SUBCLASSES[number]
        if label not in tags:
            tags.append(label)

    for label, pattern in TOPIC_PATTERNS.items():
        if pattern.search(text) and label not in tags:
            tags.append(label)

    cleaned = (category or "").strip()
    # 站点自己的分类名（「Other news」这种）没有订阅价值，不收。
    if cleaned and cleaned.lower() not in {"other news", "news", ""} and cleaned not in tags:
        tags.append(cleaned)

    return tags
