# 地形タイルの方針

盤面に敷く地形タイルの生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルは地形固有：形状・反復対策・TERRAIN STYLE・切り抜きと保管。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 形状・敷き方

- 形状: フラットトップ六角形・256×222px（中心〜頂点 R=128／上下平辺間 √3R）・角は透過。盤（[../../presentation/board/hex_board_3d.gd](../../presentation/board/hex_board_3d.gd)）が terrain_id ごとに1枚を各ヘックスに敷く（3D盤でも同じPNGをヘックスメッシュに貼る＝この寸法は現行）。置き場は `assets/terrain/{name}.png`（terrain.csv の image 列）。プレースホルダ生成は [../../tools/gen_terrain_tiles.gd](../../tools/gen_terrain_tiles.gd)、アート確定後は同名で差し替えるだけ（描画コード不変）。
- 現状は「1地形1枚・接地による遷移なし」。各ヘックスが地形の自己完結アイコン（Into the Breach 系）。
- 【視覚】地形は盤上で標高を持てる（見た目のみ・性能不変）。[hex_board_3d.gd](../../presentation/board/hex_board_3d.gd) の `ELEVATION`（地形id→高さ）でタイルを持ち上げ、低い隣接辺／盤外辺に崖のスカートを下ろしてメサに見せる。現状は台地(plateau)だけ +少し。ユニット・影・グリッド・拠点・オーバーレイ・クリック判定（ピッキング）も標高に追従する。
- 反復対策＝バリアント敷き分け（実装済み）: 同名連番 `{name}_2.png` `{name}_3.png` … を置くと、hex_board が存在する分を集め、ヘックス座標から決定的に敷き分ける（ちらつかない）。連番が無ければ従来どおり1枚。terrain.csv/JSON は変更不要のドロップイン。
- 将来: マップの美しさのため、隣接地形に合わせた「縁フリンジ」方式（境界の辺にだけ縁パーツを重ねる2パス目）へ段階的に移行する。ベースタイルを枠内で自己完結する絵にしておけば、フリンジは純粋な追加（縁パーツ＋描画パス＋地形の優先順位表）で足せる＝手戻りなし。フル遷移（Wangタイル・組合せ爆発）は不採用。

---

## 2. 生成方式（TERRAIN STYLE）

生成方式は共通のアンカー方式（共通 STYLE ＋ 地形ごとの SUBJECT／[direction.md](direction.md) §3）。ユニットの人物 STYLE（[units.md](units.md) §3.2）とは別物で、真上視点・画面いっぱい・継ぎ目が出にくい平坦テクスチャに振る。反復を避けるため大きな高コントラストの特徴は禁止（大きな色ムラは「大きな特徴」＝敷き詰めで規則的に繰り返す。平地は盤の大半を覆う背景なので特に均一・低コントラストに保ちユニットを引き立てる）。

TERRAIN STYLE（共通・固定）:
```
STYLE: A top-down ground-terrain tile for a fantasy tactics game, in the same
clean stylized cel-shaded look as the game's unit art: bold flat shading, a
mature, slightly muted, limited color palette (NOT bright saturated, NOT
painterly photorealism). Viewed straight from directly overhead — a flat lay
with NO perspective, NO horizon, NO sky. The texture fills the ENTIRE square
frame edge to edge, with NO border, NO frame, NO vignette, and no single big
focal object. CRITICAL: scatter any small details (grass tufts, pebbles)
RANDOMLY and UNEVENLY — a few loose clusters here, bare empty gaps there —
NEVER evenly spaced, NEVER in rows or a regular grid. Avoid large,
high-contrast patches or blotches (they read as a big feature and repeat
visibly when tiled); keep large-scale color even and low-contrast. Square 1:1.
```

保管・命名（ユニット（[units.md](units.md) §3.1）と同じ二層。terrain.csv/JSON は触らないドロップイン）：

| 段階 | 置き場（`{name}`＝terrain.csv の id） | 例（平地） |
|---|---|---|
| ① AI生成（正方・原寸） | `assets/terrain-src/{name}/` に任意名で複数 | `terrain-src/plain/plain_a.png` |
| SUBJECT | `assets/terrain-src/{name}/{name}_prompt.txt` | `terrain-src/plain/plain_prompt.txt` |
| ② ゲーム用（ヘックス切り抜き・256×222・角透過） | `assets/terrain/{name}.png`（＋連番 `{name}_2.png` …） | `plain.png` / `plain_2.png` |

- ②は正方の生成物を [`../../tools/gen_terrain_tile.ps1`](../../tools/gen_terrain_tile.ps1) でヘックス切り抜き＝`powershell -File tools\gen_terrain_tile.ps1 {name} <src1> <src2> …`（1枚目→`{name}.png`、以降→`_2`,`_3`）。`terrain-src/` は `.gdignore` で Godot 非インポート。
- 【指針】平地・森・山など向きの無い地形は、将来ヘックスごとの60°回転で反復をさらに消せる（回転可否は道・砦・壁・柵を除外＝要フラグ。terrain.csv に列追加で対応）。
- 面で覆う地形（平地・森）は一面テクスチャで作る（森で検証済み）。切り口は密な柄に紛れ、隣接ヘックスがひとつながりの地帯に見える。「ヘックス内に収まる塊＋周囲に地面」のアイコン方式は、塊が円形だと盤上で水玉に見えるため不採用。基準色は SUBJECT に HEX 指定で固定し、地面が覗く地形は平地の基準色（#B4C6A0）を使って地続きに見せる。
- 生成サービスの sparkle 透かしは右下コーナー付近に付く＝ヘックス切り抜きの四隅落ちで自然に消えるため、地形は専用の `_02_dew` 工程が不要＝ `_01_raw`→`_03_master` でよい（[direction.md](direction.md) §3・切り抜き後に四隅残留だけ目視確認する）。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（人物 STYLE・二層保管の原型）
- [../gdd/movement.md](../gdd/movement.md) — 移動タイプ・地形コスト
- [../../presentation/board/hex_board_3d.gd](../../presentation/board/hex_board_3d.gd) — 盤面（タイル敷き・バリアント敷き分け）
- [`../../tools/gen_terrain_tile.ps1`](../../tools/gen_terrain_tile.ps1) — ②ヘックス切り抜きツール
- [../../tools/gen_terrain_tiles.gd](../../tools/gen_terrain_tiles.gd) — プレースホルダ生成
