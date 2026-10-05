公開: https://craftkobo.itch.io/senaris/devlog/1692625/one-cleric-and-a-map-full-of-locked-doors （2026-10-06）

区分: General Update or Announcement（投稿画面の「Updates, announcements, or changelogs」の項。#3・#6 と同じ枠）。ビルドの告知が主題に入るため。

# devlog #8 — 砦の先取り（Bounties に2枚目を足す回）

## 設計

狙い：**「兵は配られない。盤の上の砦を開けて集める」を持ち帰らせる。**Senaris は生産が無いゲームだが、この盤では軍が増える。増える元は最初から盤に置いてあり、乱数も無いので、どの砦から開けるかという順番の問題になる、というところまで。

方針：ビルド更新の回（[itch_devlog.md](../../../doc/sales/itch_devlog.md) のネタの型1）。主題は Bounties の2枚目「First to the Forts」（`goblin-horde-st2`）の紹介だけ。0.3.0 からのその他の変更は載せない。クロニクルの変更はビルドに入るが、改修中なのでこの回では触れない。

語り口：#1〜#7 と同じ。CraftKobo。主語は Senaris・the game に寄せる。

話の順序：

1. 冒頭。新しいビルド。Bounties（物語なしの腕試しの板）に2枚目の依頼書が貼られた。
2. 開始時の手勢はクレリック1人だけ。
3. 残りの仲間は盤じゅうの砦の中にいる。同じ砦にゴブリンも潜んでいる。ここで1枚目。
4. 規則は1つ。先に砦を取った側の兵だけが外へ出られる。1回の占領が「こちらが増える」と「向こうが増えない」を同時に起こす。
5. 取り返せば、閉じ込められていた兵はまた出られる。砦は取って終わりではない。ここで2枚目。
6. 砦を取れるのはクレリックだけで、足は遅い。敵も同じことをしてくる。だから「どこから開けるか」が兵の数を決める。
7. 締めに、体験版に入っている、と1行。

画像（2枚。番号＝貼り順）：

- `img/devlog8-1.png` … 3番の直後。開始時の盤全体（クレリック1人と、盤に散った砦）。砦の上の数字が中の控えの数＝赤がゴブリン、青が味方。撮影セットは `debug-photo/devlog8-1.json`（st2 のコピーから会話を外した）、shot_screen で `--size 1920x1080`、盤全体。
- `img/devlog8-2.png` … 5番の直後。砦を開け合った中盤の盤。南と中央の砦を味方（青い枠）、北の砦を敵（赤い枠）が持ち、右下に中立の砦が1つ残る。味方の砦の上に赤い数字（閉じ込めたゴブリン）、敵の砦の上に青い数字（閉じ込められた味方）が写る。撮影セットは `debug-photo/devlog8-2.json`（st2 のコピーで、砦の持ち主と控えを書き換え、出撃した駒を盤に置いた）、撮り方は1枚目と同じ。駒は砦のすぐ手前に置かない（砦の絵が隠れる）。

用語：画面の語に合わせる（Bounties / Cleric / Goblin / Goblin Lord / Fort / Capture / Deploy）。ステージの名前は First to the Forts。

注意：

- どの砦から開けるのが良いか（攻略の答え）は書かない。
- 砦の数・ターン制限などの数字は書かない（盤の調整で変わる）。
- 版番号は本文に書かない。

## タイトル

One Cleric and a map full of locked doors

## 本文

```html
<p>There is a new build of the demo, and it pins a second sheet to the <strong>Bounties</strong> board &mdash; the board for one-off stages with no story, only a hard problem and the pieces to solve it.</p>
<p>The new one is called <strong>First to the Forts</strong>. You start it with a single Cleric. That is the whole army.</p>
<p>The rest of your company is on the map, but not in the field. They are holed up inside the forts scattered across it &mdash; and in most of those forts, goblins are hiding too.</p>
<p><img src=""></p>
<p>The rule is one line long: <strong>whoever captures a fort, only their troops can deploy from it.</strong> Capture one and your people walk out; the goblins inside stay shut in. So a single capture does two things at once. It adds to your side, and it takes away from theirs. Let the goblins reach that fort first and it is the same trade, pointed the other way.</p>
<p><strong>And a fort does not stay settled.</strong> Take back a fort the enemy holds and your troops shut inside can deploy again. The same is true for the goblins. A fort behind your line is not finished business; it is a reserve the enemy would like to unlock.</p>
<p><img src=""></p>
<p>Senaris has no production. Nothing is built, nothing is bought, and there are no dice. Here the army still grows &mdash; but everything it can grow into was already sitting on the board on turn one. Only a Cleric can capture a fort, and a Cleric is slow. The Goblin Lord across the map is working through the same list with captors of its own. Which door you open first decides how many of you there are when the two lines finally meet.</p>
<p>First to the Forts is in the demo now.</p>
```
