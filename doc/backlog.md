# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=6 / feature=110 / refactoring=15.

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。ゴールは、その作業で何が達成されていれば終わりなのかを1文で書く。手段ではなく到達点を書く（「タグを決める」ではなく「棚に並んだとき誰の隣に出るかが決まっている」）。作業の途中で軸がずれるのを防ぐために置く。

考慮外は、外したい軸があるときだけ足す。「この作業では○○は考えない」と書く。書いていなければ制限は無い。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

### refactoring-12
- doc/art/terrain.mdの内容精査
- 旧地形システム関連の記述は消す
- 目次を見直し


### feature-8

**タッチ操作対応（uiux フェーズ4）**
- 背景：モバイルは後回し方針（CLAUDE.md）だが、[uiux.md](gdd/uiux.md) §フェーズ4 が未実装。タッチ操作一式（タップ選択・1本指パン・ピンチズーム・長押しキャンセル）のハンドラが無く、全体表示も `F` キーのみ＝キーボードの無いタッチ環境では全体表示に到達不能。
- 対応：`hex_board_3d.gd` の `_unhandled_input` に `InputEventScreenTouch`/`ScreenDrag`/長押しを足す。`hud.gd` に全体表示ボタン（タッチ用・画面ボタン必須）を足す。
- 該当：`godot/presentation/board/hex_board_3d.gd`・`godot/presentation/ui/hud.gd`・`doc/gdd/uiux.md`。着手の引き金＝モバイル配布を見据えたら。

### feature-92

**ステージが更新されている中断セーブをプレイヤーに知らせる**
- ゴール：セーブを作ったあとにステージを直した枠が、選ぶ前に見て分かり、選んだときにも一度確認が入る。
- 背景：ステージ定義が変わっても差分はそのまま適用して再開を妨げない方針だが、黙って適用すると盤が前と違う理由がプレイヤーに分からない。枠の一覧表示は `_row_text` 一本で、ロード時の確認はいまタイトルの「冒険の続き」経由では出ない（失う盤が無いため）。
- 対応：セーブの印と今のステージ定義の印を比べ、違う枠は一覧の行に更新されている旨を添える。その枠を選んだときだけ確認を挟む（印が一致する枠のロードは今のまま）。
- 該当：`godot/presentation/ui/save_slot_panel.gd`・`godot/presentation/main/main.gd`・`godot/data/i18n/`・`doc/tech/gamesystem.md`。セーブの印は meta の `stage_digest`、今の定義の印は `StageDigest.of_file`。

### feature-13

**entitlement（DLC所有）判定によるステージ解放**
- 背景：ステージセレクトの解放は現状「クリア連鎖」だけで、有料DLC（冒険譚）の所有チェック（entitlement）が未配線＝販売時に「持っていれば解放」を判定できない（[stage_select.md](gdd/stage_select.md)）。Steam DLC 連携が前提。解放ゲート `_is_satisfied` は `cleared` のみ対応で、entitlement を含む未知条件は locked 扱い。表示側の `unlock_text` には entitlement 条件を「追加コンテンツ」と示す分岐が既にあるが、実際の充足判定の口が無い。
- 対応：所有判定の口を `CampaignProgress` に足し、DLC冒険譚は entitlement 充足で解放。Steam 側は GodotSteam 導入時に配線（それまではローカルで常時充足扱い等の切替）。
- 該当：`godot/application/campaign_progress.gd`・`godot/presentation/select/`・`doc/gdd/stage_select.md`。着手の引き金＝Steam の体験版に向けて Steamworks に登録するとき（[monetization.md](sales/monetization.md) 出す順序）。

### feature-16

