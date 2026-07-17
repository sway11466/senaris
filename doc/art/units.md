# ユニットの見た目方針

盤上のユニット画像を生成する前に決めておく設計。全陣営に共通するトーン・配色・制作メソッドは [direction.md](direction.md) が正本。本ファイルはユニット固有：全ユニット共通ルール・陣営ごとのルール・制作スペック（サイズ・命名・STYLE・SUBJECT雛形）。陣営ごとの個体特徴は各陣営フォルダの `assets/units-src/{group}/style.md`（§2）。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 全ユニット共通ルール

- 飛行は全陣営で「浮いて見える」を必須（足元に影＋宙に浮く姿勢）。
  - 理由：飛行は `atk_air>0` の駒でしか攻撃・反撃できず（[../gdd/combat.md](../gdd/combat.md)）、読み違えると1ターン丸損する罰の重い機構。武器表現は自由でも、浮遊だけはどの陣営でも揃える。
- 【指針】「動いて見せる」は絵を増やさず、コード側の移動tween＋簡単なエフェクトで出す（歩行コマ＝複数枚はAI一貫性が悪く・物量も数倍なので作らない）。行動前後は当面 `map` 1枚＋グレー化（画像スロット → [overview.md](overview.md)）。
- 造形・サイズ・背景などの制作仕様は §3、プロンプト雛形（共通STYLE）は §3.2。

---

## 2. 陣営ごとのルール

各陣営の見た目ルール（役割ごとの記号・ユニット個体の特徴）は、その陣営のソースフォルダ直下の `style.md` が正本：`assets/units-src/{group}/style.md`

- 味方: [player/style.md](../../assets/units-src/player/style.md)
- 敵陣営は着手時に作成（例: ゴブリン → `source/goblin/style.md`）。

敵陣営に共通する方針：

- 味方の形ルールをそのまま流用しない。性能（type）は味方から借りているだけで、見た目は別物。姿＝そのモンスター自身とし、味方の職業記号（聖印・魔術帽・ローブ等）は持ち込まない。
  - 例：ゴブリンは cleric 性能（弱い・占領可）を借りるが、見た目は下っ端ゴブリン雑兵であって聖職者ではない。
- 機能サインは陣営ごとに自由。ただしその陣営の中（カテゴリ内）では一貫させる。
  - 敵の遠隔役は弓とは限らない（投げ槍・呪詛・火球等でよい）。ゴブリン＝弓／アンデッド＝骨槍や呪弾／汎用の敵＝火球、のように陣営ごとに変えてよいが、同じ陣営の遠隔役どうしは揃える。
  - 根拠：各冒険譚は基本1陣営ずつ相手にする（[../campaign/tutorial1-goblin-raid.md](../campaign/tutorial1-goblin-raid.md)＝ゴブリン、[../campaign/tutorial2-undead-rush.md](../campaign/tutorial2-undead-rush.md)＝アンデッド）ので、プレイヤーは1陣営の見た目だけ覚えればよく、陣営横断の統一は不要。射程・挙動はゲーム側（射程表示・情報パネル）でも伝わる。
- キャスティングは元々モンスターの自然な姿に合う性能が選ばれている（goblin=cleric→下っ端、hobgoblin=priest→巨漢、goblin_lord=paladin→ボス、skeleton=priest→骨戦士、zombie=bishop→硬い屍、necromancer=witch→術者ボス）。聖職記号なしでも役割は成立する。

---

## 3. 制作スペック（サイズ・ワークフロー）

盤面（[../../presentation/board/hex_board_3d.gd](../../presentation/board/hex_board_3d.gd)）はフラットトップ六角の3D（タイルは `TILE=1.0` ワールド単位）。2D時代の `hex_size=36`（px）は撤去済み：

- 制作は地形タイル（256×222px＝R=128）と解像度を揃えるのが基準。実機の1マス表示pxはカメラのズーム（ロード時のオートフィット）と盤サイズ・画面解像度で変わり固定値は無い。実測（1280×720・オートフィット・盤中央）＝小盤 st1(14×8) で幅約66px、大盤 st6(30×10) で幅約32px（高さは幅の約0.7＝俯角ぶん縮む）。手動ズームインでさらに拡大。解像度が上がれば比例して大きくなる。

