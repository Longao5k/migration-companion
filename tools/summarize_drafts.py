"""给待审新闻草稿生成中文标题和摘要，写回后仍为草稿。

**这个工具不发布任何东西。** 它只把英文原文摘录变成中文编辑稿，发布仍然要人在后台
点一次。冻结规则里的人工闸门不因为摘要是机器写的就消失——恰恰相反，机器写的更需要人看。

密钥只从环境变量读，绝不写进代码或提交：

    export SUMMARIZER_API_KEY=...        # 模型服务的 key
    export SUMMARIZER_BASE_URL=...       # OpenAI 兼容地址
    export SUMMARIZER_SSH_HOST=tencent-light   # 后台只监听回环，经 ssh 转发调用

后台密钥留在服务器上，本机不需要也不应该持有——脚本经 ssh 在服务器上读它。
反过来，模型密钥只留在本机，绝不上服务器。两把钥匙各在各的一侧。

用法：

    python tools/summarize_drafts.py --dry-run     # 只看会生成什么
    python tools/summarize_drafts.py               # 写回草稿
    python tools/summarize_drafts.py --limit 5     # 先试几条
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
from urllib.request import Request, urlopen

DEFAULT_MODEL = "qwen3.8-27b"

# 产品规则的硬约束，写进提示词。这些不是风格偏好：
# 「不构成移民建议」是签核过的边界，越过它是 Migration Act s.276 的问题，不是文案问题。
SYSTEM_PROMPT = """你在为一个面向中国申请人的澳洲技术移民信息工具撰写中文编辑稿。

你的唯一任务是把官方公告的**事实**转述成中文。严格遵守：

1. 只写官方页面里写了的事实：数字、日期、类别、生效条件。原文没说的一个字都不要加。
2. 绝对不要给建议。不写「你应该」「建议申请」「值得考虑」「抓紧」这类话。
3. 绝对不判断任何人的资格。不写「符合条件者」「你可能有资格」这类推断。
4. 不预测结果、不预测审理时间、不预测未来政策走向。
5. 不暗示我们与政府有任何关系。不用「我们通知」「官方授权」这类措辞。
6. 不要整段翻译原文。用你自己的话概括，长度控制在原文之内。
7. 遇到具体数字（名额、门槛金额、职业数量、截止日期）必须准确保留，不要四舍五入或改写。
8. 专有名词保留英文并在首次出现时给中文，例如「意向登记（ROI）」「指定地区移民协议（DAMA）」。

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
BANNED_EN = [
    "you should", "we recommend", "recommended", "advisable", "eligible for",
    "you may qualify", "likely to", "expected to be approved", "we advise",
]

BANNED = [
    "建议你", "建议申请", "你应该", "应尽快", "值得考虑", "不妨",
    "有资格", "符合条件的你", "你可能", "预计将", "料将", "有望",
    "我们通知", "本机构", "官方授权", "我们建议",
]


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

    result = subprocess.run(
        ["ssh", host, remote],
        input=json.dumps(body, ensure_ascii=False) if body is not None else None,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )
    if result.returncode != 0:
        raise RuntimeError(f"后台调用失败：{result.stderr.strip()[:300]}")
    raw = result.stdout.strip()
    return json.loads(raw) if raw else None


def summarise(source_title: str, excerpt: str, model: str) -> dict:
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": f"官方标题：{source_title}\n\n官方正文摘录：\n{excerpt}",
            },
        ],
        # 低温度：这是事实转述，不是创作。同一段原文两次跑出不同数字是不能接受的。
        "temperature": 0.1,
        "max_tokens": 600,
    }
    request = Request(
        f"{require('SUMMARIZER_BASE_URL').rstrip('/')}/chat/completions",
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {require('SUMMARIZER_API_KEY')}",
            "Content-Type": "application/json",
        },
    )
    # 免费额度的服务偶尔会超时。一次失败就丢掉一条内容不值得，重试两次。
    last: Exception | None = None
    for attempt in range(3):
        try:
            with urlopen(request, timeout=180) as response:
                payload = json.loads(response.read().decode("utf-8"))
            break
        except (TimeoutError, urllib.error.URLError) as exc:
            last = exc
            time.sleep(3 * (attempt + 1))
    else:
        raise RuntimeError(f"三次调用都超时：{last}")
    content = payload["choices"][0]["message"]["content"].strip()
    # 模型有时仍会裹一层代码块。
    content = re.sub(r"^```(?:json)?|```$", "", content, flags=re.M).strip()
    return json.loads(content)