**移動/カメラ演出の速度設定・敵ターンスキップ・演出の適用範囲拡張**
- 背景：敵の全行動を見せる（移動アニメ＋カメラ追従）ぶん、敵が多いターンは総時間が伸びる。アニメ速度の設定（高速／標準／オフ）と敵ターンのスキップは SLG の定番だが、速度はどれもコード内の定数のままで、スキップ導線も無い（[uiux.md](gdd/uiux.md) システムメニュー・敵ターンのカメラ）。設定画面と設定の永続化（`SettingsStore`）は言語・音量・画面モードを持ち、盤の中からも開ける形で入っているので、値の置き場と開き口はできている（[settings.md](gdd/settings.md)）。また演出には未対応の隙間がいくつかある。
- 対応：(1) 設定画面に演出速度の項目を足し、移動アニメ速度（`MOVE_ANIM_SEC_PER_HEX`／`MOVE_ANIM_MAX_SEC`）とカメラ追従（`FOCUS_PAN_SEC`）を設定値から引く。戦闘演出の速度（[combat_scene.md](tech/combat_scene.md) テンポ・スキップの「フル／短縮／オフ」3段）も同じ設定に乗せる＝置き場所が決まっていないのはこれだけで、AIターンの短縮は仕様だけあって未実装。(2) 敵ターンのスキップ（キー／ボタンで残りを一気に最終状態へ）。(3) 出撃・降車は経路を持たずポップして現れる＝拠点／輸送から目的マスへの1歩スライドで見せる（経路探索は不要）。(4) カメラ追従は行動主体の現在位置だけを見る＝長距離移動でアニメ中に終点が画面外へ出るケースの追随、攻撃で対象も画面に含める配慮は未対応（現状は移動距離が短く実害小）。
- 該当：`godot/presentation/board/hex_board_3d.gd`（`focus_camera_on`／移動アニメ）・`godot/application/match_controller.gd`（ターンのテンポ・スキップ）・`godot/infrastructure/save/settings_store.gd`・`godot/presentation/settings/settings_screen.gd`・`doc/gdd/uiux.md`。着手の引き金＝敵ターンが長く感じ始めたら。

### feature-27

