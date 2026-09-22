# シナリオ作成バックログ

冒険譚の中身を作る未完了の作業（クロニクルの本文・ステージ実装）を追跡する。盤やシステムそのものの作業は [backlog.md](backlog.md) に置く。

## index

次回採番: scenario=11.

項目を追加するときは採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog_scenario.md | grep -oE 'scenario-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。各エントリは 背景／ゴール／対応／該当 で記す。ゴールは、その作業で何が達成されていれば終わりなのかを1文で書く。手段ではなく到達点を書く。

考慮外は、外したい軸があるときだけ足す。「この作業では○○は考えない」と書く。書いていなければ制限は無い。

## クロニクル

遊んだ冒険譚の記録として読ませる本文。採番は本書冒頭「index」。

### scenario-1

**チュートリアル１のクロニクルの中身**
- ゴール：チュートリアル１を遊んだ人が、設定集を読み切れて、物語を通して読める。
- 背景：設定集は5節ぶんを書いてあるが、[chronicle.md](gdd/chronicle.md) 設定集の構成（前半＝舞台・依頼の経緯・一行の顔ぶれ・相手は何者か、後半＝読み物）に照らすと後半が薄い。正本は [tutorial1-goblin-raid.md](campaign/tutorial1-goblin-raid.md) と [world.md](campaign/world.md) で、メモに無い裏設定は載せない。
- 対応：`godot/data/i18n/chronicle.csv` に節を書き足し、`godot/data/chronicle/tutorial1-goblin-raid.json` の `lore` に節と解放条件を並べる。`story` の並び（ステージ順とイベント）も実際の台本と突き合わせる。
- 該当：`godot/data/i18n/chronicle.csv`・`godot/data/chronicle/tutorial1-goblin-raid.json`。前提＝feature-126。

### scenario-2

**チュートリアル２のクロニクルの中身**
- ゴール：チュートリアル２を遊んだ人が、設定集を読み切れて、物語を通して読める。
- 背景：`godot/data/chronicle/` にファイルが無く、設定集も `story` の並びもまだ無い。正本は [tutorial2-undead-rush.md](campaign/tutorial2-undead-rush.md) と [world.md](campaign/world.md)。
- 対応：scenario-1 と同じ形で `godot/data/chronicle/tutorial2-undead-rush.json` を作り、`chronicle.csv` に本文を足す。
- 該当：`godot/data/i18n/chronicle.csv`・`godot/data/chronicle/tutorial2-undead-rush.json`。前提＝feature-126。

### scenario-3

**クロニクルの分岐の切り替え**
- ゴール：両方の展開を経験している箇所で、通し読みの途中にどちらを読むか切り替えられる。
- 背景：台本には在籍による行の出し入れ（`joined:<actor>`）と、どちらか一方しか起きないイベントがある（[chronicle.md](gdd/chronicle.md) 分岐の切り替え）。既定は最後に遊んだ回で、切り替えは両方を経験している箇所だけに出す＝読み始める前に顔ぶれを選ばせない。
- 対応：通し読みが分岐に差しかかったとき、パネル脇に切り替えを出す。切り替えは仲間ごとに独立。
- 該当：`godot/presentation/chronicle/`・[chronicle.md](gdd/chronicle.md) 分岐の切り替え。前提＝feature-126。

## ステージ実装

台本の決まった冒険譚を、実際に遊べるステージにする。採番は本書冒頭「index」。

### scenario-4

