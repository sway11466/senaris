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

ストア用キービジュアルに使うときは、末尾の「主題を中央に据える」「4:3」の2文を外す。ロゴを載せる面を空けるために構図を指定するので、そのままだと衝突する。

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
| ① AI生成直後（原寸・透かし入り） | `godot/assets/campaign-src/{id}/{id}_01_raw.png` | `campaign-src/tutorial2-undead-rush/tutorial2-undead-rush_01_raw.png` |
| ② 透かし除去（ツール自動・原寸） | `godot/assets/campaign-src/{id}/{id}_02_dew.png` | 同上フォルダ |
| ③ 手動調整マスター（任意・原寸） | `godot/assets/campaign-src/{id}/{id}_03_master.png` | 同上フォルダ |
| SUBJECT | `godot/assets/campaign-src/{id}/{id}_cover_prompt.txt` | 同上フォルダ |
| ④ ゲーム用（`_03_master`＞`_02_dew` を cp・比率調整は不要） | `godot/assets/campaign/{id}/{id}_cover.png`（＋連番 `{id}_cover_2.png` …） | `tutorial2-undead-rush_cover.png` |

- 変種letter：1枚だけなら **付けない**（上表＝既定）。複数の cover 変種を出して表示ごとにランダムに1枚選ばせたいときだけ `_a`/`_b`/`_c`…（例: `{id}_a_01_raw.png`）を付ける（[campaign_catalog.gd](../../godot/data/stages/campaign_catalog.gd) の連番 `{id}_cover_2.png` はゲーム用側の変種）。チュートリアル1の cover は歴史的経緯で `_a` 付き。
- 命名は他系統と揃える: slot（`_cover`/`_victory`）はユニット skin 流、連番変種（`_2`/`_3`…）は地形・羊皮紙流、-src の `_NN_raw/dew/master`（複数変種時は `_a_NN…`）は羊皮紙流。
- ②は `godot/assets/campaign/{id}/` に置くと `CampaignCatalog` が規約で自動解決し、ステージ一覧の大パネル＋冒険譚の貼り紙に反映する（ユニットの skin 画像 autowire と同じ思想）。`campaign-src/` は `.gdignore` で Godot 非インポート。
- 連番変種（`{id}_cover_2.png` …）を複数置くと、表示ごとにランダムで1枚選ぶ（[campaign_catalog.gd](../../godot/data/stages/campaign_catalog.gd) `_resolve_art_variants`／地形・羊皮紙と同思想）。1枚だけなら固定。
- cover の元は `_03_master` があればそれ、無ければ `_02_dew`（[direction.md](direction.md) §3）。既定は1枚を大パネルと貼り紙（317×230）で使い回す＝押した紙とその先の大パネルが同じ絵であることを優先する（比率はエンジンが合わせる）。紙の寸法に合わせて組んだ絵は大パネルで成立しないので、そういう冒険譚だけ貼り紙用の `{id}_card.png` を別に持つ（[../gdd/stage_select.md](../gdd/stage_select.md) 冒険譚カード）。
- 追加スロット（cover 以外の kind）：cover と同じ二層・同じ ILLUST STYLE（§2）で作り、-src ファイル名に kind トークンを前置して cover と共存させる（ユニットの map=既定／combat=トークン、と同じ思想）。単一絵なら変種letter `_a` は省く。`CampaignCatalog` は `{id}_{kind}.png` を規約解決するので、絵を置くだけで有効・無ければスキップ。
  - `victory`＝キャンペーン完走（最終ステージ勝利）で出す扉絵（[../gdd/stage_select.md](../gdd/stage_select.md) 戦闘後フロー）。SUBJECT `{id}_victory_prompt.txt` → `{id}_victory_01_raw.png` →（透かし除去）`{id}_victory_02_dew.png` → ゲーム用 `godot/assets/campaign/{id}/{id}_victory.png`。

### 手配書の貼り紙

賞金稼ぎの冒険譚の貼り紙（`{id}_card.png`）は、生成せずに組む。ユニットのマスター絵から顔を切り、`WANTED` の字を重ねる＝賞金首の手配書に見立てる。盤に出る駒と同じ顔が貼り出されるので、誰を狩りに行くのかが一目で通じる。

- 紙は敷かない＝背景は透明で出す。貼り紙が下に羊皮紙を持っているため、絵にも紙を持たせると紙の上に紙になる。
- 字は絵の手前に置く。顔を紙の幅いっぱいまで大きくすると冠や兜が字の高さまで届くので、重ねる前提で組む（重ねずに収めると顔が半分の大きさまでしか取れない）。
- 字は `godot/assets/fonts/IMFellEnglish-Regular.ttf`（ゲーム内で使っている活版風の書体）。絵に焼くので翻訳されない＝飾りと割り切る。
- 組むのは [build_wanted_card.py](../../godot/tools/keyvisual/build_wanted_card.py)。大パネル（cover）は紙の寸法に合わせた組みなので流用しない＝別に用意する。

