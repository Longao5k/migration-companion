"""用另一个模型独立复核编辑稿，找出人该重点看的地方。

**这个工具不代替人工审核，也不改 `draftAuthor`。** 它做的是体检，不是签字。
「重要政策变更必须人工核实后才能发布」是签核过的规则，把 agent 的结论标成
`editor` 等于让那个标记变成谎话——而整套闸门存在的理由就是不要假保证。

它解决的是另一个问题：`draftChecks` 里那句「未经机器核对」列了三项，
恰恰是最容易出事的——事实是否被曲解、日期与生效条件是否对应、
**是否遗漏关键限制条件**。最后一条尤其危险：漏写不会触发任何现有校验，
摘要里每个字都对，只是少了「仅限已获邀请者」那半句。

做法是两次调用，顺序不能反：

1. **盲测提取**：只给官方原文，不给我们的稿子，让模型独立列出关键事实。
   先给稿子会让它附和——那就查不出任何东西了。
2. **对照**：把盲测结果和我们的稿子放在一起，找分歧。

用与起草不同的模型家族（稿子出自 deepseek / qwen，复核用 kimi / glm）。
同一个模型的失效方式是相关的，用它查自己等于没查。

用法：

    python tools/crosscheck_drafts.py --env-file <env> --dry-run   # 只看结果
    python tools/crosscheck_drafts.py --env-file <env>             # 结果写回 draftChecks
    python tools/crosscheck_drafts.py --env-file <env> --limit 5
"""

import argparse
import importlib.util
import io
import json
import os
import sys
import time

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "summarize_drafts", os.path.join(_here, "summarize_drafts.py")
)
sd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sd)

# 与起草不同的家族。稿子是 deepseek-v4-pro / qwen3.8-27b 写的。
DEFAULT_MODEL = ",".join(["kimi-k3", "glm-5.2", "deepseek-v4-flash-0731"])

EXTRACT_PROMPT = """你在核对一份澳洲移民官方公告。

只读下面的官方原文，列出其中的关键事实。不要评论，不要补充原文没有的内容，
不要给建议。原文没写的，就写「原文未说明」。

输出严格的 JSON，不要 markdown 代码块：
{
  "dates": ["原文中出现的每一个日期及其含义，例如「2026-01-01 起新费用生效」"],
  "numbers": ["原文中的每一个数量、金额、门槛及其含义"],
  "who": ["这份公告适用于谁，原文怎么说的"],
  "conditions": ["原文写明的限制条件、前提、例外。这一项尤其重要，逐条列全"],
  "status": "这份公告在说什么事（开放/关闭/调整/延长/公布数据/其他）"
}"""

COMPARE_PROMPT = """你在做事实核对。下面有两样东西：

A. 从官方原文里独立提取出来的事实清单
B. 我们写的中文摘要和英文摘要

找出 B 相对 A 的问题。只报你有把握的，不确定就不要报——误报会让人失去对
这份核对的信任，比漏报更糟。

要找五类：
- unsupported：B 里有某个说法，A 里找不到依据
- omission：A 里有**关键限制条件或适用范围**，B 完全没提。
  这一类最重要：漏写不会被任何自动校验发现，而它会让读者以为自己适用。
- date：日期对不上，或把某个日期的含义搞错了（例如把截止日说成生效日）
- number：数量、金额、门槛对不上
- zh_en_mismatch：**中文和英文陈述的事实不一致**——一边写了某个适用前提、
  限制条件或数字，另一边没有。这不是措辞差异，是两个版本说了不同的话。
  申请人常拿英文版转述给雇主和律师，两版不一致会让他们据以行动的信息出错。

输出严格的 JSON，不要 markdown 代码块：
{
  "findings": [
    {"kind": "unsupported|omission|date|number|zh_en_mismatch",
     "severity": "high|low",
     "detail": "一句话说清楚：原文说什么，摘要说了什么"}
  ]
}

没有问题就返回 {"findings": []}。

**severity 判定**——high 的标准是：一个申请人照着这份摘要行动会做出错误决定。
- high 的例子：漏掉「仅限已获邀请者」「本地招聘失败才适用」这类适用前提
  （中文或英文任一版漏掉都算）；把截止日说成生效日；名额、门槛金额写错。
- low 的例子：措辞比原文稍强或稍弱；补充了原文没有但无害的背景。

**不要报的**（这些不是问题）：
- 时态与「今天」一致而与原文不一致。今天是 {today}。原文写于事件发生之前，
  用将来时；如果那个日期已经过去，摘要用过去时是正确的，不要报。
- 摘要比原文短。概括本来就要取舍，只有漏掉**上面 high 例子那类**的
  适用前提和限制条件才算 omission。
- 专有名词保留英文；中英文的措辞、语序、句子拆分方式不同。
  （但两版**陈述的事实**不同要报，那是 zh_en_mismatch。）"""

