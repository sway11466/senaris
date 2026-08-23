"""Senaris のキービジュアルを組む。

段によって組み方が違う。
- S … 素材（ロゴの盤常設版と赤竜のユニット立ち絵）を地の上に並べて作る。
      4倍で組んでから縮小する＝縮小のたびに輪郭がなまらないようにするため。
      寸法は SPECS に持つ。段を増やすときはここに足す。
- M … 生成した1枚絵（keyvisual_m_01_raw.jpg）にフル版ロゴを重ねるだけ。
      寸法は M_SPEC に持つ。

どちらも既にある絵をそのまま置く。絵そのものには手を入れない。

LOGO_FULL_PNG は SVG から焼いた中間物。作り直すときは
  godot --headless --script res://tools/rasterize_svg.gd --       res://assets/promo-src/logo/logo_dark.svg <出力先> 2
"""
from PIL import Image, ImageDraw

LOGO_PNG = "assets/ui/logo.png"  # 盤の常設版＝小サイズ版・暗背景
LOGO_FULL_PNG = "assets/promo-src/logo/logo_dark_2x.png"  # フル版・暗背景
DRAGON_PNG = "assets/units/red_dragon/red_dragon_combat.png"
OUT_DIR = "assets/promo-src/keyvisual"

SS = 4  # 組むときの倍率

# 地の色（横グラデーションの左端と右端）
BG_LEFT = (22, 25, 31)
BG_RIGHT = (32, 29, 28)

SPECS = {
    # size: 枠の寸法, ロゴの高さ（枠に対する比）, ロゴの左マージン,
    #       竜の高さ, 竜の左上（枠の左上から。負なら枠の外）
    "s": dict(frame=(231, 87), logo_h=0.60, logo_x=8, dragon_h=204, dragon_xy=(110, -10)),
}

# M: 元絵, ロゴの幅（元絵の幅に対する比）, ロゴの左上（元絵の左上からの px）。
# 元絵は左40%・上半分を空けて生成してある（keyvisual_m_prompt.txt）＝そこに置く。
M_SPEC = dict(
    src="assets/promo-src/keyvisual/keyvisual_m_01_raw.jpg",
    logo_w=0.40,
    logo_xy=(65, 50),
)


def _background(w, h):
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    for x in range(w):
        t = x / (w - 1)
        c = tuple(int(a + (b - a) * t) for a, b in zip(BG_LEFT, BG_RIGHT))
        d.line([(x, 0), (x, h)], fill=c + (255,))
    return im


def _fit_h(im, h):
    return im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)


def _fit_w(im, w):
    return im.resize((w, max(1, round(im.height * w / im.width))), Image.LANCZOS)


def build(size):
    spec = SPECS[size]
    fw, fh = spec["frame"]
    w, h = fw * SS, fh * SS

    logo = Image.open(LOGO_PNG).convert("RGBA")
    logo = logo.crop(logo.getbbox())  # 余白を落として、寸法をロゴの実体で測る
    dragon = Image.open(DRAGON_PNG).convert("RGBA")
    dragon = dragon.crop(dragon.getbbox())

    im = _background(w, h)
    d = _fit_h(dragon, spec["dragon_h"] * SS)
    dx, dy = spec["dragon_xy"]
    im.alpha_composite(d, (dx * SS, dy * SS))  # 枠からはみ出した分は捨てる
    l = _fit_h(logo, int(h * spec["logo_h"]))
    im.alpha_composite(l, (spec["logo_x"] * SS, (h - l.height) // 2))

    im.convert("RGB").save("%s/keyvisual_%s_4x.png" % (OUT_DIR, size))
    im.resize((fw, fh), Image.LANCZOS).convert("RGB").save(
        "%s/keyvisual_%s.png" % (OUT_DIR, size))


def build_m():
    im = Image.open(M_SPEC["src"]).convert("RGBA")

    logo = Image.open(LOGO_FULL_PNG).convert("RGBA")
    logo = logo.crop(logo.getbbox())  # 余白を落として、寸法をロゴの実体で測る
    logo = _fit_w(logo, round(im.width * M_SPEC["logo_w"]))
    im.alpha_composite(logo, M_SPEC["logo_xy"])

    im.convert("RGB").save("%s/keyvisual_m.png" % OUT_DIR)


if __name__ == "__main__":
    for size in SPECS:
        build(size)
    build_m()
