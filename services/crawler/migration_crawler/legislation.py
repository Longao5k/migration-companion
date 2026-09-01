"""从联邦法规注册库拉取与澳洲移民相关的法规条目。

这是唯一能给出**联邦层面**政策记录的来源。内政部的说明页抓不到（边缘 403），
但法规本身在这里，而且法规才是有法律效力的那一份。

## 为什么不全收

`contains(name,'Migration')` 报 2453 条，实际能翻到约 999 条（API 有分页上限）。
但把 999 条法规标题倒进一个面向中文用户的 App，比现在少几十条更糟——用户看到的会是
一屏 `Migration Amendment (Class of Persons) Instrument 2024/12` 这种看不懂的东西，
而其中相当一部分是拘留设施、执法程序或其他不会帮助申请人理解签证变化的内容。

所以按两层筛：**时间**（默认 2024 年起，更早的已经被后续修正案取代）和
**相关性**（标题必须命中签证、公民、家庭、工作、学习、人道或移民服务词表）。
这不是只看 190/491 的筛选器；它覆盖第一阶段的全部澳洲移民类型。

## 摘录用元数据，不用法条原文

法条正文是 Crown copyright，而且我们的引用配额本来就只允许很短的摘录。
这里给摘要模型的是**结构化元数据**（名称、类别、制定日期、是否仍有效、是主体法规还是修正案），
不是法条文本。澳洲法规的标题本身描述性很强，配上这些元数据足够写出一句人话，
而真正要读条文的用户，App 里有直达官方页面的链接。
"""

import json
import re
import time
from urllib.parse import quote
from urllib.request import Request, urlopen

from .models import DiscoveredNews

API = "https://api.prod.legislation.gov.au/v1/titles"
PUBLIC_URL = "https://www.legislation.gov.au/{id}"

# 站点 robots 声明 Crawl-delay: 10，逐页翻的时候必须遵守。
CRAWL_DELAY_SECONDS = 10
PAGE_SIZE = 100
# API 实际最多给到约 1000 条；设一个上限避免无限翻页。
MAX_PAGES = 12

FIELDS = "id,name,makingDate,collection,isPrincipal,isInForce,status"
QUERY_TERMS = ("Migration", "Citizenship")

# 用户可理解的移民主题词表。命中任意一个才收。
#
# 这个表是「宁缺毋滥」的：漏掉一条边缘法规，用户还能在官网找到；
# 收进来一条拘留设施内部规则，用户会以为它和签证申请有关。
RELEVANCE = re.compile(
    r"\b("
    r"skill(?:ed)?|occupation|ANZSCO|nominat|sponsor|employer"
    # 复数要一起认：真实标题是「Language Tests, Test Scores」，
    # 写成 `language test` 加词边界反而匹配不上。
    r"|english|language tests?|test scores?|points test"
    r"|subclass\s*\d{3}"
    r"|general skilled|regional|designated area|DAMA"
    r"|work(?:place)? (?:justice|visa)|temporary skill|skills in demand"
    r"|student visa|visitor visa|working holiday|work and holiday"
    r"|partner visa|parent visa|child visa|family visa|prospective marriage"
    r"|humanitarian|refugee|protection visa|temporary protection|safe haven"
    r"|citizenship|permanent migration program|migration agent|immigration assistance"
    r"|arrival control|travel declaration|visa application charge"
    r")\b",
    re.I,
)


def _fetch_page(skip: int, term: str = "Migration") -> list[dict]:
    name_filter = quote(f"contains(name,'{term}')", safe="(),'")
    url = (
        f"{API}?$filter={name_filter}"
        f"&$select={FIELDS}&$top={PAGE_SIZE}&$skip={skip}"
    )
    request = Request(
        url,
        headers={
            "User-Agent": _user_agent(),
            "Accept": "application/json",
        },
    )
    with urlopen(request, timeout=90) as response:
        return json.loads(response.read().decode("utf-8")).get("value", [])


_UA_HOLDER: dict[str, str] = {}


def _user_agent() -> str:
    return _UA_HOLDER.get("value", "MigrationCompanionBot/1.0")


def set_user_agent(value: str) -> None:
    _UA_HOLDER["value"] = value


def fetch_titles() -> list[dict]:
    """翻页取回全部可达条目。

    服务端的 `$orderby` 会 500、日期与布尔筛选会 400，所以全部在本地筛——
    与其猜它支持哪种 OData 写法，不如只依赖确定可用的 `$skip`/`$top`。
    """
    rows: dict[str, dict] = {}
    request_index = 0
    for term in QUERY_TERMS:
        for page in range(MAX_PAGES):
            if request_index:
                time.sleep(CRAWL_DELAY_SECONDS)
            request_index += 1
            batch = _fetch_page(page * PAGE_SIZE, term)
            for row in batch:
                rows.setdefault(str(row.get("id")), row)
            if len(batch) < PAGE_SIZE:
                break
    return list(rows.values())


# 明确排除的主题。
#
# 光靠「命中技术移民词表」不够：`Migration (Regional Processing Country—Republic of
# Nauru) Designation 2023` 命中了 regional，但那是离岸处理国指定，和 190/491 毫无关系。
# 这条真的被收进过库里。包含式词表总会有这种漏，加一层排除比不断给 regional 打补丁稳。
EXCLUSIONS = re.compile(
    r"\b("
    r"regional processing|offshore|detention|detainee|prohibited things"
    r"|removal|deportation|character test"
    r"|maintenance amount|unlawful non-citizen"
    r")\b",
    re.I,
)


def is_relevant(row: dict, *, since: str) -> bool:
    """只保留仍然有效、够新、且标题命中移民主题词表的条目。"""
    making_date = (row.get("makingDate") or "")[:10]
    if not making_date or making_date < since:
        return False
    if not row.get("isInForce"):
        # 已失效的法规对正在准备申请的人没有意义，反而容易被误读成现行规定。
        return False
    name = row.get("name") or ""
    if EXCLUSIONS.search(name):
        return False
    return bool(RELEVANCE.search(name))


def describe(row: dict) -> str:
    """给摘要模型的元数据描述。是事实陈述，不是法条原文。"""
    kind = {
        "Act": "法案（Act）",
        "LegislativeInstrument": "立法文书（Legislative Instrument）",
        "NotifiableInstrument": "应通知文书（Notifiable Instrument）",
    }.get(row.get("collection") or "", row.get("collection") or "法规")
    role = "主体法规" if row.get("isPrincipal") else "对既有法规的修正"
    return (
        f"Type: {kind}. Role: {role}. "
        f"Made on {(row.get('makingDate') or '')[:10]}. "
        f"Status: {row.get('status') or 'unknown'}. "
        f"Registered title: {row.get('name')}. "
        "This record comes from the Federal Register of Legislation; "
        "the operative text is on the official page."
    )


def discover_legislation(since: str = "2024-01-01") -> list[DiscoveredNews]:
    items: list[DiscoveredNews] = []
    for row in fetch_titles():
        if not is_relevant(row, since=since):
            continue
        items.append(
            DiscoveredNews(
                title=row["name"],
                url=PUBLIC_URL.format(id=row["id"]),
                category="法规",
                published_at=f"{row['makingDate'][:10]}T12:00:00+00:00",
                excerpt=describe(row),
            )
        )
    return sorted(items, key=lambda item: item.published_at)