**邪神三部作 第1部 st1「路地の人さらい」のステージ実装（twingods1-1）**
- ゴール：第1部の st1 が通しで遊べる（会話→路地の盤で娘を守り切る→会話）。娘が倒れたら敗北になり、一行7人がクリア時に名簿へ載る。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st1 が設計・台本まで決まった。護衛対象の敗北条件（`lose_unit`）と弱者狙い（`predator`）は実装済みだが、娘を置く型と人さらいの絵、冒険譚の器（フォルダ・マニフェスト・ボード）が無い。
- 対応：(1) 新 type `civilian`（攻0／防10／移3／射程0／占領不可／兵数1）を `unit_type.csv` に足し、ally スキン「娘」を `unit_skin.csv` に足す。(2) 敵スキン「人さらい」（type `novice`）を足す。新 type `lancer`（40／0／貫通0／防40／移5／歩行／射程1-2／占領不可＝[twingods.md](campaign/twingods.md) ランサー）と ally スキン「ランサー」を足す。娘・人さらい・ランサーの絵は仮でよい。(3) 冒険譚フォルダ `godot/data/stages/twingods1-cult-stirrings/` と `campaign.json`（board は新設 `twingods`＝[stage_select.md](gdd/stage_select.md) シリーズボードの表とコードの定数に行を足す）。(4) ステージ JSON `cult-stirrings-st1.json`＝路地の盤（壁で区切った幅2の路地・北の広場・南西の酒場）、一行7人（`actor`＋`supply: "join"`）、娘（`unit_id: girl`）、人さらい4体を2部隊（`predator`）、勝利＝殲滅、敗北＝`lose_unit`（girl）、`turn_limit` 15。距離の目安は設計ドキュメントのとおり（初手の敵ターンでは届かず、2ターン目で届く）。(5) 翻訳 CSV＝`campaigns.csv`（冒険譚名・説明・st1 の題）と `dialogue.csv`（戦闘前・戦闘後の台本・話者名）。(6) 効果音 `scream`（悲鳴）の素材調達と発火点（[sfx.md](audio/sfx.md)）。(7) 地形スキン＝路地の絵にする2つ（町家の壁＝`wall` 型・酒場＝`building` 型）を `terrain_skin.csv` に足す。露店（`prop` 型）と北門（`road` 型の見た目違い）は任意。地形タイプは既存（壁・道・街区・石畳）で足りる。
- 考慮外：st2 以降の盤・台本。
- 該当：`godot/data/units/unit_type.csv`・`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`godot/presentation/select/campaign_select.gd`（ボード定数）・`doc/gdd/stage_select.md`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。

### scenario-5

**邪神三部作 第1部 st2「倉庫の奇襲」のステージ実装（twingods1-2）**
- ゴール：第1部の st2 が st1 から続けて遊べる（名簿から一行7人が出て、衛士4人が加わり、倉庫の敵13体を殲滅して会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st2 が設計・台本まで決まった。待ち伏せ（`ambush`）・突撃（`charge`）・敵側バリケードは既存で、無いのは敵スキンと倉庫の地形スキン。冒険譚の器（フォルダ・マニフェスト・ボード）は scenario-4 が作る。
- 対応：(1) 敵スキン「人さらいの投石」（type `slinger`）・「人さらいの頭」（type `vanguard`）・「積み荷」（type `barricade`・崩せる荷）を `unit_skin.csv` に足す。絵は仮でよい。(2) ステージ JSON `cult-stirrings-st2.json`＝西の入口から東の奥へ幅3の通路、両脇に積み荷の塊（`rock` 型）と北南で対になる窪み。一行7人は `actor` のみ（名簿から）、衛士4人（ノービス2・アーチャー2）は `actor` 無しの配給。敵は窪みの対ごとに待ち伏せ部隊（人さらい2＋投石1・索敵2）×3、奥に突撃2、頭1（索敵小・最後の order）、崩せる積み荷を北列と南列に各1〜2か所。勝利＝殲滅、敗北＝全滅、`turn_limit` 20。(3) `campaign.json` に st2 を足す（解放条件＝st1 クリア）。(4) 翻訳 CSV＝`campaigns.csv`（st2 の題）と `dialogue.csv`（戦闘前・戦闘後の台本・話者「衛士」「人さらいの頭」）。(5) 地形スキン＝倉庫の床（`plain` か `road` の見た目違い）と倉庫の壁（`wall` 型）。積み荷の塊は `rock` 型の見た目違いで1つ。
- 考慮外：st3 以降。人さらいの頭の撤退（`withdraw`）は使わない（殲滅で決着する盤）。
- 該当：`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝scenario-4。

### scenario-6

