# itch のプロジェクトページ

対象：`craftkobo.itch.io/senaris` のページの方針と、入力した内容。素材の方針は [marketing.md](marketing.md)、チャネルとしての位置づけと出す順序は [monetization.md](monetization.md)、devlog は [itch_devlog.md](itch_devlog.md)。

---

## ページの方針

ページには必ず遊べる実体（ビルド）を置く。実質リンクだけのページは既定で de-index される。初回はチュートリアル1本の時点で出し、1本増えるごとにビルドを更新する（[monetization.md](monetization.md) の体験版の収録範囲）。

Steam への導線はプロジェクト編集画面の外部ストアリンク欄と説明文に置く。itch では見慣れた形で、規約上も置き場が用意されている。導線は itch から Steam への一方向にしか流れないため、目立つ位置に置く。

嫌われるのは素通りの踏み台にする形（遊べるものが無い、置いたきり更新されない）で、更新を続けるページはその逆に位置する。

カバー画像は 630×500 が推奨（最小 315×250、比率 315:250）。Steam の枠とアスペクト比が違うため、同じ絵から別に切り出す前提で構図に余白を残す。

itch のタグは推薦に効かず、ブラウズ導線も弱い。上限は10で、Genre はタグとは別に1つ選ぶ。itch で仕事をするのはタグではなくカバー画像と devlog。

## カバー画像

Hex Based タグの人気・売れ筋を見た結果（2026-08-23）。

- 盤や実画面をそのまま出しているカバーが多い（Struggle of the Poleis・Konkr.io・Kingdom Hex・Six-Sided Streets・Core Stratagem・Into Ruins）。Steam の同ジャンルの棚では盤面を出しているものが1本も無かったのと対照的。
- 情景やイラストに大きな題字を載せる形も並ぶ（Hex of Steel・Combat Actions: VIETNAM・Hive Time）。題字だけの黒地（Möbius Front '83）もある。
- 題字はほぼ全部に入っている。

itch のカバーは一覧でも大きく出るため細部が潰れず、実画面が成立する。ページ側は背景色・背景画像まで自分で組めるので、Steam のようにレイアウトが固定ではない（Möbius Front '83 はページ背景にゲームの地図を敷き、上に題字を大きく置いている）。

方針：カバーはまだ見つけてもらう前に出る位置なので、引きの仕事＝中サイズのキービジュアル（[marketing.md](marketing.md) のキービジュアル）を当てる。盤の実画面も候補に残す。題字は必ず入れる。

### 切り出しのレシピ

キービジュアルの standard（[marketing.md](marketing.md)）から切る。standard は 4:3 で作ってあるので、左右を削って 5:4 にしてから縮める。

```
uv run --no-project --with pillow python -c "from PIL import Image; im=Image.open('godot/assets/promo-src/keyvisual/keyvisual_standard_03_master.png'); W,H=im.size; w=int(H*630/500); x=(W-w)//2; im.crop((x,0,x+w,H)).resize((630,500), Image.LANCZOS).save('channels/itch/cover_630x500.png')"
```

- 1200×896 なら 1128×896 を切る＝左右36pxずつ落ちる。ロゴは中央、人物は端から離してあるので無傷。
- 元絵を差し替えたらこの手順でやり直す。

## ページの見た目（Theme）

`Edit game` 画面上部の `Edit theme` で組む。CSS は書けず、用意された枠だけを埋める形。枠は次の通り。

| 区分 | 枠 | 効き方 |
| --- | --- | --- |
| COLOR | BG | ページ全体の地色。背景画像が届かない外側もこの色になる |
| COLOR | BG 2 | 本文ブロックの地色 |
| COLOR | BG2 Alpha | 本文ブロックの不透明度。下げると背景画像が本文の裏に透ける |
| COLOR | Text / Link / Headers / Buttons | 文字・リンク・見出し・ボタンの色 |
| TEXT | Font / Size / Header font | 書体と本文の大きさ |
| LAYOUT | Screenshots | 紹介画像の並べ方 |
| IMAGES | Banner | ページ上部に出る帯。幅いっぱいに広がり、高さは画像の縦横比が決める。透過PNGも置けるが、透明部分にページ背景は出ず本文ブロックの地色になる。置くと、説明文の上に出ていたタイトル文字が消えてこの画像に変わる。`Align`（寄せ）を持つ |
| IMAGES | Background | ページ全体の背景。`Repeat`（敷き詰め）・`Align`・`Fixed`（スクロールで動かさない）を持つ |

