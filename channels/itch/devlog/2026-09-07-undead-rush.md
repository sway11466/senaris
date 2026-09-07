公開: 

区分: General Update or Announcement（投稿画面の「Updates, announcements, or changelogs」の項。更新・告知向け）

# devlog #4 — チュートリアル2追加

## 設計

狙い：**「スキルは並び方が入力になっている」を1つ持ち帰らせる。**#2 で語ったトリニティノヴァ（3人の三角形）に、グレイス（聖職5人が固まる）とユニットスキル（1体で撃つ最小形）を並べ、同じ仕組みが人数と形だけを変えて置かれていると見せる。強さの階段を上るのではなく、盤の上に形を作ると技が使えるようになる、という一点。

方針：リリース回（[itch_devlog.md](../../../doc/sales/itch_devlog.md) のネタの型1）。#2 で「次の更新で Undead Rush が入る」、#3 で「次の内容更新は Undead Rush」と2回言い切っているので、まずそれが入ったと告げる。柱は3本＝陣形スキル（グレイス）／ユニットスキル／乗り物（輸送）。**3つ目の陣形スキル（ディバインジャッジメント）は名前も効果も構成員も出さない**＝在ることだけ書いて、遊んで見つける余地に残す。

語り口：#1〜#3 と同じ。CraftKobo。主語は Senaris・the game に寄せる。

話の順序：

1. Undead Rush が入った。7ステージ。#2・#3 で予告した章。
2. 敵の押し方が前章と違う。ゴブリンは数えられる数で来たが、屍は湧き続ける。だから新しい3つ＝陣形スキル・ユニットスキル・運ぶユニットが要る、と柱を予告する。そのまま両陣営の顔見せへ繋ぎ、一覧の画像2枚を出す（本文で1体ずつ説明はしない＝絵で見せる）。
3. 陣形スキルとは何か（1文で再定義）。解禁するものではなく、正しい駒が正しい形に立っている間だけ使え、1体でも離れれば消える。#2 のトリニティノヴァは1行のおさらいに留める（絵は再掲しない）。
4. グレイス：聖職（クレリック／プリースト／ビショップ）5体が1つの隣接クラスタに固まると、自軍全体が攻防 1.3 倍。5体を超えると1体ごとに伸びる（6体 1.35／7体 1.4）。持続は次の自軍ターンまで。画像はここ。
5. 代金：聖職は回復役で、占領できる唯一の兵種。5人が祈っている間はどれもしていない。加えて5人が固まる＝同じ面攻撃に5人まとめて入る形で、移動2では抜けられない。強くなるのは軍ではなく「1ターンの軍」で、そのターンを選ぶのがプレイヤー。
6. 3つ目がもう1つある。何をするかは書かない。
7. ユニットスキル：同じ仕組みの最小形＝発動者1体・形は要らない。プリーストのピュリファイ（弱体を落とす）、ゴーストのドレッドタッチ（隣接1体の攻防を残兵数×10 削る・3ターン）。この章で初めて盤に状態（強化・弱体）が乗る。画像はここ。
8. 乗り物：馬車は攻撃を持たない。移動6・定員4で、移動2の聖職を前線へ運ぶ。乗車と降車のコマンド。飛空艇は移動9で、地上を止める地形の上を越えて降ろす。画像は1枚＝馬車と飛空艇を同じ盤に入れて撮る。
9. 締め：次の更新は The Dragon Hunt。中身はまだ書かない。

新要素の列挙（箇条書き）は置かない。柱の3本に絞る。飛行の敵・弱者狙いのAI・バリケード・柵は、柱の本文で触れる範囲だけに留める。

画像（5枚）：

- `img/devlog4-1.png` … 2番（章の紹介）の直後。この章で戦う味方の立ち絵の一覧。整列ツール（build_lineup.py）で組む。並びは左から ウィッチ・ウィザード・ビショップ・プリースト・クレリック・ファイター・ナイトの7体＝術者が後ろ、前衛が前（立ち絵は右向き＝右が前）。ファイターとクレリックは前章から続投だが、この章の隊の顔ぶれなので入れる。**パラディンは入れない**（3つ目の陣形スキルの構成員）。
- `img/devlog4-2.png` … 1枚目の直後。敵の立ち絵の一覧。左から スケルトン・ゾンビ・スケルトンアーチャー・グール・ゴースト・レイス・デュラハンの7体＝一番右がデュラハン（立ち絵は左向き＝左が前で、重い駒が後ろに構える）。**ネクロマンサーは入れない**（この回では出さない）。

  一覧を味方と敵の2枚に割るのは、1枚に並べると1体あたりの表示幅が落ちるため（devlog #1 の一覧は9体で102px／7体なら 131px）。向きは立ち絵に焼き込み済みで、敵だけを `--left` に渡しても左を向いたまま並ぶ。

  馬車・飛空艇・バリケードは一覧に入れない。乗り物の立ち絵は人の約2倍幅（戦闘演出と同じ ×1.4 が焼き込まれる駒）で、同じ行に混ぜると人が小さくなり馬車と飛空艇も重なる。乗り物は5枚目の盤の絵で、運んでいる姿として見せる。