KIND_LABEL = {
    "unsupported": "原文无依据",
    "omission": "遗漏限制条件",
    "date": "日期不符",
    "number": "数字不符",
    "zh_en_mismatch": "中英说法不一致",
}


# 有些模型不接受 temperature（kimi-k3 直接 400）。记下来，之后不再给它带。
# 低温度对事实核对是有意义的，所以默认还是带上，只对拒绝的模型省略——
# 而不是为了兼容所有模型把它整个去掉。
_NO_TEMPERATURE: set[str] = set()


def _raw(model: str, system: str, user: str) -> dict:
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }
    if model not in _NO_TEMPERATURE:
        body["temperature"] = 0.1
    request = sd.Request(
        f"{sd.require('SUMMARIZER_BASE_URL').rstrip('/')}/chat/completions",
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {sd.require('SUMMARIZER_API_KEY')}",
            "Content-Type": "application/json",
        },
    )
    last = None
    for attempt in range(3):
        try:
            with sd.urlopen(request, timeout=300) as response:
                payload = json.loads(response.read().decode("utf-8"))
            break
        except sd.urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:200]
            if exc.code == 400 and "temperature" in detail:
                # 这个模型不吃 temperature。去掉重来一次，并记下来，
                # 后面的每一次调用都不再带——否则每条内容都要白撞一次。
                _NO_TEMPERATURE.add(model)
                body.pop("temperature", None)
                request.data = json.dumps(body, ensure_ascii=False).encode("utf-8")
                continue
            if exc.code not in (429, 500, 502, 503, 504):
                raise RuntimeError(f"HTTP {exc.code}：{detail}") from None
            last = RuntimeError(f"HTTP {exc.code}：{detail}")
            time.sleep(5 * (attempt + 1))
        except Exception as exc:  # noqa: BLE001
            last = exc
            time.sleep(4 * (attempt + 1))
    else:
        raise RuntimeError(f"三次都失败：{last}")

    message = payload["choices"][0]["message"]
    content = (message.get("content") or "").strip()
    if not content:
        reason = payload["choices"][0].get("finish_reason", "?")
        raise RuntimeError(f"模型只返回了思考过程（finish_reason={reason}）")
    content = sd.re.sub(r"^```(?:json)?|```$", "", content, flags=sd.re.M).strip()
    try:
        return json.loads(content)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"返回不是合法 JSON：{content[:150]}") from exc


