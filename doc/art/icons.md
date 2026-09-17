# UIアイコンの方針

画面に出す小さな記号の生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルはUIアイコン固有：スロット・ICON STYLE・SUBJECT の書き方・幕間の印・依頼書の印（生成を使わず座標で作る）・保管と書き出し。

---

## 1. スロット

| 種別 | 置き場 | 出る場所 |
|---|---|---|
| 特性（敵AI） | `godot/assets/icons/ai/{特性id}.png` | 情報パネルの見出し（→ [../gdd/uiux.md](../gdd/uiux.md) ユニット情報パネル） |
| HUD のボタン | `godot/assets/icons/hud/{ボタンid}.png` | 下のボタン群（メニュー・情報板・ターン終了）の文字の左（→ [../gdd/uiux.md](../gdd/uiux.md) ターン終了・システムメニュー） |
| 依頼書の印 | `godot/assets/icons/quest/{印id}.png` | 依頼書の駒の絵の下（語の左）（→ [../gdd/stage_select.md](../gdd/stage_select.md) 依頼書） |
| 幕間の印 | `godot/assets/icons/interlude/{幕間id}.png` | ステージ一覧の札と札のあいだ（→ [../gdd/stage_select.md](../gdd/stage_select.md) 幕間の印） |

- 絵は在れば出す。無ければ額ごと消えて特性名の文字だけになるので、絵を1枚ずつ足していける（依頼書の印は語だけが残る）。
- 額（枠）はアプリ側が描く（`TavernTheme.icon_frame_stylebox`）。絵に枠を描き込ませない＝生成のたびに枠の形が揺らぐため、絵は中身だけを持つ。HUD のボタン・依頼書の印・幕間の印は額なしで載せる（板に、紙に、板に）。
- 表示寸法は特性が額の外寸44px・内側36px、HUD のボタンが高さ24px、依頼書の印が12px四方（語の左）、幕間の印が高さ24px（札と札のあいだの中央）。書き出しは128pxで、拡大表示が要るようになってもそのまま使える。

## 2. 生成方式（ICON STYLE）

生成方式は共通のアンカー方式（共通 STYLE ＋ アイコンごとの SUBJECT／[direction.md](direction.md) §3）。

ICON STYLE（共通・固定）:

```
STYLE: A single fantasy game UI icon: ONE isolated emblem on an empty
background, drawn as a branding-iron mark burned into a dark wooden signboard —
a bold flat shape in warm amber-gold, one light tone plus at most one slightly
darker tone of the same amber, with hard flat edges. Clean stylized vector-like
shapes, the same slightly muted look as the game's unit pieces. This mark labels
an ENEMY, so it reads as grim and menacing: heavy, blunt, a little crude. Follow
the arrangement the subject describes exactly, including which way each element
points and where each element sits. A crisp, bold silhouette that still reads
when shrunk to 36 pixels tall. The mark fills the square canvas edge to edge,
leaving only a thin margin. Square 1:1 composition. Keep the frame clean: the
emblem alone, no characters, no hands, no ground, no scenery, no text, no
border, and no photographic rendering, bloom, gradients, particles or metallic
sheen.
```

HUD のボタン用（HUD ICON STYLE）。プレイヤーの道具の記号なので、敵の印の一文（grim and menacing）を道具の一文に替え、読める寸法を24pxにする。それ以外は同じ:

```
STYLE: A single fantasy game UI icon: ONE isolated emblem on an empty
background, drawn as a branding-iron mark burned into a dark wooden signboard —
a bold flat shape in warm amber-gold, one light tone plus at most one slightly
darker tone of the same amber, with hard flat edges. Clean stylized vector-like
shapes, the same slightly muted look as the game's unit pieces. This mark labels
a TOOL the player uses, so it reads as plain, sturdy and calm: a familiar
everyday object, tidy and honest, neither menacing nor ornate. Follow the
arrangement the subject describes exactly, including which way each element
points and where each element sits. A crisp, bold silhouette that still reads
when shrunk to 24 pixels tall. The mark fills the square canvas edge to edge,
leaving only a thin margin. Square 1:1 composition. Keep the frame clean: the
emblem alone, no characters, no hands, no ground, no scenery, no text, no
border, and no photographic rendering, bloom, gradients, particles or metallic
sheen.
```

幕間の印用（INTERLUDE ICON STYLE）。戦いと戦いのあいだに起きたことを告げる道しるべなので、HUD 版の道具の一文を幕間の一文に替える。読める寸法は HUD と同じ24px。それ以外は同じ:

```
STYLE: A single fantasy game UI icon: ONE isolated emblem on an empty
background, drawn as a branding-iron mark burned into a dark wooden signboard —
a bold flat shape in warm amber-gold, one light tone plus at most one slightly
darker tone of the same amber, with hard flat edges. Clean stylized vector-like
shapes, the same slightly muted look as the game's unit pieces. This mark tells
what happened on the road BETWEEN two battles, so it reads as a plain, calm
signpost: a familiar everyday object, tidy and honest, neither menacing nor
ornate. Follow the arrangement the subject describes exactly, including which
way each element points and where each element sits. A crisp, bold silhouette
that still reads when shrunk to 24 pixels tall. The mark fills the square
canvas edge to edge, leaving only a thin margin. Square 1:1 composition. Keep
the frame clean: the emblem alone, no characters, no hands, no ground, no
scenery, no text, no border, and no photographic rendering, bloom, gradients,
particles or metallic sheen.
```

SUBJECT を書くときの勘所（実地で効いたもの）:

- 画角いっぱいに描かせる。放っておくと黒地の中央に小さく置かれる。「左右の辺に触れる」「余白は数パーセント」と辺を基準に指定する。
- 36pxで残るのは輪郭だけ。内側の模様・彫り・刃こぼれは潰れるので、意味を持たせない。区別は外形のくびれと張り出しで作る。
- 敵に付ける印なので、優美な形に寄せない。禍々しさは朽ちや腐食ではなく形で出す（欠けは36pxでは輪郭のノイズにしかならない）。
- 語がモチーフを呼ぶ。`wings` は鳥の翼を呼ぶので、コウモリなら膜・リブ・鉤爪という部品で描写する。
- 禁止を並べるより、位置と向きを肯定文で言い切る。「鏡像にするな」は効かないが、「鼻面が左の辺を指し、耳は頭蓋の右側にある」と書けば反転は起きない。禁止したい語を書くほど、その像が絵に出る。
- 対称は SUBJECT に持たせる。共通STYLEに「左右対称」と書くと、同じ向きの複製を3つ並べる絵で下の2つが鏡像になる（群れで踏んだ）。STYLE 側は「SUBJECT の配置と向きにそのまま従う」までにする。
- 輪郭の型を5種で散らす。色は全部同じなので、横長・縦長・丸・反復のように外形の型を分けておくと、名前を読まなくても取り違えない。HUD も同じ（歯車＝丸・砂時計＝縦長・立て看板＝横長）。
- 背景は切り抜きのコントラストで選ぶ。明るい印なら黒。暗い輪郭を持たせるなら黒どうしで分離できないので白にする。地は「まっ黒・木目なし」と言い切る＝「dark wooden signboard に焼き付ける」とだけ書くと木目の出る回がある（2026-09-08 に踏んだ。木目の明るい筋が抜きのしきい値6%を超えると半透明で残る）。

## 3. 幕間の印（生成で作る）

ステージ一覧で札と札のあいだに挟む印（[../gdd/stage_select.md](../gdd/stage_select.md) 幕間の印）。マニフェストの `interlude` の値がそのまま id。生成方式は §2 の INTERLUDE ICON STYLE＋各 SUBJECT で、保管と書き出しは §5 のとおり。

| id | 形 | 外形の型 | 意味 |
|---|---|---|---|
| `rest` | ベッド | 横長・低い（左端に頭板が立つ） | 休息。兵が満ちる |
| `revive` | 十字 | 四方の腕が同じ長さ・同じ太さ | 復帰。倒れた仲間も戻る |

- 連戦の印は無い（ベッドが無い＝休んでいない）。2つとも暗い木の板に載る。生成の背景はまっ黒（§2 の勘所）。
- 外形の型を2つで散らす（横長・対称の十字）＝色が同じでも取り違えない。
- 24px で残るのは輪郭だけ。毛布の襞・十字の飾りは描かせない。
- 依頼書の印（§4）の `refill`／`revive` とは役目が別。あちらは駒ごとの記号、こちらは話と話のあいだの絵。復帰だけは同じ十字にして、意味と形を一対一に揃える。

## 4. 依頼書の印（座標で作る）

依頼書の印（`quest`）は**生成AIを使わない**。十字・楔・紡錘といった幾何図形で絵としての情報を持たず、しかも12pxまで縮めて出す。生成 → 抜き → トリミング → 縮小の4段では、寸法も太さも塗ってある面積も最後まで決まらない（実際に、4つのうち1つだけ重く見えるのを絵の側で直せなかった）。ロゴと同じく座標で持つ（[logo.md](logo.md) 作り方）。