**邪神三部作 第1部 st3「集会の館」のステージ実装（twingods1-3）**
- ゴール：第1部の st3 が st2 から続けて遊べる（一行7人で大広間へ踏み込み、神官が裏口へ走って消え、説教壇の占領か殲滅で決着して会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st3 が設計・台本まで決まった。群れ（`swarm`）・睨み合い（`standoff`）・逃走（`flee`）・敵hq占領・戦闘中の会話イベントは既存。無いのは「逃げ切り拠点」の仕組みと、敵スキン・館の地形スキン。
- 対応：(1) **逃げ切り拠点**＝`bases[]` に任意の印（仮 `exit: true`）を足す。その拠点に敵の駒が入ると盤から消え、控え（garrison）にも残らない。占領できない（味方は入れない）。殲滅の判定（盤上＋復帰手段）に影響しない。仕様は [map.md](gdd/map.md) 拠点の値に1項目足し、`Base`・`BattleState` の入る処理と `StageLoader` で受ける。デバッグステージを `debug-victory/` か `debug-ai/` に1枚。(2) 敵スキン「見習い教徒」（type `cleric`）・「術者」（type `mage`）・「神官」（type `witch`）を `unit_skin.csv` に足す。絵は仮でよい。神官は st5・st7 でも使う。(3) ステージ JSON `cult-stirrings-st3.json`＝南の正門と西の扉から入る大広間、南寄りに柱の列（進入不可）、北に説教壇（敵hq・`rest: enemy`）、その背後に裏口（逃げ切り拠点）。一行7人は `actor` のみ。敵は見習い教徒10（`swarm`）・術者3（`standoff`）・神官1（`flee`・`retreat` 0・裏口まで2〜3マス）。勝利＝`capture_hq` か殲滅、敗北＝全滅、`turn_limit` 20。3ターン目の自軍ターン頭に `talk` イベント（`name` 付き・`focus` で裏口へ寄せる）。(4) `campaign.json` に st3 を足す（解放条件＝st2 クリア）。(5) 翻訳 CSV＝`campaigns.csv`（st3 の題）と `dialogue.csv`（戦闘前・戦闘中・戦闘後の台本・話者「神官」「見習い教徒」・イベントの見出し）。(6) 地形スキン＝館の床（`plain` か `road` の見た目違い）・館の壁（`wall` 型）・柱（`rock` 型の見た目違い）・説教壇（`fort` 型の見た目違い）・裏口（`fort` 型の見た目違い）。
- 考慮外：st4 以降。神官を捕まえられる盤にはしない（距離で必ず逃げ切る）。
- 該当：`doc/gdd/map.md`・`godot/domain/capture/base.gd`・`godot/domain/battle_state.gd`・`godot/application/stage_loader.gd`（拠点の読み込み）・`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝scenario-4・5。

### scenario-7

**邪神三部作 第1部 st4「下水道の縄張り」のステージ実装（twingods1-4）**
- ゴール：第1部の st4 が st3 から続けて遊べる（兵を戻さない連戦で一行7人が下水へ降り、盗賊3人が加わり、水路の盤を抜けて奥の扉を押さえて会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st4 が設計・台本まで決まった。群れ（`swarm`）・突撃（`charge`）・待ち伏せ（`ambush`）・睨み合い（`standoff`）・敵hq占領・飛行・瓦礫（軽歩行だけ越える）・川と橋はすべて既存。無いのはスキンと下水の地形スキン。
- 対応：(1) 敵スキン「大ネズミ」（type `scout`）・「地下コウモリの群れ」（type `birdman`）と、ally スキン「盗賊」（type `scout`）を `unit_skin.csv` に足す。絵は仮でよい。(2) ステージ JSON `cult-stirrings-st4.json`＝南の格子から北の奥の扉（敵hq・`rest: enemy`）へ。中央を水路（`river`）が縦に走り、橋2本で両岸をつなぐ。西に瓦礫（`rubble`）の抜け道、東に脇部屋。西岸の中ほど（最初の橋の先）に味方所有の拠点「盗賊のアジト」（`team: player`・`rest: player`・回復拠点）。一行7人は `actor` のみ（`supply` 無し＝連戦）、盗賊3人（スカウト2・ハーフリング1）は `actor` 無しの配給。敵は大ネズミ4（`swarm`・東の脇部屋）、コウモリ3（`charge`・水路の上）、見張り＝見習い教徒4（`ambush`）＋術者2（`standoff`・扉の前）。勝利＝`capture_hq` か殲滅、敗北＝全滅、`turn_limit` 20。(3) `campaign.json` に st4 を足す（解放条件＝st3 クリア）。(4) 翻訳 CSV＝`campaigns.csv`（st4 の題）と `dialogue.csv`（戦闘前・戦闘後の台本・話者「盗賊」）。(5) 地形スキン＝下水の足場（`road` か `plain` の見た目違い）・下水の壁（`wall` 型）・水路（`river` の見た目違い＝汚水）・下水の橋（`bridge` の見た目違い）・崩れた抜け道（`rubble` の見た目違い）・奥の扉（`fort` 型の見た目違い）・盗賊のアジト（`fort` 型の見た目違い）。
- 考慮外：st5 以降。3人の名簿への加入（載せない）。
- 該当：`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝scenario-4〜6。

