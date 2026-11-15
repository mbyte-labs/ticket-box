#!/usr/bin/env python3
"""Compose raw emulator screencaps into the images the root README shows (docs/screenshots/): a capture
inside a dark device bezel on a transparent background, so it reads on GitHub's light and dark themes.

Usage:
    compose_readme.py phone  raw.png out.png            # one framed phone capture
    compose_readme.py tablet raw.png out.png            # one framed tablet capture (landscape)
    compose_readme.py hero   tablet_raw.png phone_raw.png out.png   # tablet with the phone in front

Bezel colours and the phone's proportions come from compose.py, so the README matches the Play listing.
Requires Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageFilter

from compose import BEZEL, BODY, RING, SCREEN_RADIUS, SCREEN_W

# Output widths in pixels, bezel included. GitHub scales them down; these keep the files small.
PHONE_OUT_W = 560
TABLET_OUT_W = 1400

# Tablet bezel, in raw-capture pixels (a 2560 px wide capture).
TABLET_RADIUS = 46
TABLET_BEZEL = 58

# Hero layout, as fractions of the framed tablet.
HERO_PHONE_HEIGHT = 0.78  # phone height relative to the tablet's height
HERO_PHONE_OVERHANG_X = 0.06  # how far the phone sticks out past the tablet's right edge (of tablet width)
HERO_PHONE_OVERHANG_Y = 0.07  # and below its bottom edge (of tablet height)
SHADOW_BLUR = 28
SHADOW_ALPHA = 110


def frame(raw_path, radius, bezel):
    """The capture at its own resolution inside a rounded dark body, RGBA with a transparent background."""
    raw = Image.open(raw_path).convert('RGB')
    w, h = raw.size
    body = Image.new('RGBA', (w + 2 * bezel, h + 2 * bezel), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    box = [0, 0, body.width - 1, body.height - 1]
    draw.rounded_rectangle(box, radius=radius + bezel, fill=BODY + (255,))
    draw.rounded_rectangle(box, radius=radius + bezel, outline=(40, 40, 40, 255), width=3)
    draw.rounded_rectangle([bezel - 3, bezel - 3, bezel + w + 2, bezel + h + 2], radius=radius + 3, fill=RING + (255,))
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    body.paste(raw, (bezel, bezel), mask)
    return body


def phone(raw_path):
    scale = Image.open(raw_path).width / SCREEN_W  # compose.py's geometry is for a 902 px wide screen
    return frame(raw_path, round(SCREEN_RADIUS * scale), round(BEZEL * scale))


def tablet(raw_path):
    return frame(raw_path, TABLET_RADIUS, TABLET_BEZEL)


def fit_width(img, width):
    return img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)


def hero(tablet_raw, phone_raw):
    tab = fit_width(tablet(tablet_raw), TABLET_OUT_W)
    ph = phone(phone_raw)
    ph_h = round(tab.height * HERO_PHONE_HEIGHT)
    ph = ph.resize((round(ph.width * ph_h / ph.height), ph_h), Image.LANCZOS)

    over_x, over_y = round(tab.width * HERO_PHONE_OVERHANG_X), round(tab.height * HERO_PHONE_OVERHANG_Y)
    canvas = Image.new('RGBA', (tab.width + over_x, tab.height + over_y), (0, 0, 0, 0))
    canvas.alpha_composite(tab, (0, 0))
    px, py = canvas.width - ph.width, canvas.height - ph.height

    # Soft shadow so the phone separates from the tablet behind it, clipped to the tablet's own shape.
    shadow = Image.new('L', canvas.size, 0)
    shadow.paste(ph.getchannel('A').point(lambda a: a * SHADOW_ALPHA // 255), (px - 14, py + 10))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
    tab_alpha = Image.new('L', canvas.size, 0)
    tab_alpha.paste(tab.getchannel('A'), (0, 0))
    black = Image.new('RGBA', canvas.size, (0, 0, 0, 255))
    black.putalpha(Image.composite(shadow, Image.new('L', canvas.size, 0), tab_alpha))
    canvas.alpha_composite(black)

    canvas.alpha_composite(ph, (px, py))
    return canvas


def save(img, out_path):
    img.save(out_path, optimize=True)
    print('wrote', out_path, img.size)


if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == 'phone':
        save(fit_width(phone(args[1]), PHONE_OUT_W), args[2])
    elif len(args) == 3 and args[0] == 'tablet':
        save(fit_width(tablet(args[1]), TABLET_OUT_W), args[2])
    elif len(args) == 4 and args[0] == 'hero':
        save(hero(args[1], args[2]), args[3])
    else:
        sys.exit(__doc__)
