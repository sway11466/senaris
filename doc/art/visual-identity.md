# ビジュアルアイデンティティ（絵柄の方針＋陣営配色）

ユニットの「見た目」を生成する前に決めておく設計。全陣営に共通するルールの正本。陣営ごとのルール（役割の記号・個体の特徴）は各陣営のフォルダ（§4）に置く。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 基本方針

- 絵は顧客獲得に全振り。ゲームの本体は戦術パズルの面白さ。アートは獲得ROIが最大の場所に集中投下し、それ以外は機能的に済ませる（労力を盛らない）。
- 基調＝クリーン様式化・強シルエット・限定パレット（"Into the Breach のファンタジー版"トーン）。絵画調は不採用——緻密な絵は盤面縮小で潰れ、ゲーム構造（没個性・リスキン）とも噛まず、AI出自も目立ちやすいため。配色は渋め（muted）で大人っぽく。
- 色で陣営、シルエット＋小物で役割。戦術パズルは「どっち側の駒か」と「何をする駒か」を一瞬で読めることが生命線（敵は味方ステータスのリスキンで同じ盤に混在するため）。
- 色だけに頼らない。理由：(1) 行動済みはグレー化処理があり色が抜ける、(2) 色覚多様性。
  → 陣営は「色＋プロポーション」（味方＝人間的で端正／魔物＝異形）で二重化し、役割は必ず形で持たせる。色は補強。
- ツール＝Gemini Nano Banana（Google AI Studio・無料枠）。一貫性は共通STYLE文＋SUBJECTの言葉指定で担保（i2i／参照画像は使わない）。渾身の1枚＝ファイターで STYLE 文を固め、以降は同じ STYLE 文に「same palette / same face as the fighter」等を書いて text から展開する。
- 【指針】無料版でも商用利用は可（著作権補償は無し）。配信前に最新ToSと Steam の AI 開示を確認。生成物には SynthID 透かしが付く。

---

## 2. 陣営カラールール（color = team）

| 陣営（skin の分類） | 基調色 | 質感・補助色 | 狙い |
|---|---|---|---|
| 味方（基準） | 青〜鋼色（スティールブルー） | 銀の鎧＋白＋金の差し色／端正な人間体型 | 正規軍・秩序 |
| 敵（汎用） | 赤黒 | 黒＋深紅＋炎のオレンジの差し色 | 強大・脅威。特定の区分けに属さない敵すべてに適用する既定色 |
| ゴブリン | 緑（オリーブ〜病んだ緑） | 茶の革＋錆びた粗末な鉄／低く歪な体型 | 野卑・粗製 |
| アンデッド | 骨白＋寒色紫／青緑の燐光 | ボロ布の黒＋ネクロな紫グロウ | 死・冷たさ |

- 基調色は SUBJECT を書くときの言葉での指定。HEX 等の数値は決めない（生成はテキスト指定で、参照する工程がない。必要になったらアンカー画像から抽出する）。
- 陣営を増やすときは、既存の陣営色と色相・明度が離れた基調色を選ぶ（盤面でもストア画面でも陣営が一目で分かれること）。

---

## 3. 全ユニット共通ルール

- 飛行は全陣営で「浮いて見える」を必須（足元に影＋宙に浮く姿勢）。
  - 理由：飛行は `atk_air>0` の駒でしか攻撃・反撃できず（[../gdd/combat.md](../gdd/combat.md)）、読み違えると1ターン丸損する罰の重い機構。武器表現は自由でも、浮遊だけはどの陣営でも揃える。
- 造形・サイズ・背景などの制作仕様は §5、プロンプト雛形（共通STYLE）は §5.2。

---

## 4. 陣営ごとのルール

各陣営の見た目ルール（役割ごとの記号・ユニット個体の特徴）は、その陣営のソースフォルダ直下の `style.md` が正本：`assets/units/source/{group}/style.md`

- 味方: [player/style.md](../../assets/units/source/player/style.md)
- 敵陣営は着手時に作成（例: ゴブリン → `source/goblin/style.md`）。

敵陣営に共通する方針：