**タイトル名「Senaris」の確定手続き**
- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済み。確定前の手続きが残っている。すべてオーナー側の手作業。商標の一次スクリーニングと Bluesky ハンドルは済み（結果は同 doc の事前チェック結果サマリ）。Discord は作品名義で取らず、開発元のサーバーで持つ（[marketing.md](sales/marketing.md) Discord）。
- 対応：(1) X のハンドル。X は使わない方針（[marketing.md](sales/marketing.md) SNS）で、名前の予約だけするかは未決。(2) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`。着手の引き金＝Steam の体験版に向けて Steamworks に登録するとき（[monetization.md](sales/monetization.md) 出す順序）。
### feature-40

**Steam 実績・Stats の配線（GodotSteam 導入）**
- 背景：実績と計測の方針は [monetization.md](sales/monetization.md)（実績・計測）で決めたが、実装側の入り口が無い。GodotSteam は未導入（`godot/infrastructure/platform/` は空）で、実績を立てる呼び出しも Stats を刻む発火点も置き場所が決まっていない。実績はリリース後に削除・改名できない（解除済みの記録が消える）ため、セットの確定は 1.0 のストア提出前が締め切りになる。
- 対応：(1) GodotSteam を導入し `godot/infrastructure/platform/` の裏に隔離する（feature-13 の entitlement 配線と同じ層・同じ段。Steam が居ない環境＝エディタ実行・BOOTH 版でも落ちないダミー実装を用意）。(2) 実績の発火点＝冒険譚の完走判定。完走判定は `CampaignProgress` にあり、ランクも進捗セーブに入る（[stage_select.md](gdd/stage_select.md) クリア記録）ので判定はここに寄せる。最上位ランク達成時は下2段も同時に付与（取りこぼし防止）。(3) Stats の発火点＝ステージの開始とクリア。全ステージではなくチュートリアルに絞って刻む（見たいのは最初の1時間の離脱）。(4) 体験版のセーブを本体と共有 Steam Cloud に置き、購入後の本体初回起動でまとめて付与する経路（Valve 推奨。体験版では実績を発火させない）。
- 該当：`godot/infrastructure/platform/`（GodotSteam の隔離・新規）・`godot/application/campaign_progress.gd`（完走判定・ランク記録）・`godot/infrastructure/save/progress_store.gd`（Cloud 配置）・`doc/sales/monetization.md`。着手の引き金＝Steamworks に AppID を登録したとき（[monetization.md](sales/monetization.md) 出す順序）。前提＝ランクの評価式（[rank.md](gdd/rank.md)）は実装済み。
- 要確認（AppID 取得後に管理画面で）：体験版の AppID で Stats が使えるか（Steamworks のドキュメントは体験版について実績にしか触れていない）。実績上限100の緩和条件＝Profile Features のしきい値。

### feature-46

**タイトル画面の残り（クレジット画面）**

- 背景：タイトル画面そのものは入った（起動→扉が開く動画→店内のメニュー。仕様 → [title.md](gdd/title.md)）。残るのは、メニューに項目だけ置いてあるクレジット画面。
- クレジット：素材の権利表記。タイトルのメニューに項目は置いてあるが、受け口が無く押せない状態。画面に出す内容は [credits.md](sales/credits.md) の「ゲーム内クレジットに出すもの」が正本で、そこを読んで並べるだけにする。台帳の整備自体は済んでいるが、根拠が取れていないライセンスが残っている（feature-54）。リリース前が締め切り。
- クレジット画面の作り（決めたこと）：新規シーン `godot/presentation/credits/` を1枚。タイトルのメニューからのみ開く（ゲーム中のシステムメニューには足さない＝盤を止めてまで読むものではない）。戻るは左下の木の板ボタンで、位置と大きさはセレクトと同じ規則に揃える（[stage_select.md](gdd/stage_select.md)）。地は中立の暗色（起動スプラッシュと同じ `#0d1925`）＝操作の道具は酒場の物にしない（[title.md](gdd/title.md)）。押せる物だけが木の板、という様式は保つ。見た目は実物を見てから詰める。文言は `ui.csv` に足す（キーは `ui.<画面>.<項目>` → [i18n.md](tech/i18n.md)）。
- 該当：`godot/presentation/title/title_screen.gd`・`godot/presentation/credits/`（新規）・`doc/gdd/title.md`。関連＝feature-66〜69（UI文言の i18n キー化）。開き方と戻るの位置は設定画面（`godot/presentation/settings/settings_screen.gd`）を手本にする。着手の引き金＝配布ビルドが見えてきたとき。

### feature-62

**販売チャネルごとの機能を乗せる**
- 背景：チャネルの判定そのものは `godot/infrastructure/platform/build_info.gd` が持つ（[build.md](tech/build.md)）。その上に乗るチャネル固有の機能がまだ無い。評価ランクの実績発火（feature-40）、entitlement による DLC 解放（feature-13）が控えている。
- 対応：`channel()` の戻り値で実装を選ぶ形にし、チャネルを持たない環境（エディタ実行・itch）には何もしない実装を置く。所有権チェックは `owns(content_id) -> bool` だけを本体に見せる（[monetization.md](sales/monetization.md) のチャネル差を隔離する）。
- 該当：`godot/infrastructure/platform/`・`doc/sales/monetization.md`。前提＝feature-40（GodotSteam 導入）・feature-13（entitlement）。

### feature-93

**盤中のヘルプ（その場で用語を引く）**
- ゴール：盤の中で、いま選んでいる物の用語（敵の特性名・能力値の項目名など）の意味がその場で読める。
- 背景：マニュアル（[manual.md](gdd/manual.md)）はタイトル専用の通読画面と決め、盤中からは開かない。盤で「弱者狙いって何」「貫通率はどこに効く」と詰まったとき、その場で引く手段が無い。
- 対応：形は未検討。情報パネルの用語から短い説明を出す類を想定。説明文をマニュアルの本文と共有するかもここで決める。
- 該当：`godot/presentation/ui/`（情報パネル）・`godot/data/i18n/manual.csv`（マニュアル本文）。着手の引き金＝実プレイで用語に詰まったとき。