方針：暗い側に振り、背景に酒場の外（タイトル画面の扉）を敷く。本文ブロックは扉の暗部と同じ色で塗り、扉はその左右に見せる。文字色はロゴと同じ系統から取る。

### 入れた値

| 枠 | 値 | 備考 |
| --- | --- | --- |
| BG | `#eeeeee` | 既定のまま。背景画像を敷き詰めているので、この色は画面に出ない |
| BG 2 | `#0d1925` | 起動スプラッシュの地色と同じ（扉の絵の暗部の実測 → [../art/menu.md](../art/menu.md)）。扉と地続きに見える |
| BG2 Alpha | 最大 | 下げない。本文ブロックは塗りつぶす |
| Text | `#E9E0EF` | |
| Link | `#fa5c5c` | 既定のまま。itch では赤リンクが見慣れた形なので変えない |
| Headers / Buttons | 空 | 指定なし＝既定 |
| Font / Size | Lato / Large | |
| Screenshots | Auto | |
| Banner | `channels/itch/theme/banner.png` | ロゴを中央に置いた透過PNG。タイトル文字の代わりになる。Align=`Center` |
| Background | `channels/itch/theme/background.png` | Repeat=`Both`・Align=`Right`・Fixed=on |

`Repeat` を縦横とも敷き詰めにしているのは、扉の絵（2560×1440）より広い画面で余りが出るのを避けるため。`Fixed` はスクロールしても背景を動かさない指定で、扉が画面に留まる。

### 背景画像のレシピ

タイトル画面の扉 `godot/assets/menu/door.png`（1280×720）を2倍にして使う。画面幅いっぱいに敷くには元の寸法では足りないため。

```
magick godot/assets/menu/door.png -filter Lanczos -resize 200% channels/itch/theme/background.png
```

- 出力は `channels/itch/theme/background.png`（2560×1440）。
- 2倍までは線が保たれる。3倍はぼやけるだけでディテールは増えない（Lanczos は画素を創作しない）。背景は本文の裏に敷くもので、むしろ柔らかいほうが文字が読みやすいため2倍で足りる。生成AIの出力（1024前後）では画面を覆えないので、この拡大か、継ぎ目のないテクスチャを `Repeat` で敷くかの二択になる。
- 元の扉の絵を描き直したら、この手順でやり直す。

### バナーのレシピ

ロゴを透明なキャンバスの中央に置く。バナーの透明部分にページ背景（扉）は出ず、本文ブロックの地色になるため、地の色は焼かない。ロゴは明るいインクの `logo_dark_2x.png`（暗い地用）を使う。

```
uv run --no-project --with pillow python -c "from PIL import Image; l=Image.open('godot/assets/promo-src/logo/logo_dark_2x.png').convert('RGBA'); l=l.crop(l.getbbox()); h=384; w=round(l.width*h/l.height); l=l.resize((w,h), Image.LANCZOS); c=Image.new('RGBA',(1920,480),(0,0,0,0)); c.alpha_composite(l,((1920-w)//2,(480-h)//2)); c.save('channels/itch/theme/banner.png')"
```

- 出力は `channels/itch/theme/banner.png`（1920×480）。表示幅は itch のページ幅 960px なので、その2倍で用意する＝表示上の帯は 960×240 になる。
- `h=384` はロゴの高さ。キャンバス高 480 の8割で、上下に余白が残る。帯を厚くするなら 480 と `h` を同じ割合で変える。
- ロゴの絵を描き直したら、この手順でやり直す。

## 記入内容

