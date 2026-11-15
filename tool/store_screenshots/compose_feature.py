#!/usr/bin/env python3
"""Compose the Play Store feature graphic (1024x500): brand-red canvas, the white Ticket Box mark and
wordmark with a short tagline on the left, and three phone screens fanned in on the right.

Usage: /opt/homebrew/bin/python3.14 compose_feature.py out.png raw1.png raw2.png raw3.png
The raws are 1080x2313 emulator captures (see README.md). Output is a 24-bit RGB PNG.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FONT_BOLD = os.path.join(ROOT, 'assets', 'fonts', 'urbanist', 'Urbanist-Bold.ttf')
FONT_MED = os.path.join(ROOT, 'assets', 'fonts', 'urbanist', 'Urbanist-Medium.ttf')
LOGO = os.path.join(ROOT, 'assets', 'images', 'logos', 'ticket_box', 'ticket_box_white.png')

W, H = 1024, 500
BG = (0xF5, 0x48, 0x4A)
WHITE = (255, 255, 255)
TAGLINE = 'Track your shows and movies.\nNo account needed.'

# Phone geometry (screen aspect 1080:2313), drawn at supersampled scale then downsized
SS = 3
PHONE_SCREEN_W = 150
BEZEL = 6
RADIUS = 16


def phone(raw_path, screen_w):
    """Return an RGBA phone image (body + rounded screen) for one raw capture, at SS scale."""
    sw = screen_w * SS
    sh = round(sw * 2313 / 1080)
    bz, rad = BEZEL * SS, RADIUS * SS
    img = Image.new('RGBA', (sw + 2 * bz, sh + 2 * bz), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=rad + bz, fill=(18, 18, 18, 255))
    d.rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=rad + bz, outline=(48, 48, 48, 255), width=SS)
    raw = Image.open(raw_path).convert('RGB')
    scale = max(sw / raw.width, sh / raw.height)
    rw, rh = round(raw.width * scale), round(raw.height * scale)
    content = raw.resize((rw, rh), Image.LANCZOS)
    ox, oy = (rw - sw) // 2, (rh - sh) // 2
    content = content.crop((ox, oy, ox + sw, oy + sh))
    mask = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=rad, fill=255)
    img.paste(content, (bz, bz), mask)
    return img


def shadow(size, radius, blur, alpha=110):
    from PIL import ImageFilter
    pad = blur * 3
    s = Image.new('RGBA', (size[0] + 2 * pad, size[1] + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(s).rounded_rectangle([pad, pad, pad + size[0] - 1, pad + size[1] - 1], radius=radius, fill=(0, 0, 0, alpha))
    return s.filter(ImageFilter.GaussianBlur(blur)), pad


def compose(out_path, raws):
    canvas = Image.new('RGBA', (W * SS, H * SS), BG + (255,))

    # Phones on the right: three screens, middle one forward, all cropped by the bottom edge
    phones = [phone(r, PHONE_SCREEN_W) for r in raws]
    centre_x = 735 * SS
    positions = [  # (x centre, y top), back to front
        (centre_x - 150 * SS, 150 * SS),
        (centre_x + 150 * SS, 150 * SS),
        (centre_x, 90 * SS),
    ]
    order = [0, 2, 1] if len(phones) == 3 else list(range(len(phones)))
    for idx, (cx, top) in zip(order, positions[: len(phones)]):
        p = phones[idx]
        x = cx - p.width // 2
        sh, pad = shadow(p.size, (RADIUS + BEZEL) * SS, 10 * SS)
        canvas.alpha_composite(sh, (x - pad + 4 * SS, top - pad + 10 * SS))
        canvas.alpha_composite(p, (x, top))

    # Left block: mark, wordmark, tagline
    draw = ImageDraw.Draw(canvas)
    logo = Image.open(LOGO).convert('RGBA')
    bbox = logo.getbbox()
    logo = logo.crop(bbox)
    logo_h = 96 * SS
    logo = logo.resize((round(logo.width * logo_h / logo.height), logo_h), Image.LANCZOS)
    left = 64 * SS
    canvas.alpha_composite(logo, (left, 96 * SS))

    title_font = ImageFont.truetype(FONT_BOLD, 60 * SS)
    draw.text((left + logo.width + 22 * SS, 108 * SS), 'Ticket Box', font=title_font, fill=WHITE)

    tag_font = ImageFont.truetype(FONT_MED, 30 * SS)
    y = 228 * SS
    for line in TAGLINE.split('\n'):
        draw.text((left, y), line, font=tag_font, fill=WHITE)
        y += 40 * SS

    pill_font = ImageFont.truetype(FONT_BOLD, 20 * SS)
    pills = ['Up next', 'Progress', 'Stats', 'Where to watch']
    px, py = left, 340 * SS
    for label in pills:
        tw = draw.textlength(label, font=pill_font)
        pw, ph = tw + 28 * SS, 40 * SS
        if px + pw > 470 * SS:
            px, py = left, py + ph + 12 * SS
        draw.rounded_rectangle([px, py, px + pw, py + ph], radius=ph // 2, outline=WHITE, width=2 * SS)
        draw.text((px + 14 * SS, py + 7 * SS), label, font=pill_font, fill=WHITE)
        px += pw + 12 * SS

    out = canvas.convert('RGB').resize((W, H), Image.LANCZOS)
    out.save(out_path, optimize=True)
    print('wrote', out_path, out.size)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    compose(sys.argv[1], sys.argv[2:])
