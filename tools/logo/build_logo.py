"""Senaris のロゴ SVG を組む。

盤と同じカメラ（俯角52度・画角42度＝board_camera.gd）で7ヘックスを投影し、
中央ヘックスの中心に剣を刺し、その下に SENARIS を置く。
"""
import math
import re
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen

R = 100.0
S3 = math.sqrt(3.0)
PITCH = math.radians(52.0)
FOV = math.radians(42.0)
DIST = 6.0 * R
CLUSTER_W = 500.0
SHRINK = 0.94

TILT = 15.0
SWORD_TOTAL = 516.0
SWORD_VISIBLE = 312.0
EMBLEM_DY = 24.0  # 紋章を縦へずらす量（ロゴ単位）。正＝下
ALIGN_TO = "A"  # 紋章の横位置を、この文字の中心に合わせる（None なら語の中心）
ENTRY_DY = 10.0  # 刺さり口を中央ヘックスの中心から下へずらす量（ロゴ単位）
GROUND_SLANT = 8.0  # 剣を切る地面の線の傾き（度）。正＝右下がり
LETTER_HALO = 12.0  # 文字と剣の周りをタイルから抜く余白（ロゴ単位）
SWORD_HALO = 37.0   # 単色版のときだけ剣に使う太い抜き（同色なので広く取る）

WORD = "SENARIS"
TRACK = 0.12
WORD_W = 1200.0
OVERLAP = 0.70

FONT_PATH = "assets/promo-src/logo/fonts/EBGaramond-variable.ttf"
SWORD_SVG = "assets/promo-src/logo/sword.svg"  # tools/trace_sword.py が生成する

CENTERS = [
    (0.0, 0.0),
    (1.5 * R, +S3 / 2 * R), (1.5 * R, -S3 / 2 * R),
    (-1.5 * R, +S3 / 2 * R), (-1.5 * R, -S3 / 2 * R),
    (0.0, +S3 * R), (0.0, -S3 * R),
]

PALETTE = {
    "dark": dict(ramp=((0x6E, 0x92, 0xB8), (0x8A, 0x8A, 0x96), (0xC0, 0x5A, 0x62)),
                 steel="#d2d8de", ink="#e8ecf0"),
    "light": dict(ramp=((0xAB, 0xBE, 0xD1), (0xBE, 0xBE, 0xC6), (0xDA, 0xAF, 0xB3)),
                  steel="#586270", ink="#333942"),
    # 単色版（白1色・黒1色）は用途が見当たらないため生成していない。
    # 必要になったら次の2行を戻すだけでよい（剣を抜く処理はそのまま残してある）。
    #   "mono-white": dict(flat="#ffffff"),
    #   "mono-black": dict(flat="#000000"),
}


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def ramp_hex(rp, t):
    lo, mid, hi = rp
    c = lerp(lo, mid, t / 0.5) if t <= 0.5 else lerp(mid, hi, (t - 0.5) / 0.5)
    return "#%02x%02x%02x" % c


def project(x, z):
    """盤の平面 y=0 上の点 (x,z) を投影する。z が正＝奥。画面は y 下向き正。"""
    cy, sy = math.cos(PITCH), math.sin(PITCH)
    py, pz = -DIST * sy, z - DIST * cy
    fy = py * cy - pz * sy
    fz = py * sy + pz * cy
    f = 1.0 / math.tan(FOV / 2.0)
    return (f * x / -fz, -f * fy / -fz)


def _fit():
    xs, ys = [], []
    for cx, cz in CENTERS:
        for k in range(6):
            a = math.radians(60.0 * k)
            p = project(cx + R * math.cos(a) * SHRINK, cz + R * math.sin(a) * SHRINK)
            xs.append(p[0])
            ys.append(p[1])
    scale = CLUSTER_W / (max(xs) - min(xs))
    oy = project(0.0, 0.0)[1]
    return scale, oy, (min(ys) - oy) * scale, (max(ys) - oy) * scale


SCALE, ORIGIN_Y, CLUSTER_TOP, CLUSTER_BOTTOM = _fit()


def to_logo(p):
    return (p[0] * SCALE, (p[1] - ORIGIN_Y) * SCALE)


def tile_polys(shrink):
    """奥から手前の順に (色の位置t, 頂点列) を返す。"""
    xs = [c[0] for c in CENTERS]
    lo, hi = min(xs), max(xs)
    out = []
    for cx, cz in sorted(CENTERS, key=lambda c: -c[1]):
        pts = []
        for k in range(6):
            a = math.radians(60.0 * k)
            pts.append(to_logo(project(cx + R * math.cos(a) * shrink, cz + R * math.sin(a) * shrink)))
        out.append(((cx - lo) / (hi - lo), " ".join("%.2f,%.2f" % p for p in pts)))
    return out


def sword_bits():
    src = open(SWORD_SVG, encoding="utf-8").read()
    d = re.search(r'\sd="([^"]+)"', src).group(1)
    vb = re.search(r'viewBox="([^"]+)"', src).group(1).split()
    w, h = float(vb[2]), float(vb[3])
    scale = SWORD_TOTAL / h
    buried_local = (SWORD_TOTAL - SWORD_VISIBLE) / scale
    ex, ey = w / 2.0, h - buried_local
    return d, "translate(0,%.2f) rotate(%.3f) scale(%.5f) translate(%.3f,%.3f)" % (ENTRY_DY, TILT, scale, -ex, -ey)