| 項目 | 値 |
| --- | --- |
| Title | `Senaris: Deterministic Fantasy Tactics` |
| Project URL | `https://craftkobo.itch.io/senaris` |
| Classification | Games |
| Kind of project | Downloadable |
| Release status | In development |
| Pricing | No payments |
| Genre | Strategy |
| Tags | Hex Based / Tactical / Turn-Based Strategy / Turn-Based Combat / Fantasy / Medieval / Singleplayer / Difficult / Wargame |
| AI generation disclosure | Yes（Graphics / Sounds / Text & Dialog / Code） |
| App store links | Steam のストアページができてから記入 |
| Custom noun | 空（`game` になる） |
| Community | Comments |
| Visibility | Draft |

タグは上限10に対して9で止める。迷う語を足すと並びが濁る。

AI の開示は「出荷されるファイルに生成物が残っているか」で判断する。手を入れても残るなら該当し、下書きにだけ使って最終物に残らないものは該当しない。過少申告は delisting の材料になり、過剰申告のコストは絞り込みタグが付くだけなので、迷ったら付ける。

## 短い説明文

正本は [marketing.md](marketing.md) の本文。そのまま貼る。

```
Hex-grid fantasy tactics with no RNG and no unit production.
Reinforcements are not built — they are taken, one fort at a time.
```

## 本文

正本は [marketing.md](marketing.md) の本文（Markdown）。itch はソース編集（`<>`）に切り替えて、下の HTML 版を貼る。正本を直したらこちらも直す。

```html
<p>Senaris is a turn-based tactics game on a hex grid. There are no random rolls &mdash; the same attack resolves the same way every time, and when you lose a unit, the board can tell you why.</p>

<p>You never build units. Both sides begin with a fixed force, and the only way either side gets more is by taking forts: every stronghold holds a garrison, and whoever holds it can send that garrison out. A neutral fort may be holding something better than anything you brought with you.</p>

<p>How you are given that force changes from campaign to campaign. Some hand you a fresh company each stage. Others give you a named party that carries its levels and its losses forward &mdash; and a companion worn down to nothing is out of the fighting, but not out of the story.</p>

<h2>What to expect</h2>
<ul>
<li>Hand-crafted maps. Every stage is placed by hand, not generated.</li>
<li>Short stages &mdash; the early ones run about 10 minutes; later ones are longer sieges.</li>
<li>Some campaigns issue a fresh force each stage; others carry a named party forward, with its levels and its losses. No roster screen and no equipment &mdash; companions join by being found on the map, not picked from a menu.</li>
<li>Single-player only.</li>
<li>No base building and no strategic overworld.</li>
</ul>

<h2>About this demo</h2>
<p>This is a free demo that grows. The first build contains the opening campaign, &ldquo;The Goblin Raid&rdquo;, which teaches one idea per stage: movement, terrain, encirclement, support fire, indirect attack, capturing, and baiting an ambush. It also includes one standalone challenge map, built from the same pieces and tuned to hurt. A new campaign chapter is added to the build as it is finished, and each update comes with a devlog explaining the design decision behind it.</p>

<p>Coming to Steam later.</p>

<p>More about the game: <a href="https://senaris.in">senaris.in</a></p>

<p>Join the community on <a href="https://discord.gg/qbzPUBdzYg">Discord</a>.</p>
```

## 更新のたびにやること

- 収録する冒険譚とビルドの版番号を上げ、ビルドを作る（[../tech/build.md](../tech/build.md)）。
- 起動して確かめてから push する。作ることと出すことは分ける。

  ```
  butler push build/windows-itch-demo craftkobo/senaris:windows-demo --userversion <版番号>
  ```

  channel（`windows-demo`）はアップロード枠の名前で、ビルドに埋める刻印とは別物。
- 本文の `About this demo` に、増えた冒険譚を反映する（正本＝[marketing.md](marketing.md)、貼るのは上の HTML 版）。
- devlog を1本書く（[itch_devlog.md](itch_devlog.md)）。