| 段階 | サイズ | 用途 |
|---|---|---|
| ① AI生成（マスター） | 約1024px | 原本。別保管（キービジュアル等に再利用） |
| ② ゲーム用書き出し | 256px 四方（透過PNG） | リポジトリに入れる。地形タイル（R=128＝256px相当）と画質を揃える |
| ③ 実機表示 | 約30〜75px（720p・オートフィット。ズームで拡大） | Godot が②を自動縮小 |

- 造形：頭身は約2〜2.5頭身（強めのチビ体型＝頭・手大きめで小サイズ可読性を優先。武器・役割小物は太く大きめに保つ。moe／可愛すぎにはしない、渋い muted は維持）。正面向き・左右非対称にしない中立ポーズ（盤面に向きの概念が無く、向きを主張すると不自然／6方向で反転も無意味なため）。
- 背景は純白（後で透過処理）。ただし白系ユニット（聖職の白ローブ等）は輪郭が溶けるので薄グレー等に例外。正方形キャンバス・キャラはやや下寄り（足が下辺＝マスに立つ）。完全透過は狙わず「単色背景→背景除去」。
- 【指針】縮小して潰れない絵を狙う：1024pxを必ず30〜72pxにプレビューし（大盤では1マス30px台まで小さくなる）、役割が読めるか確認。読めなければ細部でなく形・シルエット・色を直す。

### 3.1 ファイルの保管・命名（3段階すべて git 管理）

| 段階 | 置き場（`{skin_id}`＝unit_skin のID・`{group}`＝陣営フォルダ） | 例（ファイター） |
|---|---|---|
| ① AI生成直後（原寸・SynthID入り） | `assets/units-src/{group}/{skin_id}/{skin_id}_01_raw.png` | `units-src/player/fighter/fighter_01_raw.png` |
| ② トリミング＋透過（手動マスター・原寸） | `assets/units-src/{group}/{skin_id}/{skin_id}_03_master.png` | `units-src/player/fighter/fighter_03_master.png` |
| ③ ゲーム用（256四方・透過・64色） | `assets/units/{skin_id}/{skin_id}_map.png` | `fighter_map.png` |

- `{group}`＝陣営フォルダ。味方は `player/`、敵は陣営名（例: `goblin/`）。ツールは `units-src/` 配下を再帰検索して `{skin_id}` フォルダを見つけるため、グループの増設にツール変更は不要。
- ③だけが `assets/`（ゲームが読む正）。スロット制なので将来 `{skin_id}_combat.png` / `{skin_id}_portrait.png` を同フォルダに追加。スキン側で `images.map = "res://assets/units/{skin_id}/{skin_id}_map.png"` を指すと絵に切替（コード不変）。
- ①②は `assets/units-src/`（作業ソース）。`assets/units-src/.gdignore` で Godot のインポート対象外にする（原寸を取り込ませない）。ファイル名に `{skin_id}` を前置きするのは、複数スキンを1フォルダに並べて比較できるようにするため。
- 透かし: 共通ルールの `_02_dew`（[direction.md](direction.md) §3）はユニットでは②のトリミング＝透過で一緒に落ちる（透過切り抜きで sparkle も消える）ため専用 dew ファイルは作らず `_01_raw`→`_03_master` の2段。番号は master=03 で固定＝02 が無い＝dew を通していない、と読める（`gen_unit_map.ps1` は `_03_master` を読み、旧 `_02_master` もフォールバックで拾う）。

手順（1体を追加するとき）:

1. AI生成 → `{skin_id}_01_raw.png` を `source/{group}/{skin_id}/` に保存（生成に使った SUBJECT は `{skin_id}_prompt.txt` に残す＝§3.2）。
2. 手動でトリミング＋背景透過 → `{skin_id}_03_master.png`（同フォルダ）。
3. ③を書き出す：
   ```
   powershell -File tools\gen_unit_map.ps1 {skin_id}      # 複数可 / all で全スキン
   ```
   ②master と `unit_skin.csv` の `map_scale` から「高さ＝200×倍率 → 256四方・透過・64色」を自動生成（[`tools/gen_unit_map.ps1`](../../tools/gen_unit_map.ps1)）。②が無ければ①から暫定生成し、②が来たら同コマンドで作り直す。
4. Godot 再実行 → `SkinCatalog` が `assets/units/{skin_id}/{skin_id}_map.png` を規約で自動解決し盤面に反映。

- ツールは ImageMagick（`magick`）が必要。③レシピの正本はこのツール（`.ps1` は ASCII のみ＝Windows PowerShell 5.1 の UTF-8 誤読対策）。

