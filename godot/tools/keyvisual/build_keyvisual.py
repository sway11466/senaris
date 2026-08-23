"""Senaris のキービジュアルを組む。

素材はロゴ（盤の常設版＝小サイズ版・暗背景の PNG）と赤竜のユニット立ち絵。
どちらも既にある絵をそのまま置くだけで、絵そのものには手を入れない。

いまは S（Steam の小カプセル 231x87）だけ。段を増やすときは SPECS に足す。
4倍で組んでから縮小する＝縮小のたびに輪郭がなまらないようにするため。
"""
from PIL import Image, ImageDraw

LOGO_PNG = "assets/ui/logo.png"
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


if __name__ == "__main__":
    for size in SPECS:
        build(size)