- 味方の形ルールをそのまま流用しない。性能（type）は味方から借りているだけで、見た目は別物。姿＝そのモンスター自身とし、味方の職業記号（聖印・魔術帽・ローブ等）は持ち込まない。
  - 例：ゴブリンは cleric 性能（弱い・占領可）を借りるが、見た目は下っ端ゴブリン雑兵であって聖職者ではない。
- 機能サインは陣営ごとに自由。ただしその陣営の中（カテゴリ内）では一貫させる。
  - 敵の遠隔役は弓とは限らない（投げ槍・呪詛・火球等でよい）。ゴブリン＝弓／アンデッド＝骨槍や呪弾／汎用の敵＝火球、のように陣営ごとに変えてよいが、同じ陣営の遠隔役どうしは揃える。
  - 根拠：各冒険譚は基本1陣営ずつ相手にする（[../campaign/tutorial1-goblin-raid.md](../campaign/tutorial1-goblin-raid.md)＝ゴブリン、[../campaign/tutorial2-undead-rush.md](../campaign/tutorial2-undead-rush.md)＝アンデッド）ので、プレイヤーは1陣営の見た目だけ覚えればよく、陣営横断の統一は不要。射程・挙動はゲーム側（射程表示・情報パネル）でも伝わる。
- キャスティングは元々モンスターの自然な姿に合う性能が選ばれている（goblin=cleric→下っ端、hobgoblin=priest→巨漢、goblin_lord=paladin→ボス、skeleton=priest→骨戦士、zombie=bishop→硬い屍、necromancer=witch→術者ボス）。聖職記号なしでも役割は成立する。

---

## 5. 制作スペック（サイズ・ワークフロー）

盤面の実寸（[../../presentation/board/hex_board.gd](../../presentation/board/hex_board.gd) `hex_size=36`、フラットトップ）：

- 1マス＝約 72px（横）× 62px（縦）（標準ズーム）。ズーム 0.3〜2.5 倍で最大約180pxまで拡大。

| 段階 | サイズ | 用途 |
|---|---|---|
| ① AI生成（マスター） | 約1024px | 原本。別保管（キービジュアル等に再利用） |
| ② ゲーム用書き出し | 256px 四方（透過PNG） | リポジトリに入れる。地形タイル（R=128＝256px相当）と画質を揃える |
| ③ 実機表示 | 60〜180px | Godot が②を自動縮小 |

- 造形：頭身は約2〜2.5頭身（強めのチビ体型＝頭・手大きめで小サイズ可読性を優先。武器・役割小物は太く大きめに保つ。moe／可愛すぎにはしない、渋い muted は維持）。正面向き・左右非対称にしない中立ポーズ（盤面に向きの概念が無く、向きを主張すると不自然／6方向で反転も無意味なため）。
- 背景は純白（後で透過処理）。ただし白系ユニット（聖職の白ローブ等）は輪郭が溶けるので薄グレー等に例外。正方形キャンバス・キャラはやや下寄り（足が下辺＝マスに立つ）。完全透過は狙わず「単色背景→背景除去」。
- 【指針】縮小して潰れない絵を狙う：1024pxを必ず60〜72pxにプレビューし、役割が読めるか確認。読めなければ細部でなく形・シルエット・色を直す。
- 【指針】「動いて見せる」は絵を増やさず、コード側の移動tween＋簡単なエフェクトで出す（歩行コマ＝複数枚はAI一貫性が悪く・物量も数倍なので作らない）。行動前後は当面 `map` 1枚＋グレー化（[overview.md](overview.md)）。

### 5.1 ファイルの保管・命名（3段階すべて git 管理）

| 段階 | 置き場（`{skin_id}`＝unit_skin のID・`{group}`＝陣営フォルダ） | 例（ファイター） |
|---|---|---|
| ① AI生成直後（原寸・SynthID入り） | `assets/units/source/{group}/{skin_id}/{skin_id}_01_raw.png` | `source/player/fighter/fighter_01_raw.png` |
| ② トリミング＋透過（手動マスター・原寸） | `assets/units/source/{group}/{skin_id}/{skin_id}_02_master.png` | `source/player/fighter/fighter_02_master.png` |
| ③ ゲーム用（256四方・透過・64色） | `assets/units/{skin_id}/{skin_id}_map.png` | `fighter_map.png` |