### 3.2 確定プロンプト雛形（アンカー方式）

アンカー方式の考え方は [direction.md](direction.md) §3。`STYLE:` ブロックは全ユニット共通で固定、`SUBJECT:` ブロックだけ差し替える。i2i（参照画像）は使わず、同じ STYLE 文＋SUBJECT の言葉指定だけで一貫性を出す。SUBJECT に「same steel-blue palette / same face style as the fighter」等を明記するのがコツ。Nano Banana はタグ羅列より自然文の描写が効く。

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

各ユニットの `SUBJECT:` は raw と同じ `assets/units-src/{group}/{skin_id}/{skin_id}_prompt.txt` に置く（共通の STYLE と作成ルールは本 doc が正本）。生成時は STYLE を先頭に付け、続けて `{skin_id}_prompt.txt` を貼る。参照画像（i2i）は使わない。

- SUBJECT は §2（陣営色・共通ルール・各陣営 `style.md`）と [direction.md](direction.md) §2 のルールに沿って書く。
- 歩兵ライン（ノービス／ファイター／ヴァンガード）は同一系統：剣のサイズ＋装甲の重さで段階化し、盾は持たせない（大盾はナイト専用）。系統感は SUBJECT 内の「same steel-blue palette / same face style as the fighter」で保つ。

### 3.3 戦闘立ち絵（combat スロット）

盤上の駒（map＝正面・中立ポーズ）とは別に、戦闘演出で使う立ち絵。演出シーンの仕様は [../tech/combat_scene.md](../tech/combat_scene.md)、スロット定義は [overview.md](overview.md)。

- 画角：3/4俯瞰（盤の傾けカメラ＝[../adr/ADR-0003-board-3d-hybrid.md](../adr/ADR-0003-board-3d-hybrid.md) に合わせ地続きに見せる）。臨戦ポーズ（map の正面/中立は取らない）。
- 向きは陣営で固定して焼き込む：プレイヤーは右向き・敵は左向き（プレイヤー左／敵右で対峙）。左右反転はしないので武器の持ち手が破綻しない。
- 1スキン1枚＝単体を描く。演出側が兵数（1〜8・[../gdd/combat.md](../gdd/combat.md)）ぶんを隊列スロットに複製表示する。
- 透過切り抜き（map と同じ「単色背景→背景除去」）。背景は演出側が地形ごとに敷くのでキャラのみ。
- 特別ユニット：英雄を別に1枚（combat_hero）。演出は英雄1体＋残りを base の combat で埋める（例：兵数5＝英雄1＋従者4）。敵側のボス系で使うことが多い。
- 攻撃エフェクト：ユニットごと1枚（combat_effect）。相手の隊列上に重ねて出す（斬撃＝被弾側／魔法＝着弾側）。
- 保管は §3.1 と同じ二層。追加スロットは -src 側に `_combat` トークンを前置して map ソースと共存する（map は既定＝トークン無し）：
  - 作業ソース `assets/units-src/{group}/{skin_id}/`：`{skin_id}_combat_01_raw.png` → `_combat_03_master.png`（トリム＝透過で透かしも落ちるので dew(02) は飛ばす。番号は master=03 で固定＝[direction.md](direction.md) §3 の3段命名と一致）。SUBJECT は `{skin_id}_combat_prompt.txt`。英雄／エフェクトは `_combat_hero_`／`_combat_effect_` で同様。
  - ゲーム用 `assets/units/{skin_id}/`：`{skin_id}_combat.png`（＋任意 `_combat_hero.png`／`_combat_effect.png`）。master をトリム→長辺512pxに縮小・透過維持で書き出す（256四方・減色はしない＝combat は演出側が KEEP_ASPECT で縮小表示）。書き出しは [`tools/gen_unit_combat.ps1`](../../tools/gen_unit_combat.ps1)（`{skin_id}` 複数可／`all`）。
- 生成順：combat は map と同じ生成セッションで一緒に出す（全スロットを一度に）。text アンカーだけでは既存キャラは再現できず、別セッションでは同一キャラにならないため（i2i は使わない方針＝[direction.md](direction.md) §3）。既存ユニットに後から足す場合は、そのユニットを map から作り直す。

