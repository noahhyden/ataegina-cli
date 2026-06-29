#!/usr/bin/env python3
"""Regenerate docs/social-preview.png — the repo's GitHub social preview card.

This is the 1280x640 image uploaded under
  Settings -> General -> Social preview
(it is stored by GitHub on upload; it does not need to live in the repo, but we
keep it here so the card is reproducible).

Requires Pillow (`pip install Pillow`) and the macOS system fonts (SF, Menlo);
it is rendered at 2x and downsampled for crisp anti-aliasing. Run from anywhere:
  python3 docs/social-preview.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

S = 2                      # supersample factor
W, H = 1280 * S, 640 * S
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "social-preview.png")

# palette
LIMEWASH   = (229, 228, 219)
BASALT     = ( 23,  30,  26)
LAURISILVA = ( 59,  91,  71)
OCEAN      = ( 59,  86, 105)
FALU       = (128,  24,  24)
GRANITE    = (113, 111, 101)

def blend(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

GREEN_TINT = blend(LAURISILVA, LIMEWASH, 0.45)   # readable green on dark panel
DIM_TEXT   = blend(LIMEWASH,  BASALT,   0.30)     # dimmed limewash on dark

def sf(size, weight=None):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size * S)
    if weight:
        try: f.set_variation_by_name(weight)
        except Exception: pass
    return f

def menlo(size, idx=0):
    return ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", size * S, index=idx)

def sfmono(size, weight=None):
    f = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", size * S)
    if weight:
        try: f.set_variation_by_name(weight)
        except Exception: pass
    return f

img = Image.new("RGB", (W, H), LIMEWASH)
d = ImageDraw.Draw(img)

def px(v): return v * S

# left accent edge
d.rectangle([0, 0, px(8), H], fill=FALU)

def draw_tracked(x, y, text, font, fill, track):
    cx = x
    for ch in text:
        d.text((cx, y), ch, font=font, fill=fill)
        cx += d.textlength(ch, font=font) + px(track)
    return cx

LX = px(108)
draw_tracked(LX, px(150), "GIT-WORKTREE DEV ENVIRONMENTS", sfmono(15, "Medium"), GRANITE, 4)

# wordmark
wm_font = sf(112, "Bold")
d.text((LX - px(4), px(178)), "ataegina", font=wm_font, fill=BASALT)
wm_w = d.textlength("ataegina", font=wm_font)
d.rectangle([LX, px(330), LX + wm_w * 0.46, px(330) + px(9)], fill=FALU)

# tagline
tg = sf(37, "Regular")
d.text((LX, px(366)), "Collision-free ports, processes and", font=tg, fill=BASALT)
d.text((LX, px(366) + px(50)), "databases for every git worktree.", font=tg, fill=BASALT)

# chips
chip_f = sfmono(19, "Regular")
cx, cy = LX, px(486)
for i, c in enumerate(["zero-dependency", "single bash file", "macOS + Linux"]):
    if i:
        d.text((cx, cy), "·", font=chip_f, fill=LAURISILVA)
        cx += d.textlength("·", font=chip_f) + px(14)
    d.text((cx, cy), c, font=chip_f, fill=GRANITE)
    cx += d.textlength(c, font=chip_f) + px(14)

# terminal panel
PX0, PY0, PX1, PY1 = px(726), px(168), px(1172), px(470)
d.rounded_rectangle([PX0, PY0, PX1, PY1], radius=px(16), fill=BASALT)

dx = PX0 + px(26)
for col in (FALU, GRANITE, LAURISILVA):
    r = px(7); cyd = PY0 + px(28)
    d.ellipse([dx, cyd, dx + 2 * r, cyd + 2 * r], fill=blend(col, LIMEWASH, 0.18))
    dx += px(26)

m = menlo(21)
ix = PX0 + px(28)
ty = PY0 + px(70)
d.text((ix, ty), "$ ", font=m, fill=GREEN_TINT)
d.text((ix + d.textlength("$ ", font=m), ty), "ataegina ports", font=m, fill=LIMEWASH)

ry = ty + px(46)
for label, ports in [("worktree 0", ":5173 / :8000"),
                     ("worktree 1", ":5174 / :8001"),
                     ("worktree 2", ":5175 / :8002")]:
    d.text((ix, ry), label, font=m, fill=DIM_TEXT)
    d.text((ix + d.textlength(label + "    ", font=m), ry), ports, font=m, fill=GREEN_TINT)
    ry += px(40)

# footer url
d.text((LX, px(566)), "github.com/noahhyden/ataegina-cli", font=sfmono(18, "Regular"), fill=GRANITE)

img.resize((1280, 640), Image.LANCZOS).save(OUT)
print("saved", OUT)
