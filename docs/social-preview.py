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

def px(v): return v * S

img = Image.new("RGB", (W, H), LIMEWASH)
d = ImageDraw.Draw(img)

def tracked(x, y, text, font, fill, track):
    cx = x
    for ch in text:
        d.text((cx, y), ch, font=font, fill=fill)
        cx += d.textlength(ch, font=font) + px(track)

# ---- left Laurisilva band + Falu seam ----
BAND = px(520)
d.rectangle([0, 0, BAND, H], fill=LAURISILVA)
d.rectangle([BAND, 0, BAND + px(8), H], fill=FALU)

LX = px(80)
tracked(LX, px(150), "GIT-WORKTREE DEV ENVIRONMENTS", sfmono(15, "Medium"),
        blend(LIMEWASH, LAURISILVA, 0.25), 4)

wm = sf(104, "Bold")
d.text((LX - px(4), px(182)), "ataegina", font=wm, fill=LIMEWASH)
ww = d.textlength("ataegina", font=wm)
d.rectangle([LX, px(326), LX + ww * 0.46, px(326) + px(9)], fill=blend(OCEAN, LIMEWASH, 0.35))

tg = sf(34, "Regular")
for i, line in enumerate(["Collision-free ports,", "processes and databases",
                          "for every git worktree."]):
    d.text((LX, px(362) + i * px(46)), line, font=tg, fill=blend(LIMEWASH, LAURISILVA, 0.05))

d.text((LX, px(566)), "github.com/noahhyden/ataegina-cli", font=sfmono(18),
       fill=blend(LIMEWASH, LAURISILVA, 0.3))

# ---- right side: terminal panel + chips on limewash ----
PX0, PY0, PX1, PY1 = BAND + px(70), px(190), px(1200), px(452)
d.rounded_rectangle([PX0, PY0, PX1, PY1], radius=px(16), fill=BASALT)

dx = PX0 + px(26)
for col in (FALU, GRANITE, LAURISILVA):
    r = px(7); cyd = PY0 + px(28)
    d.ellipse([dx, cyd, dx + 2 * r, cyd + 2 * r], fill=blend(col, LIMEWASH, 0.18))
    dx += px(26)

FE = blend(LAURISILVA, LIMEWASH, 0.5)   # frontend port color
BE = blend(OCEAN, LIMEWASH, 0.6)        # backend port color
DIM = blend(LIMEWASH, BASALT, 0.35)
m = menlo(21)
ix = PX0 + px(28); ty = PY0 + px(70)
d.text((ix, ty), "$ ", font=m, fill=FE)
d.text((ix + d.textlength("$ ", font=m), ty), "ataegina ports", font=m, fill=LIMEWASH)

ry = ty + px(46)
for label, fp, bp in [("worktree 0", ":5173", ":8000"),
                      ("worktree 1", ":5174", ":8001"),
                      ("worktree 2", ":5175", ":8002")]:
    d.text((ix, ry), label, font=m, fill=DIM)
    cx = ix + d.textlength(label + "    ", font=m)
    d.text((cx, ry), fp, font=m, fill=FE);  cx += d.textlength(fp, font=m)
    d.text((cx, ry), " / ", font=m, fill=DIM); cx += d.textlength(" / ", font=m)
    d.text((cx, ry), bp, font=m, fill=BE)
    ry += px(40)

cf = sfmono(18); cx, cy = PX0, px(486)
for i, c in enumerate(["zero-dependency", "single bash file", "macOS + Linux"]):
    if i:
        d.text((cx, cy), "·", font=cf, fill=LAURISILVA); cx += d.textlength("·", font=cf) + px(12)
    d.text((cx, cy), c, font=cf, fill=GRANITE); cx += d.textlength(c, font=cf) + px(12)

img.resize((1280, 640), Image.LANCZOS).save(OUT)
print("saved", OUT)
