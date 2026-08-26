"""杖の黒シルエット画像を SVG のパスに変換する。

trace_sword.py の杖版。生成画像（白地に黒のシルエット）を potrace で輪郭化し、
assets/promo-src/logo/staff.svg に書き出す。渦の抜けは白い穴としてそのまま穴になる
（fill-rule="evenodd"）。杖は左右非対称な意匠なので対称化は無い。

    uv run --no-project --with pillow --with numpy --with potracer python tools/logo/trace_staff.py
"""
import numpy as np
from PIL import Image
import potrace

SRC = "assets/promo-src/logo/staff_01_raw.jpg"
OUT = "assets/promo-src/logo/staff.svg"
TARGET_H = 1000.0
TURDSIZE = 12  # これより小さい塊は捨てる（生成物のごみ取り）

im = Image.open(SRC).convert("L")
ink = np.asarray(im) < 128

ys, xs = np.nonzero(ink)
ink = ink[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
H, W = ink.shape
print("切り抜き後のビットマップ %d x %d" % (W, H))

path = potrace.Bitmap(~ink).trace(turdsize=TURDSIZE, alphamax=1.0, opticurve=1, opttolerance=0.2)

scale = TARGET_H / ink.shape[0]
w_out = ink.shape[1] * scale


def fmt(p):
    x = getattr(p, "x", None)
    if x is None:
        x, y = p[0], p[1]
    else:
        y = p.y
    return "%.2f,%.2f" % (x * scale, y * scale)


segs = []
for curve in path:
    d = ["M %s" % fmt(curve.start_point)]
    for seg in curve:
        if seg.is_corner:
            d.append("L %s" % fmt(seg.c))
            d.append("L %s" % fmt(seg.end_point))
        else:
            d.append("C %s %s %s" % (fmt(seg.c1), fmt(seg.c2), fmt(seg.end_point)))
    d.append("Z")
    segs.append(" ".join(d))

svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.2f %.2f" width="%.0f" height="%.0f">\n'
       '<path d="%s" fill="#333942" fill-rule="evenodd"/>\n</svg>\n'
       % (w_out, TARGET_H, w_out, TARGET_H, " ".join(segs)))
open(OUT, "w", encoding="utf-8").write(svg)
print("書き出し %s（輪郭 %d 本・%d バイト・縦横比 %.3f）" % (OUT, len(segs), len(svg), w_out / TARGET_H))
