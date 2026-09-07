公開: 

区分: Game Design（投稿画面の Long-form discussion の項。「作るときの判断・過程・学び」を語る枠）。更新の告知が主題に見えると枠から外れるので、章が入ったことは末尾の1行だけにする。

# devlog #4 — 必殺技は強いだけじゃない（チュートリアル2追加の回）

## 設計

狙い：**「senaris の必殺技は、強いだけではなく代償がある」を1つ持ち帰らせる。**盲目的に撃つと盤面が不利に傾く＝撃つ場面を見極める技になっている、というところまで。値付けの理屈を体系立てて語る回ではない（それは [formations.md](../../../doc/gdd/formations.md) の設計原則にある）。代償の中身を具体で見せて、あとはユニットスキルと輸送を紹介する。

方針：Game Design の枠に載せる回。itch の投稿画面は「changelog・更新・告知なら Blogging を選べ」と書いているので、**更新の告知を主題にしない**＝チュートリアル2が入ったことは最後の1行に落とす。前半＝陣形スキルの代償、後半＝ユニットスキルと輸送の紹介（#2・#3 と同じ調子）。

語り口：#1〜#3 と同じ。CraftKobo。主語は Senaris・the game に寄せる。

話の順序：

1. senaris には「陣形スキル」という必殺技がある。特定の駒が特定の形に立つと使える。解禁もマナもクールダウンも無い。形が立っている間だけ使え、1体離れれば消える。
2. **ただし強いだけではない。**参加した駒はそのターンを使い切る。さらに威力は発動者1体ぶんで、参加者ぶんを合算しない。だから敵が1〜2体なら、3人が個別に撃つほうが強い。
3. 盲目的に撃つと盤面が不利になる。撃った3人はそのターン殴っていないし、前に出てもいない。技のほうが弱い場面で撃てば、手数を1ターンぶん捨てただけになる。見極めて放つ技になっている。
4. グレイスで具体を見せる。聖職5人が固まって祈ると自軍全体が攻防1.3倍、次の自軍ターンまで。人数が増えれば伸びる（1体ごとに+0.05）。ここで画像。
5. その代償。**占領兵が固まって動けない**のが本体＝祈るには5人が互いに隣接して立つ必要があり、移動2の駒を寄せるだけで前のターンから足を使う。祈っている間は誰も目的地へ歩いていないし、面攻撃が探しているのはまさにその塊。1ターンの倍率を買うのに、その前後の数ターンを払う。
6. ここからは紹介。ユニットスキル＝同じ仕組みの最小形（発動者1体・形は要らない）。プリーストのピュリファイ、ゴーストのドレッドタッチ。敵も同じ仕組みを使う。ここで画像。
7. 輸送＝戦闘力ゼロの駒。馬車は移動6・定員4で、移動2の聖職を運ぶ。飛空艇は移動9で、地上を止める墓石の山の上を越える。ここで画像。
8. 3つ目の陣形スキルは在るとだけ書く。締めに、これらが動いているのが第2章 Undead Rush で、体験版に入っている、と1行。

両陣営の顔ぶれの一覧は2番の直前（1番の直後）に置く＝どの駒の話をしているかを先に見せる。新要素の列挙は置かない。

画像（5枚。番号＝貼り順）：

- `img/devlog4-1.png` … 1番（陣形スキルとは何か）の直後。この章で戦う味方の立ち絵の一覧。整列ツール（build_lineup.py）で組む。左から クレリック・プリースト・ビショップ・ウィッチ・ウィザード・ファイター・ナイトの7体＝占領兵が左、前衛が右。**パラディンは入れない**（3つ目の陣形スキルの構成員）。
- `img/devlog4-2.png` … 1枚目の直後。敵の立ち絵の一覧。左から スケルトン・ゾンビ・スケルトンアーチャー・グール・ゴースト・レイス・デュラハンの7体＝一番右がデュラハン。**ネクロマンサーは入れない**。
- `img/devlog4-3.png` … 4番（グレイス）の直後。発動のカットイン＝5人が光の十字の下で祈る画＋スキルレポート。撮影セットは `debug-photo/devlog4-1.json`（t2 st5 の盤）、`--formation grace --leader 2,5 --target 2,5 --frame 0,2,14,9` の連写から4枚目。
- `img/devlog4-4.png` … 6番（ユニットスキル）の直後。ドレッドタッチの演出とスキルレポート。撮影セットは `debug-photo/devlog4-2.json`（t2 st3 の盤）、`--enemy-turn --formation dread_touch --leader 4,4 --target 5,4 --frame 0,1,14,8` の連写から9枚目。
- `img/devlog4-5.png` … 7番（輸送）の直後。馬車と飛空艇を同じ盤に入れた1枚。手前に隊と2つの乗り物、奥に墓石の山の帯・礼拝堂・納骨堂とスケルトンの列＝飛空艇が越える相手が同じ画に入る。撮影セットは `debug-photo/devlog4-3.json`（t2 st7 の盤のコピー）、`--frame 0,9,12,18`、駒は選ばない。**パラディンは盤に置かない。**

