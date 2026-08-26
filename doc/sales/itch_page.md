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

中サイズのキービジュアル `godot/assets/promo-src/keyvisual/keyvisual_m.png`（1376×768・ロゴ焼き込み済み）から切る。

- 左端から 968×768 を切り、630×500 へ縮める。968:768 が 630:500 と同じ比なので、縦は落とさず横だけを詰める。
- 出力は `channels/itch/cover_630x500.png`。中間ファイルを経由せず、切り出しと縮小を一度で通す。
- 右の 408px が落ちる。竜は横幅 639px のうち 382px が枠外になり、頭・首・前脚が残る。ロゴ（左端 x=65）と一行（x 125–730）は無傷。
- 右へずらせるのは 65px まで。それを超えるとロゴが切れる。ずらしても竜が余分に残るのは 65px で、半分は落ちる。

元絵を描き直したらこの手順でやり直す。

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