### 陣形スキルの絵

陣形スキルの絵は2種類ある（[../gdd/formations.md](../gdd/formations.md) 発動の演出）。発動で挟む1枚絵のカットインと、カットインが明けたあと盤の駒に落ちる着弾エフェクト。冒険譚ではなくレシピに紐づくので、冒険譚の絵とは別系統に置く。どちらも同じフォルダ・同じ `{recipe_id}` 起点で、着弾側に `_impact` が付く。

#### カットイン

| 段階 | 置き場（`{recipe_id}`＝Formation.RECIPES のキー） | 例（トリニティノヴァ） |
|---|---|---|
| ① AI生成直後 | `godot/assets/formations-src/{recipe_id}/{recipe_id}_01_raw.png` | `formations-src/trinity_nova/trinity_nova_01_raw.png` |
| ② 透かし除去 | `godot/assets/formations-src/{recipe_id}/{recipe_id}_02_dew.png` | 同上フォルダ |
| ③ 手動調整マスター（任意） | `godot/assets/formations-src/{recipe_id}/{recipe_id}_03_master.png` | 同上フォルダ |
| SUBJECT | `godot/assets/formations-src/{recipe_id}/{recipe_id}_prompt.txt` | 同上フォルダ |
| ④ ゲーム用 | `godot/assets/formations/{recipe_id}.png` | `godot/assets/formations/trinity_nova.png` |

- 絵柄は cover と同じ ILLUST STYLE（§2）。描くのは「機構が動く瞬間」＝獲得用キービジュアル（§1）と同じ狙いで、盤では見せられない一撃の迫力を1枚で見せる。
- 規約解決。置けば出て、無ければカットインを飛ばす（コード不変）。`formations-src/` は `.gdignore` で Godot 非インポート。
- 獲得用キービジュアルとは**共用しない**。冒険譚2の獲得絵は `trinity_nova` のカットインと画題が近い（どちらもトリニティノヴァ）が、狙う瞬間が違う＝カットインは詠唱が結実する一瞬、獲得絵は戦いが終わった後の景色。1枚で兼ねると、毎回挟むカットインと、クリア時に1度だけ出る絵が同じになって、どちらの効き目も落ちる。
- 描く瞬間はレシピごとに変える。トリニティノヴァとディバインジャッジメントは光が上へ抜ける縦の構図、ホーリーアリアは横へ広がる構図＝攻撃と祝福で画の方向を分ける。術者は目を閉じて詠唱に没入させ、暴れるのは魔法の側に任せる（静と動の対比）。

#### 盤の着弾エフェクト

| 段階 | 置き場 | 例（トリニティノヴァ） |
|---|---|---|
| ① AI生成直後 | `godot/assets/formations-src/{recipe_id}/{recipe_id}_impact_01_raw.png` | `formations-src/trinity_nova/trinity_nova_impact_01_raw.png` |
| ② 透かし除去 | `godot/assets/formations-src/{recipe_id}/{recipe_id}_impact_02_dew.png` | 同上フォルダ |
| ③ 透過マスター | `godot/assets/formations-src/{recipe_id}/{recipe_id}_impact_03_master.png` | 同上フォルダ |
| SUBJECT | `godot/assets/formations-src/{recipe_id}/{recipe_id}_impact_prompt.txt` | 同上フォルダ |
| ④ ゲーム用 | `godot/assets/formations/{recipe_id}_impact.png` | `godot/assets/formations/trinity_nova_impact.png` |

- ④は [`godot/tools/gen_formation_impact.ps1`](../../godot/tools/gen_formation_impact.ps1)（`{recipe_id}` 複数可／`all`）で書き出す。③をトリムして長辺512に収めるだけ。
- 絵柄はカットインの ILLUST STYLE ではなく、攻撃エフェクトの EFFECT STYLE（[units.md](units.md) §3.4）に寄せる。盤で30〜70px に縮む小さな絵なので、人・背景を描かず、フラットな2〜3色・硬い輪郭で痕跡そのものだけを描く。
- 向きは下向き（上から落ちてくる形）で描く。盤でしか使わないので演出側は回転させない。攻撃エフェクトの「右へ向かう一撃」の約束は適用しない。
- 大小の倍率は無い。キャンバスいっぱいに描いて釣り合わせる。
- 規約解決。置けば出て、無ければ絵を出さず面の光だけになる（コード不変）。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（二層保管の原型・キャラ造形の DNA）
- [../gdd/stage_select.md](../gdd/stage_select.md) — ステージセレクト（大パネル／カードの二層・クロップ運用）
