"""剣の黒シルエット PNG を SVG のパスに変換する。

生成画像（白地に黒のシルエット）を potrace で輪郭化し、assets/promo-src/logo/sword.svg
に書き出す。溝・柄頭の輪・巻きの隙間は白く抜けた穴として、そのまま穴になる
（fill-rule="evenodd"）。

SYMMETRIZE を真にすると、左半分を鏡像複製して左右対称にする。生成物のわずかな歪みは
消えるが、斜めの巻きのような左右非対称な意匠はV字に変わってしまうので既定は偽。

    uv run --no-project --with pillow --with numpy --with potracer python tools/trace_sword.py
"""
import numpy as np
from PIL import Image
import potrace

SRC = "assets/promo-src/logo/sword_01_raw.png"
OUT = "assets/promo-src/logo/sword.svg"
TARGET_H = 1000.0
SYMMETRIZE = False
TURDSIZE = 12  # これより小さい塊は捨てる（生成物のごみ取り）

im = Image.open(SRC).convert("L")
ink = np.asarray(im) < 128

ys, xs = np.nonzero(ink)
ink = ink[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
H, W = ink.shape
print("切り抜き後のビットマップ %d x %d" % (W, H))

if SYMMETRIZE:
    half = W // 2
    left = ink[:, :half]
    mirror = np.fliplr(left)
    mid = [ink[:, half:half + 1]] if W % 2 else []
    sym = np.concatenate([left] + mid + [mirror], axis=1)
    changed = int(np.logical_xor(sym, ink).sum())
    print("対称化：%d px 変化（形の %.2f%%）" % (changed, 100.0 * changed / ink.sum()))
    ink = sym

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
