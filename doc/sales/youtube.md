# YouTube

対象：YouTube という面の運用と、そこで起きたことの記録。動画そのものの作り方（ティザーとトレーラーの狙いの違い）は [marketing.md](marketing.md) が正本で、ここでは扱わない。

チャネル全体での位置づけは [marketing.md](marketing.md) の「チャネルの方針」。

---

## 役割

仕事は2つある。自分の動画を置く場所であることと、他人の紹介動画に開発者として出ていく場所であること。面は同じだが仕事が違う。

### 動画の置き場

ティザー・トレーラーは自前でホストせず YouTube に載せる（[marketing.md](marketing.md)）。公式サイトの紹介動画も埋め込みで賄う（[site.md](site.md)）。変換・再生互換・転送量を持たなくて済む。

### 紹介動画への対応

体験版を公開している以上、こちらの許可なく紹介動画が作られる。登録者が数千人規模のチャンネルでも、体験版のダウンロードは動く。

開発者が現れると視聴者の関心が上がり、投稿者にとっても次の版を扱う理由になる。出ていく価値はある。

書き方。

- 開発者だと最初に名乗る。
- 先行作の固有名詞は出さない。公開コメントは宣伝文と同じ扱いにする（理由は [monetization.md](monetization.md) の IP・権利）。ジャンルと年代で言い換える。
- 期日を約束するのは、すでに手が動いているものだけ。着手していないものは時期を紐付けない。守れなかったときに失うものが、書いて得るものより大きい。
- 未公開の devlog へリンクしない。公開してから投稿する。
- コメントは折りたたまれる。1行目に名乗りと、一番具体的な情報を置く。
- 優劣を主張しない。まだ入っていないと述べるにとどめる。独自性を主張すると先例を挙げて反論される。

## 記録

紹介された事実と、こちらが投稿したコメントを時系列で積む。視聴者のコメントは、返答の書き方を決める材料に使ったものだけ残す。

各項の `投稿:` 行に URL が入っていれば投稿済み、空なら未投稿。判定基準はこれ一つに絞る（[itch_devlog.md](itch_devlog.md) の原稿と同じ流儀）。

### 2026-08-31 Richard Yorke「This NEW Fantasy Wargame Has NO DICE?! | Senaris Demo」

投稿: https://www.youtube.com/watch?v=lEoUeTVAuCs （2026-09-02・`@craftkobo-w3i`）

動画は https://www.youtube.com/watch?v=lEoUeTVAuCs 、14分04秒。チャンネルは Richard Yorke（`@RichardYorke1945`）で、登録者3,730人。RTS・ウォーゲーム・戦略ゲームの実況とレビューを1日1〜3本出している。

運より計画を重視する戦術ゲームとして紹介された。概要欄のリンク先はストアページではなく devlog #1。

返答の書き方を決めるのに使った視聴者コメント。

- `No dice is a big plus / But battles seem way too simplistic` … 返答の一文を battles の語で受けた。独自性を主張せず、まだ入っていないと述べるだけの形に寄せた。

投稿したコメント。

```
Dev here — thanks for playing! The movement is confusing right now;
a fix ships this weekend. The mechanics that give the battles their
depth are still in development. Devlog #2 covers what's next:
https://craftkobo.itch.io/senaris/devlog/1649777/three-shots-or-one-blast
```

---

## 参考資料

- [marketing.md](marketing.md) — チャネルの方針・ティザーとトレーラーの狙い
- [monetization.md](monetization.md) — IP・権利（先行作の固有名詞を出さない理由）
- [itch_devlog.md](itch_devlog.md) — devlog の方針と原稿の管理
- [site.md](site.md) — 公式サイト（動画の埋め込み）