用語：画面の語に合わせる（hex / Formation Skill / Unit Skill / Board / Unload / Strength）。レシピ名は Grace・Trinity Nova・Purify・Dread Touch。乗り物は Wagon・Airship。章の名前は Undead Rush。

注意：3つ目の陣形スキルは、名前・効果・構成員（パラディン）・登場するステージのどれも書かない。墓地から屍が湧くこと・墓地を占領すれば止まることは今回書かない（次の devlog に取っておく）。ネクロマンサーも出さない。数値は画面に出るものだけ（1.3倍・+0.05・移動2/6/9・3ターン）。パッチノートの調子にしない＝「入りました」の列挙をしない。

## タイトル

Your special ability is not always the best move

## 本文

```html
<p>Senaris has a special ability, and it is called a Formation Skill. Put specific units in a specific shape on the board and the skill becomes available to them: three mages standing in a triangle can fire Trinity Nova, a blast that covers seven hexes at once. There is no research, no mana, no cooldown. The skill is live while the shape is live, and it is gone the moment one of those three steps away.</p>
<p><img src=""></p>
<p><img src=""></p>
<p><strong>What it is not is free power.</strong> Every unit in the formation is spent for that turn &mdash; three mages fired, and those three mages did not attack, did not move up, did not do anything else. And the blast lands for exactly one caster's worth of attack, not three. Against a couple of scattered enemies, three separate shots do more damage than the skill does.</p>
<p>So firing it because it is available will quietly cost you the board. You spent your three best attackers to do the work of one, and you are a turn behind where you would have been. The skill is not a button that is always right; it is a thing you save for the turn when the enemy has bunched up and one blast is worth more than three swings. Reading that turn is the game.</p>
<p><strong>The new skill in this chapter is Grace</strong>, and it charges for itself in a different currency. Five clergy &mdash; Clerics, Priests and Bishops, in any mix &mdash; standing in one connected cluster can pray instead of fighting, and every unit in your army attacks and defends at 1.3&times; until your next turn. Walk more of them into the huddle and the blessing grows: 1.35&times; with six, 1.4&times; with seven.</p>
<p><img src=""></p>
<p>And the bill is heavier than one turn of prayer. To pray, all five have to be touching each other and standing still &mdash; and clergy move 2. Gathering five of them into one cluster costs turns before the skill is ever cast, holding the cluster costs the turn it is cast on, and every one of those turns is a turn your capture units spent not walking toward anything you needed taken. Clergy are your healers and the only units that can take a position; Grace freezes all five of them in a huddle, which happens to be the exact shape an enemy area attack is looking for. You buy one multiplied turn and you pay for it with several of your slowest ones.</p>
<p><strong>Unit Skills</strong> are the same idea at its smallest size: one caster, no shape to arrange, and the same price of that unit's turn. Priests carry Purify, which strips every debuff off themselves or an adjacent ally. The enemy uses the same machinery &mdash; a Ghost's Dread Touch takes 10 points of Attack and Defense per remaining ghost off whatever it touches, and holds it there for three turns. This is the chapter where the board starts carrying state you can read: buffs and debuffs sit on units with their numbers and their remaining turns shown.</p>
<p><img src=""></p>
<p><strong>And some units cannot fight at all.</strong> The Wagon has no attack value. What it has is a move of 6 and room for four passengers, in a chapter where the clergy holding your line together move 2. Board them, drive, unload, and a prayer that would have taken four turns to walk into place happens now. The Airship does the same work in the air: move 9, straight over the piled gravestones that stop anything on foot, so its passengers step off somewhere nobody could have walked to. They are the first units in Senaris that are worth nothing in a fight and decide it anyway.</p>
<p><img src=""></p>
<p>There is a third Formation Skill in this chapter. I am not going to say what it does; it is waiting near the end, and it asks for its own price.</p>
<p>All of this is live: the second chapter, Undead Rush, is in the demo now.</p>
```
