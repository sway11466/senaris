# 扉絵・キービジュアルの方針

冒険譚の扉絵（ステージ一覧の大パネル＋冒険譚選択カードでクロップ使い回し）やストア用キービジュアルの生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルはキービジュアル固有：狙い・ILLUST STYLE・保管。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 狙い

絵柄の DNA（セル調・muted・同じキャラ造形）はユニットと同じまま、駒用の制約（正面・中立ポーズ・単色背景）を解禁し、構図・光・背景で演出する。文字は入れない（タイトルはUI側で描く）。

透かし（sparkle・右下）は共通ルールの `_02_dew`（透かし除去ツール）で消す（[direction.md](direction.md) §3）＝生成側で右を空ける・右下角を空けるといった構図制約は不要。主題は中央に据えて広めに 4:3 で生成し、大パネル＝全体／カード＝横帯として使い回す（表示比率はエンジンが KEEP_ASPECT_COVERED で合わせる）。

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
subject roughly centered in the frame with a little headroom and margin
around it. Wide 4:3 composition.
```

---

## 3. 保管・命名

ユニット（[units.md](units.md) §3.1）と同じ「source＝作業／直下＝ゲームが読む正」の二層：

| 段階 | 置き場（`{id}`＝data/stages のフォルダ名＝冒険譚id） | 例 |
|---|---|---|
| ① AI生成直後（原寸・透かし入り） | `assets/campaign-src/{id}/{id}_a_01_raw.png`（変種 a/b/c…） | `campaign-src/tutorial1-goblin-raid/tutorial1-goblin-raid_a_01_raw.png` |
| ② 透かし除去（ツール自動・原寸） | `assets/campaign-src/{id}/{id}_a_02_dew.png` | 同上フォルダ |
| ③ 手動調整マスター（任意・原寸） | `assets/campaign-src/{id}/{id}_a_03_master.png` | 同上フォルダ |
| SUBJECT | `assets/campaign-src/{id}/{id}_cover_prompt.txt` | 同上フォルダ |
| ④ ゲーム用（`_03_master`＞`_02_dew` を cp・比率調整は不要） | `assets/campaign/{id}/{id}_cover.png`（＋連番 `{id}_cover_2.png` …） | `tutorial1-goblin-raid_cover.png` |

- 命名は他系統と揃える: slot（`_cover`/`_card`）はユニット skin 流、連番変種（`_2`/`_3`…）は地形・羊皮紙流、-src の `_a_NN_raw/dew/master` は羊皮紙流。
- ②は `assets/campaign/{id}/` に置くと `CampaignCatalog` が規約で自動解決し、ステージ一覧の大パネル＋冒険譚カードに反映する（ユニットの skin 画像 autowire と同じ思想）。`campaign-src/` は `.gdignore` で Godot 非インポート。
- 連番変種（`{id}_cover_2.png` …）を複数置くと、表示ごとにランダムで1枚選ぶ（[campaign_catalog.gd](../../data/stages/campaign_catalog.gd) `_resolve_art_variants`／地形・羊皮紙と同思想）。1枚だけなら固定。
- cover の元は `_03_master` があればそれ、無ければ `_02_dew`（[direction.md](direction.md) §3）。1枚を大パネル＝全体、カード＝横帯として使い回す（比率はエンジンが合わせる）。

---

## 4. 未決事項

- [ ] 獲得用キービジュアル（冒険譚1「隘路で少数 vs 群れ」／冒険譚2「三重詠唱が屍の波を薙ぐ」＝機構が動く瞬間）。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（二層保管の原型・キャラ造形の DNA）
- [../gdd/stage_select.md](../gdd/stage_select.md) — ステージセレクト（大パネル／カードの二層・クロップ運用）
