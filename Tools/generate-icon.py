#!/usr/bin/env python3
"""Draw Zoon's app icon: the ZOON ECLIPSE mark.

The icon is generated rather than committed as an opaque binary so it has
provenance: the palette below is the same one `Theme.swift` uses, and changing
the app's colours means changing two files that visibly agree rather than
hoping someone re-exports a PNG.

Pure standard library -- no Pillow on the runner, and adding a dependency to
draw two circles would be a poor trade. PNG is a simple enough container to
write directly: filter-0 scanlines, zlib-deflated, three chunks.

Rendered at 4x and box-downsampled, which is what gives the disc a clean edge;
there is no path rasteriser here to anti-alias for us.

    python3 Tools/generate-icon.py

Writes the iPhone icon in three appearances (default, dark, tinted) and the
Watch icon.

## The mark

A bold lunar disc with one diagonal band cut out of it, and one small point
off its upper right.

The previous icon was a crescent moon over nine stars on a purple gradient,
which is the exact icon every sleep and meditation app on the store already
has -- it identified the category, not the product. This one is built from
three decisions:

**The cut is offset, not centred.** A band straight through the middle leaves
two equal halves and reads as a prohibition sign, which is a strong shape
carrying entirely the wrong meaning. Pushed off-centre it reads as what it is:
something passing in front of a disc. Roughly 54% of the disc survives as the
body, 25% as the cap above the cut.

**The cut descends to the left, which is the direction a Z's diagonal runs.**
The body's straight upper edge, the diagonal gap, and the cap's straight lower
edge trace the three strokes of a Z. It is meant to be noticed second, not
first, so nothing is distorted to strengthen it.

**One point, not a field of stars.** It sits on the cut's own axis, so it
reads as something in orbit rather than decoration, and it is the only place
the app's violet appears.

There is no text, no thin decorative linework, no baked glass or refraction,
and no gradient inside the mark -- all of which disappear below about 60pt
and none of which survive the tinted appearance at all. The silhouette is two
solid shapes, so it is the same mark at 1024, at 180, at 60, and in the Watch
grid.

## Appearances

iOS 18 asks for three, and they are not the same image recoloured:

- **Default** -- the bright disc on Zoon's night ground.
- **Dark** -- the same mark on a much deeper ground. Home screens in dark
  mode sit on dark wallpaper, and the default ground floats there as a
  visible bright square.
- **Tinted** -- greyscale by luminance, which is what the system re-colours
  with the user's chosen tint. Any hue here would be thrown away, so the
  violet point becomes the one mid-grey value instead and still separates
  from the disc.

The images are full-bleed and square: the system applies the rounded-rect
mask, and baking one in produces a visibly wrong icon with dark corners.
"""
import math
import os
import struct
import zlib

SIZE = 1024
SS = 4                      # supersampling factor
W = SIZE * SS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Theme.background, top to bottom. Kept in sync with Shared/Theme.swift.
SKY = [
    (0.024, 0.031, 0.078),
    (0.051, 0.063, 0.141),
    (0.078, 0.063, 0.200),
]
# The dark appearance sits on a much deeper version of the same three stops,
# so the two icons are recognisably one mark rather than two designs.
SKY_DARK = [tuple(c * 0.34 for c in stop) for stop in SKY]

# Theme.Metric.sleep -- the app's primary hue. The orbital point only.
ACCENT = (0.482, 0.380, 1.00)
DISC = (0.97, 0.955, 0.925)

# MARK: - Geometry, shared by every appearance.

CX = CY = 0.5
R_DISC = 0.30
# The cut descends to the left, like a Z's diagonal.
ANGLE = math.radians(38)
DIR = (-math.cos(ANGLE), math.sin(ANGLE))       # y grows downward
NORMAL = (-DIR[1], DIR[0])
CUT_HALF_WIDTH = 0.052
# Off-centre on purpose -- see the module docstring.
CUT_OFFSET = 0.070
# On the cut's own axis, clear of the disc.
DOT_DISTANCE = 0.368
DOT_RADIUS = 0.029