### scenario-8

**邪神三部作 第1部 st5「下水道の祭壇」のステージ実装（twingods1-5）**
- ゴール：第1部の st5 が st4 から続けて遊べる（一行7人と選別中の娘3人が盤に居て、娘を南の扉へ逃がしながら祭壇を押さえ、神官は隠し扉へ消え、会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st5 が設計・台本まで決まった。弱者狙い（`predator`）・睨み合い（`standoff`）・逃走（`flee`）・護衛対象の喪失（`lose_unit`）・敵hq占領・台地は既存。逃げ切り拠点は scenario-6 が敵側で作る。ここでは味方側にも効かせる。
- 対応：(1) 逃げ切り拠点（`exit`）を味方の駒にも効かせる＝南の扉に娘が入ると盤から消える（名簿にも残らない）。敵側と同じ印で、入った駒の陣営を問わない形にする。消えた駒は `lose_unit` の対象から外れる（倒れたのではない）。(2) ステージ JSON `cult-stirrings-st5.json`＝南の扉（味方側の逃げ切り拠点）から北の祭壇（敵hq・`rest: enemy`）へ。祭壇と両脇に台地（`plateau`）、登り口は幅1、左右に石柱で仕切った回廊。隠し扉（敵側の逃げ切り拠点）は祭壇の背後。一行7人は `actor` のみ（連戦・`supply` 無し）。娘3人は `civilian`・`unit_id: girl1`〜`girl3`・祭壇の前。敵は見習い教徒6（`predator`・娘から3マス以上離す）、術者3（`standoff`・両脇の台地）、神官1（`flee`・`retreat` 0）。湧き無し。勝利＝`capture_hq` か殲滅、敗北＝全滅と `lose_unit` を娘ごとに3条件、`turn_limit` 20。3ターン目の自軍ターン頭に `talk` イベント（`focus` で隠し扉へ）。(3) `campaign.json` に st5 を足す（解放条件＝st4 クリア）。(4) 翻訳 CSV＝`campaigns.csv`（st5 の題）と `dialogue.csv`（戦闘前・戦闘中・戦闘後の台本・話者「娘」「盗賊」「神官」）。(5) 地形スキン＝石室の床（`plain` の見た目違い）・石室の壁（`wall` 型）・高み（`plateau` の見た目違い）・石柱（`rock` 型の見た目違い）・祭壇（`fort` 型の見た目違い）・隠し扉（st3 の裏口と同じでよい）。
- 考慮外：st6 以降。娘を勝利条件に入れること（外へ出すのは手段）。
- 該当：`godot/domain/capture/base.gd`・`godot/domain/battle_state.gd`・`godot/domain/victory/victory.gd`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/terrain/terrain_skin.csv`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map.md`（逃げ切り拠点の陣営の扱い）・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝scenario-4〜7。

### scenario-9

