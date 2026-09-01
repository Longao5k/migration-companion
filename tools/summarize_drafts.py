"""给待审新闻草稿生成中英文标题和摘要。

这个手动工具本身不发布任何东西。持续运行的自动编辑 worker 会把它的校验结果交给
服务器；服务器仅自动发布低风险内容，高风险或复核有冲突的内容仍进入人工队列。

密钥只从环境变量读，绝不写进代码或提交：

    export SUMMARIZER_API_KEY=...        # 模型服务的 key
    export SUMMARIZER_BASE_URL=...       # 与 API key 同地域的 OpenAI 兼容地址
    export SUMMARIZER_SSH_HOST=tencent-light   # 后台只监听回环，经 ssh 转发调用

后台密钥留在服务器上，本机不需要也不应该持有——脚本经 ssh 在服务器上读它。
反过来，模型密钥只留在本机，绝不上服务器。两把钥匙各在各的一侧。

用法：

    python tools/summarize_drafts.py --dry-run     # 只看会生成什么
    python tools/summarize_drafts.py               # 写回草稿
    python tools/summarize_drafts.py --limit 5     # 先试几条
    python tools/summarize_drafts.py --list-models # 看哪些模型还有额度
    python tools/summarize_drafts.py --apply out.json  # 改了验证规则后重放，不调模型

免费额度是**按模型**算的，不是按账号。默认按 DEFAULT_MODEL 里的顺序用，
前一个耗尽自动换下一个；七个都用完再用 --list-models 找替代，用 --model 指定。
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from datetime import datetime, timezone
import urllib.error
from urllib.request import Request, urlopen

# 默认模型链，按顺序用，前一个额度耗尽自动换下一个。
#
# 免费额度是**按模型**计的。原先写死一个 qwen3.8-27b，它耗尽的那天
# 73 条里有 23 条直接失败——而同一个 key 下当时还有二十多个模型有额度。
# 自动编辑默认让起草与复核使用不同模型家族：这里仅使用新加坡区有新用户
# 免费额度的 Qwen。DeepSeek 留给独立复核；Kimi/GLM 当前没有免费额度，
# 需要付费兜底时再通过环境变量显式加入。
DEFAULT_MODEL = ",".join([
    "qwen3.8-max",
    "qwen3.7-max-2026-06-08",
    "qwen3.8-flash",
])

# 这些混合思考模型允许显式关闭思考。编辑任务要求短、可验证的结构化转述，
# 不需要长思维链；关闭后还能显著减少免费额度消耗和单条延迟。
_NON_THINKING_MODELS = (
    "qwen3.8-",
    "qwen3.7-max",
    "deepseek-v4-pro",
    "deepseek-v4-flash",
)


def supports_non_thinking(model: str) -> bool:
    return model.lower().startswith(_NON_THINKING_MODELS)

# 产品规则的硬约束，写进提示词。这些不是风格偏好：
# 「不构成移民建议」是签核过的边界，越过它是 Migration Act s.276 的问题，不是文案问题。
SYSTEM_PROMPT = """你在为一个面向中国申请人的澳洲移民资讯工具撰写编辑稿。内容可能涉及技术移民、家庭、学生、工作、访客、人道、公民入籍或其他移民相关主题。

你的唯一任务是把官方公告的**事实**转述成中文。严格遵守：

1. 只写官方页面里写了的事实：数字、日期、类别、生效条件。原文没说的一个字都不要加。
2. 绝对不要给建议。不写「你应该」「建议申请」「值得考虑」「抓紧」这类话。
3. 绝对不判断任何人的资格。不写「符合条件者」「你可能有资格」这类推断。
4. 不预测结果、不预测审理时间、不预测未来政策走向。
5. 不暗示我们与政府有任何关系。不用「我们通知」「官方授权」这类措辞。
6. 不要整段翻译原文。用你自己的话概括，长度控制在原文之内。
7. 遇到具体数字（名额、门槛金额、职业数量、截止日期）必须准确保留，不要四舍五入、
   换算或改写；中英文必须保留原文中相同的阿拉伯数字串。例如原文写 `$10 million`，
   中文也写「$10 million（约一千万澳元）」而不能只写「1000万澳元」。
8. 专有名词保留英文并在首次出现时给中文，例如「意向登记（ROI）」「指定地区移民协议（DAMA）」。
9. **不要复述元数据。** 类别、制定日期、生效状态、注册标题这些，界面上已经单独显示，
   摘要里再写一遍等于没写。要写的是「这份文件管的是什么事、对谁有影响」——
   法规类内容的这个信息通常就在它的标题里，请把标题的含义讲成人话。
   反例：「该记录为立法文书，角色为主体法规，制定日期 2019-10-29，状态 InForce。」
   正例：「这份文书指定了 494 偏远地区雇主担保签证的职业评估机构，即哪些机构出具的
   评估函被接受。」

