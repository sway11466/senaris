# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=7 / feature=130 / refactoring=18.

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。ゴールは、その作業で何が達成されていれば終わりなのかを1文で書く。手段ではなく到達点を書く（「タグを決める」ではなく「棚に並んだとき誰の隣に出るかが決まっている」）。作業の途中で軸がずれるのを防ぐために置く。

考慮外は、外したい軸があるときだけ足す。「この作業では○○は考えない」と書く。書いていなければ制限は無い。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

### bug-6

**陣形スキルの成立する組が複数あるとき、どの組かを示せない（同名の項目が並ぶ）**
- ゴール：レシピごとにメニュー項目が1つで、組が複数あるときはプレイヤーが盤の上で参加者を選べる。組が1つなら選ぶ段は出ない。③で聖職が3体隣接している盤で確認できる。
- 背景：`Formation.available_for` が成立する組を全部列挙し、`hex_board_3d.gd` の行動メニューがそれを組の数だけ同じ名前で並べる（③のパラディンの隣に聖職が3体＝「ディバインジャッジメント」が3行）。どれがどの組かは読めない。2体固定のレシピ（④⑨⑩・feature-117/118/123）が入ると常態化する。仕様は [uiux.md](gdd/uiux.md)「陣形スキルの参加者を選ぶ」・[formations.md](gdd/formations.md) 共通ルール（記入済み）。
- 対応：(1) `available_for` の返りをレシピ単位にまとめる（`FormationOption` に候補の組 `member_sets` を持たせるか、レシピ単位の `FormationChoice` を新設して組を内包）。AI（`ai_rows.gd`・`ai_pick.gd`）と撮影ツールは組を列挙する既存の形を使い続けてよいので、列挙する関数は残し、UI 向けにまとめる関数を足す。(2) `hex_board_3d.gd`：メニューはレシピごとに1項目。ホバーで候補の駒を橙で光らせる。選択後、組が1つなら従来どおり `_enter_formation`、複数なら参加者選びの状態（`_choosing_members`）に入り、クリックで1体ずつ確定（残りの候補は確定済みと組める駒に絞る）。揃ったら `_enter_formation`。④は着弾先を先に選び、その対象に隣接する斥候が複数のときだけ相方を選ぶ。(3) キャンセルは1段ずつ戻す（着弾先 → 参加者 → メニュー）。(4) 橙のオーバーレイを色の表に足す（`board overlay`）。(5) `test_formation.gd` にレシピ単位のまとめ（組が1つ／複数）のテスト。UI の段は実機で確認。
- 考慮外：AI の組の選び方（既存のまま）。タッチ操作。
- 該当：`godot/domain/formation/formation.gd`・`godot/domain/formation/formation_option.gd`・`godot/presentation/board/hex_board_3d.gd`・`godot/presentation/board/`（オーバーレイの色）・`godot/tests/small/domain/test_formation.gd`・`doc/gdd/uiux.md`。feature-117/118/123 の前提。

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
- 対応：(1) 敵スキン「大ネズミ」（type `scout`）・「地下コウモリの群れ」（type `birdman`）と、ally スキン「盗賊」（type `scout`）を `unit_skin.csv` に足す。絵は仮でよい。(2) ステージ JSON `cult-stirrings-st4.json`＝南の格子から北の奥の扉（敵hq・`rest: enemy`）へ。中央を水路（`river`）が縦に走り、橋2本で両岸をつなぐ。西に瓦礫（`rubble`）の抜け道、東に脇部屋。西岸の中ほど（最初の橋の先）に味方所有の拠点「盗賊のアジト」（`team: player`・`rest: player`・回復拠点）。一行7人は `actor` のみ（`supply` 無し＝連戦）、盗賊3人（スカウト2・ハーフリング1）は `actor` 無しの配給。敵は大ネズミ4（`swarm`・東の脇部屋）、コウモリ3（`charge`・水路の上）、見張り＝見習い教徒4（`ambush`）＋術者2（`standoff`・扉の前）。勝利＝`capture_hq` か殲滅、敗北＝全滅、`turn_limit` 20。(3) `campaign.json` に st4 を足す（解放条件＝st3 クリア）。(4) 翻訳 CSV＝`campaigns.csv`（st4 の題）と `dialogue.csv`（戦闘前・戦闘後の台本・話者「盗賊」）。(5) 地形スキン＝下水の足場（`road` か `plain` の見た目違い）・下水の壁（`wall` 型）・水路（`river` の見た目違い＝汚水）・下水の橋（`bridge` の見た目違い）・崩れた抜け道（`rubble` の見た目違い）・奥の扉（`fort` 型の見た目違い）・盗賊のアジト（`fort` 型の見た目違い）。
- 考慮外：st5 以降。3人の名簿への加入（載せない）。
- 該当：`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝feature-106〜108。

### feature-110

**邪神三部作 第1部 st5「下水道の祭壇」のステージ実装（twingods1-5）**
- ゴール：第1部の st5 が st4 から続けて遊べる（一行7人と選別中の娘3人が盤に居て、娘を南の扉へ逃がしながら祭壇を押さえ、神官は隠し扉へ消え、会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st5 が設計・台本まで決まった。弱者狙い（`predator`）・睨み合い（`standoff`）・逃走（`flee`）・護衛対象の喪失（`lose_unit`）・敵hq占領・台地は既存。逃げ切り拠点は feature-108 が敵側で作る。ここでは味方側にも効かせる。
- 対応：(1) 逃げ切り拠点（`exit`）を味方の駒にも効かせる＝南の扉に娘が入ると盤から消える（名簿にも残らない）。敵側と同じ印で、入った駒の陣営を問わない形にする。消えた駒は `lose_unit` の対象から外れる（倒れたのではない）。(2) ステージ JSON `cult-stirrings-st5.json`＝南の扉（味方側の逃げ切り拠点）から北の祭壇（敵hq・`rest: enemy`）へ。祭壇と両脇に台地（`plateau`）、登り口は幅1、左右に石柱で仕切った回廊。隠し扉（敵側の逃げ切り拠点）は祭壇の背後。一行7人は `actor` のみ（連戦・`supply` 無し）。娘3人は `civilian`・`actor: girl1`〜`girl3`・祭壇の前。敵は見習い教徒6（`predator`・娘から3マス以上離す）、術者3（`standoff`・両脇の台地）、神官1（`flee`・`retreat` 0）。湧き無し。勝利＝`capture_hq` か殲滅、敗北＝全滅と `lose_unit` を娘ごとに3条件、`turn_limit` 20。3ターン目の自軍ターン頭に `talk` イベント（`focus` で隠し扉へ）。(3) `campaign.json` に st5 を足す（解放条件＝st4 クリア）。(4) 翻訳 CSV＝`campaigns.csv`（st5 の題）と `dialogue.csv`（戦闘前・戦闘中・戦闘後の台本・話者「娘」「盗賊」「神官」）。(5) 地形スキン＝石室の床（`plain` の見た目違い）・石室の壁（`wall` 型）・高み（`plateau` の見た目違い）・石柱（`rock` 型の見た目違い）・祭壇（`fort` 型の見た目違い）・隠し扉（st3 の裏口と同じでよい）。
- 考慮外：st6 以降。娘を勝利条件に入れること（外へ出すのは手段）。
- 該当：`godot/domain/capture/base.gd`・`godot/domain/battle_state.gd`・`godot/domain/victory/victory.gd`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/terrain/terrain_skin.csv`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map.md`（逃げ切り拠点の陣営の扱い）・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝feature-106〜109。

### feature-111

**幕間の印と挿絵（連戦／休息／復帰をプレイヤーに知らせる）**
- ゴール：継承の冒険譚で、話と話のあいだに兵が戻るのか戻らないのかが、ステージ一覧を見れば分かり、連続プレイでは休息と復帰のときだけ一枚絵で知らされる。
- 背景：継承（carryover）では `supply: "refill"`／`"revive"` で兵が戻るが、それが盤の中のデータでしかなく、プレイヤーには何も見えない。連戦か休息かは難しさそのものなので、遊ぶ前に読めるべき。仕様は [stage_select.md](gdd/stage_select.md) 幕間の印・幕間の挿絵に書いた。邪神三部作 第1部（st2・st3 の前が休息、st3〜st7 が連戦）が最初の使い手。チュートリアル３「竜狩り」も継承で、st2 以降の全話が名簿の駒に `refill` を書いている＝`campaign.json` に `interlude: rest` を入れ、整合テストの対象にする。
- 対応：(1) マニフェストのステージ項目に `interlude`（`continuous`／`rest`／`revive`）を足し、[campaign_catalog.gd](../godot/data/stages/campaign_catalog.gd) で読む。(2) ステージ一覧（[stage_select.gd](../godot/presentation/select/stage_select.gd)）で行と行のあいだに印を挟む。アイコン3つ（松明・ベッド・合流の旗＝[icons.md](art/icons.md)）。(3) 戦闘後の自動遷移（[main.gd](../godot/presentation/main/main.gd)）で、次の `interlude` が `rest`／`revive` なら次の intro の前に挿絵＋一文を挟む。挿絵2枚（[keyvisual.md](art/keyvisual.md)）、文は翻訳キー。セレクトから直接始めたときは挟まない。(4) データ整合テスト＝`interlude: rest` の話は名簿の駒に `refill` が、`revive` の話は `revive` が書かれていること（逆も）。
- 考慮外：独立（各話配給）の冒険譚への印（出さない）。
- 該当：`doc/gdd/stage_select.md`・`doc/gdd/campaigns.md`・`godot/data/stages/campaign_catalog.gd`・`godot/presentation/select/stage_select.gd`・`godot/presentation/main/main.gd`・`godot/data/i18n/`・`godot/tests/`（整合テスト）・`godot/data/stages/tutorial3-dragon-hunt/campaign.json`（`interlude` の記入）。

### feature-112

**邪神三部作 第1部 st6「別荘の床下から」のステージ実装（twingods1-6）**
- ゴール：第1部の st6 が st5 から続けて遊べる（連戦の一行7人が床下から別荘へ上がり、寝ている私兵を起こさずに通るか選び、祈り所で休めて、渡り廊下の扉を押さえて会話へ）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st6 が設計・台本まで決まった。待ち伏せ・突撃・睨み合い・敵hq占領・拠点の回復（`rest: player`）は既存。敵スキンは st2 の人さらい3種と st3 の邪信徒2種を流用＝新規なし。無いのは別荘の地形スキン。
- 対応：(1) ステージ JSON `cult-stirrings-st6.json`＝床下の階段から母屋の廊下へ、両脇に私兵の部屋（待ち伏せ・索敵2）、廊下の先に中庭、2階の回廊に投石3（待ち伏せ）、中庭に私兵頭1（突撃）、中庭の先に祈り所（拠点・`team: enemy`・`rest: player`）と渡り廊下の扉（敵hq・`rest: enemy`）、その手前に見習い教徒3（突撃）と術者2（睨み合い）。一行7人は `actor` のみ（連戦・`supply` 無し）。勝利＝`capture_hq` か殲滅、敗北＝全滅、`turn_limit` 20。(2) `campaign.json` に st6 を足す（解放条件＝st5 クリア・`interlude: continuous`）。(3) 翻訳 CSV＝`campaigns.csv`（st6 の題）と `dialogue.csv`（戦闘前・戦闘後の台本）。(4) 地形スキン＝別荘の床（絨毯＝`road` か `plain` の見た目違い）・別荘の壁（`wall` 型）・中庭（`plain` の見た目違い）・2階の回廊（`plateau` の見た目違い＝撃ち下ろす高み）・祈り所（`fort` 型の見た目違い）・渡り廊下の扉（`fort` 型の見た目違い）。
- 考慮外：st7。使用人などの支援ユニット（出さない）。
- 該当：`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/terrain/terrain_skin.csv`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧に行を足す）。前提＝feature-106〜110。

### feature-113

**邪神三部作 第1部 st7「離れの決戦」のステージ実装（twingods1-7）**
- ゴール：第1部が st1 から st7 まで通しで遊べる（連戦の一行7人が離れに踏み込み、壁と高みに守られた邪神官を落として幕。完走の勝利絵と outro）。
- 背景：[twingods1-cult-stirrings.md](campaign/twingods1-cult-stirrings.md) の st7 が設計・台本まで決まった。ボス撃破（`defeat_unit`）・待ち伏せ・睨み合い・突撃・台地は既存。無いのは敵スキン2つと離れの地形スキン。
- 対応：(1) 敵スキン「邪教兵」（type `novice`・`cult_soldier`）と「商人」（type `civilian`・`merchant`＝有力者。攻撃0の非戦闘員で、倒れる＝取り押さえた）を `unit_skin.csv` に足す。絵は仮でよい。(2) ステージ JSON `cult-stirrings-st7.json`＝渡り廊下から離れの一室へ。奥の祭壇に邪神官（`actor: cult_priest`・`standoff`）、左右の台地に邪教徒3（`standoff`）、手前に邪教兵4（`ambush`・索敵1）、邪教見習い2（`charge`）、祭壇の脇に商人（`actor: patron`・`ambush`・索敵0）。一行7人は `actor` のみ（連戦・`supply` 無し）。勝利＝`defeat_unit`（cult_priest）のみ、敗北＝全滅、`turn_limit` 20。逃げ切り拠点は置かない。(3) `campaign.json` に st7 を足す（解放条件＝st6 クリア・`interlude: continuous`）。(4) 翻訳 CSV＝`campaigns.csv`（st7 の題・冒険譚の説明）と `dialogue.csv`（戦闘前・戦闘後の台本・話者「邪神官」「有力者」「有力者の娘」＝町娘のスキンの顔を流用）。(5) 地形スキン＝離れの床・壁・祭壇（st5 の祭壇と同じでよい）・高み（`plateau` の見た目違い）。(6) 完走の勝利絵 `{id}_victory.png` と扉絵 `{id}_cover.png`（[keyvisual.md](art/keyvisual.md)）は別途。
- 考慮外：第2部。有力者を勝敗条件に入れること。
- 該当：`godot/data/units/unit_skin.csv`・`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/twingods1-cult-stirrings/`・`godot/data/i18n/campaigns.csv`・`godot/data/i18n/dialogue.csv`・`doc/gdd/map_patterns.md`（ステージ一覧は記入済み。実装後に数を合わせる）。前提＝feature-106〜110・112。

### feature-114

**会話の途中で駒を盤に出す（`enter` 行と `on: "dialogue"` イベント）**
- ゴール：戦闘前の会話の任意の行で、味方でも敵でも、指定した駒だけを盤に出せる（会話の前から居る／途中で出る／会話の直後に出る、をステージデータで選べる）。
- 背景：駒は開始時に全部置かれ、その上で intro が流れる。途中で出す手段は `events` の増援（`turn`／`on: "capture"`）だけで、1ターン目のイベントは会話を流せないため「音や台詞で気づいてから敵が現れる」「合流の台詞で仲間が現れる」が書けない（[map.md](gdd/map.md) イベント）。チュートリアル１〜３の台本には効果音やト書きで登場を告げる行が既にあり、盤が先に見せてしまっている。
- 方式は未決：`events`（増援）に相乗りする形で一度実装したが取り消した（2026-09-15）。会話の途中の登場は盤の顔ぶれを変えない見た目の話なので、盤面データを書き換える `events` に載せるのが誤り。駒と部隊の定義は陣営セクション（`player[]`／`enemy[]`）に置いたまま、presentation が intro の間だけ見せ方を変える形にする。なお `player[]` は駒の配列・`enemy[]` は部隊の配列で構造が違うため、同じ書き方で敵味方を名指せない。そこをどう揃えるかが先。

- 考慮外：outro での登場（ステージが終わるので意味がない）。会話の途中で駒を消すこと。
- 該当：`doc/gdd/map.md`・`doc/campaign/authoring.md`・`godot/application/stage_loader.gd`・`godot/application/match_controller.gd`・`godot/domain/battle_state.gd`・`godot/presentation/main/story_director.gd`・`godot/presentation/ui/conversation_panel.gd`・`godot/tools/map_editor/`（イベントの引き金の選択肢）。

### feature-115

**チュートリアル１〜３の登場タイミングを会話に合わせる（会話の `enter` 行の適用）**
- ゴール：効果音やト書きで登場を告げる行のあとに、その駒が盤に現れる（会話の前から盤に見えていない）。
- 背景：会話の `enter` 行（[map.md](gdd/map.md) イベント）を決めたときに台本を洗った候補。いずれも台本に「気づく」行が既にあり、駒を後出しにするだけで噛み合う。
- 対応：各ステージの `dialogue.intro` に `enter` 行を置き、該当の駒を会話の途中で盤へ出す。campaign doc の「会話（戦闘前）」にも登場の位置をメモする。
  - チュートリアル１ st3：斥候「来ます！」→ 敵8体。st6：斥候「私が先に入りましょう」→ ハーフリング（会話だけの人物が初めて駒になる場面）。
  - チュートリアル２ st3：魔導師「もう一人、術者を呼びました」→ 3人目の術者／魔女「ゴーストよ」→ ゴースト。st4：司祭「教会が応えてくれました」→ 教会の増援／魔女「レイスよ」→ レイス。st5：司祭「聖職が五人、揃いました」→ 聖職の追加分。
  - チュートリアル３ st2：効果音「敵襲だーっ！」→ 北にハーピー・南にオーク（一番の候補）。st3：効果音「ドゴォンッ」→ 坑道の魔物／ト書き「鉱脈の外れ」→ ローグ一味。st6：シーフ「誰かが逃げてきたわね」→ 逃げるローグ本隊。
  - 見送り：チュートリアル２ st6 デュラハン・チュートリアル３ st7 竜（最初から見えている形のほうが自然）。
- 方式は未決：駒と部隊の定義は陣営セクション（`player[]`／`enemy[]`）に置いたままにする。一度 `events` へ移して実装したが、部隊がイベントの中に入ると部隊名が失われ、マップエディタからも編集できなくなるため取り消した（2026-09-15）。イベントが部隊を名指す形にするか、部隊側に登場を書くかは未決。
- 考慮外：邪神三部作への適用（別途、台本を見直すときに拾う）。
- 該当：`godot/data/stages/tutorial1-goblin-raid/`・`godot/data/stages/tutorial2-undead-rush/`・`godot/data/stages/tutorial3-dragon-hunt/`・`doc/campaign/tutorial1-goblin-raid.md`・`doc/campaign/tutorial2-undead-rush.md`・`doc/campaign/tutorial3-dragon-hunt.md`。

### feature-116

**継承の一行を戦闘演出で1体として描く（マニフェスト `actor_lineup`）**
- ゴール：継承（carryover）の冒険譚で、名簿に載る一行の駒が戦闘演出に1体だけ立ち、兵数は兵量バーで読める。支援ユニット（配給）と敵は隊列のまま＝「一行は個人、軍は隊列」が絵で分かれる。
- 背景：継承の冒険譚は駒に名前こそ無いが個人として見せているので、戦闘演出で同じ顔が8体並ぶと違和感が出る。演出には既に `single`（1体だけ描き損害は兵量バー）があるが `unit_skin.csv` のスキン単位で、一行のスキンはチュートリアルの兵と共用＝スキンでは切り替えられない。個人として描くかは冒険譚の性質なので、冒険譚のマニフェストで宣言する。
- 対応：(1) `campaign.json` に `actor_lineup`（`""`＝スキン任せ／`"single"`）を足し、`CampaignCatalog.build` で正規化（`UnitSkin.LINEUPS` で検証）。(2) `UnitSnapshot` に `actor` を写す（`BattleState.unit_snapshot`）。(3) `CombatStage` に `bind_actor_lineup` と `_lineup_of(comb)` を足し、味方（team 0）かつ `actor` 付きなら上書き。隊列を見ている3箇所（`_render_side`・`_textures_for`・`_lead_pos`）をこの1関数経由に寄せる＝戦闘・ユニットスキル・自分掛けが同じ判断を通る。(4) `main.gd` の演出部品への配線に `emblem` と同じ流れで1行ずつ。(5) 上書き時の倍率は 1.0（`SINGLE_SCALE` 1.4 は馬車・竜級のための値。味方の大きさは `combat_scale` で焼き込み済み）。発数は兵数のまま＝集中砲火として読ませ、着弾点は隊列スロットではなく本人の位置へ寄せる。倍率と発数は実機で見てから最終判断。(6) 使う冒険譚＝チュートリアル３「竜狩り」から（`tutorial3-dragon-hunt/campaign.json` に `"actor_lineup": "single"`）。三部作にも同じ1行。(7) `test_campaign_catalog.gd` に既定とパースのテスト。(8) 仕様の追記＝[combat_scene.md](tech/combat_scene.md) 兵数の表示・[stage_select.md](gdd/stage_select.md) マニフェスト・[campaigns.md](gdd/campaigns.md)。
- 副作用：地形の後ろ絵（玉座など）の立ち位置が本人の位置から決まるので味方側で動く。フラグが効かない経路＝起動時の下敷き・撮影ツール（`shot_combat.gd`・`shot_screen.gd` は冒険譚を通さず戦闘を組む）・devlog 用の並び絵 `build_lineup.py`＝撮影物と実機の見た目が食い違う。撮りたければ各々に引数を足す。
- 考慮外：スキン単位の `single`（聖女・ユニコーンのように常に1人の駒は従来どおり `unit_skin.csv` で決める）。retinue の上書き。
- 該当：`godot/data/stages/campaign_catalog.gd`・`godot/domain/unit/unit_snapshot.gd`・`godot/domain/battle_state.gd`・`godot/presentation/combat/combat_stage.gd`・`godot/presentation/main/main.gd`・`godot/data/stages/tutorial3-dragon-hunt/campaign.json`・`godot/tests/small/data/test_campaign_catalog.gd`。難易度は小〜中（配管は既存の前例どおり。重いのは見た目の判断）。
- **実装済み（実機確認待ち）**：コード・テスト・仕様追記は完了（(1)〜(8) すべて）。三部作の `campaign.json` は冒険譚が未作成のため対象外。実機確認＝竜狩り（tutorial3）で以下を確認すること: (1) actor 付き味方が1体で描かれる（配給・敵は隊列のまま） (2) 倍率が等倍で違和感がないか (3) 着弾点が SINGLE_POS に寄っているか (4) 発数が兵数どおりか (5) ユニットスキル・自分掛けでも同じ描き方になるか。

### feature-117

**陣形スキル④トリックショット（弓兵＋斥候・貫通0.5の単体射撃）**
- ゴール：斥候が敵に隣接し弓兵がその敵を射程に収めたとき、弓兵の行動メニューに項目が出て、貫通0.5・反撃なしの一撃が飛ぶ。飛行の敵には対空値で撃てる。ステージでは教えない＝出れば見つかる。
- 背景：[formations.md](gdd/formations.md) ④ で仕様確定。既存の陣形は「参加者の形」（triangle／escort／cluster）だけを見るが、これは「対象の周りに参加者が居るか」を見る初めての形。威力の計算も既存は常に対地値・貫通は発動者依存で、矢のレシピ（④⑥⑨）は相手が飛行なら対空値・貫通はレシピ側で上書き、が要る。⑥⑨がこの下地を使うので最初に作る。
- 対応：(1) `Formation.RECIPES` に `trick_shot`（leader＝archer/hunter/elf、member＝scout/thief/halfling/ninja/kunoichi、shape `spotter`、count 2、effect `single`、`pierce_override` 0.5、`attack_vs` "target"＝相手で対地／対空を切り替え）。(2) `FormationOption.Shape` に `SPOTTER` を足し、`available_for` は対象候補ごとに「その対象に隣接する member」を組で持つ（対象を選んだ時点で相方が決まる。複数なら1体を選ぶ＝option を対象×相方で複数出す）。射程は発動者の通常射程（`min_range`〜`attack_range`）。(3) `_skill_attack_breakdown` に対地／対空の切り替え、`_formation_hit` にレシピの貫通上書きを通す（`attack_vs` 未指定のレシピは従来どおり対地固定・発動者依存）。(4) 演出は③と同じ単体シーケンス（絵は `assets/formations/trick_shot_impact.png` の規約解決、無ければ共通3段）。(5) `names.csv` に `recipe.trick_shot.name/desc`。(6) `test_formation.gd` に成立（斥候が対象に隣接／弓兵が射程内）・不成立（斥候が発動者にだけ隣接）・貫通・対空の切り替えのテスト。
- 考慮外：敵AIの使用（敵スキンはレシピに書かない）。教えるステージの追加。
- 該当：`godot/domain/formation/formation.gd`・`godot/domain/formation/formation_option.gd`・`godot/domain/formation/formation_resolver.gd`・`godot/presentation/board/board_impact_renderer.gd`・`godot/data/i18n/names.csv`・`godot/tests/small/domain/test_formation.gd`・`doc/gdd/formations.md`（実装方針の段階を更新）。前提＝bug-6（参加者を選ぶ段）。

### feature-118

**陣形スキル⑨マジックアロー（弓兵＋魔法兵・大きい方＋10・貫通0.5・射程は長い方＋1）**
- ゴール：弓兵と魔法兵が隣接しているとき、弓兵から「2体の攻撃力の大きい方＋10・貫通0.5」の単体射撃が「2体の射程上限の長い方＋1」まで届く。届かなかった相手に魔法兵級の一撃が届く。
- 背景：[formations.md](gdd/formations.md) ⑨ で仕様確定。escort（count 2）の流用だが、威力の元と射程を「発動者」ではなく「参加者の性能から引く」のが新しい。対空／対地の切り替えと貫通の上書きは feature-117 の下地。
- 対応：(1) `RECIPES` に `magic_arrow`（leader＝archer/hunter/elf、member＝wizard/witch、shape `escort`、count 2、effect `single`、`pierce_override` 0.5、`attack_vs` "target"、`attack_from` "max_plus"（値 10）、`range_from_stats` "max_plus"（値 1）、下限なし）。(2) `_skill_attack_breakdown` に「参加者の攻撃力の最大＋定数」を元にする経路（兵数・レベル・包囲・地形は発動者のもの）。(3) `available_for`／`_in_range_cells` で射程を参加者の `attack_range` の最大＋1 から求める（レシピの固定 `range` と排他）。(4) 演出は④と同じ単体シーケンス（`magic_arrow_impact.png`）。(5) `names.csv`。(6) テスト＝威力の元の選び方（地上はウィザード40＋10／空はエルフ60＋10）・射程（アーチャー＋ウィザード＝5・エルフ＝6）。
- 該当：feature-117 と同じ。前提＝feature-117・bug-6。

### feature-119

**陣形スキル⑥アローレイン（弓兵3体の三角・半径2の19ヘクス・発動者ベース・貫通なし）**
- ゴール：スリンガー系を除く弓兵3体が三角になると、発動者の射程上限まで届く半径2の面攻撃が撃てる。参加者は当たらず、他の味方は当たる。飛行には対空値。
- 背景：[formations.md](gdd/formations.md) ⑥ で仕様確定。①と同型で、面の半径が2・射程が発動者の性能依存・対空／対地の切り替えあり、貫通は発動者依存（弓＝0）のまま。
- 対応：(1) `RECIPES` に `arrow_rain`（leader／member＝archer/hunter/elf、shape `triangle`、count 3、effect `area`、`radius` 2、`range_from` "any"、`range_from_stats` "leader"＝発動者の `attack_range`、`attack_vs` "target"）。(2) `blast_cells` は `radius` を読むだけで済むはず＝19ヘクスになることをテストで確認。(3) 着弾演出の順送り（中心から外へ）が半径2でも成り立つか `board_impact_renderer` を確認。プレビュー（桃の面）も半径2で出す。(4) `names.csv`・`arrow_rain_impact.png`。(5) テスト＝三角の成立（ハンター＋アーチャー＋エルフ）・スリンガーの除外・面の広さ・参加者の除外。
- 該当：feature-117 と同じ＋`godot/presentation/board/hex_board_3d.gd`（面のプレビュー）。前提＝feature-117。

### feature-120

**陣形スキル⑤シールドウォール（ノービス以外の歩兵3体以上の一列・参加者の防御 ×(1＋0.05×人数)）**
- ゴール：歩兵が3体以上一直線に並んでいるとき、列のどれからでも撃てて、列の全員の防御が人数ぶん上がる（3体 ×1.15）。次の自軍ターン開始まで。膠着の待機の上位互換で、効果は薄くてよい。
- 背景：[formations.md](gdd/formations.md) ⑤ で仕様確定。②グレイスの持続バフの器（状態補正エントリ）に、スコープ「参加者だけ」と対象「防御だけ」を足す。形は `cluster` の直線版。
- 対応：(1) `RECIPES` に `shield_wall`（leader／member＝fighter/vanguard/knight/forest_knight/dwarf/samurai/magic_knight＋lancer（type が入ったら）、shape `line`、count 3、effect `buff`、`buff_op` "mul"、`buff_scope` "participants"、`buff_target` "def"、`buff_value` 1.15、`buff_value_per_extra` 0.05、`duration_turns` 1）。(2) `FormationOption.Shape` に `LINE`：発動者を含むヘックスの3軸のどれかで途切れず連なる参加者を集める（人数は選べない）。(3) `_buff_entry`／`BattleState` の状態補正に `scope: participants`（駒の集合）と `target: def` を通す＝②は `team`・`both` のまま。(4) 見た目は列の駒の足元の光（`aura_overlay` の駒単位の光を流用）。カットインは規約解決。(5) `names.csv`。(6) テスト＝直線の判定（3軸・折れ線は不成立・ノービス除外）・人数で伸びる補正・参加者以外に乗らないこと。
- 該当：`godot/domain/formation/formation.gd`・`formation_option.gd`・`formation_resolver.gd`・`godot/domain/battle_state.gd`・`godot/domain/combat/combat.gd`（集計の scope）・`godot/presentation/ui/aura_overlay.gd`・`godot/data/i18n/names.csv`・`godot/tests/small/domain/test_formation.gd`。

### feature-121

**陣形スキル⑦マジックシールド（魔法兵＋占領兵の隣接・7ヘクスの結界・防御 +10×発動者兵数・貫通無効）**
- ゴール：ウィザード／ウィッチと占領兵が隣接しているとき、どちらからでも発動者中心の7ヘクスに結界が張れる。中に居る味方は実効防御に 10×発動者の残兵数 が足され、貫通を受けない。入れば効き、出れば切れる。次の自軍ターン開始まで。
- 背景：[formations.md](gdd/formations.md) ⑦ で仕様確定。状態補正の器に **地帯（zone）** のエントリを新設する最初の実体（[combat.md](gdd/combat.md) 状態補正に注記済み）。貫通無効は乗算・加算の外＝貫通の段で攻撃側の `pierce` を 0 にするフラグ。
- 対応：(1) `RECIPES` に `magic_shield`（leader／member＝wizard/witch × cleric/priest/bishop/paladin の両向き、shape `escort`、count 2、effect `buff`、`buff_scope` "zone"、`zone_radius` 1、`buff_op` "add"、`buff_target` "def"、`buff_value_per_troop` 10、`pierce_immune` true、`duration_turns` 1）。(2) `BattleState` の状態補正エントリに `zone`（中心ヘックス＋半径・陣営）を足し、`Combat` の集計で「対象の駒が地帯の中に居るか」を見る。(3) `Combat` の貫通の段で、防御側に `pierce_immune` の地帯が効いていれば攻撃側の `pierce` を 0 として扱う。(4) 見た目＝結界の7ヘクスに薄い光の床（`aura_overlay` に地帯の床を足す。持続の間出しておく）。(5) `names.csv`。(6) テスト＝加算（満員で +80）・貫通無効（ウィザードの攻撃が半減しない）・出入りで効く／切れる・満了。
- 該当：feature-120 と同じ＋`godot/domain/combat/combat.gd`（貫通の段）・`godot/presentation/ui/aura_overlay.gd`。前提＝feature-120（scope の拡張を先に）。

### feature-122

**陣形スキル⑧バックスタブ（シーフ＋対象を挟んで正反対の味方1体・貫通0.5・着弾後に元の位置へ戻る）**
- ゴール：シーフが敵に隣接し、その敵を挟んで正反対のヘックスに味方が居るとき、貫通0.5・反撃なしの一撃を刺し、シーフはこのターンの移動開始位置へ戻る。参加者はシーフとその味方だけで、幾何で決まる。
- 背景：[formations.md](gdd/formations.md) ⑧ で仕様確定。形 `backstab` は対象を挟んだ正反対（対象からの方向ベクトルが逆）を見る＝④の `spotter` の親戚。着弾後に発動者の位置を戻すのは初めての処理で、移動開始位置を `BattleState` が覚えている必要がある。
- 対応：(1) `RECIPES` に `backstab`（leader＝thief、member＝任意（`member_skins` 空＝種別不問の印）、shape `backstab`、count 2、effect `single`、`range` 1、`pierce_override` 0.5、`attack_vs` "target"、`return_to_origin` true）。(2) `FormationOption.Shape` に `BACKSTAB`：対象候補は発動者の隣接する敵のうち、`target + (target - leader_pos)` に味方が居るもの。相方はその1体。(3) `FormationResolver.resolve` の最後に、`return_to_origin` なら発動者を移動開始位置へ戻す（経路・コスト・足止め不問。`MatchController` が持つ移動前の位置を `SkillCast` に渡す）。中断セーブとリプレイで位置が一致することを確認。(4) 演出＝跳んで刺して戻る（駒の移動アニメを2回。絵は `backstab_impact.png`）。(5) `names.csv`。(6) テスト＝対角の判定（隣り合う2体は不成立）・相方が幾何で決まる・戻り・飛行相手は対空10。
- 考慮外：他の斥候（ハーフリング等）への拡張。撃破後の再攻撃（検討して不採用）。
- 該当：feature-117 と同じ＋`godot/application/match_controller.gd`・`godot/domain/battle_state.gd`・`godot/domain/formation/skill_cast.gd`。前提＝feature-117。

### feature-123

**回復の泉の見た目（拠点スキン）**
- ゴール：チュートリアル３ st6 の泉3つが、盤の上で泉に見える（回復・争奪の動きは今のまま）。
- 背景：拠点の地形スキンは町・詰所・礼拝堂・納骨堂などの建物だけで、泉が無い。[tutorial3-dragon-hunt.md](campaign/tutorial3-dragon-hunt.md) st6 は泉3つを汎用 fort で置いてあり、回復ローテと争奪は動くが「泉を取り合う」絵にならない。会話も泉と呼んでいるので、盤とのずれが目に付く。
- 対応：`terrain_skin.csv` に `fort` 型の見た目違いを1つ足す（洞窟の地面の上に立てる泉。占領で色が変わる `_team0`／`_team1` の規則は他の拠点と同じ＝[terrain.md](art/terrain.md)）。st6 の該当マスをそのスキンに差し替える。
- 該当：`godot/data/terrain/terrain_skin.csv`・`godot/data/stages/tutorial3-dragon-hunt/dragon-hunt-st6.json`・`doc/art/terrain.md`。着手の引き金＝竜狩りの通し確認で st6 を触るとき。

### feature-126

**クロニクルの通し読みの仕組み**
- ゴール：クロニクルの冒険譚から「物語」を選ぶと、その冒険譚の会話を最初から最後まで読み返せる。
- 背景：クロニクルの他の章（ユニット・陣形スキル・戦果・設定集）は動いていて、物語だけがプレースホルダのまま。材料は揃っている＝順序は `godot/data/chronicle/<冒険譚 id>.json` の `story`、本文は `dialogue.csv`、表示は盤で使っている `ConversationPanel`。冒険譚が増えても作り直さない共通の仕組みなので、中身（feature-127・128）とは分ける。
- 対応：(1) `story` の並びに沿って、どの会話をどの順で出すかを組み立てる。(2) ステージの挿絵を背景に敷く（盤は組み直さず、`assets/campaign/` の静止画を読む）。(3) `ConversationPanel` を盤の外でも動かす。(4) 通し読みの操作＝章題・次へ・スキップ・停止。どの回の内容を出すかは最後に遊んだ回で固定（切り替えは feature-129）。
- 該当：`godot/presentation/chronicle/`・`godot/presentation/ui/conversation_panel.gd`・`godot/data/i18n/ui.csv`（`ui.chronicle.*`）・[chronicle.md](gdd/chronicle.md) 物語。

### feature-127

**チュートリアル１のクロニクルの中身**
- ゴール：チュートリアル１を遊んだ人が、設定集を読み切れて、物語を通して読める。
- 背景：設定集は5節ぶんを書いてあるが、[chronicle.md](gdd/chronicle.md) 設定集の構成（前半＝舞台・依頼の経緯・一行の顔ぶれ・相手は何者か、後半＝読み物）に照らすと後半が薄い。正本は [tutorial1-goblin-raid.md](campaign/tutorial1-goblin-raid.md) と [world.md](gdd/world.md) で、メモに無い裏設定は載せない。
- 対応：`godot/data/i18n/chronicle.csv` に節を書き足し、`godot/data/chronicle/tutorial1-goblin-raid.json` の `lore` に節と解放条件を並べる。`story` の並び（ステージ順とイベント）も実際の台本と突き合わせる。
- 該当：`godot/data/i18n/chronicle.csv`・`godot/data/chronicle/tutorial1-goblin-raid.json`。前提＝feature-126。

### feature-128

**チュートリアル２のクロニクルの中身**
- ゴール：チュートリアル２を遊んだ人が、設定集を読み切れて、物語を通して読める。
- 背景：`godot/data/chronicle/` にファイルが無く、設定集も `story` の並びもまだ無い。正本は [tutorial2-undead-rush.md](campaign/tutorial2-undead-rush.md) と [world.md](gdd/world.md)。
- 対応：feature-127 と同じ形で `godot/data/chronicle/tutorial2-undead-rush.json` を作り、`chronicle.csv` に本文を足す。
- 該当：`godot/data/i18n/chronicle.csv`・`godot/data/chronicle/tutorial2-undead-rush.json`。前提＝feature-126。

### feature-129

**クロニクルの分岐の切り替え**
- ゴール：両方の展開を経験している箇所で、通し読みの途中にどちらを読むか切り替えられる。
- 背景：台本には在籍による行の出し入れ（`joined:<actor>`）と、どちらか一方しか起きないイベントがある（[chronicle.md](gdd/chronicle.md) 分岐の切り替え）。既定は最後に遊んだ回で、切り替えは両方を経験している箇所だけに出す＝読み始める前に顔ぶれを選ばせない。
- 対応：通し読みが分岐に差しかかったとき、パネル脇に切り替えを出す。切り替えは仲間ごとに独立。
- 該当：`godot/presentation/chronicle/`・[chronicle.md](gdd/chronicle.md) 分岐の切り替え。前提＝feature-126。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

### feature-124

**陣形スキル⑩カウンター（ノービス以外の歩兵2体の隣接・参加者の攻撃 ×1.5＝反撃強化）**
- ゴール：歩兵2体が隣接しているとき、どちらからでも撃てて、2体の攻撃が次の自軍ターン開始まで ×1.5 になる。参加者は行動完了なので効くのは敵ターンの反撃だけ。
- 背景：[formations.md](gdd/formations.md) ⑩ で仕様確定。feature-120（⑤シールドウォール）の器＝状態補正のスコープ「参加者だけ」に、対象「攻だけ」を足すだけ。形は `escort`（count 2）の流用。敵AIは陣形の効果を読まない（[ai.md](gdd/ai.md) 基本方針に追記済み）ので AI 側の変更は無い。
- 対応：(1) `RECIPES` に `counter`（leader／member＝fighter/vanguard/knight/forest_knight/dwarf/samurai/magic_knight＋lancer、shape `escort`、count 2、effect `buff`、`buff_op` "mul"、`buff_scope` "participants"、`buff_target` "atk"、`buff_value` 1.5、`duration_turns` 1）。(2) `_buff_entry`／`Combat` の集計で `target: atk` を通す（⑤は def、②は both）。(3) 見た目は2体の足元の光（⑤と同じ）。(4) `names.csv`。(5) テスト＝2体固定（3体目は参加しない）・ノービス除外・反撃に ×1.5 が乗り、自軍ターン開始で切れること・AI の戦果計算に乗らないこと。
- 該当：feature-120 と同じ＋`godot/domain/ai/`（戦果計算が状態補正を除くことの確認）。前提＝feature-120・bug-6。

### refactoring-17

**`names.csv` を他と同じ単位に割る（ユニット・地形 …）**
- ゴール：翻訳CSV のファイル名を見れば、そこに何の文字列が入っているかが分かる。
- 背景：翻訳CSV は用途で分かれている（`dialogue` / `campaigns` / `ui` / `manual` / `chronicle`）が、`names.csv` だけが「データに付いた用語」を全部抱えている＝ `ai` / `category` / `movement` / `recipe` / `terrain` / `terrain_type` / `unit` の7系統。何の name なのかをファイル名が言えていない。データ側は `godot/data/units/` `terrain/` `movement/` `ai/` のように機能フォルダで割れているので、翻訳も同じ単位にできる。
- 対応：`names.csv` を系統ごとの CSV に割る（ユニット・地形・移動・AI・陣形スキル …）。`project.godot` の `locale/translations` と [i18n.md](tech/i18n.md) のキー命名規約を合わせて直す。キー（`unit.<id>.name` 等）は変えない＝ファイルの割り方だけの変更で、コードは触らない。
- 該当：`godot/data/i18n/names.csv`・`godot/project.godot`・[i18n.md](tech/i18n.md)・`godot/tests/`（CSV を名指ししているテスト）。

### refactoring-15

**陣形スキルのドリフト検出（formations.md の一覧 ⇄ `Formation.RECIPES` ⇄ `names.csv`）**
- ゴール：レシピが doc・code・翻訳のどれか1つにだけ増減したとき、テストが落ちて気づける。
- 背景：正本は [formations.md](gdd/formations.md)「一覧（決まった項目）」の表A/表B、実行時は `godot/domain/formation/formation.gd` の `RECIPES`（ハードコード）、表示名は `godot/data/i18n/names.csv` の `recipe.<id>.name/desc`。3か所が別々に育つ（④〜⑨は doc だけ、陣形①〜③の `desc` が無い、混沌の2本は code に無い）。CSV/JSON 化は見送り（[architecture.md](tech/architecture.md) 入れ子データはコードが持つ）なので、照合で守る。
- 対応：(1) `godot/tools/` に formations.md の表A/表Bを読む小さなパーサ（`| # | id | …` の行を拾い、id・人数・形・射程・実装列を辞書に）。(2) GUT テスト `test_formation_catalog.gd`：表の id のうち実装列が「済」のものは `RECIPES` に在り、`count`・`shape`・`range` が一致すること／`RECIPES` の id はすべて表に在ること／`names.csv` に `recipe.<id>.name` と `.desc` が在ること（ユニットスキルは skills.md の見出しで同様に）。(3) 陣形①〜③の `desc` を `names.csv` に足す。(4) 表の書式を崩すと落ちるので、formations.md の一覧の冒頭に「列は固定」の注意を置く（記入済み）。
- 考慮外：効果の数値（威力・倍率）の照合＝表現が文なので見ない。CSV/JSON 化。
- 該当：`godot/tools/`・`godot/tests/small/domain/test_formation_catalog.gd`・`godot/data/i18n/names.csv`・`doc/gdd/formations.md`・`doc/tech/testing.md`（テストの位置づけを1行）。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- **隠し駒（視線に入るまで盤に出ない敵）。** 荷の陰・物陰に潜む敵を、味方の索敵に入るまで盤に出さない。出た瞬間は動かず、次の敵ターンから襲う＝1発は必ず受けるが、受けるのは兵数だけ。確定ゲームの方針（[ai.md](gdd/ai.md) 特性と部隊はプレイヤーに見せる）に穴を開けるので、入れるなら条件を守る＝食らっても駒を失わない／覚えた後にも選択が残る／やり直しが安い／潜んでいたことが物語の絵になる／冒険譚の中で1回だけの手口にする。戦闘前の会話で警告を1行置く。実装は駒の不可視・視線で露見・露見まで AI が動かない・描画の4点。邪神三部作 第1部 st2（倉庫）の検討で出た案。今回は見送り、崩せる積み荷（既存のバリケード型）で代替した。