**邪神三部作 第1部 st6「別荘の床下から」のステージ実装（twingods1-6）**
- ゴール：第1部の st6 が st5 から続けて遊べる（連戦の一行7人が床下から別荘へ上がり、寝ている私兵を起こさずに通るか選び、祈り所で休めて、渡り廊下の扉を押さえて会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st6 が設計・台本まで決まった。待ち伏せ・突撃・睨み合い・敵hq占領・拠点の回復（`rest: player`）は既存。敵スキンは st2 の人さらい3種と st3 の邪信徒2種を流用＝新規なし。無いのは別荘の地形スキン。
- 対応：(1) ステージ JSON `cult-stirrings-st6.json`＝床下の階段から母屋の廊下へ、両脇に私兵の部屋（待ち伏せ・索敵2）、廊下の先に中庭、2階の回廊に投石3（待ち伏せ）、中庭に私兵頭1（突撃）、中庭の先に祈り所（拠点・`team: enemy`・`rest: player`）と渡り廊下の扉（敵hq・`rest: enemy`）、その手前に見習い教徒3（突撃）と術者2（睨み合い）。一行7人は `actor` のみ（連戦・`supply` 無し）。勝利＝`capture_hq` か殲滅、敗北＝全滅、`turn_limit` 20。(2) `campaign.json` に st6 を足す（解放条件＝st5 クリア・`interlude` は `onward`＝連戦）。(3) 翻訳 CSV＝`campaigns.csv`（st6 の題）と `dialogue.csv`（戦闘前・戦闘後の台本）。(4) 地形スキン＝別荘の床（絨毯＝`road` か `plain` の見た目違い）・別荘の壁（`wall` 型）・中庭（`plain` の見た目違い）・2階の回廊（`plateau` の見た目違い＝撃ち下ろす高み）・祈り所（`fort` 型の見た目違い）・渡り廊下の扉（`fort` 型の見た目違い）。
- 考慮外：st7。使用人などの支援ユニット（出さない）。
- 該当：`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/terrain/terrain_skin.csv`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝scenario-4〜8。

### scenario-10

**邪神三部作 第1部 st7「離れの決戦」のステージ実装（twingods1-7）**
- ゴール：第1部が st1 から st7 まで通しで遊べる（連戦の一行7人が離れに踏み込み、壁と高みに守られた邪神官を落として幕。完走の勝利絵と outro）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st7 が設計・台本まで決まった。ボス撃破（`defeat_unit`）・待ち伏せ・睨み合い・突撃・台地は既存。無いのは敵スキン2つと離れの地形スキン。
- 対応：(1) 敵スキン「邪教兵」（type `novice`・`cult_soldier`）と「商人」（type `civilian`・`merchant`＝有力者。攻撃0の非戦闘員で、倒れる＝取り押さえた）を `unit_skin.csv` に足す。絵は仮でよい。(2) ステージ JSON `cult-stirrings-st7.json`＝渡り廊下から離れの一室へ。奥の祭壇に邪神官（`unit_id: cult_priest`・`standoff`）、左右の台地に邪教徒3（`standoff`）、手前に邪教兵4（`ambush`・索敵1）、邪教見習い2（`charge`）、祭壇の脇に商人（`actor: patron`・`ambush`・索敵0）。一行7人は `actor` のみ（連戦・`supply` 無し）。勝利＝`defeat_unit`（cult_priest）のみ、敗北＝全滅、`turn_limit` 20。逃げ切り拠点は置かない。(3) `campaign.json` に st7 を足す（解放条件＝st6 クリア・`interlude` は `onward`＝連戦）。(4) 翻訳 CSV＝`campaigns.csv`（st7 の題・冒険譚の説明）と `dialogue.csv`（戦闘前・戦闘後の台本・話者「邪神官」「有力者」「有力者の娘」＝町娘のスキンの顔を流用）。(5) 地形スキン＝離れの床・壁・祭壇（st5 の祭壇と同じでよい）・高み（`plateau` の見た目違い）。(6) 完走の勝利絵 `{id}_victory.png` と扉絵 `{id}_cover.png`（[keyvisual.md](art/keyvisual.md)）は別途。
- 考慮外：第2部。有力者を勝敗条件に入れること。
- 該当：`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧は記入済み。実装後に数を合わせる）。前提＝scenario-4〜9。
