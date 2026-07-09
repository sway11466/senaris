# 扉絵・キービジュアルの方針

冒険譚の扉絵（ステージ一覧の大パネル＋冒険譚選択カードでクロップ使い回し）やストア用キービジュアルの生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルはキービジュアル固有：狙い・透かし対策・ILLUST STYLE・保管。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 狙いと透かし対策

絵柄の DNA（セル調・muted・同じキャラ造形）はユニットと同じまま、駒用の制約（正面・中立ポーズ・単色背景）を解禁し、構図・光・背景で演出する。文字は入れない（タイトルはUI側で描く）。

生成の透かし（右下）対策＝4:3 で生成し右側を切り捨てる方針。主題は中央〜左に置き、右端15%は切り捨て可能なモブ・背景のみ、右下角には何も置かない。右を切った仕上がり（5:4〜ほぼ正方形）がパネルの正、カードは横帯クロップ。

---

## 2. 生成方式（ILLUST STYLE）

生成方式は共通のアンカー方式（[direction.md](direction.md) §3）。この ILLUST STYLE を先頭に付け、続けて各冒険譚の `cover_prompt.txt` を貼る（ユニットと同じ）。

ILLUST STYLE（共通・固定）:
```
STYLE: A dramatic fantasy key-art illustration for a hex-grid tactics game,
in the SAME art style as the game's unit pieces: clean stylized cel-shading,
bold readable shapes, and chunky chibi characters about 2 to 2.5 heads tall
with oversized heads and hands — charming and heroic with a bit of grit, NOT
moe, NOT overly cute. Mature, slightly muted, limited color palette; NOT
bright saturated anime coloring, NOT painterly photorealism. Unlike the unit
pieces, this is a full illustrated scene: dynamic composition and camera
angle, expressive action poses, a fully painted environment background and
dramatic cinematic lighting are all encouraged; rendering may be a step
richer than the game pieces, but keep shapes simple and readable. NO text,
NO title, NO logo anywhere in the image. Composition rule: place the main
subjects in the center and left of the frame; the rightmost 15% of the image
must contain ONLY expendable background or crowd filler (it will be cropped
away), and keep the bottom-right corner empty of anything important. Wide
4:3 composition.
```

---

## 3. 保管・命名

ユニット（[units.md](units.md) §3.1）と同じ「source＝作業／直下＝ゲームが読む正」の二層：

| 段階 | 置き場（`{campaign_id}`＝data/stages のフォルダ名） | 例 |
|---|---|---|
| ① AI生成直後（原寸・透かし入り） | `assets/campaign-src/{campaign_id}/{campaign_id}_01_raw.png` | `campaign-src/tutorial1-goblin-raid/tutorial1-goblin-raid_01_raw.png` |
| SUBJECT | `assets/campaign-src/{campaign_id}/cover_prompt.txt` | 同上フォルダ |
| ② ゲーム用（右15%クロップで透かし除去） | `assets/campaign/{campaign_id}/{campaign_id}_cover.png` | `tutorial1-goblin-raid_cover.png` |

- ②は `assets/campaign/{campaign_id}/` に置くと `CampaignCatalog` が規約で自動解決し、ステージ一覧の大パネル＋冒険譚カードに反映する（ユニットの skin 画像 autowire と同じ思想）。`campaign-src/` は `.gdignore` で Godot 非インポート。
- クロップは右を落とす（透かしが右下・主題は中央〜左に寄せる構図ルールと一致）。1枚を大パネル＝クロップ後の全体、カード＝横帯クロップで使い回す。

---

## 4. 未決事項

- [ ] 獲得用キービジュアル（冒険譚1「隘路で少数 vs 群れ」／冒険譚2「三重詠唱が屍の波を薙ぐ」＝機構が動く瞬間）。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（二層保管の原型・キャラ造形の DNA）
- [../gdd/stage_select.md](../gdd/stage_select.md) — ステージセレクト（大パネル／カードの二層・クロップ運用）