### feature-94

**収集図鑑（名前は未決）**
- ゴール：出会ったユニットと見たスキルが図鑑に溜まり、まだ埋まっていない枠があることがプレイヤーに分かる。
- 背景：マニュアル（[manual.md](gdd/manual.md)）は用語と仕組みの説明に徹していて、個々のユニットやスキルの一覧を持たない。個体の性能や見た目を確かめる場と、集める楽しみの受け皿が無い。
- 対応：載せるのはユニット（味方・敵の両方）とスキル（陣形スキル・ユニットスキル）。プレイで遭遇したものが埋まる形式なので、解放状態をセーブに持つ。【未決】名前・開き口（タイトル画面か、マニュアルの中の章か）・枠が埋まる条件（見た／戦った／使った）・未解放の枠の見せ方。
- 該当：`doc/gdd/` に新規1本・`godot/presentation/`・解放状態のセーブは [gamesystem.md](tech/gamesystem.md)。

### feature-95

**サイトの中身を作る**
- ゴール：senaris.in を開くと、ゲームの紹介とルールが読める。
- 背景：ドメイン取得・DNS・配信構成は済んでいる（[site.md](sales/site.md)・[ADR-0005](adr/ADR-0005-site-hosting-cloudflare-workers.md)）。残るのは中身で、いま置くものが無い。
- 対応：(1) ランディングは1ページ。ストアページ（[steam_page.md](sales/steam_page.md)）の文と絵が決まってから流用して作る。(2) ルールのページ（`senaris.in/rules` 相当）をランディングからリンクする。マニュアルの構造定数と `manual.csv` から生成できる想定で、範囲と見せ方は未検討。
- 該当：`site/`・`doc/sales/site.md`・`godot/data/i18n/manual.csv`。着手の引き金＝配布が見えてきたとき。

### feature-99

**プレスキットを用意する**
- ゴール：紹介したい人に「ここを見て」と1つ渡せば、本物のロゴ・スクリーンショット・説明文・権利表記が揃う。
- 背景：体験版の公開後、こちらの許可なく紹介動画が出た（[sales/youtube.md](sales/youtube.md) の記録）。使われたサムネイルは実際の画面ではない生成画像で、期待と実物の落差が視聴者コメントに出た。渡せる素材が手元に無いと、第一接触の絵を他人の生成物に握られる。[site.md](sales/site.md) はランディングページのフッターに置くリンク項目として名前を挙げているだけで、中身も置き場も決めていない。
- 対応：中身と置き場を決める。素材は3面と共通のものを流用できる（[marketing.md](sales/marketing.md) の素材の置き場）。ストアページ（[steam_page.md](sales/steam_page.md)）を待たずに出せる範囲で先に組む。【未決】置き場（`senaris.in/press` か itch のページ内か）・同梱物（ロゴ・スクリーンショット・キービジュアル・説明文・権利表記・連絡先）・配り方（zip か個別ダウンロードか）。
- 該当：`channels/`・`doc/sales/site.md`・`doc/sales/marketing.md`・`doc/sales/youtube.md`。着手の引き金＝次に紹介の話が来たとき、またはサイトの中身を作るとき（feature-95）。

### feature-100

**情報板を自動で開く場面を設定で選べるようにする**
- ゴール：畳んだ情報板を、プレイヤーが選んだ場面（会話の前後・戦闘レポートなど）でだけ自動で開ける。
- 背景：最小化（[uiux.md](gdd/uiux.md) 最小化）は「畳んでいる間は何が起きても開かない」と決めた。会話の前後だけは開いてほしい人が居そうだが、勝手に開く規則を板に持たせると、覚える状態が増える。
- 対応：設定画面（[settings.md](gdd/settings.md)）に「情報板を開く場面」の項目を足し、選んだ場面でだけ開く。場面の候補と既定は着手時に決める。
- 該当：`doc/gdd/settings.md`・`godot/presentation/ui/unit_info_panel.gd`・`godot/infrastructure/save/settings_store.gd`。着手の引き金＝畳んで遊んで「ここで開いてほしい」が出たとき。

