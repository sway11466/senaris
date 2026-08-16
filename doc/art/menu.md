# メニュー画面のアート方針

メニュー画面の絵の生成設計。中心はセレクト画面（酒場の依頼ボード）の材質テクスチャ（木壁・ボード板・羊皮紙・汚し）で、加えてタイトル画面の扉（1枚絵・動画／§5）と起動スプラッシュ（§6）。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルはメニュー画面固有：狙い・スロット・敷き方（タイル/ナインパッチ）・MATERIAL STYLE・保管。他のメニュー画面が増えたらここに足す。画面の設計そのものは [../gdd/stage_select.md](../gdd/stage_select.md)。

凡例: 【暫定】 【指針】 【未決】（ラベルなし＝決定事項。ただし決定は覆りうる）

---

## 1. 狙い（材質だけ画像・構造と光はコード）

セレクト画面は「材質＝画像／構造・光・装飾＝コード」のハイブリッドで作る。木目・汚れ・角のスレは画像が得意で、プロシージャル（ノイズ）では天井がある。一方で枠線・ランタン光・ビネット・焼き印スタンプはコードで動的に載せる（[../gdd/stage_select.md](../gdd/stage_select.md)）。

- 画面まるごと1枚の背景にはしない。ボード寸法やポスター枚数は動くので、材質だけをタイル/ナインパッチで焼き、構図はコードが組む＝解像度非依存で融通が効く。
- 反復対策は地形タイル（[terrain.md](terrain.md)）と同じ思想：タイル材は大きな高コントラストの特徴を避け、低コントラストに保って継ぎ目を目立たせない。
- 材質ルール: 羊皮紙＝手渡される紙（ダイアログ・依頼書）／木＝常設の面（ボード・パネル・ボタン）。戦闘画面のUI（右情報エリアの看板＝wall 流用・木ボタン）もこのスロットから引く＝メニューと戦闘で見た目が同族になる。

## 2. スロット（autowire）

`assets/menu/{name}.png` を規約で自動解決する（[tavern_theme.gd](../../presentation/select/tavern_theme.gd) の `_tex`）。置けば材質に、無ければコードのプロシージャル／ベタ塗りへフォールバック＝ドロップイン（コード不変）。ユニットの skin 画像 autowire と同じ思想。

| name | 用途 | 敷き方 | 縁（ナインパッチ） | 未配置時のフォールバック |
|---|---|---|---|---|
| `wall` | 酒場の壁（両画面共通の背景） | タイル（シームレス・上下左右つながる） | — | プロシージャルな縦板（`_Planks`） |
| `board` | 依頼ボード板（貼り紙を貼る面） | ナインパッチ（縁固定・辺は引き伸ばし） | 四辺約80px（実測 L82/T76/R83/B79） | ベタ塗り木色＋枠＋影 |
| `list_board` | ステージ一覧の背板（行を並べる面。→ [../gdd/stage_select.md](../gdd/stage_select.md)） | ナインパッチ（縁固定・辺は引き伸ばし）。実寸 384×688 | 四辺56px | ベタ塗り木色＋枠 |
| `parchment` | 貼り紙（冒険譚ポスターの地・複数枚可） | ナインパッチ（縁固定・縦はタイル／横は引き伸ばし）。実寸 300×440＝縦は `POSTER_SIZE` と同寸で1:1。横は `POSTER_SIZE.x` のほうが広いので引き伸ばす（タイルだと繰り返しの継ぎ目が出る） | 8px（傷んだ縁を残す） | クリーム地＋薄縁＋落ち影 |
| `grunge` | 汚し/スレ（壁の上に薄く重ねる） | タイル・半透明PNG | — | なし（重ねない） |
| `parchment_sheet` | 依頼書（出撃確認ダイアログの紙） | ナインパッチ（縁固定・中央タイル）。実寸 560×400＝`QuestSheet.SHEET_SIZE` と同寸（中央タイルが1:1） | 8px | クリーム地＋薄縁＋落ち影 |
| `plank` | 木の板ボタン（会話パネル・HUD） | ナインパッチ（縁固定・辺も中央も引き伸ばし）。実寸 256×96 | L6/T5/R6/B5（ベベル実測） | ベタ塗り木色＋枠 |