- 形の正本は `godot/assets/icons-src/quest/{id}/{id}.svg`。手で書き、手で直す（Inkscape で開いてもよい）。座標は 100×100 の正方形で書く。
- PNG は [`rasterize_svg.gd`](../../godot/tools/rasterize_svg.gd) で焼く。ロゴと同じ道具・同じ経路なので、この用途のための道具は持たない。

```
godot --headless --path godot --script res://tools/rasterize_svg.gd -- assets/icons-src/quest/new/new.svg assets/icons/quest/new.png 1.28
```

倍率 1.28＝SVG の 100 が 128px になる。

- 色は種類ごとに変え、羊皮紙（`#DEC99E`）とのコントラスト比で選ぶ。見出しのインク `#664D33` が 4.84、下限の目安は 3.0。明るい黄は紙と明度が近く `#C9A227` で 1.49＝ほぼ見えないので `#8C6A12` まで落とした（2026-09-09 実測）。
- 塗ってある面積を4つで揃える＝並べたとき1つだけ重く見えない。`magick <png> -alpha extract -format "%[fx:mean]" info:` で測る。
- 12pxまで縮むので、細い線と小さな模様は置かない。1px幅になる部品（ラッパの吹き口・旗）は形を粒に割るだけなので落とす。意味は隣の語が言うので、印は外形が分かればよい。
- 部品を足すのではなく輪郭で言う。ラッパは「一様な太さの管＋左右対称に開く杯」にするとラバーカップになる。吹き口から鐘まで連続して太くし、開きを内側へえぐると角笛になる。
- 外形の型を散らす＝横長の楔・十字・縦長の瓶・斜めの筋。色が違っても形で取り違えないようにする。

| id | 形 | 色 | 塗り | 意味（→ [../gdd/stage_select.md](../gdd/stage_select.md) 依頼書） |
|---|---|---|---|---|
| `new` | ラッパ | `#8C6A12` | 34% | 新加入 |
| `revive` | 十字 | `#4E7A3A` | 44% | 復帰 |
| `refill` | ポーション | `#3C5F8A` | 34% | 補充 |
| `damaged` | 裂け目 | `#9A3B2E` | 24% | 損耗 |

## 5. 保管・書き出し

| 段階 | 置き場（`{group}`＝種別フォルダ・`{id}`＝アイコンID） | 例 |
|---|---|---|
| ① SUBJECT | `godot/assets/icons-src/{group}/{id}/{id}_prompt.txt` | `icons-src/ai/charge/charge_prompt.txt` |
| ② AI生成直後（原寸） | `godot/assets/icons-src/{group}/{id}/{id}_01_raw.png`（`.jpg` も可） | `icons-src/ai/charge/charge_01_raw.jpg` |
| ③ ゲーム用（128px・透過） | `godot/assets/icons/{group}/{id}.png` | `icons/ai/charge.png` |

- ③だけがゲームの読む正。`{group}` はそのままゲーム側のフォルダになるので、種別が増えてもツールは変えない。
- ①②は作業ソース。`godot/assets/icons-src/.gdignore` で Godot のインポート対象外にする（原寸を取り込ませない）。
- ここは生成で作る印（`ai`・`hud`・`interlude`）の話。依頼書の印（`quest`）は①②を持たず、正本の SVG が `icons-src/quest/{id}/{id}.svg`、③は同じく `icons/quest/{id}.png`（§4）。
- 手で抜きたい絵は `{id}_03_master.png`（透過済み）を同じフォルダに置く。ツールは master があればそちらを優先するので、自動の抜きで足りない1枚だけ差し替えられる。ユニットと違って master は常備しない＝背景が単色フラットなので、ふつうは②から直接書き出せる。

書き出し:

```
powershell -File godot\tools\gen_icon.ps1 charge      # 複数可 / all で全アイコン
```

輝度からアルファを起こして背景を抜き（暗いほど透明・しきい値は6〜20%）、余白をトリムして128px四方に収める（[`../../tools/gen_icon.ps1`](../../godot/tools/gen_icon.ps1)）。色は動かさない。抜いたあとは木の色に載せて拡大し、輪郭に黒い縁（ハロー）が残っていないかを見る。

---

関連:

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（二層保管の原型・EFFECT STYLE）
- [menu.md](menu.md) — メニュー画面の材質（木の看板・羊皮紙）
- [../gdd/uiux.md](../gdd/uiux.md) — 情報パネル（アイコンの出る場所）
- [../gdd/ai.md](../gdd/ai.md) — 特性（アイコンにする対象）
- [`../../tools/gen_icon.ps1`](../../godot/tools/gen_icon.ps1) — 書き出しツール
