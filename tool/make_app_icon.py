#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LiquidGlass for Bilibili —— App 图标初稿生成（阶段一 #6）

按 Apple WWDC25 Session 220 的三态语言产出三张 1024×1024 初稿：
  icon-light.png   浅色外观（浅冰蓝→白渐变背景 + 玻璃透镜）
  icon-dark.png    深色外观（深炭蓝背景 + 发光边缘）
  icon-tinted.png  着色外观（透明底 + 灰阶主体，交给系统 tint）

为什么用代码画而不是找/生成位图：
  1. 品牌资产必须**原创且可追溯**——本项目明令禁止使用 B 站商标/素材（素材红线）；
  2. 图标要进 #16 的打包链路（flutter_launcher_icons 会再切多尺寸），
     可复现的脚本比一张"来路不明的 PNG"更可控；
  3. 2× 超采样 + 高斯模糊就能得到干净的边缘与果冻质感，够初稿用。

用法::

    python tool/make_app_icon.py                 # 输出到 assets/branding/icon/
    python tool/make_app_icon.py --size 512      # 换尺寸（默认 1024）
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

APP = Path(__file__).resolve().parent.parent
OUT = APP / "assets" / "branding" / "icon"

SS = 2  # 超采样倍数


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    h = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None]
    arr = np.zeros((size, size, 4), dtype=np.float32)
    for i in range(3):
        arr[:, :, i] = (top[i] * (1 - h) + bottom[i] * h)
    arr[:, :, 3] = 255
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def squircle_mask(size: int, side: int, radius_ratio: float = 0.30) -> Image.Image:
    """近似 squircle：先画 4 倍超采样的圆角矩形再缩回来，边缘足够干净。

    radius_ratio 取 0.30 左右最像"玻璃面板"（继续加大就退化成圆了）。
    """
    big = Image.new("L", (size * 4, size * 4), 0)
    d = ImageDraw.Draw(big)
    pad = (size - side) // 2
    d.rounded_rectangle(
        [pad * 4, pad * 4, (pad + side) * 4, (pad + side) * 4],
        radius=int(side * radius_ratio * 4),
        fill=255,
    )
    return big.resize((size, size), Image.LANCZOS)


def glass_lens(size: int, tint: tuple[int, int, int], rim_gain: float = 1.0) -> Image.Image:
    """画玻璃面板本体（折射填充 + 厚度边 + 渐隐 rim light + 内部高光 + 下方 caustic）。"""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    side = int(size * 0.62)
    pad = (size - side) // 2
    box = [pad, pad, pad + side, pad + side]
    radius = int(side * 0.30)

    mask = squircle_mask(size, side)

    # 1) 面板的"折射"填充：上亮下透的双色渐变
    fill = vertical_gradient(size, (255, 255, 255), tint)
    fill.putalpha(Image.fromarray((np.asarray(mask, dtype=np.float32) * 0.60).astype(np.uint8)))
    layer = Image.alpha_composite(layer, fill)

    w = max(3, int(size * 0.0055))

    # 2) 整圈厚度边（弱）——玻璃的"侧壁"
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rim)
    dr.rounded_rectangle(box, radius=radius, outline=(255, 255, 255, int(85 * rim_gain)), width=w)
    inset = int(side * 0.045)
    dr.rounded_rectangle(
        [box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset],
        radius=max(1, radius - inset), outline=(255, 255, 255, int(38 * rim_gain)), width=max(2, w // 2),
    )
    layer = Image.alpha_composite(layer, rim.filter(ImageFilter.GaussianBlur(size * 0.0022)))

    # 3) 左上高光弧：单段弧 + 较大模糊 → 两端自然渐隐（分段会露出硬断口）
    bright = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    db = ImageDraw.Draw(bright)
    db.arc(box, start=162, end=300, fill=(255, 255, 255, int(170 * rim_gain)), width=int(w * 1.5))
    layer = Image.alpha_composite(layer, bright.filter(ImageFilter.GaussianBlur(size * 0.0055)))

    # 4) 左上角软光斑（内部高光）
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dh = ImageDraw.Draw(hl)
    cx, cy = pad + side * 0.30, pad + side * 0.24
    rx, ry = side * 0.24, side * 0.13
    dh.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(255, 255, 255, 105))
    layer = Image.alpha_composite(layer, hl.filter(ImageFilter.GaussianBlur(size * 0.022)))

    # 6) 下方 caustic：玻璃把光聚在底面形成的一小片暖光
    ca = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dc = ImageDraw.Draw(ca)
    cx2, cy2 = size / 2, pad + side * 1.01
    dc.ellipse([cx2 - side * 0.28, cy2 - side * 0.045, cx2 + side * 0.28, cy2 + side * 0.045],
               fill=(255, 244, 222, 120))
    layer = Image.alpha_composite(layer, ca.filter(ImageFilter.GaussianBlur(size * 0.025)))
    return layer


def compose(kind: str, size: int) -> Image.Image:
    """size 为最终边长；内部按 SS 倍超采样后缩回。"""
    s = size * SS
    if kind == "light":
        bg = vertical_gradient(s, (232, 240, 254), (255, 255, 255))
        lens = glass_lens(s, tint=(214, 231, 255), rim_gain=1.0)
    elif kind == "dark":
        bg = vertical_gradient(s, (12, 15, 22), (28, 34, 48))
        lens = glass_lens(s, tint=(86, 120, 190), rim_gain=1.25)
    elif kind == "tinted":
        # 着色外观：透明底 + 灰阶主体（系统负责上色）；背景透明
        bg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        lens = glass_lens(s, tint=(190, 190, 190), rim_gain=0.9)
        grey = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        lum = lens.convert("LA").convert("RGBA")
        grey = Image.alpha_composite(grey, lum)
        grey.putalpha(lens.getchannel("A"))
        lens = grey
    else:
        raise ValueError(kind)
    img = Image.alpha_composite(bg, lens)
    return img.resize((size, size), Image.LANCZOS)


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 LiquidGlass App 图标初稿（三态）")
    ap.add_argument("--size", type=int, default=1024)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for kind in ("light", "dark", "tinted"):
        img = compose(kind, args.size)
        path = OUT / f"icon-{kind}.png"
        img.save(path)
        print(f"  {path.relative_to(APP)}  {img.size[0]}×{img.size[1]}  {path.stat().st_size:,} 字节")
    print("说明：这是**初稿**（原创、无第三方商标），正式版在 #16 打包链路里用 flutter_launcher_icons 派生各尺寸。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())