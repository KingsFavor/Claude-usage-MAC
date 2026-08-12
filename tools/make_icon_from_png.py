#!/usr/bin/env python3
"""Build AppIcon iconset from packaging/logo_src.png: white pixel-art on a black squircle.

Usage:  python3 tools/make_icon_from_png.py [out.iconset]
Then:   iconutil -c icns <out.iconset> -o packaging/AppIcon.icns

The source logo stores its shape in the PNG alpha channel (RGB is ~black), so
the artwork is lifted from alpha, level-stretched to crisp white, and centered
on a black rounded-rect matching the macOS icon grid.
"""
import os, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "packaging", "logo_src.png")
OUT_ICONSET = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "packaging", "AppIcon.iconset")

# --- Extract artwork from the alpha channel (that's where the white shape lives) ---
im = Image.open(SRC).convert("RGBA")
alpha = im.split()[3]
art = alpha.crop(alpha.getbbox())  # tight crop to the pixel-art subject

# Level-stretch alpha -> crisp white intensity (kills the soft haze, keeps AA edges).
lo, hi = 0.22, 0.60
lut = [0 if v/255 <= lo else 255 if v/255 >= hi
       else round(255 * ((v/255 - lo) / (hi - lo))) for v in range(256)]
art = art.point(lut)

# --- Master canvas at 1024, supersampled 2x for clean edges ---
def render(px):
    ss = 2
    S = px * ss
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    # Black squircle background (transparent margin), matching prior icon geometry.
    margin = S * 0.06
    inner = S - 2 * margin
    radius = inner * 0.2237
    draw.rounded_rectangle(
        [margin, margin, S - margin, S - margin],
        radius=radius, fill=(0, 0, 0, 255))

    # White artwork, centered. Wide subject -> constrain by width.
    target_w = inner * 0.82
    scale = target_w / art.width
    aw, ah = round(art.width * scale), round(art.height * scale)
    art_r = art.resize((aw, ah), Image.LANCZOS)
    ox, oy = round((S - aw) / 2), round((S - ah) / 2)
    # Paste solid white using the artwork as its own alpha mask.
    white = Image.new("RGBA", (aw, ah), (255, 255, 255, 255))
    canvas.paste(white, (ox, oy), art_r)

    return canvas.resize((px, px), Image.LANCZOS)

sizes = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
os.makedirs(OUT_ICONSET, exist_ok=True)
for name, px in sizes:
    render(px).save(os.path.join(OUT_ICONSET, name + ".png"))
# A standalone 1024 preview for review.
render(1024).save(os.path.join(os.path.dirname(OUT_ICONSET), "icon_preview.png"))
print("wrote iconset ->", OUT_ICONSET)
