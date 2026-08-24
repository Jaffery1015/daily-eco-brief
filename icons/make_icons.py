# -*- coding: utf-8 -*-
"""生成每日经济早报 PWA 图标（512/192/180）。"""
from PIL import Image, ImageDraw, ImageFont
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = r"C:\Windows\Fonts\msyhbd.ttc"

def make_icon(size, out):
    s = size / 512.0
    W = H = size
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 1) 纵向渐变背景（深海军蓝 -> 近黑）
    top = (17, 27, 45)
    bottom = (6, 9, 15)
    for y in range(H):
        t = y / (H - 1.0)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        d.line([(0, y), (W, y)], fill=(r, g, b, 255))

    # 2) 顶部金色光晕
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    glow_r = int(300 * s)
    cx, cy = int(W * 0.5), int(H * 0.32)
    for i in range(glow_r, 0, -8):
        a = int(38 * (1 - i / glow_r))
        gd.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(240, 180, 41, a))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)

    # 3) 浅色网格线（图表背景）
    for i in range(1, 5):
        y = int(H * 0.30) + i * int(H * 0.075)
        d.line([(int(64 * s), y), (int(448 * s), y)], fill=(255, 255, 255, 14), width=max(1, int(2 * s)))

    # 4) K 线蜡烛（升势，最后红涨）
    candles = [  # (x_center, body_top, body_bottom)
        (int(105 * s), int(398 * s), int(430 * s)),
        (int(160 * s), int(380 * s), int(424 * s)),
        (int(215 * s), int(360 * s), int(416 * s)),
        (int(270 * s), int(342 * s), int(406 * s)),
        (int(325 * s), int(322 * s), int(396 * s)),
        (int(380 * s), int(304 * s), int(386 * s)),
    ]
    wick_w = max(2, int(4 * s))
    body_w = max(5, int(24 * s))
    for idx, (cx, bt, bb) in enumerate(candles):
        color = (255, 93, 93, 255) if idx == len(candles) - 1 else (47, 196, 127, 230)
        # 影线
        d.line([(cx, bt - int(12 * s)), (cx, bb + int(10 * s))], fill=color, width=wick_w)
        # 实体
        d.rectangle([cx - body_w // 2, bt, cx + body_w // 2, bb], fill=color)

    # 5) 金色上涨趋势线（穿过蜡烛顶部）
    pts = [(int(100 * s), int(398 * s)), (int(160 * s), int(380 * s)),
           (int(215 * s), int(360 * s)), (int(270 * s), int(342 * s)),
           (int(325 * s), int(322 * s)), (int(385 * s), int(300 * s))]
    line_w = max(4, int(9 * s))
    for off in range(int(6 * s), 0, -2):  # 光晕
        d.line(pts, fill=(240, 180, 41, 60 // (off // 2 + 1)), width=line_w + off, joint="curve")
    d.line(pts, fill=(255, 205, 82, 255), width=line_w, joint="curve")

    # 6) “经”字（金色，居中偏上，带阴影）
    font = ImageFont.truetype(FONT, int(225 * s))
    text = "经"
    # 测量
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (W - tw) / 2 - bbox[0]
    ty = int(H * 0.20) - bbox[1]
    d.text((tx, ty + int(6 * s)), text, font=font, fill=(0, 0, 0, 160))
    d.text((tx, ty), text, font=font, fill=(240, 180, 41, 255))

    img.save(out, "PNG")
    print("saved", out, img.size)

if __name__ == "__main__":
    make_icon(512, os.path.join(HERE, "icon-512.png"))
    make_icon(192, os.path.join(HERE, "icon-192.png"))
    make_icon(180, os.path.join(HERE, "apple-touch-icon-180.png"))