### feature-103

**盤エリアを、情報板が塞いでいない側にする**
- ゴール：情報板を畳んだとき・動かしたときに、盤も演出も画面いっぱいを使う。
- 背景：盤エリア（ステージ読み込み時のカメラのフィット・戦闘窓・陣形カットイン・完走の勝利イラストの置き場）を板の既定の矩形で固定していたので、畳んでも盤は左800pxの中に小さく出て、右は空いたままだった。仕様は決めてある（[uiux.md](gdd/uiux.md) 盤エリア）。
- 対応：`UiLayout.board_area` を板の状態（既定の場所で開いているか）で切り替える。ターン終了ボタンは盤エリアから外し、板の既定の矩形のすぐ左に固定する。戦果票は元から画面中央＝変更なし。
- 該当：`godot/presentation/ui/ui_layout.gd`・`godot/presentation/board/hex_board_3d.gd`（`_vis_rect`）・`godot/presentation/ui/hud.gd`・`godot/presentation/combat/combat_stage.gd`・`godot/presentation/formation/formation_cutin.gd`・`godot/presentation/victory/victory_screen.gd`。

### feature-106

**邪神三部作 第1部 st1「路地の人さらい」のステージ実装（twingods1-1）**
- ゴール：第1部の st1 が通しで遊べる（会話→路地の盤で娘を守り切る→会話）。娘が倒れたら敗北になり、一行7人がクリア時に名簿へ載る。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st1 が設計・台本まで決まった。護衛対象の敗北条件（`lose_unit`）と弱者狙い（`predator`）は実装済みだが、娘を置く型と人さらいの絵、冒険譚の器（フォルダ・マニフェスト・ボード）が無い。
- 対応：(1) 新 type `civilian`（攻0／防10／移3／射程0／占領不可／兵数1）を `unit_type.csv` に足し、ally スキン「娘」を `unit_skin.csv` に足す。(2) 敵スキン「人さらい」（type `novice`）を足す。新 type `lancer`（40／0／貫通0／防40／移5／歩行／射程1-2／占領不可＝[twingods.md](campaign/twingods.md) ランサー）と ally スキン「ランサー」を足す。娘・人さらい・ランサーの絵は仮でよい。(3) 冒険譚フォルダ `godot/data/stages/twingods1-cult-stirrings/` と `campaign.json`（board は新設 `twingods`＝[stage_select.md](gdd/stage_select.md) シリーズボードの表とコードの定数に行を足す）。(4) ステージ JSON `cult-stirrings-st1.json`＝路地の盤（壁で区切った幅2の路地・北の広場・南西の酒場）、一行7人（`actor`＋`supply: "join"`）、娘（`actor: girl`）、人さらい4体を2部隊（`predator`）、勝利＝殲滅、敗北＝`lose_unit`（girl）、`turn_limit` 15。距離の目安は設計ドキュメントのとおり（初手の敵ターンでは届かず、2ターン目で届く）。(5) 翻訳 CSV＝`campaigns.csv`（冒険譚名・説明・st1 の題）と `dialogue.csv`（戦闘前・戦闘後の台本・話者名）。(6) 効果音 `scream`（悲鳴）の素材調達と発火点（[sfx.md](audio/sfx.md)）。(7) 地形スキン＝路地の絵にする2つ（町家の壁＝`wall` 型・酒場＝`building` 型）を `terrain_skin.csv` に足す。露店（`prop` 型）と北門（`road` 型の見た目違い）は任意。地形タイプは既存（壁・道・街区・石畳）で足りる。
- 考慮外：st2 以降の盤・台本。
- 該当：`godot/data/units/unit_type.csv`・`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`godot/presentation/select/campaign_select.gd`（ボード定数）・`doc/gdd/stage_select.md`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。

### feature-107

**邪神三部作 第1部 st2「倉庫の奇襲」のステージ実装（twingods1-2）**
- ゴール：第1部の st2 が st1 から続けて遊べる（名簿から一行7人が出て、衛士4人が加わり、倉庫の敵13体を殲滅して会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st2 が設計・台本まで決まった。待ち伏せ（`ambush`）・突撃（`charge`）・敵側バリケードは既存で、無いのは敵スキンと倉庫の地形スキン。冒険譚の器（フォルダ・マニフェスト・ボード）は feature-106 が作る。
- 対応：(1) 敵スキン「人さらいの投石」（type `slinger`）・「人さらいの頭」（type `vanguard`）・「積み荷」（type `barricade`・崩せる荷）を `unit_skin.csv` に足す。絵は仮でよい。(2) ステージ JSON `cult-stirrings-st2.json`＝西の入口から東の奥へ幅3の通路、両脇に積み荷の塊（`rock` 型）と北南で対になる窪み。一行7人は `actor` のみ（名簿から）、衛士4人（ノービス2・アーチャー2）は `actor` 無しの配給。敵は窪みの対ごとに待ち伏せ部隊（人さらい2＋投石1・索敵2）×3、奥に突撃2、頭1（索敵小・最後の order）、崩せる積み荷を北列と南列に各1〜2か所。勝利＝殲滅、敗北＝全滅、`turn_limit` 20。(3) `campaign.json` に st2 を足す（解放条件＝st1 クリア）。(4) 翻訳 CSV＝`campaigns.csv`（st2 の題）と `dialogue.csv`（戦闘前・戦闘後の台本・話者「衛士」「人さらいの頭」）。(5) 地形スキン＝倉庫の床（`plain` か `road` の見た目違い）と倉庫の壁（`wall` 型）。積み荷の塊は `rock` 型の見た目違いで1つ。
- 考慮外：st3 以降。人さらいの頭の撤退（`withdraw`）は使わない（殲滅で決着する盤）。
- 該当：`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝feature-106。

### feature-108

**邪神三部作 第1部 st3「集会の館」のステージ実装（twingods1-3）**
- ゴール：第1部の st3 が st2 から続けて遊べる（一行7人で大広間へ踏み込み、神官が裏口へ走って消え、説教壇の占領か殲滅で決着して会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st3 が設計・台本まで決まった。群れ（`swarm`）・睨み合い（`standoff`）・逃走（`flee`）・敵hq占領・戦闘中の会話イベントは既存。無いのは「逃げ切り拠点」の仕組みと、敵スキン・館の地形スキン。
- 対応：(1) **逃げ切り拠点**＝`bases[]` に任意の印（仮 `exit: true`）を足す。その拠点に敵の駒が入ると盤から消え、控え（garrison）にも残らない。占領できない（味方は入れない）。殲滅の判定（盤上＋復帰手段）に影響しない。仕様は [map.md](gdd/map.md) 拠点の値に1項目足し、`Base`・`BattleState` の入る処理と `StageLoader` で受ける。デバッグステージを `debug-victory/` か `debug-ai/` に1枚。(2) 敵スキン「見習い教徒」（type `cleric`）・「術者」（type `mage`）・「神官」（type `witch`）を `unit_skin.csv` に足す。絵は仮でよい。神官は st5・st7 でも使う。(3) ステージ JSON `cult-stirrings-st3.json`＝南の正門と西の扉から入る大広間、南寄りに柱の列（進入不可）、北に説教壇（敵hq・`rest: enemy`）、その背後に裏口（逃げ切り拠点）。一行7人は `actor` のみ。敵は見習い教徒10（`swarm`）・術者3（`standoff`）・神官1（`flee`・`retreat` 0・裏口まで2〜3マス）。勝利＝`capture_hq` か殲滅、敗北＝全滅、`turn_limit` 20。3ターン目の自軍ターン頭に `talk` イベント（`name` 付き・`focus` で裏口へ寄せる）。(4) `campaign.json` に st3 を足す（解放条件＝st2 クリア）。(5) 翻訳 CSV＝`campaigns.csv`（st3 の題）と `dialogue.csv`（戦闘前・戦闘中・戦闘後の台本・話者「神官」「見習い教徒」・イベントの見出し）。(6) 地形スキン＝館の床（`plain` か `road` の見た目違い）・館の壁（`wall` 型）・柱（`rock` 型の見た目違い）・説教壇（`fort` 型の見た目違い）・裏口（`fort` 型の見た目違い）。
- 考慮外：st4 以降。神官を捕まえられる盤にはしない（距離で必ず逃げ切る）。
- 該当：`doc/gdd/map.md`・`godot/domain/capture/base.gd`・`godot/domain/battle_state.gd`・`godot/application/stage_loader.gd`（拠点の読み込み）・`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝feature-106・107。

### feature-109

**邪神三部作 第1部 st4「下水道の縄張り」のステージ実装（twingods1-4）**
- ゴール：第1部の st4 が st3 から続けて遊べる（兵を戻さない連戦で一行7人が下水へ降り、盗賊3人が加わり、水路の盤を抜けて奥の扉を押さえて会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st4 が設計・台本まで決まった。群れ（`swarm`）・突撃（`charge`）・待ち伏せ（`ambush`）・睨み合い（`standoff`）・敵hq占領・飛行・瓦礫（軽歩行だけ越える）・川と橋はすべて既存。無いのはスキンと下水の地形スキン。
- 対応：(1) 敵スキン「大ネズミ」（type `scout`）・「地下コウモリの群れ」（type `birdman`）と、ally スキン「盗賊」（type `scout`）を `unit_skin.csv` に足す。絵は仮でよい。(2) ステージ JSON `cult-stirrings-st4.json`＝南の格子から北の奥の扉（敵hq・`rest: enemy`）へ。中央を水路（`river`）が縦に走り、橋2本で両岸をつなぐ。西に瓦礫（`rubble`）の抜け道、東に脇部屋。一行7人は `actor` のみ（`supply` 無し＝連戦）、盗賊3人（スカウト2・ハーフリング1）は `actor` 無しの配給。敵は大ネズミ4（`swarm`・東の脇部屋）、コウモリ3（`charge`・水路の上）、見張り＝見習い教徒4（`ambush`）＋術者2（`standoff`・扉の前）。勝利＝`capture_hq` か殲滅、敗北＝全滅、`turn_limit` 20。(3) `campaign.json` に st4 を足す（解放条件＝st3 クリア）。(4) 翻訳 CSV＝`campaigns.csv`（st4 の題）と `dialogue.csv`（戦闘前・戦闘後の台本・話者「盗賊」）。(5) 地形スキン＝下水の足場（`road` か `plain` の見た目違い）・下水の壁（`wall` 型）・水路（`river` の見た目違い＝汚水）・下水の橋（`bridge` の見た目違い）・崩れた抜け道（`rubble` の見た目違い）・奥の扉（`fort` 型の見た目違い）。
- 考慮外：st5 以降。盗賊ギルドの拠点や名簿への加入（3人は名簿に載せない）。
- 該当：`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝feature-106〜108。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- **隠し駒（視線に入るまで盤に出ない敵）。** 荷の陰・物陰に潜む敵を、味方の索敵に入るまで盤に出さない。出た瞬間は動かず、次の敵ターンから襲う＝1発は必ず受けるが、受けるのは兵数だけ。確定ゲームの方針（[ai.md](gdd/ai.md) 特性と部隊はプレイヤーに見せる）に穴を開けるので、入れるなら条件を守る＝食らっても駒を失わない／覚えた後にも選択が残る／やり直しが安い／潜んでいたことが物語の絵になる／冒険譚の中で1回だけの手口にする。戦闘前の会話で警告を1行置く。実装は駒の不可視・視線で露見・露見まで AI が動かない・描画の4点。邪神三部作 第1部 st2（倉庫）の検討で出た案。今回は見送り、崩せる積み荷（既存のバリケード型）で代替した。
