公開: https://craftkobo.itch.io/senaris/devlog/1656851/your-special-ability-is-not-always-the-best-move （2026-09-12）

区分: Game Design（投稿画面の Long-form discussion の項。「作るときの判断・過程・学び」を語る枠）。更新の告知が主題に見えると枠から外れるので、章が入ったことは末尾の1行だけにする。

# devlog #4 — 陣形スキルは強いだけじゃない（チュートリアル2追加の回）

## 設計

狙い：**「senaris の陣形スキルは、強いだけではなく代償がある」を1つ持ち帰らせる。**盲目的に撃つと盤面が不利に傾く＝撃つ場面を見極める技になっている、というところまで。値付けの理屈を体系立てて語る回ではない（それは [formations.md](../../../doc/gdd/formations.md) の設計原則にある）。

方針：Game Design の枠に載せる回。itch の投稿画面は「changelog・更新・告知なら Blogging を選べ」と書いているので、**更新の告知を主題にしない**＝チュートリアル2が入ったことは末尾に1行。**扱うのは陣形スキルだけに振り切る**。ユニットスキルと輸送は devlog #5 に回す（画像も撮ってある＝`img/devlog5-1.png`・`img/devlog5-2.png`）。

語り口：#1〜#3 と同じ。CraftKobo。主語は Senaris・the game に寄せる。

話の順序：

1. senaris には「陣形スキル」という必殺技がある。特定の駒が特定の形に立つと使える。解禁もマナもクールダウンも無い。形が立っている間だけ使え、1体離れれば消える。
2. トリニティノヴァ。魔法兵3人が三角形に並ぶと7ヘックスをまとめて焼く。
3. **ただし強いだけではない。**参加した3人はそのターンを使い切り、威力は発動者1体ぶんで合算されない。だから敵が1〜2体なら、3人が個別に撃つほうが強い。使えるから撃つと、最良の攻撃手3人を1人ぶんの働きに使って1ターン遅れる＝盤面が不利になる。ここでトリニティノヴァの絵。
4. グレイス。聖職5人が固まって祈ると自軍全体が攻防1.3倍、次の自軍ターンまで。人数が増えれば伸びる（6人1.35・7人1.4）。
5. その代償。**占領兵が固まって動けない**のが本体＝祈るには5人が互いに隣接して立ち止まる必要があり、移動2の駒を寄せる時点で前のターンから足を使う。祈っている間は誰も目的地へ歩いていない＝5人まとめて、必要な場所から数ターン離れた位置で止まる。ここでグレイスの絵。
6. 3つ目がもう1つある。何をするかは書かない＝**遊んで確かめてほしい**、と誘う。**代償には触れない**（3つ目は代償が軽く、代償の話を続けると嘘になる）。
7. これらが動くのが第2章「Undead Rush」＝アンデッドの群れとの戦い。騎士・聖職・魔法ギルドの混成隊が、湧き続ける屍を押し返す。ここで味方と敵の一覧2枚。
8. 締めに、体験版に入っている、と1行。

新要素の列挙は置かない。ユニットスキル・輸送・墓地の湧き・ネクロマンサーはこの回では出さない。

画像（4枚。番号＝貼り順）：

