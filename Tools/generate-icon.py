#!/usr/bin/env python3
"""Draw Zoon's app icon: a waxing crescent you can read as a moon.

The previous mark cut a diagonal band through a disc (a Z-shaped eclipse).
At 29px that read as a banana or a C, not the moon the first-run screen
uses. This file draws a dim full sphere first, then a thick bright limb
on the right — the same geometry as the in-app crescent.

Pure standard library. Rendered at 4x and box-downsampled.

    python3 Tools/generate-icon.py
"""
import math
import os
import struct
import zlib

SIZE = 1024
SS = 4
W = SIZE * SS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SKY = (0.024, 0.031, 0.067)
SKY_DARK = (0.012, 0.016, 0.035)
# Unlit face — bright enough that the full disc reads at 29px.
DIM = (0.46, 0.51, 0.62)
DISC = (0.97, 0.975, 0.99)
LIMB = (0.84, 0.88, 1.00)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def luminance(colour):
    r, g, b = colour
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def render(ground, dim, disc, limb):
    """Full moon disc, then a waxing crescent on top, then a thin rim."""
    cx = cy = 0.5 * W
    r_moon = 0.34 * W
    ox = cx - 0.12 * W
    oy = cy - 0.01 * W
    r_occ = 0.325 * W
    r_occ2 = r_occ * r_occ
    rim = r_moon * 0.04

    rows = []
    acc = [[0.0, 0.0, 0.0] for _ in range(SIZE)]

    for y in range(W):
        dy = y - cy
        ody = y - oy
        for x in range(W):
            colour = ground
            dx = x - cx
            dist2 = dx * dx + dy * dy
            outer = r_moon + rim
            if dist2 <= outer * outer:
                dist = math.sqrt(dist2)
                if dist > r_moon:
                    fade = 1.0 - (dist - r_moon) / rim
                    colour = mix(ground, mix(dim, disc, 0.4), fade * 0.85)
                else:
                    nr = dist / r_moon
                    light = 0.62 + 0.38 * max(0.0, (-dx * 0.28 - dy * 0.5) / r_moon + 0.2)
                    colour = mix(mix(ground, dim, 0.72), dim, min(1.0, light))
                    colour = mix(colour, dim, 0.4 + 0.6 * (1.0 - nr * 0.3))

                    odx = x - ox
                    if odx * odx + ody * ody > r_occ2:
                        shine = mix(disc, limb, min(1.0, nr * 0.35))
                        colour = mix(colour, shine, 0.92)

            cell = acc[x // SS]
            cell[0] += colour[0]
            cell[1] += colour[1]
            cell[2] += colour[2]

        if (y + 1) % SS == 0:
            n = SS * SS
            row = bytearray()
            row.append(0)
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

    default_rows = render(SKY, DIM, DISC, LIMB)
    write_png(os.path.join(ios, 'icon-1024.png'), default_rows)
    write_png(os.path.join(watch, 'icon-1024.png'), default_rows)
    write_png(os.path.join(ios, 'icon-1024-dark.png'),
              render(SKY_DARK, mix(DIM, SKY_DARK, 0.12), DISC, LIMB))

    grey_ground = (luminance(SKY_DARK),) * 3
    write_png(os.path.join(ios, 'icon-1024-tinted.png'),
              render(grey_ground, (0.42, 0.42, 0.42), (0.96, 0.96, 0.96), (0.78, 0.78, 0.78)))


if __name__ == '__main__':
    main()
