"""从 assets/brand/app-icon.svg 生成 App 图标全套资源。

源文件是设计稿本身，这里只做光栅化和按平台切分，不重画图形。要改图形就改 SVG。

光栅化用 `npx sharp-cli`（sharp 内置 librsvg，Windows 有预编译二进制）。
Windows 上没有可用的 cairo，cairosvg 装得上但加载不了 DLL；ImageMagick 也不在，
`convert` 是系统自带的磁盘工具，不是 ImageMagick。

用法（在 apps/mobile 下）：
    python tool/generate_app_icon.py
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/brand/app-icon.svg"

# 渐变的深色端。iOS 与 Play 商店图标不能带 alpha，压平时用它做底，
# 这样即使有半透明边缘也不会露出白边。
FLATTEN = (6, 46, 112)

# Android 自适应图标的保证可视区：108dp 画布上直径 66dp 的圆。
# 超出这个圆的部分，在圆形启动器上会被裁掉。
SAFE_RADIUS_RATIO = 33 / 108

# 光栅化的工作分辨率。前景层要先在高分辨率下量出图形的真实半径再缩放，
# 分辨率太低会让边缘的抗锯齿像素影响测量结果。
WORK = 2048


def rasterize(svg_text: str, size: int, out: Path) -> Image.Image:
    """把一段 SVG 源码渲染成指定边长的 PNG。"""
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", suffix=".svg", delete=False, encoding="utf-8"
    ) as handle:
        handle.write(svg_text)
        temp = Path(handle.name)
    try:
        result = subprocess.run(
            [
                "npx",
                "-y",
                "sharp-cli",
                "--input",
                str(temp),
                "--output",
                str(out),
                "resize",
                str(size),
                str(size),
            ],
            capture_output=True,
            text=True,
            shell=sys.platform == "win32",
        )
        if result.returncode != 0 or not out.exists():
            raise RuntimeError(f"sharp 光栅化失败：{result.stderr.strip()}")
        return Image.open(out).convert("RGBA")
    finally:
        temp.unlink(missing_ok=True)


def variants(svg_text: str):
    """派生出三种 SVG：满幅圆角、满幅方角、去背景的前景。"""
    background = re.search(
        r'<rect width="1024" height="1024" rx="\d+" fill="url\(#\w+\)"/>', svg_text
    )
    if background is None:
        raise RuntimeError("找不到背景矩形，SVG 结构变了，需要更新这个脚本")

    rounded = svg_text
    # iOS 自己加圆角遮罩。如果图标本身就带圆角，iOS 会再切一次，
    # 露出的直角区域会显示压平用的底色，看起来像一圈脏边。
    square = svg_text.replace(background.group(0), background.group(0).replace('rx="220"', 'rx="0"'))
    # 自适应图标的前景层不能自带背景——背景是独立的一层。
    foreground = svg_text.replace(background.group(0), "")
    return rounded, square, foreground


def fit_to_safe_zone(foreground: Image.Image, canvas: int) -> Image.Image:
    """把前景图形居中并缩放到自适应图标的安全区内。

    不按外接矩形算，而是量出所有不透明像素到图形中心的**最大距离**——
    这张图的图形接近方形，用矩形对角线会白白缩掉一圈。
    """
    bbox = foreground.getbbox()
    if bbox is None:
        raise RuntimeError("前景是空的")
    art = foreground.crop(bbox)

    alpha = art.getchannel("A")
    width, height = art.size
    cx, cy = width / 2, height / 2
    max_radius = 0.0
    # 只看边界像素就够了：最远点一定在轮廓上。逐行取最左最右、逐列取最上最下。
    pixels = alpha.load()
    for y in range(height):
        for x in (range(width), reversed(range(width))):
            for px in x:
                if pixels[px, y] > 8:
                    max_radius = max(max_radius, ((px - cx) ** 2 + (y - cy) ** 2) ** 0.5)
                    break
    for x in range(width):
        for y in (range(height), reversed(range(height))):
            for py in y:
                if pixels[x, py] > 8:
                    max_radius = max(max_radius, ((x - cx) ** 2 + (py - cy) ** 2) ** 0.5)
                    break

    target_radius = canvas * SAFE_RADIUS_RATIO
    scale = target_radius / max_radius
    new_size = (max(1, round(width * scale)), max(1, round(height * scale)))
    scaled = art.resize(new_size, Image.LANCZOS)

    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(
        scaled,
        ((canvas - new_size[0]) // 2, (canvas - new_size[1]) // 2),
    )
    return out


def save(image: Image.Image, path: Path, *, flatten: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if flatten:
        flat = Image.new("RGB", image.size, FLATTEN)
        flat.paste(image, mask=image.split()[3])
        flat.save(path, "PNG")
    else:
        image.save(path, "PNG")
    print(f"  {path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}")


ANDROID_BUCKETS = [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"找不到源文件 {SOURCE}")
    svg_text = SOURCE.read_text(encoding="utf-8")
    rounded_svg, square_svg, foreground_svg = variants(svg_text)

    work = Path(tempfile.mkdtemp(prefix="app-icon-"))
    try:
        rounded = rasterize(rounded_svg, WORK, work / "rounded.png")
        square = rasterize(square_svg, WORK, work / "square.png")
        foreground_full = rasterize(foreground_svg, WORK, work / "foreground.png")

        print("Android 启动图标（旧版位图，自带圆角）")
        for bucket, legacy, _ in ANDROID_BUCKETS:
            save(
                rounded.resize((legacy, legacy), Image.LANCZOS),
                ROOT / f"android/app/src/main/res/mipmap-{bucket}/ic_launcher.png",
            )

        print("Android 自适应图标：背景层（满幅方角，圆角由系统遮罩决定）")
        for bucket, _, adaptive in ANDROID_BUCKETS:
            background = Image.new("RGBA", (adaptive, adaptive), (0, 0, 0, 0))
            background.paste(square.resize((adaptive, adaptive), Image.LANCZOS))
            save(
                background,
                ROOT
                / f"android/app/src/main/res/mipmap-{bucket}/ic_launcher_background.png",
            )

        print("Android 自适应图标：前景层（缩放进 66dp 安全区）")
        fitted = fit_to_safe_zone(foreground_full, WORK)
        for bucket, _, adaptive in ANDROID_BUCKETS:
            save(
                fitted.resize((adaptive, adaptive), Image.LANCZOS),
                ROOT
                / f"android/app/src/main/res/mipmap-{bucket}/ic_launcher_foreground.png",
            )

        print("Play 商店图标（512×512，不带 alpha）")
        save(
            rounded.resize((512, 512), Image.LANCZOS),
            ROOT / "store/play-icon-512.png",
            flatten=True,
        )

        print("iOS（方角满幅，压平 alpha）")
        appicon = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        contents = json.loads((appicon / "Contents.json").read_text(encoding="utf-8"))
        done = set()
        for entry in contents["images"]:
            filename = entry.get("filename")
            if not filename or filename in done:
                continue
            done.add(filename)
            base = float(entry["size"].split("x")[0])
            size = int(round(base * int(entry["scale"].rstrip("x"))))
            save(
                square.resize((size, size), Image.LANCZOS),
                appicon / filename,
                flatten=True,
            )

        print("\n预览图")
        save(
            rounded.resize((1024, 1024), Image.LANCZOS),
            ROOT / "store/icon-preview-1024.png",
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print("\n完成。")


if __name__ == "__main__":
    main()
