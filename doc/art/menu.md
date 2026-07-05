# メニュー画面のアート方針

メニュー画面（当面はセレクト画面＝酒場の依頼ボード）の材質テクスチャ（木壁・ボード板・羊皮紙・汚し）の生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルはメニュー画面固有：狙い・スロット・敷き方（タイル/ナインパッチ）・MATERIAL STYLE・保管。タイトル画面など他のメニュー画面が増えたらここに足す。画面の設計そのものは [../gdd/stage_select.md](../gdd/stage_select.md)。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 狙い（材質だけ画像・構造と光はコード）

セレクト画面は「材質＝画像／構造・光・装飾＝コード」のハイブリッドで作る。木目・汚れ・角のスレは画像が得意で、プロシージャル（ノイズ）では天井がある。一方で枠線・ランタン光・ビネット・封蝋ピン・焼き印スタンプはコードで動的に載せる（[../gdd/stage_select.md](../gdd/stage_select.md)）。

- 画面まるごと1枚の背景にはしない。ボード寸法やポスター枚数は動くので、材質だけをタイル/ナインパッチで焼き、構図はコードが組む＝解像度非依存で融通が効く。
- 反復対策は地形タイル（[terrain.md](terrain.md)）と同じ思想：タイル材は大きな高コントラストの特徴を避け、低コントラストに保って継ぎ目を目立たせない。

## 2. スロット（autowire）

`assets/menu/{name}.png` を規約で自動解決する（[tavern_theme.gd](../../presentation/select/tavern_theme.gd) の `_tex`）。置けば材質に、無ければコードのプロシージャル／ベタ塗りへフォールバック＝ドロップイン（コード不変）。ユニットの skin 画像 autowire と同じ思想。

| name | 用途 | 敷き方 | 縁（ナインパッチ） | 未配置時のフォールバック |
|---|---|---|---|---|
| `wall` | 酒場の壁（両画面共通の背景） | タイル（シームレス・上下左右つながる） | — | プロシージャルな縦板（`_Planks`） |
| `board` | 依頼ボード板（貼り紙を貼る面） | ナインパッチ（縁固定・中央タイル） | 16px（彫り枠を縁に描く） | ベタ塗り木色＋枠＋影 |
| `parchment` | 貼り紙（冒険譚ポスターの地） | ナインパッチ（縁固定・中央タイル） | 8px（傷んだ縁を残す） | クリーム地＋薄縁＋落ち影 |
| `grunge` | 汚し/スレ（壁の上に薄く重ねる） | タイル・半透明PNG | — | なし（重ねない） |

- ナインパッチ縁幅（board=16 / parchment=8）は tavern_theme.gd の実装値と一致させる。変えるならコード側も合わせる。
- `grunge` はコードで modulate α0.5 まで薄める（PNG 自体も透過前提）。壁の上・UI の下に敷く。

## 3. 生成方式（MATERIAL STYLE）

生成方式は共通のアンカー方式（[direction.md](direction.md) §3）。人物・地形とは別に、真正面フラット・継ぎ目の出ない材質に振る。文字・ロゴは入れない（見出しは UI 側で描く）。色味は direction.md の渋いパレット、木は暖色。

MATERIAL STYLE（共通・固定・叩き台）:
```
STYLE: A flat material texture for a fantasy game's UI, in the same clean
stylized cel-shaded look as the game art: mature, slightly muted, limited
palette (NOT bright saturated, NOT painterly photorealism). Viewed straight-on
as a flat lay, NO perspective, NO lighting gradient baked in (lighting is added
by the UI). Fills the ENTIRE frame edge to edge, NO text, NO logo, NO single
big focal object. Keep large-scale contrast LOW so it tiles without an obvious
repeat.
```

SUBJECT は材質ごとに差し替える。SUBJECT の正本は各 `assets/menu/source/{name}/{name}_prompt.txt`（ユニットと同じ「共通STYLE＝doc／per-asset SUBJECT＝prompt.txt」）。生成時は上の STYLE ブロック＋対象 prompt.txt の SUBJECT を続けて貼る。透かし除去・低コントラスト・四辺シームレスといった実地で効いた指示は各 prompt.txt に反映済み（ここには複製しない＝ドリフト防止）。

## 4. 保管・命名（二層）

ユニット（[units.md](units.md) §3.1）と同じ「source＝作業／直下＝ゲームが読む正」の二層。

| 段階 | 置き場 | 例 |
|---|---|---|
| ① AI生成（原寸・作業） | `assets/menu/source/{name}/` に任意名で複数 | `source/wall/wall_a.png` |
| SUBJECT | `assets/menu/source/{name}/{name}_prompt.txt` | `source/wall/wall_prompt.txt` |
| ② ゲーム用（正・autowire） | `assets/menu/{name}.png` | `wall.png` / `board.png` / `parchment.png` / `grunge.png` |

- ②を置けば `tavern_theme.gd` が規約で拾う。`source/` は `.gdignore` で Godot 非インポート。
- タイル材（`wall` / `grunge`）は Godot のインポート設定で Repeat を Enabled にする（継ぎ目タイルに必須）。上下左右がつながるシームレス画像で作る。
- ナインパッチ材（`board` / `parchment`）は縁が固定・中央がタイル。縁に枠/傷みを描き、中央は伸ばしても歪まない一様な地にする。

## 5. 未決事項

- [ ] 汚し（grunge）を壁だけでなく画面全体（ボード・貼り紙の上）にも薄く重ねるか。当面は壁のみ。
- [ ] 材質サイズ（タイル 512px 目安／ナインパッチの実寸）は生成サンプルを見て確定。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [terrain.md](terrain.md) — 地形タイル（反復対策・タイル材の作法の原型）
- [../gdd/stage_select.md](../gdd/stage_select.md) — セレクト画面の設計（酒場の依頼ボード）
- [../../presentation/select/tavern_theme.gd](../../presentation/select/tavern_theme.gd) — 材質スロットの autowire＋フォールバック実装