- `{group}`＝陣営フォルダ。味方は `player/`、敵は陣営名（例: `goblin/`）。ツールは `source/` 配下を再帰検索して `{skin_id}` フォルダを見つけるため、グループの増設にツール変更は不要。
- ③だけが `assets/`（ゲームが読む正）。スロット制なので将来 `{skin_id}_combat.png` / `{skin_id}_portrait.png` を同フォルダに追加。スキン側で `images.map = "res://assets/units/{skin_id}/{skin_id}_map.png"` を指すと絵に切替（コード不変）。
- ①②は `assets/units/source/`（作業ソース）。`assets/units/source/.gdignore` で Godot のインポート対象外にする（原寸を取り込ませない）。ファイル名に `{skin_id}` を前置きするのは、複数スキンを1フォルダに並べて比較できるようにするため。

手順（1体を追加するとき）:

1. AI生成 → `{skin_id}_01_raw.png` を `source/{group}/{skin_id}/` に保存（生成に使った SUBJECT は `{skin_id}_prompt.txt` に残す＝§5.2）。
2. 手動でトリミング＋背景透過 → `{skin_id}_02_master.png`（同フォルダ）。
3. ③を書き出す：
   ```
   powershell -File tools\gen_unit_map.ps1 {skin_id}      # 複数可 / all で全スキン
   ```
   ②master と `unit_skin.csv` の `map_scale` から「高さ＝200×倍率 → 256四方・透過・64色」を自動生成（[`tools/gen_unit_map.ps1`](../../tools/gen_unit_map.ps1)）。②が無ければ①から暫定生成し、②が来たら同コマンドで作り直す。
4. Godot 再実行 → `SkinCatalog` が `assets/units/{skin_id}/{skin_id}_map.png` を規約で自動解決し盤面に反映。

- ツールは ImageMagick（`magick`）が必要。③レシピの正本はこのツール（`.ps1` は ASCII のみ＝Windows PowerShell 5.1 の UTF-8 誤読対策）。

### 5.2 確定プロンプト雛形（アンカー方式）

`STYLE:` ブロックは全ユニット共通で固定、`SUBJECT:` ブロックだけ差し替える。i2i（参照画像）は使わず、同じ STYLE 文＋SUBJECT の言葉指定だけで一貫性を出す。SUBJECT に「same steel-blue palette / same face style as the fighter」等を明記するのがコツ。Nano Banana はタグ羅列より自然文の描写が効く。

STYLE（共通・固定）:
```
STYLE: A single fantasy tactics-game unit piece, clean stylized vector-like
illustration with bold flat cel-shading and a strong readable silhouette.
Chunky, appealing, strong super-deformed / chibi proportions — about 2 to 2.5
heads tall, with a very large oversized head, a small stubby body and short
thick limbs; keep the weapon and role props chunky and bold so they still read
clearly even at tiny sizes. Expressive face with large clear eyes and a calm,
confident personality (not angry or grimacing). Simplified, bold, rounded
chunky shapes. Charming and heroic with a bit of grit — a strong chibi build,
but NOT moe and NOT overly cute; grounded in a mature, slightly
muted, limited color palette. NOT bright saturated anime coloring, NOT
painterly photorealism. Soft rim light, minimal fussy detail so the shape
reads clearly even when shrunk very small. Strictly symmetrical, straight-on front
view — the character faces the camera directly, shoulders square to the viewer
(NO three-quarter turn, NO side view). Full body, standing in a neutral,
evenly-weighted stance that does NOT commit to a left or right direction —
weapon(s) held upright and ready in front, close to the body, not extended or
pointing off to one side. Centered, feet near the
lower third with a small soft ground shadow. Plain pure-white background
(single flat color, for easy cutout). Square 1:1 composition.
```

SUBJECT（生成プロンプト本体）の置き場：

各ユニットの `SUBJECT:` は raw と同じ `assets/units/source/{group}/{skin_id}/{skin_id}_prompt.txt` に置く（共通の STYLE と作成ルールは本 doc が正本）。生成時は STYLE を先頭に付け、続けて `{skin_id}_prompt.txt` を貼る。参照画像（i2i）は使わない。