def validate(result: dict, excerpt: str, known_year: str = "") -> list[str]:
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
    if len(summary_en) > 400:
        problems.append(f"英文摘要 {len(summary_en)} 字符，超过 400")
    if not re.search(r"[㐀-鿿]", title):
        problems.append("标题没有中文")
    if not re.search(r"[㐀-鿿]", summary):
        problems.append("摘要没有中文")
    if len(title) > 40:
        problems.append(f"标题 {len(title)} 字，超过 40")
    if len(summary) > 300:
        problems.append(f"摘要 {len(summary)} 字，超过 300")
    for word in BANNED:
        if word in title or word in summary:
            problems.append(f"出现建议/推断口吻：「{word}」")
    for word in BANNED_EN:
        if re.search(rf"{word}", summary_en, re.I):
            problems.append(f"英文摘要出现建议口吻：「{word}」")

    # 数字幻觉检查：摘要里出现的四位以上数字，原文里必须也有。
    # 名额和收入门槛写错一位，用户就会按错的数字做决定。
    excerpt_digits = set(re.findall(r"\d[\d,]{3,}", excerpt.replace(" ", "")))
    excerpt_plain = {d.replace(",", "") for d in excerpt_digits}
    # 发布年份是我们喂给模型的上下文，不是它编的。原文常只写「25 November」，
    # 年份要靠发布日期补，这是正确行为，不该打回。
    if known_year:
        excerpt_plain.add(known_year)
    for label, text in (("中文", summary), ("英文", summary_en)):
        for number in re.findall(r"\d[\d,]{3,}", text):
            if number.replace(",", "") not in excerpt_plain:
                problems.append(f"{label}摘要里的数字 {number} 在原文摘录中找不到")

    # 中英两份必须陈述同一组事实。数字对不上说明至少有一份是编的。
    zh_numbers = {n.replace(",", "") for n in re.findall(r"\d[\d,]{3,}", summary)}
    en_numbers = {n.replace(",", "") for n in re.findall(r"\d[\d,]{3,}", summary_en)}
    if zh_numbers != en_numbers:
        problems.append(
            f"中英摘要的数字对不上：中文 {sorted(zh_numbers) or '无'}，"
            f"英文 {sorted(en_numbers) or '无'}"
        )
    return problems


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--model", default=os.environ.get("SUMMARIZER_MODEL", DEFAULT_MODEL))
    parser.add_argument("--env-file", default="")
    parser.add_argument(
        "--out",
        default="summaries.json",
        help="把生成结果另存一份，便于人工过目",
    )
    args = parser.parse_args()

    if args.env_file:
        load_env_file(args.env_file)

    items = admin_request("/content/admin/news")
    drafts = [item for item in items if not item["isPublished"]]
    # 需要处理的：还没写中文的，或者写了中文但缺英文的。
    # 人手写过的中文不会被覆盖——只有整条都缺才会重写。
    drafts = [
        item
        for item in drafts
        if not re.search(r"[㐀-鿿]", item["titleZh"]) or not item.get("summaryEn")
    ]
    drafts.sort(key=lambda item: item["publishedAt"])
    if args.limit:
        drafts = drafts[: args.limit]

    print(f"待处理草稿 {len(drafts)} 条，模型 {args.model}\n")
    written = skipped = failed = 0
    record = []

    for index, item in enumerate(drafts):
        if index:
            time.sleep(1)
        try:
            excerpt = item.get("sourceExcerpt") or item["summaryZh"]
            result = summarise(item["sourceTitle"], excerpt, args.model)
        except urllib.error.HTTPError as exc:
            print(f"  调用失败  {item['sourceTitle'][:50]}  HTTP {exc.code}")
            failed += 1
            continue
        except Exception as exc:  # noqa: BLE001
            print(f"  调用失败  {item['sourceTitle'][:50]}  {type(exc).__name__}")
            failed += 1
            continue

        problems = validate(result, excerpt, item["publishedAt"][:4])
        record.append({
            "id": item["id"],
            "publishedAt": item["publishedAt"][:10],
            "sourceTitle": item["sourceTitle"],
            "title": result.get("title"),
            "summary": result.get("summary"),
            "titleEn": result.get("titleEn"),
            "summaryEn": result.get("summaryEn"),
            "problems": problems,
        })
        if problems:
            print(f"  打回  {result.get('title', '')[:30]}  —— {'；'.join(problems)}")
            skipped += 1
            continue
        if args.dry_run:
            written += 1
            continue
        admin_request(
            f"/content/admin/news/{item['id']}",
            method="PATCH",
            body={
                "titleZh": result["title"],
                "summaryZh": result["summary"],
                "titleEn": result["titleEn"],
                "summaryEn": result["summaryEn"],
                # 标注是模型起草的：这类稿子要在后台逐字对照原文，
                # 它编造过邀请人数，也写出过「建议申请」。
                "draftAuthor": "model",
            },
        )
        print(f"  写回  {result['title'][:40]}")
        written += 1

    with io.open(args.out, "w", encoding="utf-8") as handle:
        json.dump(record, handle, ensure_ascii=False, indent=2)

    verb = "可写回" if args.dry_run else "已写回"
    print(f"\n{verb} {written}，打回 {skipped}，调用失败 {failed}")
    print(f"全文已存到 {args.out}，请过目后再到后台发布。")


if __name__ == "__main__":
    main()
