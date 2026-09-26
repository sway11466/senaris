公開:

区分: Game Design（投稿画面の Long-form discussion の項。#4・#5 と同じ枠）。更新の告知が主題に見えると枠から外れるので、章が入ったことは末尾の1行だけにする。

# devlog #7 — 継承（チュートリアル3追加の回）

## 設計

狙い：**「名前の無い駒でも、この冒険譚の中では育ち、失えば戻らない」を持ち帰らせる。**育てれば弱い駒でも前線に立てる、というところまで。

方針：Game Design の枠に載せる回。題材はゲームシステムとしての継承（[campaigns.md](../../../doc/gdd/campaigns.md) の戦力供給モデル）。仲間が増える側として中立拠点の勧誘を添える。0.2.1 からのその他の変更は載せない。#6 で予告したドラゴンは締めに絵で回収する。

語り口：#1〜#6 と同じ。CraftKobo。主語は Senaris・the game に寄せる。

話の順序：

1. Senaris の駒には名前が無い。多くの冒険譚では、ステージごとに新しい部隊が配られる。
2. 第3章 Dragon Hunt は違う。同じ一行が7ステージを通して進み、駒はレベルを持ち越す。レベルは戦えば +1、倒せばさらに +1、拠点を取れば +10。1つごとに攻防が少しずつ上がる。
3. **育てれば弱い駒でも前線に立てる。**章はベテラン5人と、同じ役どころで一段弱い新米5人で始まる（ヴァンガードとファイター、ハンターとアーチャー）。最初は新米を後ろに置くが、戦わせて倒させたファイターは、数ステージ後には最初のマップでヴァンガードが立っていた位置に立てる。誰にとどめを刺させるかが、そのターンではなく数マップ先の前線の話になる。
4. **兵数がゼロになった駒は次のマップに出ない。**勝ったステージでも失ったまま。会話には出るので物語からは消えない。生き残った駒は毎ステージ満員で始まる＝戻らないのは失った駒だけ。1体を捨てて早く勝つ手が、次のマップで効いてくる。
5. 仲間は増えることもある。ローグに捕らえられていたピクシーは、助けると加わる。中立の集落（ドワーフ・エルフ・バードマン）は先に占領した側に付く＝ローグより先に取れば章の終わりまで連れていける、先に取られると敵に回る。ここで1枚目。
6. 旅の終わり、火口で #6 のあれが待っている。ここで2枚目。
7. 締めに、体験版に入っている、と1行。

画像（2枚。番号＝貼り順）：

- `img/devlog7-1.png` … 5番の直後。この章で初めて出る仲間の立ち絵の一覧。整列ツール（build_lineup.py）で `--left pixie,dwarf,elf,birdman` で組み、横 1920px の透明なキャンバスの中央に置く。
- `img/devlog7-2.png` … 6番の直後。st7 の火口のマップ（左下に一行、右奥の岩の柱にドラゴン）。撮影セットは `debug-photo/devlog7-2.json`（st7 のコピー。名簿なしで一行が出るよう actor・supply を外し、会話を外した）、shot_screen で `--size 1920x1080`、盤全体。

用語：画面の語に合わせる（Level / Vanguard / Fighter / Hunter / Archer / Pixie / Dwarf / Elf / Birdman）。章の名前は Dragon Hunt。

注意：

- 3種族が敵に回る理由の中身は書かない。
- 飛行と対空、各ステージの攻略、ドラゴンの能力は書かない。
- 「死亡」と書かない。兵数ゼロは戦線離脱。
- 兵数が減ったまま持ち越す話は書かない（竜狩りは毎ステージ `refill` で満員に戻る）。

## タイトル

（案）Nameless, but not replaceable

## 本文

```html
<p>Units in Senaris have no names. A Fighter is a Fighter and an Archer is an Archer, and in most campaigns each stage hands you a fresh company: whatever you lost on the last map is simply issued again on the next one.</p>
<p>The third chapter, <strong>Dragon Hunt</strong>, works differently. The same party walks through all seven stages, and every unit keeps its level from one map to the next. Levels come from fighting: a unit gains one each time it trades blows, one more when it finishes its opponent, and ten when it takes a fort. Each level adds a little to attack and defense.</p>
<p><strong>That little adds up.</strong> The chapter opens with five veterans and five young adventurers who fill the same roles one step weaker &mdash; a Fighter beside the Vanguard, an Archer beside the Hunter. On the first map the youngsters belong behind the line. Feed a Fighter enough fights and finishing blows, and a few stages later it can hold the line the Vanguard held on that first map. Who gets the kill is no longer only a question about this turn; it is a question about who you want standing at the front three maps from now.</p>
<p><strong>And a unit that falls stays fallen.</strong> If a unit is wiped out, it does not appear on the next map, even though you won. It is out of the fighting, not out of the story &mdash; it still speaks in the conversations between battles &mdash; but its levels are gone from the board. Survivors start every stage back at full strength; the only thing that does not come back is a unit you lost. So a stage can be won in a way that costs you the next one. Throwing a unit away to end the map two turns sooner is a trade you will feel later.</p>
<p>The party can grow, too. A pixie caged by the rogues joins once freed. Out in the wilds sit neutral villages &mdash; dwarves at a mine, elves in the forest, birdmen on the cliffs &mdash; and their people side with whoever captures the village first. Get there before the rogues and they join your party and march with you to the end of the chapter. Let the rogues get there first and they fight against you instead.</p>
<p><img src=""></p>
<p>And at the end of the road, in the crater, the thing from the last devlog is waiting.</p>
<p><img src=""></p>
<p>Dragon Hunt is in the demo now.</p>
```