- ナインパッチ縁幅（board=四辺約80px / parchment・parchment_sheet=8 / plank=L6/T5/R6/B5）は tavern_theme.gd の実装値と一致させる（画像の彫り枠・ベベルの内側境界を実測した px。四辺個別。絵を差し替えたら測り直す）。変えるならコード側も合わせる。
- `list_board` は四隅に鉄具が描いてあるので、ナインパッチの固定幅を鉄具より大きく取る（実測で鉄具は一辺52pxまで＝56px で切る）。枠そのものは約26pxで、残りは内側の板が固定部に入る。ゲーム用は元絵（768×1376）の50%に縮めて焼く＝Godot はナインパッチの縁を元画像のピクセル数どおりに描くため、原寸のままだと枠が太くなりすぎる。
- ナインパッチ材の枠は「まっすぐ・一定・節なし」に描くこと（辺は引き伸ばされる＝節やコブがあると伸びて崩れる。飾りは四隅だけ）。board は辺を STRETCH（タイルでなく引き伸ばし）で敷く。
- `grunge` はコードで modulate α0.5 まで薄める（PNG 自体も透過前提）。壁の上・UI の下に敷く。
- `parchment` は複数枚可＝`parchment.png` に加え `parchment_2.png`/`parchment_3.png`… を置くと、カードごとに冒険譚idの hash で1枚を決定的に選ぶ（同じカードは常に同じ紙・隣とは違う紙・hover でも変わらない）。ポスターは固定サイズ（`POSTER_SIZE`）なので傷んだ縁の一様性は不問。実装は `tavern_theme.gd` の `_parchment_texs`/`parchment_stylebox(seed, bright)`。
- `parchment` の変種は生成3枚（master a/b/c）×4向き（縦長化の回転方向×左右反転）＝12枚を書き出しで焼く。実行時に反転する手段がない（`StyleBoxTexture` は flip 非対応）ため、地形タイルと違い向き違いはファイルとして持つ。

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

SUBJECT は材質ごとに差し替える。SUBJECT の正本は各 `assets/menu-src/{name}/{name}_prompt.txt`（ユニットと同じ「共通STYLE＝doc／per-asset SUBJECT＝prompt.txt」）。生成時は上の STYLE ブロック＋対象 prompt.txt の SUBJECT を続けて貼る。低コントラスト・四辺シームレスといった実地で効いた指示は各 prompt.txt に反映済み（ここには複製しない＝ドリフト防止）。

透かし（生成サービスが付ける sparkle マーク）はプロンプトで禁止しない。"watermark" の語は生成エラーを誘発し、否定形で書いても消えない（サービスが必ず付与する）＝共通ルールの `_02_dew`（透かし除去ツール）で消し、必要なら手動 master で整える（[direction.md](direction.md) §3）。

## 4. 保管・命名（二層）

ユニット（[units.md](units.md) §3.1）と同じ「source＝作業／直下＝ゲームが読む正」の二層。

| 段階 | 置き場 | 例 |
|---|---|---|
| ① AI生成（原寸・作業） | `assets/menu-src/{name}/` に任意名で複数 | `menu-src/wall/wall_a.png` |
| SUBJECT | `assets/menu-src/{name}/{name}_prompt.txt` | `menu-src/wall/wall_prompt.txt` |
| ② ゲーム用（正・autowire） | `assets/menu/{name}.png` | `wall.png` / `board.png` / `parchment.png` / `grunge.png` |

- ②を置けば `tavern_theme.gd` が規約で拾う。`source/` は `.gdignore` で Godot 非インポート。
- タイル材（`wall` / `grunge`）は Godot のインポート設定で Repeat を Enabled にする（継ぎ目タイルに必須）。上下左右がつながるシームレス画像で作る。
- ナインパッチ材（`board` / `parchment`）は縁が固定・中央がタイル。縁に枠/傷みを描き、中央は伸ばしても歪まない一様な地にする。

## 5. タイトル画面の扉（1枚絵・動画）

起動時に酒場の扉が開いて店内へ入る動画を流し（スキップ可）、入り終わりの店内静止画の上にタイトルメニューを出す（画面の設計は [../gdd/title.md](../gdd/title.md)）。セレクト画面の依頼ボードは「入って振り向いた先」にあたる＝扉からは見えない向きの壁なので、店内の映像とボードの画は矛盾しない。

材質スロット（§2〜§4）とは別系統。真正面フラットの MATERIAL STYLE ではなく1枚絵なので、絵柄は ILLUST STYLE（[keyvisual.md](keyvisual.md) §2）に従う。ただし画面背景なので末尾の `Wide 4:3 composition.` は落として 16:9 にする。SUBJECT の正本は `{name}_prompt.txt`（静止画）と `{name}_open_prompt.txt`（動画の MOTION）。

| 段階 | 置き場 | 例 |
|---|---|---|
| SUBJECT（静止画） | `assets/menu-src/door/door_prompt.txt` | |
| ① AI生成 | `assets/menu-src/door/door_01_raw.png` | |
| ② 透かし除去 | `assets/menu-src/door/door_02_dew.png` | |
| MOTION（動画） | `assets/menu-src/door/door_open_prompt.txt` | |
| ① AI生成 | `assets/menu-src/door/door_open_{letter}_01_raw.mp4` | `door_open_b_01_raw.mp4` |
| ② 透かし切り落とし | `assets/menu-src/door/door_open_{letter}_02_crop.mp4` | `door_open_b_02_crop.mp4` |
| ③ ゲーム用（動画） | `assets/menu/door_open.ogv` | |
| ③ ゲーム用（静止画・扉） | `assets/menu/door.png` | ②の1コマ目を抜いたもの |
| ③ ゲーム用（静止画・店内） | `assets/menu/room.png` | ②の最終コマを抜いたもの |