生成は3ブロックを順に貼る：STYLE（共通・固定・ポーズ非依存）＋ POSE（下のカタログから役割で選ぶ）＋ SUBJECT（ユニット別）。POSE と SUBJECT は `{skin_id}_combat_prompt.txt` に一緒に置く（先頭に POSE 行 → SUBJECT）。STYLE は本 doc が正本。

STYLE（共通・固定・ポーズ非依存）:
```
STYLE: A single fantasy tactics-game battle piece of ONE unit, drawn in the
SAME character style, palette and face as the game's board unit pieces: clean
stylized vector-like illustration, bold flat cel-shading, chunky appealing
super-deformed / chibi proportions about 2 to 2.5 heads tall with a large head
and short thick limbs, expressive calm face, mature slightly muted limited color
palette (NOT bright saturated anime, NOT painterly photorealism), soft rim
light, minimal fussy detail so it still reads when small. Unlike the board
piece, this is seen from a slight high three-quarter overhead angle, as if
looking down onto the battlefield, and the character is turned to face toward
the RIGHT edge of the frame (facing the enemy line). Full body with both feet
visible. Exactly ONE character, no crowd, no companions. Plain pure-white
background (single flat color, for easy cutout), NO ground, NO ground shadow or
drop shadow under the feet, NO scenery, NO text or logo. Square 1:1 composition.
```

POSE カタログ（役割で選ぶ。増やしてよい）:
```
POSE (melee): A dynamic battle-ready action pose — weapon raised or mid-strike, weight forward, leaning into the blow as the character presses toward the enemy on the right.
```
```
POSE (channel): A calm, grounded channelling pose — standing composed with both feet planted, focused on working a spell or blessing rather than striking; not lunging, not advancing.
```
```
POSE (ranged): A poised shooting stance — bow drawn to the cheek (or crossbow/gun leveled), aiming toward the enemy on the right, weight balanced and steady, focused down the shot; not lunging into melee.
```
- 近接（歩兵・盗賊系）＝`melee`／支援・詠唱（クレリック・プリースト・ビショップ・魔法兵）＝`channel`／遠隔（弓・砲兵）＝`ranged`。
- 向きは陣営で焼き込む：味方は STYLE の `RIGHT`（右向き）、敵スキンは `RIGHT` を `LEFT`（左向き）に1語替える。
- 分担：佇まい＝POSE、キャラ・持ち物・特徴＝SUBJECT。SUBJECT には「same face / same steel-blue palette as the fighter（map と同一キャラ）」を明記して同一性を担保する（§3.2 と同じコツ）。

---

## 4. 未決事項

- [ ] （次アクション）ファイター・アンカーの60px縮小テスト：白余白をクロップ→実寸ヘックス（72×62px）で「剣＋盾の前衛」と読めるか確認。潰れなければ正式にアンカー確定。読めなければ形・シルエット・色を直す。※クラウド環境ではチャット添付がファイル化されず処理不可だったため、ローカルセッションで画像をファイルにして実施する。
- [ ] 敵スキン個別の姿（陣営ごとの機能サイン表現＝遠隔の武器など）＝各陣営の `style.md` として着手時に作成。
- [ ] 会話用クラスポートレート（`portrait` スロット・役職原型 8〜10枚）の着手判断。combat 立ち絵（§3.3）とは別。
- [ ] 移動tween／攻撃エフェクト（コード側＝絵を増やさず動きを出す手段）の実装可否。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・陣営配色・共通メソッド）
- [assets/units-src/player/style.md](../../assets/units-src/player/style.md) — 味方陣営の見た目ルール（役割の記号・27種の個体特徴）
- [overview.md](overview.md) — 画像スロット（`map`/`combat`）・プレースホルダ
- [../gdd/units.md](../gdd/units.md) — 性能と見た目の分離（`UnitType`/`UnitSkin`・skin_id 方式）
- [../gdd/combat.md](../gdd/combat.md) — 対空機構（飛行の浮遊必須ルールの根拠）
- [../campaign/tutorial1-goblin-raid.md](../campaign/tutorial1-goblin-raid.md) / [../campaign/tutorial2-undead-rush.md](../campaign/tutorial2-undead-rush.md) — 各陣営（§2 の根拠）
- [../../presentation/board/hex_board_3d.gd](../../presentation/board/hex_board_3d.gd) — 盤面（3D・タイル敷き。`TILE=1.0` ワールド単位）
- [`tools/gen_unit_map.ps1`](../../tools/gen_unit_map.ps1) — ③ゲーム用画像の書き出しツール