- `img/devlog4-1.png` … 3番（トリニティノヴァの代償）の直後。発動のカットイン＋スキルレポートの損害一覧（7ヘックスぶん・2体撃破）。撮影セットは `debug-photo/devlog4-2.json`（t2 st3 の盤）、`--formation trinity_nova --leader 5,4 --target 9,3 --frame 0,1,14,8` の連写から4枚目。
- `img/devlog4-2.png` … 5番（グレイスの代償）の直後。発動のカットイン＝5人が光の十字の下で祈る画＋スキルレポート。撮影セットは `debug-photo/devlog4-1.json`（t2 st5 の盤）、`--formation grace --leader 2,5 --target 2,5 --frame 0,2,14,9` の連写から4枚目。2枚ともカットインで揃える＝2つの技を同じ土俵で見せる。
- `img/devlog4-3.png` … 7番（章の紹介）の直後。この章で戦う味方の立ち絵の一覧。整列ツール（build_lineup.py）で組む。左から クレリック・プリースト・ビショップ・ウィッチ・ウィザード・ファイター・ナイトの7体＝占領兵が左、前衛が右。**パラディンは入れない**（3つ目の陣形スキルの構成員）。
- `img/devlog4-4.png` … 3枚目の直後。敵の立ち絵の一覧。左から スケルトン・ゾンビ・スケルトンアーチャー・グール・ゴースト・レイス・デュラハンの7体＝一番右がデュラハン。**ネクロマンサーは入れない**。

用語：画面の語に合わせる（hex / Formation Skill / Strength）。レシピ名は Trinity Nova・Grace。章の名前は Undead Rush。

注意：3つ目の陣形スキルは、名前・効果・構成員（パラディン）・登場するステージのどれも書かない。代償の重さにも触れない。敵の範囲攻撃は今のところ存在しないので、塊が狙われる話も書かない。数値は画面に出るものだけ（1.3倍・1.35・1.4・移動2）。パッチノートの調子にしない＝「入りました」の列挙をしない。

## タイトル

Your special ability is not always the best move

## 本文

```html
<p>Senaris has a special ability, and it is called a Formation Skill. Put specific units in a specific shape on the board and a skill becomes available to them. There is no research, no mana, no cooldown. The skill is live while the shape is live, and it is gone the moment one of those units steps away.</p>
<p>Three mages standing in a triangle, each one touching the other two, can fire <strong>Trinity Nova</strong>: a blast that covers seven hexes in a single action. On a board where the dead arrive in a crowd, that is exactly the picture you want.</p>
<p><strong>What it is not is free power.</strong> All three mages are spent for that turn &mdash; they did not attack, did not move up, did not do anything else. And the blast lands for exactly one caster's worth of attack, not three. Against a couple of scattered enemies, three separate shots do more damage than the skill does. Fire it because it happens to be available and it will quietly cost you the board: you spent your three best attackers to do the work of one, and you are a turn behind where you would have been. The skill is not a button that is always right. It is a thing you hold until the turn when one blast is worth more than three swings, and reading that turn is the game.</p>
<p><img src=""></p>
<p>The second skill, <strong>Grace</strong>, charges you in a different currency. Five clergy &mdash; Clerics, Priests and Bishops, in any mix &mdash; standing in one connected cluster can pray instead of fighting, and every unit in your army attacks and defends at 1.3&times; until your next turn. Walk more of them into the huddle and the blessing grows: 1.35&times; with six, 1.4&times; with seven.</p>
<p>And its bill is heavier than one turn of prayer. To pray, all five have to be touching each other and standing still &mdash; and clergy move 2. Gathering five of them into one cluster costs turns before the skill is ever cast, holding the cluster costs the turn it is cast on, and every one of those turns is a turn your capture units spent not walking toward anything you needed taken. Clergy are your healers and the only units that can take a position; Grace freezes all five of them in one huddle, several turns away from anywhere they were needed. You buy one multiplied turn and you pay for it with several of your slowest ones.</p>
<p><img src=""></p>
<p>There is a third Formation Skill in this chapter. I am not going to say what it does &mdash; it is waiting near the end, and I would rather you found it on the board than read about it here.</p>
<p>All three of them live in the second chapter, <strong>Undead Rush</strong>. Skeletons and zombies climb out of the graveyards outside a provincial city, and the city sends what a city has: knights to hold the line, clergy from the church, mages from the guild. The dead do not come in a number you can count, and the skills above are how a smaller company answers a bigger one &mdash; on the turns you choose them correctly.</p>
<p><img src=""></p>
<p><img src=""></p>
<p>Undead Rush is in the demo now.</p>
```
