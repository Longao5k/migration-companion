"""生成 App 图标全套资源。

图形：一条从左下走到右上的折线，三个节点——对应 App 里的「申请路线 / 下一步」。
抽象线条，不用任何徽章、盾牌、国旗或政府符号：冻结规则禁止暗示官方身份。

品牌色沿用 lib/core/theme/app_theme.dart 里已有的桉树绿与墨色，不另起一套。

设计稿是浅底绿线，这里改成深绿底 + 亮色路径。原因是尺寸：mdpi 的启动图标只有
48×48 像素，浅底上的细绿线在这个尺寸下会糊成一团甚至断开。同一个图形，反过来配色
在 48px 下仍然立得住。

用法（在 apps/mobile 下）：
    python tool/generate_app_icon.py
"""

import json
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

INK = (20, 34, 49)
EUCALYPTUS = (20, 123, 102)
DEEP = (10, 63, 52)
MINT = (162, 242, 220)
WHITE = (255, 255, 255)

# 先在放大 4 倍的画布上画，再缩小回目标尺寸——Pillow 没有抗锯齿绘图，
# 超采样是拿到干净斜线的唯一办法。
SS = 4

# 路径节点，坐标是画布边长的比例。
#
# 三点必须不共线，否则画出来是一条直线，不是「路线」。中间那个点定出一个明显的
# 转折：先陡后缓，读起来像走过一段路。
# 全部落在中心 66% 的安全区内：Android 自适应图标会按设备形状裁掉外圈，
# 圆形启动器上超出安全区的部分会被切掉。
NODES = [(0.262, 0.715), (0.437, 0.395), (0.747, 0.295)]


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def draw_mark(size, *, with_background, background_scale=1.0, mark_scale=1.0):
    """画出图标。

    mark_scale 把图形整体向画布中心收缩，供 Android 自适应图标的前景层使用。
    自适应图标的保证可视区是**中心直径 66dp 的圆**（108dp 画布上半径 0.3056）。
    满幅画的图形在圆形启动器上会被切掉终点环和起点——必须单独缩一档，
    不能和满幅的旧版图标共用一套坐标。
    """
    canvas = size * SS
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if with_background:
        # 从深绿到桉树绿的对角渐变。纯色在大尺寸下显得平，渐变在 48px 下又看不出来，
        # 两头都不吃亏。
        inset = canvas * (1 - background_scale) / 2
        box = (inset, inset, canvas - inset, canvas - inset)
        side = box[2] - box[0]
        gradient = Image.new("RGB", (int(side), int(side)))
        gdraw = ImageDraw.Draw(gradient)
        for y in range(int(side)):
            gdraw.line(
                [(0, y), (side, y)], fill=_lerp(EUCALYPTUS, DEEP, y / max(1, side - 1))
            )
        mask = Image.new("L", (int(side), int(side)), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, side - 1, side - 1), radius=side * 0.225, fill=255
        )
        image.paste(gradient, (int(box[0]), int(box[1])), mask)

    points = [
        (
            (0.5 + (x - 0.5) * mark_scale) * canvas,
            (0.5 + (y - 0.5) * mark_scale) * canvas,
        )
        for x, y in NODES
    ]
    line_width = max(1, int(canvas * 0.055 * mark_scale))

    # 折线本身。round join/cap 让转角不出现尖刺。
    draw.line(points, fill=WHITE + (255,), width=line_width, joint="curve")
    for point in (points[0], points[-1]):
        r = line_width / 2
        draw.ellipse(
            (point[0] - r, point[1] - r, point[0] + r, point[1] + r),
            fill=WHITE + (255,),
        )

    # 节点只比线略粗。之前给到 1.6 倍线宽，三个球把线盖住了，
    # 图形读成「三个点」而不是「一条路」。
    for index, point in enumerate(points):
        last = index == len(points) - 1
        outer = line_width * (1.34 if last else 0.92)
        draw.ellipse(
            (point[0] - outer, point[1] - outer, point[0] + outer, point[1] + outer),
            fill=WHITE + (255,),
        )
        if last:
            # 终点画成环：那是「下一步」，要和已经走过的实心点区分开。
            #
            # 前景层（自适应图标）必须把环心真正挖空，不能填色：Android 13 的主题
            # 图标只取 alpha 通道再上色，填了色的环心在那里会变成一个实心点。
            # 挖空之后，自适应图标透出的是背景层的桉树绿，主题图标也保留环形。
            inner = outer * 0.46
            box = (
                point[0] - inner,
                point[1] - inner,
                point[0] + inner,
                point[1] + inner,
            )
            if with_background:
                draw.ellipse(box, fill=DEEP + (255,))
            else:
                draw.ellipse(box, fill=(0, 0, 0, 0))

    return image.resize((size, size), Image.LANCZOS)


def write(image, path, *, flatten_to=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if flatten_to is not None:
        # iOS 拒收带 alpha 通道的图标，必须先压到不透明底上。
        flat = Image.new("RGB", image.size, flatten_to)
        flat.paste(image, mask=image.split()[3])
        flat.save(path, "PNG")
    else:
        image.save(path, "PNG")
    print(f"  {path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}")


def main():
    print("Android 启动图标（旧版位图）")
    for bucket, size in [
        ("mdpi", 48),
        ("hdpi", 72),
        ("xhdpi", 96),
        ("xxhdpi", 144),
        ("xxxhdpi", 192),
    ]:
        write(
            draw_mark(size, with_background=True),
            ROOT / f"android/app/src/main/res/mipmap-{bucket}/ic_launcher.png",
        )

    print("Android 自适应图标前景（108dp 画布，图形只占中心安全区）")
    for bucket, size in [
        ("mdpi", 108),
        ("hdpi", 162),
        ("xhdpi", 216),
        ("xxhdpi", 324),
        ("xxxhdpi", 432),
    ]:
        write(
            # 最远的节点中心在 0.32 半径处，加上终点环的 0.074，满幅伸展约 0.394，
            # 超过 0.3056 的安全半径（108dp 画布上直径 66dp 的圆）。
            # 0.76 之后约 0.30，刚好落在安全区内又不至于缩成一颗芝麻。
            draw_mark(size, with_background=False, mark_scale=0.76),
            ROOT
            / f"android/app/src/main/res/mipmap-{bucket}/ic_launcher_foreground.png",
        )

    print("Play 商店图标")
    write(
        draw_mark(512, with_background=True),
        ROOT / "store/play-icon-512.png",
        flatten_to=DEEP,
    )

    print("iOS")
    appicon = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((appicon / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        size = int(round(base * scale))
        # iOS 自己加圆角，图标必须是方的、满幅的、不透明的。
        write(
            draw_mark(size, with_background=True, background_scale=1.0),
            appicon / filename,
            flatten_to=DEEP,
        )

    print("\n预览图")
    write(draw_mark(1024, with_background=True), ROOT / "store/icon-preview-1024.png")


if __name__ == "__main__":
    main()
    print("\n完成。")
    print("提醒：Android 自适应图标还需要 mipmap-anydpi-v26/ic_launcher.xml，")
    print("以及 values/ic_launcher_background.xml 里的背景色。")
    os.sys.exit(0)