- SUBJECT は §2〜4 のルール（陣営色・共通ルール・各陣営 `style.md`）に沿って書く。
- 歩兵ライン（ノービス／ファイター／ヴァンガード）は同一系統：剣のサイズ＋装甲の重さで段階化し、盾は持たせない（大盾はナイト専用）。系統感は SUBJECT 内の「same steel-blue palette / same face style as the fighter」で保つ。

### 5.3 扉絵・キービジュアル用 STYLE（ILLUST）

冒険譚の扉絵（ステージ一覧の大パネル＋冒険譚選択カードでクロップ使い回し）やストア用キービジュアルに使う。絵柄の DNA（セル調・muted・同じキャラ造形）はユニットと同じまま、駒用の制約（正面・中立ポーズ・単色背景）を解禁し、構図・光・背景で演出する。文字は入れない（タイトルはUI側で描く）。

生成の透かし（右下）対策＝4:3 で生成し右側を切り捨てる方針。主題は中央〜左に置き、右端15%は切り捨て可能なモブ・背景のみ、右下角には何も置かない。右を切った仕上がり（5:4〜ほぼ正方形）がパネルの正、カードは横帯クロップ。

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

- 生成時はこの ILLUST STYLE を先頭に付け、続けて各冒険譚の `cover_prompt.txt` を貼る（ユニットと同じアンカー方式）。

保管・命名（ユニット §5.1 と同じ「source＝作業／直下＝ゲームが読む正」の二層）：

| 段階 | 置き場（`{campaign_id}`＝data/stages のフォルダ名） | 例 |
|---|---|---|
| ① AI生成直後（原寸・透かし入り） | `assets/campaign/source/{campaign_id}/{campaign_id}_01_raw.png` | `source/tutorial1-goblin-raid/tutorial1-goblin-raid_01_raw.png` |
| SUBJECT | `assets/campaign/source/{campaign_id}/cover_prompt.txt` | 同上フォルダ |
| ② ゲーム用（右15%クロップで透かし除去） | `assets/campaign/{campaign_id}/{campaign_id}_cover.png` | `tutorial1-goblin-raid_cover.png` |

- ②は `assets/campaign/{campaign_id}/` に置くと `CampaignCatalog` が規約で自動解決し、ステージ一覧の大パネル＋冒険譚カードに反映する（ユニットの skin 画像 autowire と同じ思想）。`source/` は `.gdignore` で Godot 非インポート。
- クロップは右を落とす（透かしが右下・主題は中央〜左に寄せる構図ルールと一致）。1枚を大パネル＝クロップ後の全体、カード＝横帯クロップで使い回す。

## 5.4 地形タイル（盤面）

- 形状: フラットトップ六角形・256×222px（中心〜頂点 R=128／上下平辺間 √3R）・角は透過。盤（[../../presentation/board/hex_board.gd](../../presentation/board/hex_board.gd)）が terrain_id ごとに1枚を各ヘックスに敷く。置き場は `assets/terrain/{name}.png`（terrain.csv の image 列）。プレースホルダ生成は [../../tools/gen_terrain_tiles.gd](../../tools/gen_terrain_tiles.gd)、アート確定後は同名で差し替えるだけ（描画コード不変）。
- 現状は「1地形1枚・接地による遷移なし」。各ヘックスが地形の自己完結アイコン（Into the Breach 系）。
- 反復対策＝バリアント敷き分け（実装済み）: 同名連番 `{name}_2.png` `{name}_3.png` … を置くと、hex_board が存在する分を集め、ヘックス座標から決定的に敷き分ける（ちらつかない）。連番が無ければ従来どおり1枚。terrain.csv/JSON は変更不要のドロップイン。
- 将来: マップの美しさのため、隣接地形に合わせた「縁フリンジ」方式（境界の辺にだけ縁パーツを重ねる2パス目）へ段階的に移行する。ベースタイルを枠内で自己完結する絵にしておけば、フリンジは純粋な追加（縁パーツ＋描画パス＋地形の優先順位表）で足せる＝手戻りなし。フル遷移（Wangタイル・組合せ爆発）は不採用。

