#!/usr/bin/env python3
"""Draws Zoon's alternate app icons into the asset catalog.

The crescent in `AppIcon` stays the default. These four are alternates a
person can pick in Settings > App > App icon; the build lists them in
ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES (Tools/generate-pbxproj.py).

For each one it writes an `.appiconset` with light, dark and tinted 1024 px
images, and a small `IconPreview*` image set the picker shows, because an
app icon set can't be loaded as an `Image` at runtime.

Textured moon and Moonrise use the app's own moon (MoonTexture, an
AI-generated image the owner supplied; see docs/ASSET-LEDGER.md). Ring and
Crescent + stars are drawn from shapes alone.

Run with a Python that has Pillow:  python3 Tools/generate-alternate-icons.py
"""

import json
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Zoon", "Assets.xcassets")
TEX = os.path.join(ASSETS, "MoonTexture.imageset", "moon.png")
S = 2048  # supersampled, scaled to 1024 at the end
TOP, BOTTOM = (16, 15, 34), (38, 30, 74)
VIOLET = (124, 108, 255)
CREAM = (246, 241, 226)

def background(top=TOP, bottom=BOTTOM):
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return im.convert("RGBA")

def glow(im, cx, cy, r, color=VIOLET, alpha=110, blur=180):
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (alpha,))
    im.alpha_composite(g.filter(ImageFilter.GaussianBlur(blur)))

