公開:

# devlog #2 — 陣形スキル

## 設計

狙い：**「必殺技が、強さではなく選択として設計されている」を1つ持ち帰らせる。**読者が受け取るのは「3人が個別に撃つか、7ヘックスをまとめて焼くか」という二択と、その代金が「陣形を組むための位置合わせで行動が縛られること」だと分かること。#1 で「残るのは位置取り」と言い切ったので、位置が守りだけでなく攻めの前払いでもある、という続きになる。

方針：予告回。ビルドを伴わないため、次の更新で入ると明言する（[itch_devlog.md](../../../doc/sales/itch_devlog.md) の例外規定）。触れるのはトリニティノヴァ1本に絞る。グレイスとディバインジャッジメントは名前も出さず #3 に残す。

語り口：#1 と同じ。CraftKobo。主語は Senaris・the game に寄せる。

話の順序：

1. 次の章＝チュートリアル2を作っている。次の更新で入る。
2. 今度はアンデッド。墓地から屍が湧き続ける。倒しても止まらない。ゴブリンとは押し方が違い、物量で来る。
3. この章で魔法兵が加わる。長射程で貫通を持つ、一番強い攻撃手。1体でも主戦力。
4. その魔法兵3体で撃てるのが陣形スキル＝トリニティノヴァ。三角形に並べると7ヘックスをまとめて焼く。本作の看板機能。
5. バリケードで関門を作り、屍を詰まらせて、そこへ落とす。
6. 二択が生まれる。3人が個別に撃つか、まとめて1発にするか。一番強い攻撃手の手数で払う代金。威力は合算されず発動者1体ぶんなので、常に技が正解にはならない。
7. 代償の正体は、陣形を組むための位置合わせで行動に制約ができること。三角形は相互隣接で、ヘックスの輪の1つ飛ばしは距離2＝見た目より狭い。撃つターンに動けるのは発動者1体だけなので、残り2体は前のターンまでの移動を位置合わせに使って隣接させておく。敵の動きを1ターン先まで読んで、そこに形を置いておく。
8. 締め。次の更新でチュートリアル2が入る。他の要素は入ってから話す。

注意：7を博打として書かない。乱数が無いので1ターン先の位置決めは読みであり、外したときは運ではなく読み違い。#1 の「負けたら盤面を思い返せば理由が分かる」の実例として書く。英語の本文でも `bet` / `gamble` は使わず `read` の側で書く。

目安（「敵3体以上なら技」等）は書かなくてよい。理由が自明なので、読者が自分で引く。

画像（4枚）：

- `img/devlog2-cast.png` … 3番（魔法兵の紹介）の直後。ウィザードとウィッチの戦闘立ち絵の2体並び。整列ツール（build_lineup.py）で組む。原寸 781px。
- `img/devlog2-1.png` … 4番（トリニティノヴァ）の直後。発動時のカットイン＋スキルレポートの損害一覧。`debug-photo/devlog2-1` を `shot_screen --formation trinity_nova` で連写した03枚目。
- `img/devlog2-3.png` … 5番（盤の絵面）の直後。t2.st3 の実盤面コピー（`debug-photo/devlog2-2`）を `--frame 2,0,14,8` で撮る。バリケードで関門を塞ぎ、屍の群れが詰まり、ゴーストが脇から回り込む中盤。
- `img/devlog2-2.png` … 6番（二択）の直後。着弾範囲7ヘックスに魔法弾が落ちる盤面。カットインと同じ連写の08枚目。

用語：画面の語に合わせる（hex / Strength）。陣形スキルは Formation Skill、レシピ名は Trinity Nova。

## タイトル

Three shots or one blast

## 本文

```html
<p>The next chapter of Senaris is called "Undead Rush", and it will land in the next update.</p>
<p>This time the enemy is undead. Skeletons and zombies crawl out of graveyards and keep coming &mdash; clear a wave and another rises behind it. The goblins from the first chapter came in a group you could count. The dead come in a tide.</p>
<p>To meet that tide, the chapter introduces mage units: Wizards and Witches. They strike from four or five hexes away, and their damage penetrates armor. A single mage standing behind a line of knights is already the strongest attacker on the board.</p>
<p><img src=""></p>
<p>Now put three of them in a triangle &mdash; each one adjacent to the other two &mdash; and they can fire Trinity Nova. It hits the target hex and every hex around it: seven hexes, one action. This is a Formation Skill, the signature mechanic of Senaris. A special attack that unlocks only when specific units stand in a specific shape.</p>
<p><img src=""></p>
<p>The chapter&rsquo;s centerpiece stage hands you a chokepoint: barricades seal a gap in a fence line, the dead pile up against the wall, and Trinity Nova drops on the crowd. The shape of the board does half the work.</p>
<p><img src=""></p>
<p>But those three mages could have fired three separate shots &mdash; long-range, armor-piercing shots, each aimed wherever it needed to go. Trinity Nova&rsquo;s damage equals one caster, not all three combined. Against a couple of scattered targets, three individual shots do more. The skill is not always the right call, and that is the point: it is a choice, not an upgrade.</p>
<p><img src=""></p>
<p>The real price is the setup: lining up the formation binds your moves. A triangle on a hex grid means all three mages touching each other &mdash; tighter than it looks. Only the caster can move on the turn the skill fires; the other two must already be standing in place, their earlier moves spent getting there. You read where the enemy will clump next turn and set the shape there a turn early. Get it right and a wave disappears in one action. Get it wrong and two mages spent a turn walking into a formation that hit nothing &mdash; not bad luck, a misread you can trace on the board.</p>
<p>The next update adds the full Undead Rush chapter to the demo. There is more in it, but the rest is better played than previewed &mdash; that devlog comes with the build.</p>
```
