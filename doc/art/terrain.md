# 地形タイルの方針

盤面に敷く地形タイルの生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルは地形固有：形状・反復対策・TERRAIN STYLE・切り抜きと保管・線地形の接続タイル。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 形状・敷き方

- 形状: フラットトップ六角形・256×222px（中心〜頂点 R=128／上下平辺間 √3R）・角は透過。盤（[../../presentation/board/hex_board_3d.gd](../../presentation/board/hex_board_3d.gd)）が terrain_id ごとに1枚を各ヘックスに敷く（3D盤でも同じPNGをヘックスメッシュに貼る＝この寸法は現行）。置き場は `assets/terrain/{name}.png`（terrain.csv の image 列）。プレースホルダ生成は [../../tools/gen_terrain_tiles.gd](../../tools/gen_terrain_tiles.gd)、アート確定後は同名で差し替えるだけ（描画コード不変）。
- 3Dのヘックスメッシュに貼るUVは外接矩形（[terrain_tiles.gd](../../presentation/board/terrain_tiles.gd)）。横の係数は 0.5、縦は 1/√3 で、横と同じ 0.5 にしてはいけない。0.5 は外接「正方形」（2R×2R）用の値で、PNGは 2R×√3R だから縦だけ 2/√3＝1.155倍に伸び、上下端6.7%が六角形の外へ出て描かれなくなる。自然テクスチャでは正しい縦横比が無いので気付けず、絵の中に位置の約束を持つ地形（§3の接続タイル＝腕の先が辺の中点に来る）で初めて斜めの継ぎ目がずれて見える。
- 現状は「1地形1枚・接地による遷移なし」。各ヘックスが地形の自己完結アイコン（Into the Breach 系）。
- 同じPNGを戦闘演出シーンの地面にも敷く（[../tech/combat_scene.md](../tech/combat_scene.md)）。盤より寄って映る＝繰り返しと継ぎ目が見えやすいので、反復対策（変種・回転）は盤のためだけの措置ではない。
- 【視覚】地形は盤上で標高を持てる（見た目のみ・性能不変）。[hex_board_3d.gd](../../presentation/board/hex_board_3d.gd) の `ELEVATION`（地形id→高さ）でタイルを持ち上げ、低い隣接辺／盤外辺に崖のスカートを下ろしてメサに見せる。現状は台地(plateau)だけ +少し。ユニット・影・グリッド・拠点・オーバーレイ・クリック判定（ピッキング）も標高に追従する。
- 柵・道のような線地形は、隣り合う同スキンとの繋がり方でタイルを選び分ける（§3）。
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

## 3. 接続タイル

柵や道のように隣と繋がって見える地形は、隣り合う同スキンとの繋がり方でタイルの絵が変わる。terrain_skin.csv の `connect` 列を true にすると、盤（[hex_board_3d.gd](../../presentation/board/hex_board_3d.gd)）と [map_editor](../tech/tools.md) が向きの組み合わせ別のタイルを引く。

作り方は2つある（3.2 線方式／3.3 面方式）。**どちらで作っても出力の命名・枚数は同じで、盤とマップエディタは方式を知らない**。`connect` が bool のままなのはそのため＝方式は生成時の話であって、ゲームが読むデータではない。

### 3.1 共通

- ファイル名は `assets/terrain/{skin_id}_c{6桁}.png`。6桁は [Hex.DIRECTIONS](../../domain/hex/hex.gd) の順で、1＝その方向の隣も同じスキン。64通り。欠けている組み合わせは `{skin_id}.png` に落ちる。
- 64枚は手描きしない。元絵1枚から生成する。ヘックス中心から辺の中点までは6方向とも 110.85px なので、1方向ぶんの素材があれば6方向に回せる。
- 切り抜きは明るさで行う（`-Threshold`＝これより明るい画素を地面として捨てる）。**地形の絵は背景より暗いこと**が条件。背景の色は何でもよい＝下地は別に敷くので元絵の背景は全部捨てられる。
  - 柵: 芝地（#B4C6A0・70%）に濃い木材。既定の閾値66%。
  - 道: 純白（100%）に砂色（89%）。`-Threshold 96`。明るい地形は芝地の上に描くと分離できない（差が4ポイントしかない）ので背景を白にする。
