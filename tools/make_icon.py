#!/usr/bin/env python3
"""Genera el icono de la app (diseño propio: escudo dorado con esmeralda y corona).

    python3 tools/make_icon.py        -> icon.png (1024), icon.icns (macOS) e icon.ico

Requiere Pillow. Se dibuja a 2048 px y se reduce (bordes suaves).
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLD = (236, 194, 90)
GOLD_DARK = (160, 118, 40)
GOLD_LIGHT = (255, 232, 160)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    px = grad.load()
    c0, c1 = (22, 92, 66), (5, 28, 22)
    for y in range(0, S, 4):
        for x in range(0, S, 4):
            d = math.hypot(x - S * 0.5, y - S * 0.38) / (S * 0.75)
            col = lerp(c0, c1, min(1.0, d)) + (255,)
            for yy in range(y, min(S, y + 4)):
                for xx in range(x, min(S, x + 4)):
                    px[xx, yy] = col
    mask = Image.new("L", (S, S), 0)
    m = int(S * 0.08)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, S - m, S - m], radius=int(S * 0.2), fill=255)
    img.paste(grad, (0, 0), mask)
    # borde dorado fino
    ImageDraw.Draw(img).rounded_rectangle([m, m, S - m, S - m], radius=int(S * 0.2), outline=GOLD_DARK + (255,), width=int(S * 0.008))
    return img


def shield_points(cx, top, w, h):
    pts = []
    left, right = cx - w / 2, cx + w / 2
    pts.append((left, top))
    pts.append((right, top))
    # lado derecho curvo hasta la punta
    for i in range(1, 25):
        t = i / 24
        x = right - (w / 2) * (t ** 1.8)
        y = top + h * 0.45 + (h * 0.55) * t
        pts.append((x, y if i > 0 else top))
    pts.insert(2, (right, top + h * 0.45))
    left_side = []
    for i in range(24, 0, -1):
        t = i / 24
        x = left + (w / 2) * (t ** 1.8)
        y = top + h * 0.45 + (h * 0.55) * t
        left_side.append((x, y))
    pts += left_side
    pts.append((left, top + h * 0.45))
    return pts


def draw_shield(img):
    d = ImageDraw.Draw(img)
    cx = S / 2
    top, w, h = S * 0.36, S * 0.56, S * 0.52
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x, y + S * 0.02) for x, y in shield_points(cx, top, w, h)], fill=(0, 0, 0, 140))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.015)))
    d.polygon(shield_points(cx, top, w, h), fill=GOLD + (255,))
    b = S * 0.03
    d.polygon(shield_points(cx, top + b, w - 2 * b, h - 2.2 * b), fill=(14, 40, 31, 255))
    b2 = S * 0.042
    d.line(shield_points(cx, top + b2, w - 2 * b2, h - 2.6 * b2) + [shield_points(cx, top + b2, w - 2 * b2, h - 2.6 * b2)[0]], fill=GOLD_DARK + (255,), width=int(S * 0.006))


def draw_emerald(img):
    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S * 0.595
    w, h = S * 0.25, S * 0.3
    c = S * 0.055  # esquinas cortadas (talla esmeralda)
    outer = [(cx - w / 2 + c, cy - h / 2), (cx + w / 2 - c, cy - h / 2), (cx + w / 2, cy - h / 2 + c), (cx + w / 2, cy + h / 2 - c),
             (cx + w / 2 - c, cy + h / 2), (cx - w / 2 + c, cy + h / 2), (cx - w / 2, cy + h / 2 - c), (cx - w / 2, cy - h / 2 + c)]
    k = 0.52
    inner = [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in outer]
    d.polygon(outer, fill=(8, 120, 72, 255))
    shades = [(60, 200, 130), (30, 170, 105), (12, 110, 66), (8, 90, 55), (10, 100, 60), (20, 140, 88), (40, 180, 115), (80, 215, 150)]
    for i in range(8):
        a, b = outer[i], outer[(i + 1) % 8]
        ia, ib = inner[i], inner[(i + 1) % 8]
        d.polygon([a, b, ib, ia], fill=shades[i] + (255,))
    d.polygon(inner, fill=(22, 160, 98, 255))
    ii = [(cx + (x - cx) * 0.55, cy + (y - cy) * 0.55) for x, y in inner]
    d.polygon(ii, fill=(34, 185, 115, 255))
    d.line(outer + [outer[0]], fill=GOLD_LIGHT + (255,), width=int(S * 0.008))
    # brillo
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon([outer[7], outer[0], inner[0], inner[7]], fill=(220, 255, 235, 110))
    img.alpha_composite(glow)


def draw_crown(img):
    d = ImageDraw.Draw(img)
    cx = S / 2
    base_y, w = S * 0.33, S * 0.4
    left, right = cx - w / 2, cx + w / 2
    peak = S * 0.16
    pts = [(left, base_y), (left - S * 0.01, base_y - peak * 0.95), (cx - w * 0.25, base_y - peak * 0.45), (cx, base_y - peak * 1.15),
           (cx + w * 0.25, base_y - peak * 0.45), (right + S * 0.01, base_y - peak * 0.95), (right, base_y)]
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x, y + S * 0.015) for x, y in pts], fill=(0, 0, 0, 130))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.012)))
    d.polygon(pts, fill=GOLD + (255,))
    d.polygon([(left + S * 0.02, base_y - S * 0.005), (cx - w * 0.25, base_y - peak * 0.4), (cx, base_y - peak * 1.0), (cx, base_y - S * 0.005)], fill=GOLD_LIGHT + (120,))
    band = S * 0.05
    d.rounded_rectangle([left - S * 0.01, base_y - S * 0.01, right + S * 0.01, base_y + band], radius=int(S * 0.012), fill=GOLD_DARK + (255,))
    d.rounded_rectangle([left, base_y - S * 0.004, right, base_y + band - S * 0.008], radius=int(S * 0.01), fill=GOLD + (255,))
    r = S * 0.026
    for x, y in [pts[1], pts[3], pts[5]]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=GOLD_LIGHT + (255,), outline=GOLD_DARK + (255,), width=int(S * 0.004))
    for i, x in enumerate([cx - w * 0.3, cx, cx + w * 0.3]):
        rr = S * (0.022 if i == 1 else 0.016)
        y = base_y + band * 0.45
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(30, 170, 100, 255) if i == 1 else (170, 40, 50, 255))


def main():
    img = background()
    draw_shield(img)
    draw_emerald(img)
    draw_crown(img)
    out = img.resize((1024, 1024), Image.LANCZOS)
    out.save(os.path.join(ROOT, "icon.png"))
    out.save(os.path.join(ROOT, "icon.icns"), sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    out.save(os.path.join(ROOT, "icon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icon.png, icon.icns, icon.ico")


if __name__ == "__main__":
    main()
