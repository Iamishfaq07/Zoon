#!/usr/bin/env python3
"""Draw Zoon's app icon.

The icon is generated rather than committed as an opaque binary so it has
provenance: the palette below is the same one `Theme.swift` uses, and changing
the app's colours means changing two files that visibly agree rather than
hoping someone re-exports a PNG.

Pure standard library — no Pillow on the runner, and adding a dependency to
draw one circle would be a poor trade. PNG is a simple enough container to
write directly: filter-0 scanlines, zlib-deflated, three chunks.

Rendered at 4x and box-downsampled, which is what gives the crescent a clean
edge; there is no path rasteriser here to anti-alias for us.

    python3 Tools/generate-icon.py

Writes Zoon/Assets.xcassets/AppIcon.appiconset/icon-1024.png.

iOS 17+ takes a single 1024x1024 image and derives every other size, so this
is the only asset needed. It is deliberately full-bleed and square: the system
applies the rounded-rect mask, and baking one in produces a visibly wrong icon
with dark corners.
"""
import math
import os
import struct
import zlib

SIZE = 1024
SS = 4                      # supersampling factor
W = SIZE * SS

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'Zoon', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png',
)

# Theme.background, top to bottom. Kept in sync with Shared/Theme.swift.
SKY = [
    (0.024, 0.031, 0.078),
    (0.051, 0.063, 0.141),
    (0.078, 0.063, 0.200),
]
# Theme.Metric.sleep — the app's primary hue, used for the glow.
GLOW = (0.482, 0.380, 1.00)
MOON = (0.98, 0.96, 0.90)


def lerp(a, b, t):
    return a + (b - a) * t


def sky_at(y):
    """Vertical gradient through the three sky stops."""
    t = y / (W - 1)
    if t < 0.5:
        u = t / 0.5
        return tuple(lerp(SKY[0][i], SKY[1][i], u) for i in range(3))
    u = (t - 0.5) / 0.5
    return tuple(lerp(SKY[1][i], SKY[2][i], u) for i in range(3))


def main():
    cx, cy = W * 0.52, W * 0.50
    r_moon = W * 0.30
    # The bite. Offset up and right so the crescent opens toward the lower
    # left, which is where the glow sits — a crescent lit from the same side
    # as its glow reads as flat.
    bx, by = cx + r_moon * 0.52, cy - r_moon * 0.30
    r_bite = r_moon * 0.92

    glow_r = r_moon * 2.1

    # Stars: fixed positions, no RNG, so the icon is byte-identical every run.
    stars = [
        (0.170, 0.205, 0.0075), (0.300, 0.128, 0.0045), (0.815, 0.190, 0.0060),
        (0.128, 0.560, 0.0050), (0.222, 0.815, 0.0065), (0.870, 0.700, 0.0042),
        (0.760, 0.855, 0.0055), (0.400, 0.900, 0.0038), (0.640, 0.085, 0.0035),
    ]
    stars = [(sx * W, sy * W, sr * W) for sx, sy, sr in stars]

    # Accumulate at full supersampled width one row at a time, folding each
    # block of SS rows down immediately. Holding a 4096x4096 RGB buffer would
    # be ~200 MB of Python floats; this keeps it to a few megabytes.
    rows = []
    acc = [[0.0, 0.0, 0.0] for _ in range(SIZE)]

    for y in range(W):
        base = sky_at(y)
        for x in range(W):
            r, g, b = base

            # Soft radial glow behind the moon.
            d = math.hypot(x - cx, y - cy)
            if d < glow_r:
                t = 1.0 - d / glow_r
                a = 0.34 * t * t * t
                r = lerp(r, GLOW[0], a)
                g = lerp(g, GLOW[1], a)
                b = lerp(b, GLOW[2], a)

            # Stars, drawn under the moon so none appear on top of it.
            for sx, sy, sr in stars:
                sd = math.hypot(x - sx, y - sy)
                if sd < sr * 3.0:
                    a = max(0.0, 1.0 - sd / (sr * 3.0)) ** 2.2
                    r = lerp(r, 1.0, a * 0.85)
                    g = lerp(g, 1.0, a * 0.85)
                    b = lerp(b, 1.0, a * 0.90)

            # The crescent: inside the moon, outside the bite.
            if d < r_moon and math.hypot(x - bx, y - by) >= r_bite:
                # Very slight vertical shading so it reads as a sphere edge
                # rather than a flat sticker.
                shade = 1.0 - 0.10 * ((y - (cy - r_moon)) / (2 * r_moon))
                r, g, b = (MOON[0] * shade, MOON[1] * shade, MOON[2] * shade)

            ox = x // SS
            cell = acc[ox]
            cell[0] += r
            cell[1] += g
            cell[2] += b

        if (y + 1) % SS == 0:
            n = SS * SS
            row = bytearray()
            row.append(0)  # filter type 0 (None)
            for cell in acc:
                for c in cell:
                    v = int(round(min(1.0, max(0.0, c / n)) * 255))
                    row.append(v)
            rows.append(bytes(row))
            acc = [[0.0, 0.0, 0.0] for _ in range(SIZE)]

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    # Colour type 2 (truecolour, no alpha). App icons must be fully opaque —
    # an alpha channel is a submission rejection, and the icon has no
    # transparent region anyway.
    ihdr = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(b''.join(rows), 9))
           + chunk(b'IEND', b''))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'wb') as handle:
        handle.write(png)
    print(f"wrote {OUT} ({len(png):,} bytes)")


if __name__ == '__main__':
    main()
