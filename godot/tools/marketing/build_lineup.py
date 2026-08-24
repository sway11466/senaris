"""ユニットの戦闘立ち絵を横一列に並べたPNGを組む（marketing用）。

左グループと右グループを向かい合わせに並べる。向きはスキンに焼き込み
（プレイヤー陣営＝右向き・敵陣営＝左向き。doc/art/units.md）なので反転はしない。
左にプレイヤー陣営・右に敵陣営のスキンを渡す前提。

入力: godot/assets/units/<skin_id>/<skin_id>_combat.png（下端揃え・透過）
      大小は書き出し時に焼き込み済み（gen_unit_combat.ps1 が高さ=384×combat_scale で
      キャンバスに置く）ため、キャンバスの下端を共通の地面線としてそのまま並べる。
      例外は combat_lineup=single の駒（馬車・ドラゴン級）で、戦闘演出シーンが表示時に
      さらに×1.4 する（combat_stage.gd の SINGLE_SCALE）ぶんをここでも掛ける。

実行（リポジトリ直下）:
  uv run --no-project --with pillow python godot/tools/marketing/build_lineup.py \
    --left fighter,novice,archer,cleric,halfling \
    --right goblin,hobgoblin,goblin_archer,goblin_lord \
    -o channels/itch/devlog/img/tutorial1_cast.png

オプション:
  --step N   同グループ内の駒の中心間隔px（既定 380。704キャンバスを少し重ねて隊列に見せる）
  --gap N    グループ間に追加で空けるpx（既定 300）
  --margin N 仕上げで内容の外に残す余白px（既定 24）
"""
import argparse
import csv
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]  # リポジトリ直下
UNITS = ROOT / "godot" / "assets" / "units"
SKIN_CSV = ROOT / "godot" / "data" / "units" / "unit_skin.csv"
SINGLE_SCALE = 1.4  # combat_stage.gd の SINGLE_SCALE と同値に保つ


def load_lineups() -> dict[str, str]:
    with open(SKIN_CSV, encoding="utf-8") as f:
        rows = csv.DictReader(f)
        return {r["skin_id"]: r["combat_lineup"] for r in rows if r["skin_id"]}


def load_standee(skin_id: str, lineups: dict[str, str]) -> Image.Image:
    path = UNITS / skin_id / f"{skin_id}_combat.png"
    if not path.exists():
        sys.exit(f"error: 立ち絵が無い: {path}")
    if skin_id not in lineups:
        sys.exit(f"error: unit_skin.csv に無いスキン: {skin_id}")
    im = Image.open(path).convert("RGBA")
    if lineups[skin_id] == "single":
        w = round(im.width * SINGLE_SCALE)
        h = round(im.height * SINGLE_SCALE)
        im = im.resize((w, h), Image.LANCZOS)  # 下端揃えは貼り付け側が保つ
    return im


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--left", required=True, help="左グループ（右向き＝プレイヤー陣営）のskin_idをカンマ区切り")
    ap.add_argument("--right", required=True, help="右グループ（左向き＝敵陣営）のskin_idをカンマ区切り")
    ap.add_argument("-o", "--out", required=True, help="出力PNG（リポジトリ直下からの相対 or 絶対）")
    ap.add_argument("--step", type=int, default=380)
    ap.add_argument("--gap", type=int, default=300)
    ap.add_argument("--margin", type=int, default=24)
    args = ap.parse_args()

    lineups = load_lineups()
    left = [load_standee(s, lineups) for s in args.left.split(",")]
    right = [load_standee(s, lineups) for s in args.right.split(",")]
    all_imgs = left + right

    canvas_h = max(im.height for im in all_imgs)
    # 中心xの並び: 左グループ→gap→右グループ
    centers: list[int] = []
    x = 0
    for i in range(len(left)):
        centers.append(x)
        x += args.step
    x += args.gap
    for i in range(len(right)):
        centers.append(x)
        x += args.step

    width = centers[-1] + max(im.width for im in all_imgs)
    offset_x = max(im.width for im in all_imgs) // 2
    canvas = Image.new("RGBA", (width + offset_x, canvas_h), (0, 0, 0, 0))
    # 後ろの駒が前の駒に隠れる向き＝中央側を後から貼る（左グループは右ほど手前、右グループは左ほど手前）
    order = list(range(len(left))) + list(range(len(all_imgs) - 1, len(left) - 1, -1))
    for idx in order:
        im = all_imgs[idx]
        cx = centers[idx] + offset_x
        canvas.alpha_composite(im, (cx - im.width // 2, canvas_h - im.height))

    bbox = canvas.getbbox()
    if bbox is None:
        sys.exit("error: 中身が空")
    m = args.margin
    bbox = (max(0, bbox[0] - m), max(0, bbox[1] - m),
            min(canvas.width, bbox[2] + m), min(canvas.height, bbox[3] + m))
    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = ROOT / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.crop(bbox).save(out_path)
    print(f"saved: {out_path} ({bbox[2]-bbox[0]}x{bbox[3]-bbox[1]})")


if __name__ == "__main__":
    main()
