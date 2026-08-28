"""Senaris のロゴ SVG を組む。

盤と同じカメラ（俯角52度・画角42度＝board_camera.gd）で7ヘックスを投影し、
中央ヘックスに剣と杖を X にクロスさせて刺し、その下に SENARIS を置く。
剣が左から刺さって頭が右へ、杖が右から刺さって頭が左へ。剣が手前。

起動スプラッシュ版はロゴの右下に開発元名を小さく足し、ピクセル寸法を焼いて書き出す
（地の色は焼かない＝project.godot の boot_splash/bg_color が持つ）。
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

TILT = 20.0         # 剣と杖の傾き（度）。剣が＋（頭が右）・杖が−（頭が左）
SWORD_TOTAL = 516.0
SWORD_VISIBLE = 312.0
STAFF_TOTAL = 504.0
STAFF_VISIBLE = 306.0
EMBLEM_DY = 24.0  # 紋章を縦へずらす量（ロゴ単位）。正＝下
ALIGN_TO = "A"  # 紋章の横位置を、この文字の中心に合わせる（None なら語の中心）
ENTRY_DX = 30.0  # 刺さり口を中央から左右へ離す量（ロゴ単位）。剣が左・杖が右
ENTRY_DY = 14.0  # 刺さり口を中央ヘックスの中心から下へずらす量（ロゴ単位）。両者同じ高さ
GROUND_SLANT = 8.0  # 武器を切る地面の線の傾き（度）。各自の刺さり口を通り、剣は右下がり（＼）・
                    # 杖は右肩上がり（／）＝どちらも自分の軸と噛み合う向きに切る
LETTER_HALO = 12.0  # 文字と武器の周りをタイルから抜く余白（ロゴ単位）
WEAPON_HALO = 12.0  # 手前の剣を奥の杖から抜く余白（ロゴ単位）
SWORD_HALO = 37.0   # 単色版のときだけ武器に使う太い抜き（同色なので広く取る）

WORD = "SENARIS"
TRACK = 0.12
WORD_W = 1200.0
OVERLAP = 0.70

DEV_WORD = "craftkobo"  # 開発元名（起動スプラッシュだけに載る）
DEV_TRACK = 0.20
DEV_W = 200.0        # 開発元名の幅（ロゴ単位）。ロゴ幅の 1/6 で、副題に見えない大きさ
DEV_GAP = 48.0       # SENARIS の下端から開発元名のベースラインまで（ロゴ単位）
DEV_INSET = 10.0     # 右端の微調整。字送り幅ではなく字の見た目の右端を S にそろえる分
SPLASH_PX_W = 760.0  # スプラッシュ PNG の横幅（px）。1280x720 のウィンドウで約6割

FONT_PATH = "assets/promo-src/logo/fonts/EBGaramond-variable.ttf"
SWORD_SVG = "assets/promo-src/logo/sword.svg"  # tools/logo/trace_sword.py が生成する
STAFF_SVG = "assets/promo-src/logo/staff.svg"  # tools/logo/trace_staff.py が生成する

CENTERS = [
    (0.0, 0.0),
    (1.5 * R, +S3 / 2 * R), (1.5 * R, -S3 / 2 * R),
    (-1.5 * R, +S3 / 2 * R), (-1.5 * R, -S3 / 2 * R),
    (0.0, +S3 * R), (0.0, -S3 * R),
]

PALETTE = {
    "dark": dict(ramp=((0x6E, 0x92, 0xB8), (0x8A, 0x8A, 0x96), (0xC0, 0x5A, 0x62)),
                 steel="#d2d8de", ink="#e8ecf0", dev="#6d7784"),
    "light": dict(ramp=((0xAB, 0xBE, 0xD1), (0xBE, 0xBE, 0xC6), (0xDA, 0xAF, 0xB3)),
                  steel="#586270", ink="#333942", dev="#6b7482"),
    # 単色版（白1色・黒1色）は用途が見当たらないため生成していない。
    # 必要になったら次の2行を戻すだけでよい（武器を抜く処理はそのまま残してある）。
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


def tile_polys(shrink, centers=CENTERS):
    """奥から手前の順に (色の位置t, 頂点列) を返す。centers で描く枚数を絞れる。"""
    xs = [c[0] for c in CENTERS]
    lo, hi = min(xs), max(xs)
    out = []
    for cx, cz in sorted(centers, key=lambda c: -c[1]):
        pts = []
        for k in range(6):
            a = math.radians(60.0 * k)
            pts.append(to_logo(project(cx + R * math.cos(a) * shrink, cz + R * math.sin(a) * shrink)))
        out.append(((cx - lo) / (hi - lo), " ".join("%.2f,%.2f" % p for p in pts)))
    return out


def weapon_bits(svg_path, total, visible, dx, tilt):
    """武器の SVG を読み、刺さり口 (dx, ENTRY_DY)・傾き tilt で置くパスと変換を返す。"""
    src = open(svg_path, encoding="utf-8").read()
    d = re.search(r'\sd="([^"]+)"', src).group(1)
    vb = re.search(r'viewBox="([^"]+)"', src).group(1).split()
    w, h = float(vb[2]), float(vb[3])
    scale = total / h
    buried_local = (total - visible) / scale
    ex, ey = w / 2.0, h - buried_local
    return d, ("translate(%.2f,%.2f) rotate(%.3f) scale(%.5f) translate(%.3f,%.3f)"
               % (dx, ENTRY_DY, tilt, scale, -ex, -ey))



def glyph_paths(word, target_w, track, align_to=None):
    f = TTFont(FONT_PATH)
    upem = f["head"].unitsPerEm
    cap = getattr(f["OS/2"], "sCapHeight", 0) or 700
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    hmtx = f["hmtx"]
    x = 0.0
    items = []
    for ch in word:
        gname = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        gs[gname].draw(pen)
        items.append((pen.getCommands(), x))
        x += hmtx[gname][0] + upem * track
    total = x - upem * track
    scale = target_w / total
    dx = 0.0
    if align_to:
        i = word.index(align_to)
        adv = hmtx[cmap[ord(align_to)]][0]
        dx = -target_w / 2.0 + (items[i][1] + adv / 2.0) * scale
    return items, scale, cap * scale, dx


def wordmark(gid, items, scale, target_w, baseline, fill, left=None):
    """パス化した語を、指定のベースラインに置く。left 省略で中央そろえ。"""
    x = -target_w / 2.0 if left is None else left
    out = ['<g id="%s" transform="translate(%.2f,%.2f) scale(%.5f,%.5f)" fill="%s">'
           % (gid, x, baseline, scale, -scale, fill)]
    for cmds, ox in items:
        out.append('<path d="%s" transform="translate(%.1f,0)"/>' % (cmds, ox))
    out.append("</g>")
    return out


def build(mode, shrink=SHRINK, dev=False, px_w=None, word=True, centers=CENTERS,
          staff=True, weapon_scale=1.0, sweep="cluster", tile_fill=None, square=False,
          entry_dx=None, tilt_deg=TILT, steel=None):
    """ロゴを組む。word=False で文字を落とした紋章だけの版（アプリアイコン用）。

    centers に中央1枚だけを渡し staff=False にすると、小さい寸法用の
    「ヘックス1枚に剣が刺さっただけ」の版になる。weapon_scale は武器の長さの倍率、
    square=True は viewBox を短いほうの辺に余白を足して正方形へ広げる。
    """
    pal = PALETTE[mode]
    flat = pal.get("flat")
    steel = steel or pal["steel"]
    tiles = tile_polys(shrink, centers)
    if entry_dx is None:
        entry_dx = ENTRY_DX if staff else 0.0
    sword_d, sword_tf = weapon_bits(SWORD_SVG, SWORD_TOTAL * weapon_scale,
                                    SWORD_VISIBLE * weapon_scale, -entry_dx, +tilt_deg)
    staff_d, staff_tf = weapon_bits(STAFF_SVG, STAFF_TOTAL * weapon_scale,
                                    STAFF_VISIBLE * weapon_scale, +entry_dx, -tilt_deg)
    glyphs, gscale, cap_h, emblem_dx = glyph_paths(WORD, WORD_W, TRACK, ALIGN_TO)
    emblem_dy = EMBLEM_DY
    if not word:
        emblem_dx, emblem_dy = 0.0, 0.0

    txs = [float(v.split(",")[0]) for _t, pts in tiles for v in pts.split()]
    tys = [float(v.split(",")[1]) for _t, pts in tiles for v in pts.split()]
    tilt = math.radians(tilt_deg)
    tips = [(-entry_dx + SWORD_VISIBLE * weapon_scale * math.sin(tilt),
             ENTRY_DY - SWORD_VISIBLE * weapon_scale * math.cos(tilt))]
    if staff:
        tips.append((entry_dx - STAFF_VISIBLE * weapon_scale * math.sin(tilt),
                     ENTRY_DY - STAFF_VISIBLE * weapon_scale * math.cos(tilt)))

    word_top = CLUSTER_BOTTOM - cap_h * OVERLAP
    word_bottom = word_top + cap_h
    if dev:
        dev_glyphs, dscale, _dcap, _dx = glyph_paths(DEV_WORD, DEV_W, DEV_TRACK)
        dev_baseline = word_bottom + DEV_GAP
    if word:
        top = min(CLUSTER_TOP, -SWORD_VISIBLE, -STAFF_VISIBLE)
        # craftkobo に下へ出る字は無いのでベースラインが下端
        bottom = dev_baseline if dev else word_bottom
        half_w = max(CLUSTER_W / 2.0, WORD_W / 2.0)
        left, right = -half_w, half_w
        pad = 24.0
    else:
        top = min(min(tys), min(t[1] for t in tips))
        bottom = max(tys)
        left = min(min(txs), min(t[0] for t in tips))
        right = max(max(txs), max(t[0] for t in tips))
        pad = 12.0
    vb = [left - pad, top - pad, (right - left) + 2 * pad, (bottom - top) + 2 * pad]
    if square:
        side = max(vb[2], vb[3])
        vb = [vb[0] - (side - vb[2]) / 2.0, vb[1] - (side - vb[3]) / 2.0, side, side]
    vb = tuple(vb)

    big = 4000.0
    m = math.tan(math.radians(GROUND_SLANT))
    parts = []
    for cid, x0, mi in (("ground_l", -entry_dx, +m), ("ground_r", +entry_dx, -m)):
        parts.append('<clipPath id="%s"><polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f"/></clipPath>'
                     % (cid, -big, ENTRY_DY + (-big - x0) * mi, big, ENTRY_DY + (big - x0) * mi,
                        big, -big, -big, -big))
    if not flat and not tile_fill:
        lo, mid, hi = pal["ramp"]
        # グラデはクラスタ全体を横切る。1枚版で sweep="tile" にすると、その1枚を横切る
        gx = (min(txs), max(txs)) if sweep == "tile" else (-CLUSTER_W / 2.0, CLUSTER_W / 2.0)
        parts.append('<linearGradient id="sweep" gradientUnits="userSpaceOnUse" x1="%.1f" y1="0" x2="%.1f" y2="0">'
                     % gx)
        for off, c in ((0.0, lo), (1.0, hi)):
            parts.append('<stop offset="%.2f" stop-color="#%02x%02x%02x"/>' % ((off,) + c))
        parts.append("</linearGradient>")
    parts.append('<mask id="cut" maskUnits="userSpaceOnUse" x="%.1f" y="%.1f" width="%.1f" height="%.1f">' % vb)
    parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff"/>' % vb)
    cuts = [(sword_d, sword_tf, "ground_l")]
    if staff:
        cuts.append((staff_d, staff_tf, "ground_r"))
    for d, tf, cid in cuts:
        parts.append('<g clip-path="url(#%s)"><path d="%s" transform="%s" fill="#000" stroke="#000"'
                     ' stroke-width="%.1f" stroke-linejoin="round"/></g>'
                     % (cid, d, tf, SWORD_HALO if flat else LETTER_HALO))
    if word:
        # マスクはタイル群の座標系（紋章の移動が効いた後）で解釈されるので、その分を打ち消す
        parts.append('<g transform="translate(%.2f,%.2f) scale(%.5f,%.5f)" fill="#000" stroke="#000"'
                     ' stroke-width="%.1f" stroke-linejoin="round">'
                     % (-WORD_W / 2.0 - emblem_dx, word_bottom - EMBLEM_DY, gscale, -gscale,
                        LETTER_HALO / gscale))
        for cmds, ox in glyphs:
            parts.append('<path d="%s" transform="translate(%.1f,0)"/>' % (cmds, ox))
        parts.append("</g>")
    parts.append("</mask>")
    if staff:
        # 手前の剣を、奥の杖から抜くマスク（重なりの分離＝文字の抜きと同じ流儀）
        parts.append('<mask id="front" maskUnits="userSpaceOnUse" x="%.1f" y="%.1f" width="%.1f" height="%.1f">' % vb)
        parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff"/>' % vb)
        parts.append('<path d="%s" transform="%s" fill="#000" stroke="#000" stroke-width="%.1f"'
                     ' stroke-linejoin="round"/>' % (sword_d, sword_tf, SWORD_HALO if flat else WEAPON_HALO))
        parts.append("</mask>")
    parts.append('<g id="emblem" transform="translate(%.2f,%.2f)">' % (emblem_dx, emblem_dy))
    parts.append('<g id="tiles" mask="url(#cut)">')
    for t, pts in tiles:
        parts.append('<polygon points="%s" fill="%s"/>' % (pts, flat or tile_fill or "url(#sweep)"))
    parts.append("</g>")
    if staff:
        parts.append('<g id="staff" clip-path="url(#ground_r)" mask="url(#front)">')
        parts.append('<path d="%s" transform="%s" fill="%s"/>' % (staff_d, staff_tf, flat or steel))
        parts.append("</g>")
    parts.append('<g id="sword" clip-path="url(#ground_l)">')
    parts.append('<path d="%s" transform="%s" fill="%s"/>' % (sword_d, sword_tf, flat or steel))
    parts.append("</g>")
    parts.append("</g>")
    if word:
        parts += wordmark("wordmark", glyphs, gscale, WORD_W, word_bottom, flat or pal["ink"])
        if dev:
            # ロゴの右下に寄せる（右端を SENARIS の右端にそろえる）。中央に置くと副題に見える。
            parts += wordmark("devname", dev_glyphs, dscale, DEV_W, dev_baseline, flat or pal["dev"],
                              left=WORD_W / 2.0 - DEV_W - DEV_INSET)

    w, h = vb[2], vb[3]
    if px_w:
        w, h = px_w, px_w * vb[3] / vb[2]
    head = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.1f %.1f %.1f %.1f" width="%.0f" height="%.0f">'
            % (vb[0], vb[1], vb[2], vb[3], w, h))
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
    # 起動スプラッシュ用。ゲームに入る画像の作業元なので promo-src ではなく menu-src に置く
    # （PNG への変換は tools/rasterize_svg.gd）。
    p = "assets/menu-src/splash/splash.svg"
    open(p, "w", encoding="utf-8").write(build("dark", dev=True, px_w=SPLASH_PX_W))
    print("wrote", p)

    # アプリアイコン用（文字を落とした紋章だけの版）。寸法で2つを使い分ける
    # （64px 以上＝7枚版・48px 以下＝1枚版）。仕様 → doc/art/icon.md
    icons = {
        # 7枚版は武器をそのままの長さで使い、正方形にする分を左右の余白で足す。
        "icon_large": dict(word=False, square=True),
        # 1枚版は中央ヘックスだけ。刺さり口±30・傾き28度・武器0.48倍＝小さい寸法でも
        # クロスが X と読める組み合わせ。タイルはこの1枚を青から赤へ横切らせる。
        "icon_small": dict(word=False, centers=[CENTERS[0]], entry_dx=30.0, tilt_deg=28.0,
                           weapon_scale=0.48, sweep="tile", square=True),
    }
    for name, kw in icons.items():
        p = "assets/icon-src/%s.svg" % name
        open(p, "w", encoding="utf-8").write(build("dark", shrink=0.90, **kw))
        print("wrote", p)