- `img/devlog4-3.png` … 4番（グレイス）の直後。発動して盤全体に金の光が差した瞬間＋スキルレポート。撮影セットは `debug-photo/devlog4-1.json`（t2 st5 の実盤面を写す）を新規に作り、聖職5体を隣接クラスタに置いて `shot_screen --formation grace --leader <c,r> --target <c,r> --frame ...` で連写、光が最も乗った1枚を選ぶ。
- `img/devlog4-4.png` … 7番（ユニットスキル）の直後。ドレッドタッチの発動とスキルレポート、削られた駒に弱体の印が乗っている画。撮影セットは `debug-photo/devlog4-2.json`（t2 st3 の実盤面）を新規に作り、ゴーストを味方の隣に置いて同じ手順で撮る（unit skill もレシピIDで指定できる想定。撮るときに確認する）。
- `img/devlog4-5.png` … 8番（乗り物）の直後。**馬車と飛空艇を同じ盤に入れた1枚。**聖職を乗せた馬車が街道を進み、その先で飛空艇が墓石の山と柵の列の上を越えている画。撮影セットは `debug-photo/devlog4-3.json` を新規に作る。**st7 の盤は使わない。**盤に置くのは馬車・飛空艇と運ばれる聖職だけで、パラディンは置かない（3つ目の陣形スキルの構成員が写るため）。盤の地の絵は t2 st2 の街道と、墓石の山・柵のある区画を組み合わせて作る。

用語：画面の語に合わせる（hex / Formation Skill / Unit Skill / Board / Unload / Strength）。レシピ名は Grace・Trinity Nova・Purify・Dread Touch。乗り物は Wagon・Airship。章の名前は Undead Rush。

注意：3つ目の陣形スキルは、名前・効果・構成員（パラディン）・登場するステージのどれも書かない。飛空艇は在ることと何ができるかだけ書き、いつどこで手に入るかは書かない。**墓地から屍が湧くこと・墓地を占領すれば止まることは、今回は書かない**（次の devlog に取っておく＝絵も含めてそこで見せる）。ネクロマンサーもこの回では出さない。グレイスの倍率は書くが、トリニティノヴァの威力の話は #2 で済んでいるので繰り返さない。

## タイトル

Three mages, five clergy, one wagon

## 本文

```html
<p>The second chapter, <strong>Undead Rush</strong>, is in the demo. Seven stages, on the same board in the tavern as the first one.</p>
<p>The goblins of the first chapter came in a number you could count. The dead do not: clear a wave and the next one is already walking, and the pressure never quite lifts. Three new things exist to answer that: Formation Skills, Unit Skills, and units whose job is to carry other units.</p>
<p>Both sides bring a new cast for it. A city sends what a city has &mdash; knights, clergy, and mages of the guild &mdash; and the ground sends back everything that was buried in it.</p>
<p><img src=""></p>
<p><img src=""></p>
<p><strong>A Formation Skill is not something you unlock.</strong> There is no research, no cost, no cooldown. It is simply available while the right units are standing in the right shape, and it is gone the moment one of them steps away. Last time I showed Trinity Nova: three mages in a triangle, seven hexes in a single action. Here is another one.</p>
<p><strong>Grace.</strong> Five clergy &mdash; Clerics, Priests and Bishops, in any mix &mdash; standing in one connected cluster can pray instead of fighting, and every unit in your army attacks and defends at 1.3&times; until your next turn. Gather more than five and the blessing grows: six make it 1.35&times;, seven 1.4&times;.</p>
<p><img src=""></p>
<p>The price is what turns it into a decision. Clergy are your healers, and they are the only units that can capture. Five of them praying are five of them not healing anyone, not taking anything, not standing anywhere they were needed. And five clergy pressed into one cluster is five clergy inside the same area attack, with a move of 2 to get back out. Grace does not make your army stronger; it makes one turn of your army stronger, and choosing which turn is the whole game.</p>
<p>There is a third Formation Skill in this chapter. I am not going to say what it does. It is waiting near the end.</p>
<p><strong>Unit Skills</strong> are the same machine at its smallest size: one caster, no formation to arrange, the skill sitting in the same menu. Priests carry Purify, which strips every debuff off themselves or an adjacent ally. Ghosts &mdash; on the other side of the board &mdash; carry Dread Touch, which takes 10 points of Attack and Defense per remaining ghost off the unit it touches, and holds it there for three turns. This is the chapter where the board starts carrying state: buffs and debuffs sit on units where you can see them, with numbers you can read, and Purify becomes the answer to a Ghost that already got through.</p>
<p><img src=""></p>
<p><strong>And some units carry others.</strong> The Wagon has no attack at all. What it has is a move of 6 and room for four passengers, in a chapter where the clergy who hold your line together move 2. Board them, drive, unload, and a prayer that would have taken four turns to walk into place happens now. The Airship does the same work in the air: it moves 9, and it goes straight over the fences and the piled stone that stop anything on foot, so its passengers step off in a place nobody could have walked to this turn. Transports are the first units in Senaris that are worth nothing in a fight and decide it anyway.</p>
<p><img src=""></p>
<p>That is Undead Rush. The next update brings the third chapter, The Dragon Hunt &mdash; more about that before it lands.</p>
```
