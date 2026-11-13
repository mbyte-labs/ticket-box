#!/usr/bin/env python3
"""Compose a raw emulator screencap into a Play Store phone screenshot: brand-red canvas, a white
Urbanist caption at the top and a dark phone bezel below, cropped at the bottom edge.

Capture recipe (screen aspect 1080:2313 so nothing is distorted):
    adb shell wm size 1080x2313 && adb shell wm density 405
    adb exec-out screencap -p > raw.png
    adb shell wm size reset && adb shell wm density reset

Usage: /opt/homebrew/bin/python3.14 compose.py raw.png out.png "Caption text"
Output: 1080x2134 24-bit RGB PNG (Play rejects alpha). Requires Pillow.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FONT = os.path.join(ROOT, 'assets', 'fonts', 'urbanist', 'Urbanist-Bold.ttf')

W, H = 1080, 2134
BG = (0xF5, 0x48, 0x4A)  # ThemeColors.primary
CAPTION_COLOR = (255, 255, 255)
CAPTION_SIZE = 66
CAPTION_TOP = 96
CAPTION_MAX_WIDTH = 940
LINE_GAP = 12

# Phone geometry (same proportions as the website frame: screen 902x1932, radius 85, 2px ring)
SCREEN_W = 902
SCREEN_H = round(SCREEN_W * 2313 / 1080)  # 1932
SCREEN_RADIUS = 85
BEZEL = 24  # bezel thickness around the screen
BODY_RADIUS = SCREEN_RADIUS + BEZEL
BODY = (18, 18, 18)
RING = (2, 2, 2)
PHONE_TOP = 330  # top edge of the phone body on the canvas


def wrap(draw, text, font, max_width):
    """One line when it fits, otherwise the most balanced two-line split that fits (no orphan words)."""
    words = text.split()
    width = lambda ws: draw.textlength(' '.join(ws), font=font)
    if width(words) <= max_width:
        return [' '.join(words)]
    best = None
    for i in range(1, len(words)):
        a, b = words[:i], words[i:]
        wa, wb = width(a), width(b)
        if wa <= max_width and wb <= max_width:
            score = abs(wa - wb)
            if best is None or score < best[0]:
                best = (score, [' '.join(a), ' '.join(b)])
    if best:
        return best[1]
    # Fallback: greedy wrap for very long captions
    lines, cur = [], []
    for w in words:
        if cur and width(cur + [w]) > max_width:
            lines.append(' '.join(cur))
            cur = []
        cur.append(w)
    lines.append(' '.join(cur))
    return lines


def compose(raw_path, out_path, caption):
    canvas = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(canvas)

    # Caption
    font = ImageFont.truetype(FONT, CAPTION_SIZE)
    lines = wrap(draw, caption, font, CAPTION_MAX_WIDTH)
    y = CAPTION_TOP
    for line in lines:
        tw = draw.textlength(line, font=font)
        draw.text(((W - tw) / 2, y), line, font=font, fill=CAPTION_COLOR)
        y += CAPTION_SIZE + LINE_GAP

    # Phone body (cropped at the bottom edge on purpose)
    body_w = SCREEN_W + 2 * BEZEL
    body_h = SCREEN_H + 2 * BEZEL
    bx = (W - body_w) // 2
    by = PHONE_TOP
    draw.rounded_rectangle([bx, by, bx + body_w - 1, by + body_h - 1], radius=BODY_RADIUS, fill=BODY)
    # Subtle highlight on the body edge
    draw.rounded_rectangle([bx, by, bx + body_w - 1, by + body_h - 1], radius=BODY_RADIUS, outline=(40, 40, 40), width=2)

    # Screen: cover-fit the raw capture into the screen rect, rounded corners, glass ring
    sx, sy = bx + BEZEL, by + BEZEL
    raw = Image.open(raw_path).convert('RGB')
    scale = max(SCREEN_W / raw.width, SCREEN_H / raw.height)
    rw, rh = round(raw.width * scale), round(raw.height * scale)
    content = raw.resize((rw, rh), Image.LANCZOS)
    ox, oy = (rw - SCREEN_W) // 2, (rh - SCREEN_H) // 2
    content = content.crop((ox, oy, ox + SCREEN_W, oy + SCREEN_H))
    draw.rounded_rectangle([sx - 2, sy - 2, sx + SCREEN_W + 1, sy + SCREEN_H + 1], radius=SCREEN_RADIUS + 2, fill=RING)
    mask = Image.new('L', (SCREEN_W, SCREEN_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SCREEN_W - 1, SCREEN_H - 1], radius=SCREEN_RADIUS, fill=255)
    canvas.paste(content, (sx, sy), mask)

    canvas.save(out_path, optimize=True)
    print('wrote', out_path, canvas.size, '| caption lines:', len(lines))


if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    compose(sys.argv[1], sys.argv[2], sys.argv[3])
