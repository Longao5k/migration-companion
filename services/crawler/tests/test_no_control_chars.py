"""源码里不能出现字面控制字符。

这条测试存在的唯一理由是同一个错误已经犯过四次：正则里的 `\\b`（词边界）
经 shell heredoc 写入时被解释成**字面退格符** 0x08，于是模式要求匹配一个
退格字符，永远匹配不上。

它的危险在于完全静默：
- `tagging.py` 里坏掉，签证类别标签一个也抽不出来，内容照常入库，只是没有标签；
- `summarize_drafts.py` 里坏掉，整张英文建议口吻黑名单（you should /
  we recommend / eligible for ...）从加上那天起就没执行过，而「不给移民建议」
  是签核过的边界。

编辑器里 `\\b` 和退格符长得一模一样，靠看是看不出来的——第四次是靠
`file` 报告 "with overstriking" 才发现的。所以钉一条测试。
"""

from pathlib import Path

import pytest

# 允许的控制字符：制表、换行、回车。其余（尤其是 0x08 退格、0x1b 转义）
# 出现在源码里几乎总是转义被吃掉的结果。
ALLOWED = {0x09, 0x0A, 0x0D}
SUFFIXES = {".py", ".sh", ".mjs", ".json", ".toml", ".cfg"}

_ROOT = Path(__file__).resolve().parents[3]
_SCAN_DIRS = ("services/crawler", "tools", "infra/server", "services/api/scripts")


def _sources() -> list[Path]:
    files: list[Path] = []
    for relative in _SCAN_DIRS:
        base = _ROOT / relative
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix in SUFFIXES and "__pycache__" not in path.parts:
                files.append(path)
    return files


@pytest.mark.parametrize("path", _sources(), ids=lambda p: p.name)
def test_source_has_no_literal_control_characters(path: Path) -> None:
    raw = path.read_bytes()
    offenders = {byte for byte in raw if byte < 0x20 and byte not in ALLOWED}
    assert not offenders, (
        f"{path} 含字面控制字符 "
        f"{sorted(hex(b) for b in offenders)}。"
        "常见原因：正则里的 \\b 被 shell 转义吃成了退格符（0x08），"
        "该模式将永远匹配不上，且不会报错。"
    )


LF_ONLY = {".sh"}


@pytest.mark.parametrize(
    "path", [p for p in _sources() if p.suffix in LF_ONLY], ids=lambda p: p.name
)
def test_shell_scripts_use_lf(path: Path) -> None:
    """在 Linux 上执行的脚本不能带 CRLF。

    .gitattributes 管的是提交与检出，管不住「在 Windows 上写完直接 scp 上去」。
    带 CRLF 的脚本里，`set -euo pipefail` 末尾会多一个回车，bash 把
    `pipefail` 连同那个回车当成一个非法选项名直接退出——服务器上六个脚本
    曾经同时中招，而错误信息完全看不出是换行符的问题。
    """
    crlf = bytes([13, 10])
    assert crlf not in path.read_bytes(), (
        f"{path} 是 CRLF 换行。它在 Linux 上执行，必须是 LF。"
    )


def test_scan_actually_covers_files() -> None:
    # 防止上面那些因为路径写错而变成「零个文件全部通过」。
    # CRLF 那条第一版就踩了这个坑：扫描目录里没有任何 .sh，
    # 参数化拿到空列表，pytest 报 skipped，看起来一切正常。
    assert len(_sources()) > 20
    assert len([p for p in _sources() if p.suffix == ".sh"]) >= 5