def glyph_paths(target_w):
    f = TTFont(FONT_PATH)
    upem = f["head"].unitsPerEm
    cap = getattr(f["OS/2"], "sCapHeight", 0) or 700
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    hmtx = f["hmtx"]
    x = 0.0
    items = []
    for ch in WORD:
        gname = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        gs[gname].draw(pen)
        items.append((pen.getCommands(), x))
        x += hmtx[gname][0] + upem * TRACK
    total = x - upem * TRACK
    scale = target_w / total
    dx = 0.0
    if ALIGN_TO:
        i = WORD.index(ALIGN_TO)
        adv = hmtx[cmap[ord(ALIGN_TO)]][0]
        dx = -target_w / 2.0 + (items[i][1] + adv / 2.0) * scale
    return items, scale, cap * scale, dx


def build(mode, shrink=SHRINK):
    pal = PALETTE[mode]
    flat = pal.get("flat")
    tiles = tile_polys(shrink)
    sword_d, sword_tf = sword_bits()
    glyphs, gscale, cap_h, emblem_dx = glyph_paths(WORD_W)

    top = min(CLUSTER_TOP, -SWORD_VISIBLE)
    word_top = CLUSTER_BOTTOM - cap_h * OVERLAP
    word_bottom = word_top + cap_h
    half_w = max(CLUSTER_W / 2.0, WORD_W / 2.0)
    pad = 24.0
    vb = (-half_w - pad, top - pad, 2 * (half_w + pad), (word_bottom - top) + 2 * pad)

    big = 4000.0
    m = math.tan(math.radians(GROUND_SLANT))
    parts = ['<clipPath id="ground"><polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f"/></clipPath>'
             % (-big, ENTRY_DY - big * m, big, ENTRY_DY + big * m, big, -big, -big, -big)]
    if not flat:
        lo, mid, hi = pal["ramp"]
        parts.append('<linearGradient id="sweep" gradientUnits="userSpaceOnUse" x1="%.1f" y1="0" x2="%.1f" y2="0">'
                     % (-CLUSTER_W / 2.0, CLUSTER_W / 2.0))
        for off, c in ((0.0, lo), (1.0, hi)):
            parts.append('<stop offset="%.2f" stop-color="#%02x%02x%02x"/>' % ((off,) + c))
        parts.append("</linearGradient>")
    parts.append('<mask id="cut" maskUnits="userSpaceOnUse" x="%.1f" y="%.1f" width="%.1f" height="%.1f">' % vb)
    parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff"/>' % vb)
    parts.append('<g clip-path="url(#ground)"><path d="%s" transform="%s" fill="#000" stroke="#000"'
                 ' stroke-width="%.1f" stroke-linejoin="round"/></g>'
                 % (sword_d, sword_tf, SWORD_HALO if flat else LETTER_HALO))
    # マスクはタイル群の座標系（紋章の移動が効いた後）で解釈されるので、その分を打ち消す
    parts.append('<g transform="translate(%.2f,%.2f) scale(%.5f,%.5f)" fill="#000" stroke="#000"'
                 ' stroke-width="%.1f" stroke-linejoin="round">'
                 % (-WORD_W / 2.0 - emblem_dx, word_bottom - EMBLEM_DY, gscale, -gscale,
                    LETTER_HALO / gscale))
    for cmds, ox in glyphs:
        parts.append('<path d="%s" transform="translate(%.1f,0)"/>' % (cmds, ox))
    parts.append("</g>")
    parts.append("</mask>")
    parts.append('<g id="emblem" transform="translate(%.2f,%.2f)">' % (emblem_dx, EMBLEM_DY))
    parts.append('<g id="tiles" mask="url(#cut)">')
    for t, pts in tiles:
        parts.append('<polygon points="%s" fill="%s"/>' % (pts, flat or "url(#sweep)"))
    parts.append("</g>")
    parts.append('<g id="sword" clip-path="url(#ground)">')
    parts.append('<path d="%s" transform="%s" fill="%s"/>' % (sword_d, sword_tf, flat or pal["steel"]))
    parts.append("</g>")
    parts.append("</g>")
    parts.append('<g id="wordmark" transform="translate(%.2f,%.2f) scale(%.5f,%.5f)" fill="%s">'
                 % (-WORD_W / 2.0, word_bottom, gscale, -gscale, flat or pal["ink"]))
    for cmds, ox in glyphs:
        parts.append('<path d="%s" transform="translate(%.1f,0)"/>' % (cmds, ox))
    parts.append("</g>")

    head = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.1f %.1f %.1f %.1f" width="%.0f" height="%.0f">'
            % (vb[0], vb[1], vb[2], vb[3], vb[2], vb[3]))
    return head + "\n" + "\n".join(parts) + "\n</svg>\n"


if __name__ == "__main__":
    print("cluster top/bottom in logo units: %.1f / %.1f" % (CLUSTER_TOP, CLUSTER_BOTTOM))
    for mode in ("dark", "light"):
        p = "assets/promo-src/logo/logo_%s.svg" % mode
        open(p, "w", encoding="utf-8").write(build(mode))
        print("wrote", p)
    p = "assets/promo-src/logo/logo_small_dark.svg"
    open(p, "w", encoding="utf-8").write(build("dark", shrink=0.90))
    print("wrote", p)
