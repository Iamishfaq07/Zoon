"""Draws Zoon's app icon.

The icon is geometry, not a picture, so it lives as the code that produces it
rather than as a binary nobody can edit. Re-run this and copy the three PNGs
into `Zoon/Assets.xcassets/AppIcon.appiconset` (and the default one into
`ZoonWatch/...`).

**What it replaces.** A photographic crescent: rendered crater detail, a star
field, and nebula wisps, at 1.3 MB. Every one of those survives only at
1024 px. At the 60 px the home screen actually draws, the craters became mud,
the stars became noise, and what was left was an undifferentiated crescent --
the most generic sleep-app silhouette there is.

**What it is.** A solid crescent inside a 240-degree open arc, gap at the
bottom, amber through mint. The arc is not decoration: it is the same
geometry and the same gradient as the app's own shortfall gauge, so the icon
and the first screen share a shape. Three candidates were rendered and judged
at 180, 60 and 40 px before this one was picked -- a tilted orbit ring merged
with the crescent at 60 px, and a bare crescent with a dot was clean but
indistinguishable from every other moon on the home screen.

Three appearances, as iOS 18 expects:

  default   navy ground, gradient arc
  dark      identical artwork on a transparent ground
  tinted    luminance greyscale on transparent; the system applies the tint

No glow, no texture, no star field. About 65 KB each instead of 1.3 MB.
"""

from PIL import Image, ImageDraw
import math

S, SS = 1024, 4
NAVY   = (11, 11, 18)
NAVY2  = (26, 24, 50)
MOON   = (247, 244, 236)
AMBER  = (255, 169, 64)
MINT   = (0, 230, 118)

def crescent_mask(size, cx, cy, r, cut_dx, cut_r):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=255)
    d.ellipse([cx+cut_dx-cut_r, cy-cut_r, cx+cut_dx+cut_r, cy+cut_r], fill=0)
    return m

def arc_layer(size, cx, cy, R, w, start, sweep, c0, c1):
    """Gradient arc, drawn as overlapping segments so the sweep is smooth."""
    out = Image.new("RGBA", size, (0,0,0,0))
    steps = 300
    for i in range(steps):
        a0 = start + sweep * i / steps
        a1 = start + sweep * (i+1) / steps + 0.8
        t = i / (steps - 1)
        col = tuple(int(c0[j] + (c1[j]-c0[j]) * t) for j in range(3))
        m = Image.new("L", size, 0)
        ImageDraw.Draw(m).arc([cx-R, cy-R, cx+R, cy+R], a0, a1, fill=255, width=w)
        seg = Image.new("RGBA", size, col + (255,))
        out.paste(seg, (0,0), m)
    return out

def build(background):
    size = (S*SS, S*SS)
    if background == "navy":
        im = Image.new("RGBA", size, NAVY + (255,))
        d = ImageDraw.Draw(im)
        for y in range(size[1]):
            t = 1 - y / size[1]
            c = tuple(int(NAVY[i] + (NAVY2[i]-NAVY[i]) * (t**2) * 0.9) for i in range(3))
            d.line([(0,y),(size[0],y)], fill=c + (255,))
    else:
        im = Image.new("RGBA", size, (0,0,0,0))

    cx, cy = size[0]*0.5, size[1]*0.5
    # Centred inside the ring, and large enough to survive 40 px.
    r = S*SS*0.215
    m = crescent_mask(size, cx - S*SS*0.012, cy, r, S*SS*0.125, r*0.94)
    moon = Image.new("RGBA", size, MOON + (255,))
    im.paste(moon, (0,0), m)

    # 240-degree open arc with the gap at the bottom -- the same geometry the
    # app's own shortfall gauge uses.
    R = S*SS*0.345
    w = int(S*SS*0.034)
    im.alpha_composite(arc_layer(size, cx, cy, R, w, 150, 240, AMBER, MINT))
    return im.resize((S, S), Image.LANCZOS)

def to_tinted(im):
    """Greyscale by luminance on a transparent ground; the system tints it."""
    out = Image.new("RGBA", im.size, (0,0,0,0))
    px, op = im.load(), out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r,g,b,a = px[x,y]
            if a == 0: continue
            lum = int(0.2126*r + 0.7152*g + 0.0722*b)
            op[x,y] = (lum, lum, lum, a)
    return out

light = build("navy")
light.convert("RGB").save("icon-1024.png")
dark = build("clear")
dark.save("icon-1024-dark.png")
to_tinted(dark).save("icon-1024-tinted.png")

sheet = Image.new("RGB", (760, 300), (28,28,34))
for i, f in enumerate(["icon-1024.png", "icon-1024-dark.png", "icon-1024-tinted.png"]):
    im = Image.open(f).convert("RGBA")
    flat = Image.new("RGBA", im.size, (20,20,26,255)); flat.alpha_composite(im)
    x = 30 + i*240
    sheet.paste(flat.convert("RGB").resize((180,180), Image.LANCZOS), (x, 20))
    sheet.paste(flat.convert("RGB").resize((60,60), Image.LANCZOS), (x+15, 215))
    sheet.paste(flat.convert("RGB").resize((40,40), Image.LANCZOS), (x+100, 225))
sheet.save("final-compare.png")
import os
for f in ["icon-1024.png","icon-1024-dark.png","icon-1024-tinted.png"]:
    print(f, os.path.getsize(f)//1024, "KB")