- 動画は同じ MOTION でも生成のたびに結果が大きく振れる（人物の描き分け・位置の飛び）ので、複数 take を撮って選ぶ前提。take ごとに変種letter（`_a`/`_b`…）を付け、採用した1本だけを ③ に焼く。`door_open_prompt.txt` は採用 take を生成した文面に合わせる。
- ③ は材質ではないので `tavern_theme.gd` の autowire は拾わない。`assets/menu/` に置くのは他のメニュー資産と並べるため。読むのは [../../presentation/title/title_screen.gd](../../presentation/title/title_screen.gd)。
- タイトル画面の静止画は、元の1枚絵ではなく動画のコマを抜いて作る（扉＝②の1コマ目・店内＝②の最終コマ）。元絵から切り出しを再現しようとすると、生成側が行った縮小と一致せず（実測 PSNR 26.1 dB＝目に見えて違う）、動画と静止画が切り替わる瞬間に画がジャンプする。店内は動画の終わりでそのまま止まって見える必要があるので、必ず最終コマから焼く。
- 動画の透かしは除去ツールが使えない。ツールは半透明オーバーレイを逆算する仕組みで、非可逆圧縮された動画では画素値が戻らないため。右下ごと切り落とす。
- 透かしの大きさと位置は生成のたびに変わる（実測: ある take は 24px 角・右下から48px、別の take は 48px 角・右下から96px）。毎回コマを抜いて測ってから切り出し範囲を決める。16:9 を保つには、透かしの左端より内側で幅を決め、その幅から高さを割り出して左上を原点に切り、元の解像度へ戻す。
- 変換は Ogg Theora（Godot が標準で再生できる唯一の動画コーデック）。`-c:v libtheora -q:v 8 -c:a libvorbis -q:a 5`。変換後は必ずコマ数を数えて全コマ読めることを確かめる。ffmpeg 8.1.2（gyan build）は Theora 書き出しが壊れており、読めるコマが数枚まで落ちて後半が完全に崩壊した。9.0 で解消。
- 音声は動画に含める（扉の軋み・焚き火）。絵と合っているものを分解しない。店内の賑わいは別トラックで足す（[../audio/sfx.md](../audio/sfx.md)）。

## 6. 起動スプラッシュ

エンジンが最初のシーンより前に出す静止画。ロゴ（暗背景版）の右下に開発元名 `craftkobo` を小さく添えた1枚で、絵は足さない。ロゴの方針は [promo.md](promo.md) §1 が正本。

開発元名は控えめに。中央そろえで下に置くと副題に見えるので、右端を SENARIS の右端（字送り幅ではなく字の見た目の端）にそろえ、幅はロゴの 1/6、色も一段沈める。

地の色は画像に焼かず `project.godot` の `boot_splash/bg_color` が持つ＝画像は透過。値は `#0d1925` で、[keyvisual.md](keyvisual.md) 系の扉の絵（`assets/menu/door.png`）の暗部を測った色（夜空 `#0d1929`／陰った石壁 `#0d1925`／石畳の影 `#0f1822`、いずれも輝度23前後）。画面が扉に切り替わったときに明るさが跳ねない。

画像は原寸中央（`boot_splash/stretch_mode=0`＝Disabled）。解像度が変わってもロゴが歪まない代わり、ウィンドウに対する見かけの大きさは変わる。横幅 760px は 1280×720 のウィンドウで約6割。

| 段階 | 置き場 | 例 |
|---|---|---|
| ① 作業元（SVG） | `assets/menu-src/splash/splash.svg` | `build_logo.py` の出力 |
| ② ゲーム用 | `assets/menu/splash.png` | 760×433・透過 |

- 生成AIを使わないので、他のメニュー資産と違って段階名（`_01_raw` ほか）と `_prompt.txt` は無い。
- ②は材質ではないので `tavern_theme.gd` の autowire は拾わない（スロット名で引くため）。読むのはエンジン本体。
- 作り直す手順は、`build_logo.py` を走らせて①を出し、`rasterize_svg.gd`（[../tech/tools.md](../tech/tools.md)）で②へ変換する。寸法・開発元名の字間・地の色との関係は `build_logo.py` の `SPLASH_PX_W` / `DEV_*` が持つ。
- エンジン起動前の静止画なのでフェードや動きは付けられない。動かしたくなったらタイトルシーン側の演出として作る。
- 地の色と合わせた見え方は `assets/menu-src/splash/preview_1280x720.png` で見る（②を地の色の上に原寸中央で置いた合成）。②だけ見ても透過部分が分からないため。

## 7. 未決事項

- [ ] 汚し（grunge）を壁だけでなく画面全体（ボード・貼り紙の上）にも薄く重ねるか。当面は壁のみ。

材質サイズは配置済み実物で確定: wall 1024×1024（タイル）／board 1408×768／parchment 260×380（§2）。

---

## 参考資料

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [keyvisual.md](keyvisual.md) — 扉絵・キービジュアル（ILLUST STYLE の正本。タイトル画面の扉もこれに従う）
- [terrain.md](terrain.md) — 地形タイル（反復対策・タイル材の作法の原型）
- [../gdd/stage_select.md](../gdd/stage_select.md) — セレクト画面の設計（酒場の依頼ボード）
- [../../presentation/select/tavern_theme.gd](../../presentation/select/tavern_theme.gd) — 材質スロットの autowire＋フォールバック実装
