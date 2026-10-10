#!/usr/bin/env python3
"""Composes Zoon's App Store screenshots from the app's own captures.

Each image is a headline over a real capture from `docs/screenshots/hires`
(written by the Screenshots workflow), framed as a phone on the app's night
gradient. The captures are the app as it renders, not mock-ups, so the set
stays honest: re-run the Screenshots workflow, then this, and the store
images follow the app.

Output: `docs/appstore/NN-name.png` at 1320 x 2868, the 6.9-inch iPhone size
App Store Connect asks for (it scales down for smaller displays).

Run with a Python that has Pillow:  python3 Tools/generate-appstore-screenshots.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "screenshots", "hires")
OUT = os.path.join(ROOT, "docs", "appstore")

W, H = 1320, 2868

# The app's night: near-black navy into a deeper violet, the same family as
# `nightBackground()`.
TOP = (12, 12, 22)
BOTTOM = (30, 26, 58)
GLOW = (124, 108, 255)
INK = (246, 244, 255)
INK2 = (176, 172, 206)

FONT_DIR = "/usr/share/fonts/opentype/inter"
BOLD = os.path.join(FONT_DIR, "InterDisplay-Bold.otf")
MEDIUM = os.path.join(FONT_DIR, "InterDisplay-Medium.otf")

# (capture, headline, supporting line). Every claim is one the app makes on
# its own screens: on-device processing, nothing recorded by Snore Check,
# answers drawn from the person's own nights.
SHOTS = [
    ("today-morning", "Last night,\nin one look", "Sleep, need and what you're owed, on one moon."),
    ("sleepDetail", "The whole night,\nstage by stage", "Deep, REM, heart rate and every awakening."),
    ("patterns", "See what helps\nand what doesn't", "Your habits, against your own nights."),
    ("snoreCheck", "Hear your night", "Snore Check works on your iPhone. Nothing is recorded."),
    ("tomorrow", "A plan for\ntomorrow", "Wind-down, bed and wake, built around your morning."),
    ("coach", "Ask about\nyour sleep", "Answers from your own data, on this device."),
    ("soundscapes", "Sounds to\nfall asleep to", "Noise, rain and nature, with a sleep timer."),
    ("trends", "How your sleep\nis changing", "Bounce-back, your baseline and how you compare."),
]


def gradient() -> Image.Image:
    base = Image.new("RGB", (W, H), TOP)
    draw = ImageDraw.Draw(base)
    for y in range(H):
        t = y / (H - 1)
        draw.line(
            [(0, y), (W, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)),
        )
    # A soft violet glow behind the phone, so the frame sits in light rather
    # than on a flat fill.
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.08, H * 0.30, W * 0.92, H * 0.78], fill=GLOW + (90,))
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    base = base.convert("RGBA")
    base.alpha_composite(glow)
    return base


def stars(img: Image.Image, seed: int) -> None:
    """A sparse, fixed star field in the headline area."""
    import random

    rnd = random.Random(seed)
    d = ImageDraw.Draw(img)
    for _ in range(46):
        x = rnd.uniform(0, W)
        y = rnd.uniform(0, H * 0.26)
        r = rnd.choice([1.2, 1.6, 2.2])
        a = rnd.randint(60, 170)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def phone(capture: Image.Image, width: int) -> Image.Image:
    """The capture with screen corners, a thin bezel and a soft edge light."""
    scale = width / capture.size[0]
    screen = capture.resize((width, round(capture.size[1] * scale)), Image.LANCZOS)
    bezel = 18
    radius = 118
    body = Image.new("RGBA", (screen.size[0] + bezel * 2, screen.size[1] + bezel * 2), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle(
        [0, 0, body.size[0] - 1, body.size[1] - 1], radius + bezel,
        fill=(18, 18, 26, 255), outline=(92, 88, 128, 255), width=3,
    )
    body.alpha_composite(rounded(screen, radius), (bezel, bezel))
    return body


def compose(name: str, headline: str, line: str, index: int) -> Image.Image:
    canvas = gradient()
    stars(canvas, seed=index)
    draw = ImageDraw.Draw(canvas)

    title_font = ImageFont.truetype(BOLD, 112)
    line_font = ImageFont.truetype(MEDIUM, 46)

    y = 190
    for row in headline.split("\n"):
        w = draw.textlength(row, font=title_font)
        draw.text(((W - w) / 2, y), row, font=title_font, fill=INK)
        y += 128
    y += 18
    w = draw.textlength(line, font=line_font)
    if w > W - 300:
        # Two lines for a long supporting line, split at the middle space.
        words = line.split(" ")
        mid = len(words) // 2
        rows = [" ".join(words[:mid]), " ".join(words[mid:])]
    else:
        rows = [line]
    for row in rows:
        w = draw.textlength(row, font=line_font)
        draw.text(((W - w) / 2, y), row, font=line_font, fill=INK2)
        y += 62

    capture = Image.open(os.path.join(SRC, f"{name}.jpg")).convert("RGB")
    device = phone(capture, width=1000)
    top = max(y + 70, 760)
    x = (W - device.size[0]) // 2

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x + 10, top + 40, x + device.size[0] - 10, top + device.size[1]], 140, fill=(0, 0, 0, 150)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(device, (x, top))
    return canvas.convert("RGB")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for index, (name, headline, line) in enumerate(SHOTS, start=1):
        image = compose(name, headline, line, index)
        path = os.path.join(OUT, f"{index:02d}-{name}.png")
        image.save(path, optimize=True)
        print(f"wrote {os.path.relpath(path, ROOT)}  {image.size[0]}x{image.size[1]}")


if __name__ == "__main__":
    main()
