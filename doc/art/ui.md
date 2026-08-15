# UIアイコンの方針

画面に出す小さな記号の生成設計。全アセット共通のトーン・制作メソッド（アンカー方式・二層保管・ドロップイン差し替え）は [direction.md](direction.md) が正本。本ファイルはUIアイコン固有：スロット・ICON STYLE・SUBJECT の書き方・保管と書き出し。

---

## 1. スロット

| 種別 | 置き場 | 出る場所 |
|---|---|---|
| 特性（敵AI） | `assets/ui/ai/{特性id}.png` | 情報パネルの見出し（→ [../gdd/uiux.md](../gdd/uiux.md) ユニット情報パネル） |

- 絵は在れば出す。無ければ額ごと消えて特性名の文字だけになるので、絵を1枚ずつ足していける。
- 額（枠）はアプリ側が描く（`TavernTheme.icon_frame_stylebox`）。絵に枠を描き込ませない＝生成のたびに枠の形が揺らぐため、絵は中身だけを持つ。
- 表示寸法は額の外寸44px・内側36px。書き出しは128pxで、拡大表示が要るようになってもそのまま使える。

## 2. 生成方式（ICON STYLE）

生成方式は共通のアンカー方式（共通 STYLE ＋ アイコンごとの SUBJECT／[direction.md](direction.md) §3）。

ICON STYLE（共通・固定）:

```
STYLE: A single fantasy game UI icon, drawn as ONE isolated emblem: NO
character, NO hands, NO ground, NO scenery, NO text, NO frame, NO border. It
looks like a branding-iron mark burned into a dark wooden signboard — a bold
flat shape in warm amber-gold, one light tone plus at most one slightly darker
tone of the same amber, with hard flat edges. Clean stylized vector-like shapes,
the same slightly muted look as the game's unit pieces. This mark labels an
ENEMY, so it must read as grim and menacing: heavy, blunt, a little crude, never
elegant, never heroic or angelic — no feathered wings, no halos, no laurels.
NOT photorealistic, NO glowing bloom, NO soft gradients, NO sparkle particles,
NO smoke, NO metallic sheen. Symmetrical about the axis given in the subject. A
crisp, bold silhouette that still reads when shrunk to 36 pixels tall. The mark
fills the square canvas edge to edge, leaving only a thin margin — never a small
mark floating in a large empty background. Square 1:1 composition.
```

SUBJECT を書くときの勘所（実地で効いたもの）:

- 画角いっぱいに描かせる。放っておくと黒地の中央に小さく置かれる。「左右の辺に触れる」「余白は数パーセント」と辺を基準に指定する。
- 36pxで残るのは輪郭だけ。内側の模様・彫り・刃こぼれは潰れるので、意味を持たせない。区別は外形のくびれと張り出しで作る。
- 敵に付ける印なので、優美な形に寄せない。禍々しさは朽ちや腐食ではなく形で出す（欠けは36pxでは輪郭のノイズにしかならない）。
- 語がモチーフを呼ぶ。`wings` は鳥の翼を呼ぶので、コウモリなら膜・リブ・鉤爪という部品で描写する。
- 背景は切り抜きのコントラストで選ぶ。明るい印なら黒。暗い輪郭を持たせるなら黒どうしで分離できないので白にする。

## 3. 保管・書き出し

| 段階 | 置き場（`{group}`＝種別フォルダ・`{id}`＝アイコンID） | 例 |
|---|---|---|
| ① SUBJECT | `assets/ui-src/{group}/{id}/{id}_prompt.txt` | `ui-src/ai/charge/charge_prompt.txt` |
| ② AI生成直後（原寸） | `assets/ui-src/{group}/{id}/{id}_01_raw.png`（`.jpg` も可） | `ui-src/ai/charge/charge_01_raw.jpg` |
| ③ ゲーム用（128px・透過） | `assets/ui/{group}/{id}.png` | `ui/ai/charge.png` |

- ③だけがゲームの読む正。`{group}` はそのままゲーム側のフォルダになるので、種別が増えてもツールは変えない。
- ①②は作業ソース。`assets/ui-src/.gdignore` で Godot のインポート対象外にする（原寸を取り込ませない）。
- 手で抜きたい絵は `{id}_03_master.png`（透過済み）を同じフォルダに置く。ツールは master があればそちらを優先するので、自動の抜きで足りない1枚だけ差し替えられる。ユニットと違って master は常備しない＝背景が単色フラットなので、ふつうは②から直接書き出せる。

書き出し:

```
powershell -File tools\gen_ui_icon.ps1 charge      # 複数可 / all で全アイコン
```

輝度からアルファを起こして背景を抜き（暗いほど透明・しきい値は6〜20%）、余白をトリムして128px四方に収める（[`../../tools/gen_ui_icon.ps1`](../../tools/gen_ui_icon.ps1)）。色は動かさない。抜いたあとは木の色に載せて拡大し、輪郭に黒い縁（ハロー）が残っていないかを見る。

---

関連:

- [direction.md](direction.md) — アートの全体方針（絵柄・共通メソッド）
- [units.md](units.md) — ユニットの見た目方針（二層保管の原型・EFFECT STYLE）
- [menu.md](menu.md) — メニュー画面の材質（木の看板・羊皮紙）
- [../gdd/uiux.md](../gdd/uiux.md) — 情報パネル（アイコンの出る場所）
- [../gdd/ai.md](../gdd/ai.md) — 特性（アイコンにする対象）
- [`../../tools/gen_ui_icon.ps1`](../../tools/gen_ui_icon.ps1) — 書き出しツール