**同时给出中文和英文两份**。英文不是中文的机器翻译，是同一组事实的英文写法——
申请人常要把政策转述给雇主、律师或职业评估机构，那些场合要能直接用。
两份必须陈述同一组事实，数字完全一致。

输出严格的 JSON，不要 markdown 代码块，格式：
{"title": "……", "summary": "……", "titleEn": "…", "summaryEn": "…"}

title：不超过 40 个字，直接说最重要的那个事实（含数字优先），不要用「关于……的通知」这种空标题。
summary：2 到 4 句，不超过 300 字。
titleEn：不超过 90 个字符，同样直接说事实。
summaryEn：2 到 4 句，不超过 400 字符。"""

# 输出里出现这些词就打回。宁可少一条，不可发出一条带建议口吻的。
# 英文侧的同类词。中文拦住了不等于英文也拦住了。
# 这两张表挡的是**对读者的建议和资格判断**，不是「资格」这个词本身。
#
# 第一版里有裸的「有资格」和 "eligible for"，它们会把转述官方规则的句子
# 一并打回——「文件过期将没有资格获得 NSW 提名」是在复述规则，
# 正是这个工具该做的事；「你可能有资格申请 190」才是越界。
# 同理 "Employers are eligible for DAMA concessions" 是事实，
# "you may be eligible" 是判断。
#
# 收窄到第二人称与推测形态，是让这道闸对准真正的危险，不是放松它。
BANNED_EN = [
    "you should", "we recommend", "it is recommended", "applicants are recommended", "advisable",
    "you are eligible", "you may be eligible", "you may qualify", "you qualify",
    "likely to", "expected to be approved", "we advise",
]

BANNED = [
    "建议你", "建议申请", "你应该", "应尽快", "值得考虑", "不妨",
    "你有资格", "您有资格", "可能有资格", "符合条件的你", "你可能",
    "预计将", "料将", "有望",
    "我们通知", "本机构", "官方授权", "我们建议",
]


class ModelPool:
    """按顺序使用模型，某个模型额度耗尽就换下一个。

    免费额度是**按模型**计的，不是按账号。第一轮 73 条里 23 条失败，
    原因是我把「这个模型没额度了」当成了「没得用了」，撞上就停整轮——
    而同一个 key 下当时还有二十多个模型有额度。

    退役是单向的：一个模型报过额度耗尽就不再回头试，否则每条内容都要
    重新撞一遍同样的 403。
    """

    def __init__(self, models: list[str]) -> None:
        self.models = [m.strip() for m in models if m.strip()]
        if not self.models:
            raise SystemExit("至少要给一个模型")
        self.index = 0
        self.retired: list[str] = []

    @property
    def current(self) -> str:
        return self.models[self.index]

    def retire_current(self) -> bool:
        """当前模型不可用，换下一个。没有下一个就返回 False。"""
        self.retired.append(self.current)
        if self.index + 1 >= len(self.models):
            return False
        self.index += 1
        return True


def is_quota_error(exc: Exception) -> bool:
    text = str(exc).lower()
    return "quota" in text or "insufficient" in text or "arrearage" in text


def load_env_file(path: str) -> None:
    """从本地 env 文件补充环境变量。文件本身不进仓库。"""
    if not os.path.exists(path):
        return
    for line in io.open(path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"缺少环境变量 {name}")
    return value


def admin_request(path: str, *, method: str = "GET", body: dict | None = None):
    """经 ssh 在服务器上调后台接口。

    后台只监听回环，本机连不上。开隧道在这个环境里不稳（Windows 与 Git Bash 的 ssh
    用不同的密钥路径），而 `ssh host "curl ..."` 一直是可靠的——这一整轮部署都靠它。

    密钥在服务器的 .env 里现取，不经过本机，也不出现在命令行参数里（会进 ps 和历史）。
    """
    host = require("SUMMARIZER_SSH_HOST")
    remote = (
        'cd ~/migration-companion/infra/server && '
        'KEY=$(sed -n "s/^ADMIN_API_KEY=//p" ./.env | head -1) && '
        f'curl -sS -X {method} '
        '-H "x-admin-key: $KEY" '
    )
    if body is not None:
        remote += '-H "content-type: application/json" --data-binary @- '
    remote += f'"http://127.0.0.1:53101/v1{path}"'

    # 一轮写回是几十次串行 ssh，链路抖一下整轮就得从头再来（实测撞到过三次）。
    # 连接层的失败重试，业务层的错误照常抛出——curl 拿到 4xx 时 ssh 仍然返回 0，
    # 所以这里重试的只可能是连不上，不会把服务端的拒绝重放一遍。
    payload = json.dumps(body, ensure_ascii=False) if body is not None else None
    last = ""
    for attempt in range(4):
        result = subprocess.run(
            ["ssh", "-o", "ConnectTimeout=20", host, remote],
            input=payload,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=90,
        )
        if result.returncode == 0:
            break
        last = result.stderr.strip()[:300]
        if "onnect" not in last and "imed out" not in last:
            break
        time.sleep(4 * (attempt + 1))
    if result.returncode != 0:
        raise RuntimeError(f"后台调用失败：{last}")
    raw = result.stdout.strip()
    if not raw:
        return None
    parsed = json.loads(raw)
    # curl 拿到 4xx/5xx 时 ssh 仍然返回 0，错误 JSON 就这样被当成正常返回值收下。
    # 实测后果：一批写回全被 400 拒绝（字段超长），工具却报告「已写回 N 条」，
    # 库里一个字都没变。这正是这个项目里反复出现的那类静默失败。
    if isinstance(parsed, dict) and isinstance(parsed.get("statusCode"), int):
        if parsed["statusCode"] >= 400:
            message = parsed.get("message")
            if isinstance(message, list):
                message = "；".join(str(m) for m in message)
            raise RuntimeError(
                f"接口拒绝（HTTP {parsed['statusCode']}）：{str(message)[:300]}"
            )
    return parsed


def summarise(
    source_title: str,
    excerpt: str,
    model: str,
    *,
    previous_draft: dict | None = None,
    review_findings: list[str] | None = None,
) -> dict:
    user_content = f"官方标题：{source_title}\n\n官方正文摘录：\n{excerpt}"
    if previous_draft and review_findings:
        # 第一次独立复核发现冲突时，不把同一份稿子原样送审第二遍。
        # findings 只用于指出要修的地方；事实来源仍然只能是上面的官方摘录。
        user_content += (
            "\n\n上一版稿件未通过独立复核。请重新从官方摘录起草，不要仅做措辞润色，"
            "并删除所有无法由原文直接支持的细节。\n"
            f"上一版 JSON：{json.dumps(previous_draft, ensure_ascii=False)}\n"
            "复核发现：\n- "
            + "\n- ".join(str(item)[:300] for item in review_findings[:12])
        )
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": user_content,
            },
        ],
        # 低温度：这是事实转述，不是创作。同一段原文两次跑出不同数字是不能接受的。
        "temperature": 0.1,
        # 阿里云兼容接口的 JSON Object 模式保证响应本身是合法 JSON。
        # 提示词已经明确包含 JSON，且当前 Qwen 起草模型均关闭思考模式，
        # 符合服务端约束；否则偶发的半截 JSON 会让同一条每 15 分钟反复重跑。
        "response_format": {"type": "json_object"},
        # 长度由 validate() 检查，不用 token 上限截断 JSON。
    }
    if supports_non_thinking(model):
        body["enable_thinking"] = False
    request = Request(
        f"{require('SUMMARIZER_BASE_URL').rstrip('/')}/chat/completions",
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {require('SUMMARIZER_API_KEY')}",
            "Content-Type": "application/json",
        },
    )
    # 只重试真正可能自愈的错误：超时、连接问题、429 限流、5xx。
    #
    # 原先捕获的是 `(TimeoutError, URLError)`，而 `HTTPError` 是 `URLError` 的子类——
    # 于是 401、400、配额耗尽这类确定性错误也被重试三次，白等 18 秒，
    # 最后统一报成「三次调用都超时」，真实状态码被吞掉，看日志完全不知道发生了什么。
    last: Exception | None = None
    for attempt in range(3):
        try:
            # 网络拥塞或服务端限流仍可能造成长尾，因此保留较宽的网络超时；
            # 默认模型已显式关闭思考，不应再用数分钟生成不可见思维链。
            with urlopen(request, timeout=300) as response:
                payload = json.loads(response.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:200]
            if exc.code not in (429, 500, 502, 503, 504):
                raise RuntimeError(f"HTTP {exc.code}：{detail}") from None
            last = RuntimeError(f"HTTP {exc.code}：{detail}")
            time.sleep(5 * (attempt + 1))
        except (TimeoutError, urllib.error.URLError) as exc:
            last = exc
            time.sleep(3 * (attempt + 1))
    else:
        raise RuntimeError(f"三次都失败：{last}")
    message = payload["choices"][0]["message"]
    content = (message.get("content") or "").strip()
    if not content:
        # 空正文几乎总是被 max_tokens 截断：推理模型把额度花在思考上了。
        # 直接说清楚，不要留一个「Expecting value: line 1 column 1」让人去猜。
        reason = payload["choices"][0].get("finish_reason", "?")
        thinking = len(message.get("reasoning_content") or "")
        raise RuntimeError(
            f"模型只返回了思考过程、没有正文（finish_reason={reason}，"
            f"思考 {thinking} 字符）。多半是 max_tokens 不够。"
        )
    # 模型有时仍会裹一层代码块。
    content = re.sub(r"^```(?:json)?|```$", "", content, flags=re.M).strip()
    try:
        return json.loads(content)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"返回不是合法 JSON：{content[:150]}") from exc


# 摘要里要核对的数字：带千分位逗号的，或四位以上的纯数字。
#
# 原先是 `\d[\d,]{3,}`，它要求至少四个字符，于是把英文里的
# 「subclass 491, and…」当成了数字 491——而中文写「491签证」时只有三位，不匹配。
# 结果每条提到签证类别的英文摘要都会被判成「数字在原文里找不到」外加
# 「中英数字对不上」。签证类别恰好全是三位数，英文里后面又常跟逗号。
#
# 真正要防的是编造的名额、金额、门槛（实测抓到过 9224、6540），
# 那些要么四位以上，要么带千分位逗号。
NUMBER = re.compile(r"\d{1,3}(?:,\d{3})+|\d{4,}")


def display_width(text: str) -> int:
    """标题的显示宽度：汉字算 2，拉丁字母算 1。

    按字符数卡长度会误伤含英文专名的标题——「Migration Queensland」二十个字符，
    但它在屏幕上只占十个汉字的宽度。而系统提示词要求专有名词保留英文，
    于是这类标题被系统性打回（实测两条 43、44 字）。
    """
    return sum(
        2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
        for char in text
    )


def checks_performed(result: dict, excerpt: str, source_title: str) -> list[str]:
    """校验层实际验过哪些项，用人话写，直接显示在审核界面上。

    `validate` 返回的是「哪里不合格」，一条都没有时它返回空列表——而空列表
    传达不了任何信息。审的人真正需要的是反过来那一面：**哪些地方机器已经核过、
    我可以少看一眼，哪些没核过、必须我自己盯**。

    这些字符串会写进 NewsItem.draftChecks，在后台逐条列出来。
    不要在这里写没真正做过的检查——它的全部价值就在于可信。
    """
    summary = (result.get("summary") or "").strip()
    summary_en = (result.get("summaryEn") or "").strip()
    checked = [f"已与官方原文摘录逐项比对（{len(excerpt)} 字符）"]

    numbers = set(re.findall(NUMBER, summary)) | set(re.findall(NUMBER, summary_en))
    if numbers:
        listed = "、".join(sorted(numbers)[:6])
        checked.append(f"摘要中的数字均见于原文：{listed}")
        checked.append("中英两份数字一致")
    else:
        # 说清楚「没有数字可查」，而不是让人以为数字查过了。
        checked.append("摘要中没有需要核对的数字（四位以上或带千分位）")

    checked.append(f"未出现中文建议口吻词（{len(BANNED)} 项词表）")
    checked.append(f"未出现英文建议口吻词（{len(BANNED_EN)} 项词表）")
    checked.append("标题与摘要长度在上限内")

    # 校验层管不到的，明说。这几项只有人能判断，写出来是为了让人知道要盯哪里。
    checked.append(
        "以下未经机器核对，需人工判断：事实是否被曲解、"
        "日期与生效条件是否对应、是否遗漏关键限制条件"
    )
    return checked


def validate(
    result: dict,
    excerpt: str,
    known_year: str = "",
    source_title: str = "",
) -> list[str]:
    """返回问题列表；非空就不要写回，留给人处理。"""
    problems = []
    title = (result.get("title") or "").strip()
    summary = (result.get("summary") or "").strip()

    title_en = (result.get("titleEn") or "").strip()
    summary_en = (result.get("summaryEn") or "").strip()

    if not title or not summary:
        problems.append("中文标题或摘要为空")
        return problems
    if not title_en or not summary_en:
        problems.append("英文标题或摘要为空")
    if len(title_en) > 90:
        problems.append(f"英文标题 {len(title_en)} 字符，超过 90")
    # 英文上限不能照搬中文的 400：一个中文字承载的信息约等于两三个英文字符，
    # 同一组事实的英文写法天然长一倍多。第一版用 400 卡英文，打回的两条读下来
    # 都没有多余的话，纯粹是被单位不同的尺子量了。
    # 上限与中文上限成比例：中文摘要卡 300 字，一段忠实的英文转述约为其 2.4~2.7 倍。
    # 700 定得偏紧，一条无一句废话的完整转述实测 711 字符被打回。
    if len(summary_en) > 800:
        problems.append(f"英文摘要 {len(summary_en)} 字符，超过 800")
    if not re.search(r"[㐀-鿿]", title):
        problems.append("标题没有中文")
    if not re.search(r"[㐀-鿿]", summary):
        problems.append("摘要没有中文")
    # 40 个汉字 = 80 显示宽度。纯中文标题的上限一点没放松，
    # 只是不再把「Migration Queensland」当成二十个汉字那么宽。
    if display_width(title) > 80:
        problems.append(f"标题显示宽度 {display_width(title)}，超过 80（约 40 个汉字）")
    if len(summary) > 300:
        problems.append(f"摘要 {len(summary)} 字，超过 300")
    for word in BANNED:
        if word in title or word in summary:
            problems.append(f"出现建议/推断口吻：「{word}」")
    for word in BANNED_EN:
        if re.search(rf"\b{word}\b", summary_en, re.I):
            problems.append(f"英文摘要出现建议口吻：「{word}」")

    # 数字幻觉检查：摘要里出现的四位以上数字，原文里必须也有。
    # 名额和收入门槛写错一位，用户就会按错的数字做决定。
    # 语料含标题：「2023 - 24 Program closed」的年份写在标题里、摘录里没有，
    # 只比对摘录会把一条完全正确的稿子打回去（第一轮四条打回里就有这么一条）。
    corpus = source_title + " " + excerpt
    # 两种读法都算数：
    #   - 原样：让「+61 8 9224 6540」里的 9224 和 6540 各自成立；
    #   - 去空格：让原文里写成「40, 000」的数字也能对上摘要里的「40,000」。
    #
    # 只用去空格那一种会把相邻数字粘成一个：电话号码 +61 8 9224 6540 变成
    # 892246540，于是摘要里照抄的 9224 和 6540 双双「在原文中找不到」。
    # 我据此判过一条内容是模型编造数字——其实是这行代码编的。
    excerpt_digits = set(re.findall(NUMBER, corpus)) | set(
        re.findall(NUMBER, corpus.replace(" ", ""))
    )
    excerpt_plain = {d.replace(",", "") for d in excerpt_digits}
    # 发布年份是我们喂给模型的上下文，不是它编的。原文常只写「25 November」，
    # 年份要靠发布日期补，这是正确行为，不该打回。
    if known_year:
        excerpt_plain.add(known_year)
    for label, text in (("中文", summary), ("英文", summary_en)):
        for number in re.findall(NUMBER, text):
            if number.replace(",", "") not in excerpt_plain:
                problems.append(f"{label}摘要里的数字 {number} 在原文摘录中找不到")

    # 中英两份必须陈述同一组事实。数字对不上说明至少有一份是编的。
    zh_numbers = {n.replace(",", "") for n in re.findall(NUMBER, summary)}
    en_numbers = {n.replace(",", "") for n in re.findall(NUMBER, summary_en)}
    # 年份例外：只要它在标题或摘录里出现过，就不是模型编的。中英对同一个财年的
    # 惯用写法不同（中文「2023-24 年度」对英文「the 2024 program」），
    # 强求两边年份集合相同只会制造假警报。名额、金额、门槛这些实质数字仍然严格。
    known_years = set(re.findall(r"(?:19|20)\d{2}", corpus))
    if known_year:
        known_years.add(known_year)
    zh_numbers -= known_years
    en_numbers -= known_years
    if zh_numbers != en_numbers:
        problems.append(
            f"中英摘要的数字对不上：中文 {sorted(zh_numbers) or '无'}，"
            f"英文 {sorted(en_numbers) or '无'}"
        )
    return problems


def admin_patch_many(entries: list[dict]) -> dict:
    """一次 ssh 连接里做完全部 PATCH，返回 id 到 HTTP 状态码的映射。

    为什么不是循环调 `admin_request`：连发几十次 ssh 会被限流，第一次写回撞到三次
    「Connection timed out」，而单独手测同一台机器 4/4 都在一秒内连上。加重试没用——
    重试本身就是更多连接。Windows 的 OpenSSH 又不支持 ControlMaster 复用，
    所以把整批塞进一次连接：一行一条，`read -r id body` 按第一个空格切开，
    id 里没有空格，剩下的整段 JSON 原样进 body。
    """
    host = require("SUMMARIZER_SSH_HOST")
    remote = (
        "cd ~/migration-companion/infra/server && "
        'KEY=$(sed -n "s/^ADMIN_API_KEY=//p" ./.env | head -1) && '
        'while read -r id body; do '
        '  code=$(printf "%s" "$body" | curl -sS -o /dev/null -w "%{http_code}" '
        '    -X PATCH -H "x-admin-key: $KEY" -H "content-type: application/json" '
        '    --data-binary @- "http://127.0.0.1:53101/v1/content/admin/news/$id"); '
        '  echo "$id $code"; '
        "done"
    )
    payload = "".join(
        entry["id"] + " " + json.dumps(entry["body"], ensure_ascii=False) + chr(10)
        for entry in entries
    )
    # 这里当初漏了重试——只给 admin_request 加了。整批写回是一次连接，
    # 一次抖动就赔掉整批（实测连着赔了两批）。同样只重试连不上，
    # 服务端的拒绝照常抛出：curl 拿到 4xx 时 ssh 仍返回 0。
    last = ""
    for attempt in range(4):
        result = subprocess.run(
            ["ssh", "-o", "ConnectTimeout=20", host, remote],
            input=payload,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=600,
        )
        if result.returncode == 0:
            break
        last = result.stderr.strip()[:300]
        if "onnect" not in last and "imed out" not in last and "banner" not in last:
            break
        time.sleep(6 * (attempt + 1))
    if result.returncode != 0:
        raise RuntimeError("批量写回失败：" + last)
    codes = {}
    for line in result.stdout.split(chr(10)):
        parts = line.split()
        if len(parts) == 2:
            codes[parts[0]] = parts[1]
    return codes


def list_models() -> None:
    """列出端点上哪些文本模型还有额度。

    免费额度按模型计。默认链上的七个都用完时，用这个查还有什么能用，
    再用 --model 指定。每个模型只发一次 5 token 的请求，代价可忽略。
    """
    base = require("SUMMARIZER_BASE_URL").rstrip("/")
    key = require("SUMMARIZER_API_KEY")
    request = Request(base + "/models", headers={"Authorization": "Bearer " + key})
    with urlopen(request, timeout=60) as response:
        catalogue = json.loads(response.read().decode("utf-8"))

    # 图像、音频、翻译、向量这些模型接不了这个任务，不必浪费一次请求。
    skip = ("image", "audio", "video", "asr", "tts", "embedding", "rerank",
            "vl", "vq", "omni", "ocr", "mt-", "character", "search")
    names = sorted(
        entry.get("id", "")
        for entry in catalogue.get("data", [])
        if entry.get("id") and not any(word in entry["id"].lower() for word in skip)
    )
    print(f"文本模型 {len(names)} 个，逐个探测额度")
    print()

    usable = []
    for name in names:
        body = json.dumps({
            "model": name,
            "messages": [{"role": "user", "content": "回复一个字：好"}],
            "max_tokens": 5,
        }).encode("utf-8")
        probe = Request(
            base + "/chat/completions",
            data=body,
            headers={"Authorization": "Bearer " + key,
                     "Content-Type": "application/json"},
        )
        try:
            with urlopen(probe, timeout=90) as response:
                response.read()
            usable.append(name)
            print(f"  可用  {name}")
        except Exception:  # noqa: BLE001
            continue
        time.sleep(0.3)

    print()
    print(f"有额度 {len(usable)} 个。用法：--model " + ",".join(usable[:3]))


def apply_stored(path: str, items: dict, dry_run: bool) -> None:
    """重新校验一次存好的生成结果，把现在能通过的写回。

    存在的理由：验证器本身会出错。第一轮四条打回里有两条是尺子的问题——
    数字校验没看标题、英文长度上限照搬了中文的。改完尺子之后，那些稿子本身
    是好的，不该为了重新量一遍再花一次额度（何况额度可能已经没了）。
    """
    rows = json.load(io.open(path, encoding="utf-8"))
    written = skipped = missing = skipped_human = no_source = 0
    pending: list[dict] = []
    for row in rows:
        item = items.get(row["id"])
        if not item:
            missing += 1
            continue
        # 人写过的不覆盖。主流程靠「整条都缺才重写」保证这点，重放这条路径必须
        # 有同样的闸——否则改一次验证规则、重放一次结果文件，就会把编辑在后台
        # 逐字对照原文改出来的稿子，用模型的原稿悄悄盖回去。
        if item.get("draftAuthor") not in (None, "", "model"):
            skipped_human += 1
            continue
        excerpt = (item.get("sourceExcerpt") or "").strip()
        if not excerpt:
            # 同上：没有原文就没有可核对的基准，不能算「校验通过」。
            print(f"  跳过（无原文摘录）  {(row.get('title') or '')[:34]}")
            no_source += 1
            continue
        problems = validate(row, excerpt, row["publishedAt"][:4], row["sourceTitle"])
        if problems:
            print(f"  打回  {(row.get('title') or '')[:30]}  —— {'；'.join(problems)}")
            skipped += 1
            continue
        if item["isPublished"]:
            # 已发布的中文是审过的、正在用户眼前的文案，只补英文，绝不覆盖中文。
            #
            # 种子内容的 draftAuthor 是 null（直接经 Prisma 写入的），
            # 上面那道「人工改过就跳过」的闸拦不住它们——只看 draftAuthor
            # 会把人写的中文用模型稿盖掉。已发布本身就是「审过了」的证据。
            body = {
                "titleEn": row["titleEn"],
                "summaryEn": row["summaryEn"],
                # 已发布条目的中文是人写的，draftAuthor 保持不动；但英文是模型
                # 补的，溯源要留下——否则界面上没有任何东西说明这几段英文
                # 没有人看过。
                "draftModel": row.get("model", ""),
                "draftChecks": ["英文摘要由模型起草，中文为人工撰写"]
                + checks_performed(row, excerpt, row["sourceTitle"]),
            }
        else:
            body = {
                "titleZh": row["title"],
                "summaryZh": row["summary"],
                "titleEn": row["titleEn"],
                "summaryEn": row["summaryEn"],
                "draftAuthor": "model",
                # 重放走的是当初那次生成的结果，模型名从结果文件里带出来；
                # 老的结果文件没有这一项时留空，不要瞎猜一个填上去。
                "draftModel": row.get("model", ""),
                "draftChecks": checks_performed(row, excerpt, row["sourceTitle"]),
            }
        pending.append({"id": row["id"], "body": body})
        written += 1
    failed = []
    if pending and not dry_run:
        codes = admin_patch_many(pending)
        for entry in pending:
            code = codes.get(entry["id"], "无响应")
            if not code.startswith("2"):
                failed.append(f"{entry['id']} -> HTTP {code}")
                print(f"  写回被拒  {entry['id']}  HTTP {code}")
        written -= len(failed)

    verb = "可写回" if dry_run else "已写回"
    print()
    # 「打回」和「跳过」是两回事：打回是稿子有问题，跳过是我们没有原文可比对。
    # 混在一个数字里会让人以为模型出错了，其实是我们缺材料。
    print(
        f"{verb} {written}，打回 {skipped}，无原文跳过 {no_source}，"
        f"已不在草稿列表 {missing}，人工改过跳过 {skipped_human}"
    )
    for line in failed:
        print(f"  写回失败  {line}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument(
        "--model",
        default=os.environ.get("SUMMARIZER_MODEL", DEFAULT_MODEL),
        help="逗号分隔的模型顺序。免费额度按模型计，前一个耗尽自动换下一个。",
    )
    parser.add_argument("--env-file", default="")
    parser.add_argument(
        "--force-urls",
        default="",
        help="只处理这个 JSON 文件里列出的 sourceUrl，且无视「已经有中英文」的过滤。"
             "用于重新生成那些当初在没有官方原文的情况下写出来的稿子。",
    )
    parser.add_argument(
        "--include-published",
        action="store_true",
        help="把已发布但缺英文的条目也纳入。这些内容已经在用户眼前，"
             "模型稿直接写回等于绕过人工闸门——建议配 --dry-run 生成后过目，"
             "再用 --apply 写回。",
    )
    parser.add_argument(
        "--list-models",
        action="store_true",
        help="列出端点上还有额度的文本模型。默认链都用完时用它找替代。",
    )
    parser.add_argument(
        "--apply",
        default="",
        help="重新校验一次已有的结果文件并写回通过的，不调用模型。"
             "改了验证规则之后用它，不必为了换一把尺子重烧一遍额度。",
    )
    parser.add_argument(
        "--out",
        default="summaries.json",
        help="把生成结果另存一份，便于人工过目",
    )
    args = parser.parse_args()

    if args.env_file:
        load_env_file(args.env_file)

    if args.list_models:
        list_models()
        return

    items = admin_request("/content/admin/news")

    if args.apply:
        apply_stored(args.apply, {item["id"]: item for item in items}, args.dry_run)
        return

    # 默认只处理草稿。已发布的内容改动会立刻出现在用户面前，
    # 而这个工具产出的是模型稿——它编造过邀请人数，也写出过带建议口吻的句子。
    drafts = items if args.include_published else [
        item for item in items if not item["isPublished"]
    ]
    # 需要处理的：还没写中文的，或者写了中文但缺英文的。
    # 人手写过的中文不会被覆盖——只有整条都缺才会重写。
    drafts = [
        item
        for item in drafts
        if not re.search(r"[㐀-鿿]", item["titleZh"]) or not item.get("summaryEn")
    ]
    if args.force_urls:
        # 强制重跑：这些条目当初是在没有官方原文摘录的情况下生成的，
        # 摘要转写自上一版摘要，数字从未与官方页面比对过。现在原文补上了，
        # 必须拿真原文重写一遍——否则溯源里那句「已与官方原文逐项比对」是假的，
        # 而这份记录的全部价值就在于可信。
        wanted = set(json.loads(io.open(args.force_urls, encoding="utf-8").read()))
        drafts = [item for item in items if item["sourceUrl"] in wanted]
        missing = wanted - {item["sourceUrl"] for item in drafts}
        if missing:
            print(f"警告：{len(missing)} 个 URL 在库里找不到")
            for url in sorted(missing)[:5]:
                print("   ", url)

    drafts.sort(key=lambda item: item["publishedAt"])
    if args.limit:
        drafts = drafts[: args.limit]

    pool = ModelPool(args.model.split(","))
    # 起草时间在这一轮内固定：审的人关心的是「这批稿子是什么时候写的」，
    # 精确到每条秒级没有意义，反而让同一批看起来像来自不同时刻。
    now_iso = datetime.now(timezone.utc).isoformat()
    print(f"待处理草稿 {len(drafts)} 条")
    print("模型顺序：" + " → ".join(pool.models))
    print()
    written = skipped = failed = 0
    record = []
    exhausted = False

    for index, item in enumerate(drafts):
        if exhausted:
            break
        if index:
            time.sleep(1)
        excerpt = (item.get("sourceExcerpt") or "").strip()
        if not excerpt:
            # 没有原文摘录就不生成。
            #
            # 原先这里退回 item["summaryZh"]，也就是拿已有的中文摘要当「原文」
            # 再摘一次。后果有两层：产出是摘要的摘要，与官方页面隔了一手；
            # 而「摘要里的数字必须在原文中出现」那道校验比对的也是上一版摘要，
            # 于是它只能证明「这一版和上一版一致」，证明不了「与官方一致」——
            # 一个数字错了一位，只会被忠实地传下去。
            #
            # 实测线上有 12 条是这种情况（11 条昆士兰 + 1 条联邦法规），
            # 它们和另外 66 条在后台长得一模一样，看不出没经过原文核对。
            print(
                f"[{index + 1}/{len(drafts)}] 跳过（无原文摘录）"
                f"  {item['sourceTitle'][:44]}",
                flush=True,
            )
            skipped += 1
            continue
        # 开始之前就报一行。原先只在成功时打印，一条卡住就完全看不出跑到哪了——
        # 实际发生过：后台跑了 25 分钟，输出里只有开头两行，无法判断是慢还是死。
        print(f"[{index + 1}/{len(drafts)}] {item['sourceTitle'][:52]}", flush=True)
        result = None
        # 同一条内容在换模型之后重试。额度是按模型算的，换一个就继续，
        # 不该让这一条以及后面所有条陪着一起失败。
        while True:
            try:
                result = summarise(item["sourceTitle"], excerpt, pool.current)
                break
            except Exception as exc:  # noqa: BLE001
                if is_quota_error(exc):
                    print(f"  {pool.current} 额度耗尽，换下一个")
                    if pool.retire_current():
                        continue
                    print()
                    print("  候选模型都没有额度了，本轮停止。"
                          "已写回的不会被重复处理，补额度或加模型后重跑即可。")
                    exhausted = True
                    break
                print(f"  调用失败  {item['sourceTitle'][:50]}  {exc}")
                failed += 1
                break
        if result is None:
            continue

        problems = validate(
            result, excerpt, item["publishedAt"][:4], item["sourceTitle"]
        )
        record.append({
            "id": item["id"],
            "model": pool.current,
            "publishedAt": item["publishedAt"][:10],
            "sourceTitle": item["sourceTitle"],
            "title": result.get("title"),
            "summary": result.get("summary"),
            "titleEn": result.get("titleEn"),
            "summaryEn": result.get("summaryEn"),
            "problems": problems,
        })
        if problems:
            print(
                f"  打回  {result.get('title', '')[:30]}  —— {'；'.join(problems)}",
                flush=True,
            )
            skipped += 1
            continue
        if args.dry_run:
            written += 1
            continue
        if item["isPublished"]:
            # 已发布的中文正在用户眼前、且已经过审，只补英文。
            # 用模型稿覆盖审过的中文，是把一次审核成果直接抹掉。
            body = {"titleEn": result["titleEn"], "summaryEn": result["summaryEn"]}
        else:
            body = {
                "titleZh": result["title"],
                "summaryZh": result["summary"],
                "titleEn": result["titleEn"],
                "summaryEn": result["summaryEn"],
                # 标注是模型起草的：这类稿子要在后台逐字对照原文，
                # 它写出过「建议申请」这类带建议口吻的句子。
                "draftAuthor": "model",
                # 溯源随稿子一起走，审的人才知道是谁写的、验过哪些项。
                "draftModel": pool.current,
                "draftedAt": now_iso,
                "draftChecks": checks_performed(
                    result, excerpt, item["sourceTitle"]
                ),
            }
        admin_request(
            f"/content/admin/news/{item['id']}",
            method="PATCH",
            body=body,
        )
        print(f"  写回  {result['title'][:40]}", flush=True)
        written += 1

    with io.open(args.out, "w", encoding="utf-8") as handle:
        json.dump(record, handle, ensure_ascii=False, indent=2)

    verb = "可写回" if args.dry_run else "已写回"
    print(f"\n{verb} {written}，打回 {skipped}，调用失败 {failed}")
    if pool.retired:
        print("额度耗尽的模型：" + "、".join(pool.retired))
    print("当前使用：" + pool.current)
    print(f"全文已存到 {args.out}，请过目后再到后台发布。")


if __name__ == "__main__":
    main()
