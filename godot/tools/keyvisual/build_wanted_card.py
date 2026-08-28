"""手配書の貼り紙の絵（賞金稼ぎの冒険譚の card）を組む。

生成AIは使わず、ユニットのマスター絵の顔だけを切って `WANTED` の字を重ねる。
紙は敷かない＝背景は透明。貼り紙が下に羊皮紙を持っているため、絵まで紙を持つと
紙の上に紙になる。

字は絵の手前に置く。顔を紙の幅いっぱいまで大きくすると冠が字の高さまで届くので、
重ねる前提で組む（重ねずに収めると顔が半分の大きさまでしか取れない）。

実行（リポジトリ直下）:
  uv run --no-project --with pillow python godot/tools/keyvisual/build_wanted_cover.py \
    --skin goblin_lord --src godot/assets/units-src/goblin/goblin_lord \
    -o godot/assets/campaign/bounty1-goblin-horde/bounty1-goblin-horde_card.png

オプション:
  --text S      刷る言葉（既定 WANTED）
  --head-w N    顔の横幅px（既定 820＝キャンバス1200の68%）。あごが下端に触れる手前が上限
  --crop A,B,C,D  マスター絵から切る箱（既定は冠の先〜肩）
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]  # リポジトリ直下
FONT = ROOT / "godot" / "assets" / "fonts" / "IMFellEnglish-Regular.ttf"
W, H = 1200, 896  # 他の冒険譚の絵と同じ寸法。貼り紙の枠 317×230 とほぼ同じ縦横比
INK = (58, 40, 26)  # 羊皮紙に乗るインクの色
EARS = (28, 410)  # マスター絵の上での耳の左右。顔の中心と大きさをここで測る
TEXT_SIZE = 170
TEXT_CY = 120  # 字の中心の高さ
TRACK = 0.18  # 字間（字の大きさに対する割合）


def draw_text(text: str) -> Image.Image:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    font = ImageFont.truetype(str(FONT), TEXT_SIZE)
    d = ImageDraw.Draw(layer)
    widths = [d.textlength(c, font=font) for c in text]
    track = TEXT_SIZE * TRACK
    x = (W - (sum(widths) + track * (len(text) - 1))) / 2
    top = d.textbbox((0, 0), text, font=font)[1]
    for c, w in zip(text, widths):
        d.text((x, TEXT_CY - top - TEXT_SIZE * 0.36), c, font=font, fill=INK)
        x += w + track
    return layer


def build(master: Path, crop: tuple[int, int, int, int], head_w: int, text: str) -> Image.Image:
    scale = head_w / (EARS[1] - EARS[0])  # 耳の左右は顔の大きさを決めるためだけに使う
    face = Image.open(master).convert("RGBA").crop(crop)
    face = face.resize((round(face.width * scale), round(face.height * scale)), Image.LANCZOS)

    # 横は絵の中身の幅で中心を取る。顔（耳の左右）だけで測ると、右へ張り出した
    # 得物のぶん絵が右に寄って見えるため。
    box = face.getbbox()
    x = round(W / 2 - (box[0] + box[2]) / 2)

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    img.alpha_composite(face, (x, 30))  # 冠の先を上端の近くに置き、下端は絵の外へ流す
    img.alpha_composite(draw_text(text))
    return img


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--skin", required=True)
    p.add_argument("--src", required=True, help="マスター絵の置き場（units-src の陣営フォルダ）")
    p.add_argument("-o", "--out", required=True)
    p.add_argument("--text", default="WANTED")
    p.add_argument("--head-w", type=int, default=820)
    p.add_argument("--crop", default="8,6,482,560")
    a = p.parse_args()

    master = Path(a.src) / f"{a.skin}_03_master.png"
    crop = tuple(int(v) for v in a.crop.split(","))
    img = build(master, crop, a.head_w, a.text)
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"{out} {img.width}x{img.height}")


if __name__ == "__main__":
    main()