def phase_mask(size, fill, waxing=True):
    """Lit region of a disc of `size` at lit fraction `fill` (0 new, 1 full)."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    R = size / 2
    a = abs(1 - 2 * fill) * R  # terminator half-width
    half = Image.new("L", (size, size), 0)
    ImageDraw.Draw(half).pieslice([0, 0, size - 1, size - 1], -90, 90, fill=255)  # right half
    ell = Image.new("L", (size, size), 0)
    ImageDraw.Draw(ell).ellipse([R - a, 0, R + a, size - 1], fill=255)
    m = ImageChops.subtract(half, ell) if fill < 0.5 else ImageChops.lighter(half, ell)
    if not waxing:
        m = m.transpose(Image.FLIP_LEFT_RIGHT)
    # soften the terminator a touch
    return m.filter(ImageFilter.GaussianBlur(size / 180))

def disc_mask(size):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse([0, 0, size - 1, size - 1], fill=255)
    return m

def textured_moon(size, fill, earthshine=0.10, waxing=True):
    tex = Image.open(TEX).convert("RGB").resize((size, size), Image.LANCZOS)
    # a slightly cool, lifted grade so it sits on navy
    tex = Image.blend(tex, Image.new("RGB", tex.size, (220, 224, 240)), 0.12)
    lit = phase_mask(size, fill, waxing)
    dark = Image.eval(tex.convert("L"), lambda v: int(v * earthshine)).convert("RGB")
    dark = Image.blend(dark, Image.new("RGB", tex.size, (40, 36, 80)), 0.5)
    moon = Image.composite(tex, dark, lit).convert("RGBA")
    moon.putalpha(disc_mask(size))
    return moon

def flat_moon(size, fill, color=CREAM, dark=(44, 38, 92), craters=True):
    base = Image.new("RGBA", (size, size), dark + (255,))
    litc = Image.new("RGBA", (size, size), color + (255,))
    if craters:
        rnd = random.Random(7)
        d = ImageDraw.Draw(litc)
        for _ in range(9):
            r = rnd.uniform(size * 0.03, size * 0.09)
            x = rnd.uniform(size * 0.2, size * 0.85); y = rnd.uniform(size * 0.15, size * 0.85)
            d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(c * 0.9) for c in color) + (255,))
    moon = Image.composite(litc, base, phase_mask(size, fill))
    moon.putalpha(disc_mask(size))
    return moon

def star(d, x, y, r, a=255):
    # four-point sparkle
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.28
        pts.append((x + rr * math.cos(ang), y + rr * math.sin(ang)))
    d.polygon(pts, fill=(255, 255, 255, a))

def finish(im, name):
    return im.convert("RGB").resize((1024, 1024), Image.LANCZOS)

# 1. Textured gibbous: the app's own moon at the phase the app draws it.
def textured():
    im = background()
    glow(im, S * 0.5, S * 0.5, S * 0.36, alpha=120)
    size = int(S * 0.64)
    moon = textured_moon(size, 0.62)
    im.alpha_composite(moon, ((S - size) // 2, (S - size) // 2))
    return finish(im, "1-textured.png")

# 2. Ring: a flat moon inside a progress ring, the app's ring motif.
def ring():
    im = background()
    glow(im, S * 0.5, S * 0.5, S * 0.3, alpha=90)
    c, R, w = S / 2, S * 0.34, S * 0.055
    track = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(track).arc([c - R, c - R, c + R, c + R], 0, 360, fill=(255, 255, 255, 30), width=int(w))
    im.alpha_composite(track)
    d = ImageDraw.Draw(im)
    d.arc([c - R, c - R, c + R, c + R], -90, -90 + 0.72 * 360, fill=VIOLET + (255,), width=int(w))
    # rounded cap at the end of the arc
    for ang in (-90, -90 + 0.72 * 360):
        t = math.radians(ang)
        x, y = c + (R - w / 2) * math.cos(t), c + (R - w / 2) * math.sin(t)
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=VIOLET + (255,))
    size = int(S * 0.40)
    im.alpha_composite(flat_moon(size, 0.62), (int(c - size / 2), int(c - size / 2)))
    return finish(im, "2-ring.png")

# 3. Crescent and stars: vector, cream on deep violet.
def crescent():
    im = background((22, 16, 52), (52, 36, 102))
    glow(im, S * 0.46, S * 0.52, S * 0.3, color=(160, 140, 255), alpha=80)
    size = int(S * 0.62)
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([0, 0, size - 1, size - 1], fill=255)
    off = size * 0.30
    d.ellipse([off, -size * 0.08, size - 1 + off, size - 1 - size * 0.08], fill=0)
    m = m.rotate(-18, resample=Image.BICUBIC)
    grad = Image.new("RGBA", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        gd.line([(0, y), (size, y)], fill=(255, int(246 - 22 * t), int(224 - 40 * t), 255))
    grad.putalpha(m)
    im.alpha_composite(grad, (int(S * 0.17), int(S * 0.19)))
    d = ImageDraw.Draw(im)
    star(d, S * 0.70, S * 0.30, S * 0.06)
    star(d, S * 0.79, S * 0.50, S * 0.032, 220)
    star(d, S * 0.62, S * 0.66, S * 0.022, 180)
    return finish(im, "3-crescent-stars.png")

# 4. Moonrise: a large textured moon breaking the top-right corner.
def moonrise():
    im = background((10, 10, 24), (34, 26, 70))
    size = int(S * 1.05)
    # Waning, so the lit limb faces down-left into the frame.
    moon = textured_moon(size, 0.78, earthshine=0.06, waxing=False)
    glow(im, S * 0.72, S * 0.28, S * 0.5, alpha=90, blur=220)
    im.alpha_composite(moon, (int(S * 0.36), int(-S * 0.40)))
    # a soft horizon of sleep: a dark band at the bottom
    band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for y in range(int(S * 0.62), S):
        t = (y - S * 0.62) / (S * 0.38)
        bd.line([(0, y), (S, y)], fill=(8, 8, 20, int(255 * min(1, t * 1.4))))
    im.alpha_composite(band)
    return finish(im, "4-moonrise.png")


# (asset name, preview name, drawing)
ICONS = [
    ("AppIconTextured", "IconPreviewTextured", textured),
    ("AppIconRing", "IconPreviewRing", ring),
    ("AppIconCrescent", "IconPreviewCrescent", crescent),
    ("AppIconMoonrise", "IconPreviewMoonrise", moonrise),
]


def appiconset(name, image):
    folder = os.path.join(ASSETS, f"{name}.appiconset")
    os.makedirs(folder, exist_ok=True)
    # Each design is already a night scene, so dark appearance uses it as is.
    # Tinted is the luminance alone: iOS colours it with the person's tint.
    image.save(os.path.join(folder, "icon-1024.png"), optimize=True)
    image.save(os.path.join(folder, "icon-1024-dark.png"), optimize=True)
    image.convert("L").convert("RGB").save(os.path.join(folder, "icon-1024-tinted.png"), optimize=True)
    entry = {"idiom": "universal", "platform": "ios", "size": "1024x1024"}
    contents = {
        "images": [
            dict(entry, filename="icon-1024.png"),
            dict(entry, filename="icon-1024-dark.png",
                 appearances=[{"appearance": "luminosity", "value": "dark"}]),
            dict(entry, filename="icon-1024-tinted.png",
                 appearances=[{"appearance": "luminosity", "value": "tinted"}]),
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")


def preview(name, image):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    image.resize((180, 180), Image.LANCZOS).save(os.path.join(folder, "preview.png"), optimize=True)
    contents = {
        "images": [{"filename": "preview.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")


def main():
    for name, preview_name, draw in ICONS:
        image = draw()
        appiconset(name, image)
        preview(preview_name, image)
        print("wrote", name, preview_name)
    # The default icon's preview, from the committed artwork.
    default = Image.open(os.path.join(ASSETS, "AppIcon.appiconset", "icon-1024.png")).convert("RGB")
    preview("IconPreviewDefault", default)
    print("wrote IconPreviewDefault")


if __name__ == "__main__":
    main()