生成方式はユニットと同じアンカー方式（共通 STYLE ＋ 地形ごとの SUBJECT）。ユニットの人物 STYLE（§5.2）とは別物で、真上視点・画面いっぱい・継ぎ目が出にくい平坦テクスチャに振る。反復を避けるため大きな高コントラストの特徴は禁止（大きな色ムラは「大きな特徴」＝敷き詰めで規則的に繰り返す。平地は盤の大半を覆う背景なので特に均一・低コントラストに保ちユニットを引き立てる）。

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

保管・命名（ユニット §5.1 と同じ二層。terrain.csv/JSON は触らないドロップイン）：

| 段階 | 置き場（`{name}`＝terrain.csv の id） | 例（平地） |
|---|---|---|
| ① AI生成（正方・原寸） | `assets/terrain/source/{name}/` に任意名で複数 | `source/plain/plain_a.png` |
| SUBJECT | `assets/terrain/source/{name}/{name}_prompt.txt` | `source/plain/plain_prompt.txt` |
| ② ゲーム用（ヘックス切り抜き・256×222・角透過） | `assets/terrain/{name}.png`（＋連番 `{name}_2.png` …） | `plain.png` / `plain_2.png` |

- ②は正方の生成物を [`../../tools/gen_terrain_tile.ps1`](../../tools/gen_terrain_tile.ps1) でヘックス切り抜き＝`powershell -File tools\gen_terrain_tile.ps1 {name} <src1> <src2> …`（1枚目→`{name}.png`、以降→`_2`,`_3`）。`source/` は `.gdignore` で Godot 非インポート。
- 【指針】平地・森・山など向きの無い地形は、将来ヘックスごとの60°回転で反復をさらに消せる（回転可否は道・砦・壁・柵を除外＝要フラグ。terrain.csv に列追加で対応）。

---

## 6. 未決事項

- [ ] （次アクション）ファイター・アンカーの60px縮小テスト：白余白をクロップ→実寸ヘックス（72×62px）で「剣＋盾の前衛」と読めるか確認。潰れなければ正式にアンカー確定。読めなければ形・シルエット・色を直す。※クラウド環境ではチャット添付がファイル化されず処理不可だったため、ローカルセッションで画像をファイルにして実施する。
- [ ] 敵スキン個別の姿（陣営ごとの機能サイン表現＝遠隔の武器など）＝各陣営の `style.md` として着手時に作成。
- [ ] 会話用クラスポートレート（`combat` 系・役職原型 8〜10枚）の着手判断。
- [ ] 獲得用キービジュアル（冒険譚1「隘路で少数 vs 群れ」／冒険譚2「三重詠唱が屍の波を薙ぐ」＝機構が動く瞬間）。
- [ ] 移動tween／攻撃エフェクト（コード側＝絵を増やさず動きを出す手段）の実装可否。

---

## 参考資料

- [assets/units/source/player/style.md](../../assets/units/source/player/style.md) — 味方陣営の見た目ルール（役割の記号・27種の個体特徴）
- [overview.md](overview.md) — 画像スロット（`map`/`combat`）・プレースホルダ・制作手段（生成AI）
- [../gdd/units.md](../gdd/units.md) — 性能と見た目の分離（`UnitType`/`UnitSkin`・skin_id 方式）
- [`../../data/units/unit_type.csv`](../../data/units/unit_type.csv) / [`../../data/units/unit_skin.csv`](../../data/units/unit_skin.csv) — ロスター正本
- [../campaign/tutorial1-goblin-raid.md](../campaign/tutorial1-goblin-raid.md) / [../campaign/tutorial2-undead-rush.md](../campaign/tutorial2-undead-rush.md) — 各冒険譚の敵陣営（§4 の根拠）
- [../gdd/combat.md](../gdd/combat.md) — 対空機構（飛行の浮遊必須ルールの根拠）
- [../../presentation/board/hex_board.gd](../../presentation/board/hex_board.gd) — 盤面実寸（`hex_size=36`）
- [`tools/gen_unit_map.ps1`](../../tools/gen_unit_map.ps1) — ③ゲーム用画像の書き出しツール
