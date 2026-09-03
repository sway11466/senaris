# UIアイコンの方針

画面に出す小さな記号の生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルはUIアイコン固有：スロット・ICON STYLE・SUBJECT の書き方・保管と書き出し。

---

## 1. スロット

| 種別 | 置き場 | 出る場所 |
|---|---|---|
| 特性（敵AI） | `godot/assets/icons/ai/{特性id}.png` | 情報パネルの見出し（→ [../gdd/uiux.md](../gdd/uiux.md) ユニット情報パネル） |
| HUD のボタン | `godot/assets/icons/hud/{ボタンid}.png` | 下のボタン群（メニュー・情報板・ターン終了）の文字の左（→ [../gdd/uiux.md](../gdd/uiux.md) ターン終了・システムメニュー） |

- 絵は在れば出す。無ければ額ごと消えて特性名の文字だけになるので、絵を1枚ずつ足していける。
- 額（枠）はアプリ側が描く（`TavernTheme.icon_frame_stylebox`）。絵に枠を描き込ませない＝生成のたびに枠の形が揺らぐため、絵は中身だけを持つ。HUD のボタンは額なしで板に直に載せる。
- 表示寸法は特性が額の外寸44px・内側36px、HUD のボタンが高さ24px。書き出しは128pxで、拡大表示が要るようになってもそのまま使える。

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

SUBJECT を書くときの勘所（実地で効いたもの）:

- 画角いっぱいに描かせる。放っておくと黒地の中央に小さく置かれる。「左右の辺に触れる」「余白は数パーセント」と辺を基準に指定する。
- 36pxで残るのは輪郭だけ。内側の模様・彫り・刃こぼれは潰れるので、意味を持たせない。区別は外形のくびれと張り出しで作る。
- 敵に付ける印なので、優美な形に寄せない。禍々しさは朽ちや腐食ではなく形で出す（欠けは36pxでは輪郭のノイズにしかならない）。
- 語がモチーフを呼ぶ。`wings` は鳥の翼を呼ぶので、コウモリなら膜・リブ・鉤爪という部品で描写する。
- 禁止を並べるより、位置と向きを肯定文で言い切る。「鏡像にするな」は効かないが、「鼻面が左の辺を指し、耳は頭蓋の右側にある」と書けば反転は起きない。禁止したい語を書くほど、その像が絵に出る。
- 対称は SUBJECT に持たせる。共通STYLEに「左右対称」と書くと、同じ向きの複製を3つ並べる絵で下の2つが鏡像になる（群れで踏んだ）。STYLE 側は「SUBJECT の配置と向きにそのまま従う」までにする。
- 輪郭の型を5種で散らす。色は全部同じなので、横長・縦長・丸・反復のように外形の型を分けておくと、名前を読まなくても取り違えない。HUD も同じ（歯車＝丸・砂時計＝縦長・立て看板＝横長）。
- 背景は切り抜きのコントラストで選ぶ。明るい印なら黒。暗い輪郭を持たせるなら黒どうしで分離できないので白にする。

## 3. 保管・書き出し

| 段階 | 置き場（`{group}`＝種別フォルダ・`{id}`＝アイコンID） | 例 |
|---|---|---|
| ① SUBJECT | `godot/assets/icons-src/{group}/{id}/{id}_prompt.txt` | `icons-src/ai/charge/charge_prompt.txt` |
| ② AI生成直後（原寸） | `godot/assets/icons-src/{group}/{id}/{id}_01_raw.png`（`.jpg` も可） | `icons-src/ai/charge/charge_01_raw.jpg` |
| ③ ゲーム用（128px・透過） | `godot/assets/icons/{group}/{id}.png` | `icons/ai/charge.png` |

- ③だけがゲームの読む正。`{group}` はそのままゲーム側のフォルダになるので、種別が増えてもツールは変えない。
- ①②は作業ソース。`godot/assets/icons-src/.gdignore` で Godot のインポート対象外にする（原寸を取り込ませない）。
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
