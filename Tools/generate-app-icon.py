"""Draws Zoon's app icon.

The icon is geometry, not a picture, so it lives as the code that produces it
rather than as a binary nobody can edit. Re-run this and copy the three PNGs
into `Zoon/Assets.xcassets/AppIcon.appiconset` (and the default one into
`ZoonWatch/...`).

**What it is.** A crescent moon. Nothing else.

**What it replaced, twice.** First a photographic crescent — crater detail, a
star field, nebula wisps, 1.3 MB — all of which survives only at 1024 px and
turned to mud at the 60 px the home screen actually draws.

Then a solid crescent inside a 240-degree amber-to-mint gauge arc, on the
reasoning that the arc echoed the app's own shortfall gauge. On a real home
screen that reasoning did not survive contact: the ring reads as a progress
spinner, it competes with the moon for the eye, and the crescent inside it was
squat enough to look like a bitten disc rather than a moon. An icon is not the
place to make an argument about internal consistency.

**The geometry.** Two circles. The moon is one; the second is subtracted from
it, very slightly larger and offset by a little under half a radius. Equal
radii would give a crescent whose horns taper to nothing at exactly the top
and bottom; the slightly larger cut pulls the horns in and sharpens them,
which is what reads as a moon rather than as a letter C.

Tilted 18 degrees, because a crescent hanging dead vertical looks like a logo
and a crescent in the sky never is. Modest on purpose: past about 25 degrees
it starts to read as a shape at an angle rather than as a moon.

The body carries a faint vertical gradient, warm ivory at the top to a cool
pale blue at the bottom, and sits in a soft glow. Both are nearly invisible at
1024 px and doing real work at 60: they are what keeps the crescent from
flattening into a paper cut-out when every other cue is gone.

Three appearances, as iOS 18 expects:

  default   navy ground, gradient crescent
  dark      identical artwork on a transparent ground
  tinted    luminance greyscale on transparent; the system applies the tint
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S, SS = 1024, 4          # output size, and the supersample factor
NAVY   = (11, 11, 18)
NAVY2  = (26, 24, 50)
MOON_W = (255, 250, 240)  # warm ivory, top
MOON_C = (214, 226, 246)  # cool pale blue, bottom
GLOW   = (150, 170, 255)

TILT = 18.0               # degrees, horns up-right


def crescent_mask(size, cx, cy, r):
    """The crescent itself: a disc with a slightly larger disc taken out.

    `cut` bigger than `r` is what sharpens the horns. Equal radii leave them
    tapering to a hair exactly at top and bottom, which at icon sizes fills in
    and reads as a ring.
    """
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    cut = r * 1.04
    dx = r * 0.46
    d.ellipse([cx + dx - cut, cy - cut, cx + dx + cut, cy + cut], fill=0)
    return m.rotate(TILT, resample=Image.BICUBIC, center=(cx, cy))


def centred(mask, size):
    """Shifts a mask so its own bounding box sits in the middle of the canvas.

    A crescent is not centred on the circle it was cut from: subtracting a
    disc offset to the right leaves all the remaining mass on the left, so
    drawing it at the canvas centre puts it visibly left of centre. The first
    render of this icon did exactly that.

    Measuring the bbox rather than hand-tuning an offset means the geometry
    above can be changed without this silently going wrong again.
    """
    box = mask.getbbox()
    if box is None:
        return mask
    left, top, right, bottom = box
    dx = int(size[0] / 2 - (left + right) / 2)
    dy = int(size[1] / 2 - (top + bottom) / 2)
    return ImageChops.offset(mask, dx, dy)


def vertical_gradient(size, top, bottom):
    g = Image.new("RGBA", size, top + (255,))
    d = ImageDraw.Draw(g)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size[0], y)], fill=c + (255,))
    return g


def build(background):
    size = (S * SS, S * SS)
    if background == "navy":
        im = vertical_gradient(size, NAVY2, NAVY)
    else:
        im = Image.new("RGBA", size, (0, 0, 0, 0))

    cx, cy = size[0] * 0.5, size[1] * 0.5
    # Large enough that the crescent is still unmistakable at 40 px, with
    # enough ground left that it does not crowd the corner radius.
    r = S * SS * 0.315
    mask = centred(crescent_mask(size, cx, cy, r), size)

    # Glow first, so the moon sits in it rather than on it. Blur radius is a
    # fraction of the canvas so it survives the downsample unchanged.
    glow = Image.new("RGBA", size, GLOW + (255,))
    halo = mask.filter(ImageFilter.GaussianBlur(S * SS * 0.022)).point(
        lambda v: int(v * 0.30)
    )
    im.paste(glow, (0, 0), halo)

    body = vertical_gradient(size, MOON_W, MOON_C)
    im.paste(body, (0, 0), mask)
    return im.resize((S, S), Image.LANCZOS)


def to_tinted(im):
    """Greyscale by luminance on a transparent ground; the system tints it."""
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    px, op = im.load(), out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = int(0.2126 * r + 0.7152 * g + 0.0722 * b)
            op[x, y] = (lum, lum, lum, a)
    return out


light = build("navy")
light.convert("RGB").save("icon-1024.png")
dark = build("clear")
dark.save("icon-1024-dark.png")
to_tinted(dark).save("icon-1024-tinted.png")

# A contact sheet at the sizes that actually matter. The 1024 px render is
# not the thing being judged -- 60 px is the home screen and 40 px is
# Spotlight, and every icon this file has replaced looked fine at 1024.
SIZES = [180, 120, 60, 40]
GUTTER, PAD = 28, 24
row_h = max(SIZES) + GUTTER
col_x, x = [], PAD
for px in SIZES:
    col_x.append(x)
    x += px + GUTTER
sheet = Image.new("RGB", (x + PAD - GUTTER, PAD * 2 + row_h * 3 - GUTTER), (28, 28, 34))
for i, f in enumerate(["icon-1024.png", "icon-1024-dark.png", "icon-1024-tinted.png"]):
    im = Image.open(f).convert("RGBA")
    flat = Image.new("RGBA", im.size, (20, 20, 26, 255))
    flat.alpha_composite(im)
    for j, px in enumerate(SIZES):
        thumb = flat.resize((px, px), Image.LANCZOS).convert("RGB")
        # Bottom-aligned within the row so the sizes read as a ramp.
        sheet.paste(thumb, (col_x[j], PAD + i * row_h + (max(SIZES) - px)))
sheet.save("icon-contact-sheet.png")
print("wrote icon-1024.png, -dark, -tinted, and icon-contact-sheet.png")
