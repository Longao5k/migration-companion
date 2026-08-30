"""辖区代码与中文标签的唯一对照表。

采集器给条目打标签时必须走这里，不能各处自己拼。

起因是一次真实事故：`submit_news_draft` 里写死了 `tags = ["南澳"]`，接入昆士兰、
西澳、NSW 和联邦法规之后，**47 条内容全部带着「南澳」标签入库**——昆士兰的提名
政策在 App 里显示为南澳的政策。移民产品里这种错会让人按错误的州准备材料。

覆盖八个州领地，不是只覆盖当前接入的那几个：下一次接入新的州时，忘了改这里会
立刻报错（`label_for` 抛异常），而不是安静地又打成南澳。
"""

JURISDICTION_LABELS = {
    "AU-SA": "南澳",
    "AU-QLD": "昆士兰",
    "AU-NSW": "新南威尔士",
    "AU-VIC": "维州",
    "AU-WA": "西澳",
    "AU-TAS": "塔州",
    "AU-NT": "北领地",
    "AU-ACT": "首都领地",
    "AU-FED": "联邦",
}


def label_for(jurisdiction: str) -> str:
    """辖区代码转中文标签。未知代码直接抛错，不猜、不退回默认值。

    退回默认值正是上一次事故的形态：一个错误的辖区标签比没有标签危险得多，
    因为它看起来是对的。
    """
    try:
        return JURISDICTION_LABELS[jurisdiction]
    except KeyError:
        raise ValueError(
            f"未知辖区代码 {jurisdiction!r}；请先在 jurisdictions.py 里登记它的中文标签，"
            "不要让它退回默认值。"
        ) from None