def lerp(a, b, t):
    return a + (b - a) * t


def sky_at(y, stops):
    """Vertical gradient through the three sky stops."""
    t = y / (W - 1)
    if t < 0.5:
        u = t / 0.5
        return tuple(lerp(stops[0][i], stops[1][i], u) for i in range(3))
    u = (t - 0.5) / 0.5
    return tuple(lerp(stops[1][i], stops[2][i], u) for i in range(3))


def luminance(colour):
    r, g, b = colour
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def render(ground, disc, accent):
    """One appearance, as a list of PNG scanlines.

    Accumulates at the supersampled width one row at a time, folding each
    block of SS rows down immediately. Holding a 4096x4096 RGB buffer would be
    ~200 MB of Python floats; this keeps it to a few megabytes.
    """
    cx, cy = CX * W, CY * W
    r_disc = R_DISC * W
    half = CUT_HALF_WIDTH * W
    offset = CUT_OFFSET * W
    dot_x = cx - DIR[0] * DOT_DISTANCE * W
    dot_y = cy - DIR[1] * DOT_DISTANCE * W
    dot_r = DOT_RADIUS * W

    rows = []
    acc = [[0.0, 0.0, 0.0] for _ in range(SIZE)]

    for y in range(W):
        base = sky_at(y, ground)
        dy = y - cy
        for x in range(W):
            r, g, b = base
            dx = x - cx

            # The disc, minus the band cut out of it.
            if dx * dx + dy * dy < r_disc * r_disc:
                signed = dx * NORMAL[0] + dy * NORMAL[1]
                if abs(signed - offset) >= half:
                    r, g, b = disc

            # The orbital point, drawn last so it is never eaten by the disc.
            if math.hypot(x - dot_x, y - dot_y) < dot_r:
                r, g, b = accent

            cell = acc[x // SS]
            cell[0] += r
            cell[1] += g
            cell[2] += b

        if (y + 1) % SS == 0:
            n = SS * SS
            row = bytearray()
            row.append(0)  # filter type 0 (None)
            for cell in acc:
                for c in cell:
                    row.append(int(round(min(1.0, max(0.0, c / n)) * 255)))
            rows.append(bytes(row))
            acc = [[0.0, 0.0, 0.0] for _ in range(SIZE)]

    return rows


def write_png(path, rows):
    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    # Colour type 2 (truecolour, no alpha). App icons must be fully opaque --
    # an alpha channel is a submission rejection, and the mark has no
    # transparent region anyway.
    ihdr = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(b''.join(rows), 9))
           + chunk(b'IEND', b''))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as handle:
        handle.write(png)
    print(f"wrote {path} ({len(png):,} bytes)")


def main():
    ios = os.path.join(ROOT, 'Zoon', 'Assets.xcassets', 'AppIcon.appiconset')
    watch = os.path.join(ROOT, 'ZoonWatch', 'Assets.xcassets', 'AppIcon.appiconset')

    default_rows = render(SKY, DISC, ACCENT)
    write_png(os.path.join(ios, 'icon-1024.png'), default_rows)
    # The Watch icon is the default appearance: watchOS has no dark or tinted
    # variant, and the mark is centred so the circular crop takes nothing.
    write_png(os.path.join(watch, 'icon-1024.png'), default_rows)

    write_png(os.path.join(ios, 'icon-1024-dark.png'),
              render(SKY_DARK, DISC, ACCENT))

    # Greyscale by luminance. The accent's own luminance is close enough to
    # the ground to vanish, so the point is given an explicit mid value --
    # it has to stay visible against the disc *and* the ground.
    grey_ground = [(luminance(stop),) * 3 for stop in SKY_DARK]
    write_png(os.path.join(ios, 'icon-1024-tinted.png'),
              render(grey_ground, (luminance(DISC),) * 3, (0.52, 0.52, 0.52)))


if __name__ == '__main__':
    main()
