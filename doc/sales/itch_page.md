# itch のプロジェクトページ

対象：`craftkobo.itch.io/senaris` に入力した内容。見せ方の方針は [marketing.md](marketing.md)、チャネルとしての位置づけと出す順序は [monetization.md](monetization.md)。

---

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

```
Hex-grid fantasy tactics with no RNG and no unit production: you win with the squad you are handed.
```

副題が `Deterministic` を使うため、ここは `no RNG` で言い換える（[marketing.md](marketing.md) の役割分担）。

## 本文

ソース編集（`<>`）に切り替えて貼る。

```html
<p>Senaris is a turn-based tactics game on a hex grid. There are no random rolls and no unit production. Both sides start with a fixed force, and the whole game is how you interlock the units you already have. The same attack resolves the same way every time &mdash; when you lose a unit, the board can tell you why.</p>

<h2>What to expect</h2>
<ul>
<li>Hand-crafted maps. Every stage is placed by hand, not generated.</li>
<li>Short stages, from about 10 minutes each, so you can stop at a clean break.</li>
<li>Single-player only.</li>
<li>No base building, no persistent army management, no strategic overworld.</li>
</ul>

<h2>About this demo</h2>
<p>This is a free demo that grows. The first build contains the opening campaign, &ldquo;The Goblin Raid&rdquo;, which teaches one idea per stage: movement, terrain, encirclement, support fire, indirect attack, capturing, and baiting an ambush. A new campaign chapter is added to the build as it is finished, and each update comes with a devlog explaining the design decision behind it.</p>

<p>Coming to Steam later.</p>

<p>More about the game: <a href="https://senaris.in">senaris.in</a></p>
```

一行目で差別化（乱数なし・生産なし）、`What to expect` で期待値の設定という分担にする。carryover はチュートリアル1が各話独立のため初回では書かない。継承の入るチュートリアル3を収録する回で足す。

## 更新のたびにやること

- ビルドを push する。
- 本文の `About this demo` に、増えた冒険譚を反映する。
- devlog を1本書く（[marketing.md](marketing.md)）。