def crosscheck(item: dict, model: str, today: str) -> list[dict]:
    """返回这一条的分歧列表。

    `today` 必须传进来：模型不知道今天几号，会把「原文写将来时、摘要写过去时」
    一律报成日期不符——而那个日期可能早就过去了，摘要才是对的。
    实测第一轮三条里就有一条是这么误报的。
    """
    excerpt = (item.get("sourceExcerpt") or "").strip()

    # 第一步必须是盲测。先给稿子，模型只会附和，什么都查不出来。
    facts = _raw(
        model,
        EXTRACT_PROMPT,
        f"官方标题：{item['sourceTitle']}\n\n官方原文：\n{excerpt}",
    )

    compared = _raw(
        model,
        COMPARE_PROMPT.replace("{today}", today),
        "A. 从官方原文提取的事实：\n"
        + json.dumps(facts, ensure_ascii=False, indent=2)
        + "\n\nB. 我们写的摘要：\n"
        + f"中文标题：{item['titleZh']}\n"
        + f"中文摘要：{item['summaryZh']}\n"
        + f"英文标题：{item.get('titleEn') or ''}\n"
        + f"英文摘要：{item.get('summaryEn') or ''}",
    )
    findings = compared.get("findings") or []
    return [f for f in findings if isinstance(f, dict) and f.get("detail")]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--out", default="crosscheck.json")
    args = parser.parse_args()

    if args.env_file:
        sd.load_env_file(args.env_file)

    items = sd.admin_request("/content/admin/news")
    # 只核对有官方原文的：没有原文就没有可比对的基准，
    # 硬做只会产出一份看起来像核对过的空报告。
    targets = [
        item
        for item in items
        if (item.get("sourceExcerpt") or "").strip()
        and (item.get("summaryZh") or "").strip()
    ]
    targets.sort(key=lambda item: item["publishedAt"], reverse=True)
    if args.limit:
        targets = targets[: args.limit]

    today = sd.datetime.now(sd.timezone.utc).strftime("%Y-%m-%d")
    pool = sd.ModelPool(args.model.split(","))
    print(f"待复核 {len(targets)} 条")
    print("复核模型顺序：" + " → ".join(pool.models))
    print("（与起草模型不同家族：同一个模型的失效方式是相关的，用它查自己等于没查）")
    print()

    report = []
    flagged = clean = failed = 0
    for index, item in enumerate(targets):
        title = (item["titleZh"] or item["sourceTitle"])[:46]
        print(f"[{index + 1}/{len(targets)}] {title}", flush=True)
        findings = None
        while True:
            try:
                findings = crosscheck(item, pool.current, today)
                break
            except Exception as exc:  # noqa: BLE001
                if sd.is_quota_error(exc):
                    print(f"  {pool.current} 额度耗尽，换下一个", flush=True)
                    if pool.retire_current():
                        continue
                    print("  候选模型都没额度了，本轮停止", flush=True)
                    findings = None
                    break
                print(f"  复核失败  {exc}", flush=True)
                failed += 1
                break
        if findings is None:
            break

        high = [f for f in findings if f.get("severity") == "high"]
        for finding in findings:
            mark = "‼" if finding.get("severity") == "high" else "·"
            label = KIND_LABEL.get(finding.get("kind", ""), finding.get("kind", "?"))
            print(f"  {mark} {label}：{finding['detail'][:90]}", flush=True)
        if findings:
            flagged += 1
        else:
            clean += 1
            print("  无分歧", flush=True)

        report.append({
            "id": item["id"],
            "title": item["titleZh"],
            "sourceUrl": item["sourceUrl"],
            "isPublished": item["isPublished"],
            "model": pool.current,
            "findings": findings,
            "highCount": len(high),
        })

        if not args.dry_run and findings:
            # 写进 draftChecks，就显示在审核界面上那条稿子旁边——
            # 人打开它的时候正好看到该重点看哪里。
            # 用 ⚠ 开头，界面上和「已核过」的条目区分开：这不是核过了，
            # 是「这里可能有问题」。
            lines = [
                f"⚠ 复核（{pool.current}）{KIND_LABEL.get(f.get('kind',''), '')}"
                f"{'【重要】' if f.get('severity') == 'high' else ''}：{f['detail'][:100]}"
                for f in findings
            ]
            existing = [c for c in (item.get("draftChecks") or []) if not c.startswith("⚠ 复核")]
            sd.admin_request(
                f"/content/admin/news/{item['id']}",
                method="PATCH",
                body={"draftChecks": existing + lines},
            )
        time.sleep(1)

    with io.open(args.out, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)

    high_total = sum(entry["highCount"] for entry in report)
    print()
    print(f"有分歧 {flagged} 条（其中重要 {high_total} 处），无分歧 {clean} 条，失败 {failed} 条")
    print(f"报告已存到 {args.out}")
    print()
    print("这份报告不代表已经审核。它只是告诉你先看哪几条——")
    print("签字仍然要人在后台逐条保存。")


if __name__ == "__main__":
    main()