- 元絵の縦横比は問わない。スクリプトは元絵の寸法を読まず、渡した矩形だけを切る。
- 落ち影は元絵に焼き込まない。回した素材の影が別方向を向くため、影は生成時に一定方向で付ける。平らな地形は影そのものを出さない（`-NoShadow`）。

### 3.2 線方式（柵）

細い構造物向け。**中心から繋がっている方向へ腕を伸ばして重ねる**（空の状態から足していく）。生成は [`../../tools/gen_connect_tiles.ps1`](../../tools/gen_connect_tiles.ps1)。

- 中心の柱から1つ上の柱までを「腕」として切り出し、60°刻みで回して重ね、中心に柱を置く。
- 繋がるのは腕の先が辺の中点に来るため。柱がちょうど辺の上に乗り、隣のタイルと半分ずつ分け合って1本の柱に見える。
- 元絵の条件: 縦一直線・左右中央・上下端まで貫通・全長どこも同じ姿・フレーム中心と少し上に柱。
- 腕どうしが重なっても「板が重なった」として読めるものだけに使う。地面そのものが変わる地形には向かない（→ 3.3）。

### 3.3 面方式（道）

地面そのものが変わる地形向け。**全面がその地形のタイルを基本形にして、繋がっていない辺を隣の素材で削る**（埋まった状態から引いていく）。線方式とは逆向きの組み立て。

- 基本形（全面が道）は普通の1枚タイル。回転も重ねもしないので、模様も変種（`_2` `_3`）もそのまま持てる。
- 削りは隣の素材（既定は `plain.png`）を「その辺の外側」の形にマスクして被せる。同素材どうしが角で重なっても継ぎ目が見えない。
- 直線の道は「4辺が削られて帯が残る」という形で自然に出る。帯の幅は削りの食い込み量ひとつで決まる（中心から辺の中点までが 110.85px なので、食い込み46で帯は約60%）。
- 削る素材は生成時のパラメータ。洞窟の道なら `plain_cave1` を削り素材に指定する、といった使い分けができる。
- 線方式を面地形に流用しない。腕どうしの重なりが模様のズレとして継ぎ目になり、避けようとすると模様を捨てる（＝ベタ塗りになる）ところまで追い込まれる。

### 3.4 元絵とレシピの置き場

`assets/terrain-src/{skin_id}/` に3点を置く。

| ファイル | 中身 |
|---|---|
| `{skin_id}_prompt.txt` | 生成プロンプト（STYLE＋SUBJECT） |
| `{skin_id}_01_raw.png` ／ `_03_master.png` | 元絵。手を入れたものが master |
| `{skin_id}_recipe.txt` | タイルを書き出したコマンドそのもの（1行） |

レシピを残すのは、生成パラメータ（切り出し位置・閾値・食い込み量）が元絵ごとに違い、実測して決めるため。残さないと作り直しのたびに測り直しになる。コミットメッセージに書くだけでは追えない。

### 3.5 盤の形に由来する制約

- ヘックスの左右は頂点で、東西に隣が無い。真横の直線は引けず、東西に伸ばす線は120°の曲がりが交互に並ぶジグザグになる。ステージJSONでは同じ row に識別文字を並べるとこの形になる。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（人物 STYLE・二層保管の原型）
- [../gdd/movement.md](../gdd/movement.md) — 移動タイプ・地形コスト
- [../../presentation/board/hex_board_3d.gd](../../presentation/board/hex_board_3d.gd) — 盤面（タイル敷き・バリアント敷き分け）
- [`../../tools/gen_terrain_tile.ps1`](../../tools/gen_terrain_tile.ps1) — ②ヘックス切り抜きツール
- [`../../tools/gen_connect_tiles.ps1`](../../tools/gen_connect_tiles.ps1) — 線地形の接続タイル64通りの生成
- [../../tools/gen_terrain_tiles.gd](../../tools/gen_terrain_tiles.gd) — プレースホルダ生成
