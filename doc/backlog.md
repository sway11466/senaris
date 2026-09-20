# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。冒険譚の中身を作る作業（クロニクルの本文・ステージ実装）は [backlog_scenario.md](backlog_scenario.md) に分けてある。

## index

次回採番: bug=12 / feature=134 / refactoring=23.

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。ゴールは、その作業で何が達成されていれば終わりなのかを1文で書く。手段ではなく到達点を書く（「タグを決める」ではなく「棚に並んだとき誰の隣に出るかが決まっている」）。作業の途中で軸がずれるのを防ぐために置く。

考慮外は、外したい軸があるときだけ足す。「この作業では○○は考えない」と書く。書いていなければ制限は無い。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

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
- 対応：所有判定の口を `CampaignProgress` に足し、DLC冒険譚は entitlement 充足で解放。Steam 側は GodotSteam 導入時に配線する。チャネルごとのアダプターと「常に所有」の部品は feature-62。
- 該当：`godot/application/campaign_progress.gd`・`godot/presentation/select/`・`doc/gdd/stage_select.md`。着手の引き金＝Steam の体験版に向けて Steamworks に登録するとき（[monetization.md](sales/monetization.md) 出す順序）。

### feature-16

**演出の隙間（出撃と降車の見せ方・カメラ追従の追随）**
- 背景：演出の設定（[settings.md](gdd/settings.md) 戦闘の演出・盤面の演出）と、盤面のみの戦闘の一撃は入った。残るのは演出そのものの隙間。(a) 出撃・降車は経路を持たずポップして現れる。(b) カメラ追従は行動主体の現在位置だけを見る。
- 対応：(1) 出撃・降車は拠点／輸送から目的マスへの1歩スライドで見せる（経路探索は不要）。(2) 長距離移動でアニメ中に終点が画面外へ出るケースの追随、攻撃で対象も画面に含める配慮（現状は移動距離が短く実害小）。
- 該当：`godot/presentation/board/hex_board_3d.gd`（`focus_camera_on`／移動アニメ）・`doc/gdd/uiux.md`。着手の引き金＝出撃の多いステージで駒の湧きが読めないと感じたら。

### feature-27

**タイトル名「Senaris」の確定手続き**
- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済み。確定前の手続きが残っている。すべてオーナー側の手作業。商標の一次スクリーニングと Bluesky ハンドルは済み（結果は同 doc の事前チェック結果サマリ）。Discord は作品名義で取らず、開発元のサーバーで持つ（[marketing.md](sales/marketing.md) Discord）。
- 対応：(1) X のハンドル。X は使わない方針（[marketing.md](sales/marketing.md) SNS）で、名前の予約だけするかは未決。(2) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`。着手の引き金＝Steam の体験版に向けて Steamworks に登録するとき（[monetization.md](sales/monetization.md) 出す順序）。
### feature-40

**Steam 実績・Stats の配線（GodotSteam 導入）**
- 背景：実績と計測の方針は [monetization.md](sales/monetization.md)（実績・計測）で決めたが、実装側の入り口が無い。GodotSteam は未導入（`godot/infrastructure/platform/` は空）で、実績を立てる呼び出しも Stats を刻む発火点も置き場所が決まっていない。実績はリリース後に削除・改名できない（解除済みの記録が消える）ため、セットの確定は 1.0 のストア提出前が締め切りになる。
- 対応：(1) GodotSteam を導入し `godot/infrastructure/platform/` の裏に隔離する（feature-13 の entitlement 配線と同じ層・同じ段。チャネルごとのアダプターと部品の構造、Steam 以外のチャネルでの実績の保管先は feature-62）。(2) 実績の発火点＝冒険譚の完走判定。完走判定は `CampaignProgress` にあり、ランクも進捗セーブに入る（[stage_select.md](gdd/stage_select.md) クリア記録）ので判定はここに寄せる。最上位ランク達成時は下2段も同時に付与（取りこぼし防止）。(3) Stats の発火点＝ステージの開始とクリア。全ステージではなくチュートリアルに絞って刻む（見たいのは最初の1時間の離脱）。(4) 体験版のセーブを本体と共有 Steam Cloud に置き、購入後の本体初回起動でまとめて付与する経路（Valve 推奨。体験版では実績を発火させない）。
- 該当：`godot/infrastructure/platform/`（GodotSteam の隔離・新規）・`godot/application/campaign_progress.gd`（完走判定・ランク記録）・`godot/infrastructure/save/progress_store.gd`（Cloud 配置）・`doc/sales/monetization.md`。着手の引き金＝下の段階1と2は登録前から進められる。段階3は Steamworks に AppID を登録したとき（[monetization.md](sales/monetization.md) 出す順序）。前提＝ランクの評価式（[rank.md](gdd/rank.md)）は実装済み。
- 導入の形：GodotSteam は GDExtension 版（`godot/addons/` に置くアドオン）を採る。GodotSteam 同梱のエディタは使わない＝手元の Godot エディタと二重管理になる。
- 進め方（登録前に進められる範囲）：
  1. 登録なし・Steam なし。feature-62 のアダプターと部品を作り、dev アダプターで実績の発火点・所有チェックの呼び出し・Stats の刻む場所を全部作る。エディタと GUT はここで回る。GUT は Steam 実装を通さず、アダプターの選択と部品の挙動だけを見る。
  2. 登録なし・テスト用 AppID 480（Valve が公開している Spacewar）。GodotSteam を入れ steam アダプターを書き、480 に繋いで初期化・実績の読み書き・Stats の送信が通ることを確認する。実績名は Spacewar に定義済みのものを仮に使う。Senaris 固有の実績の定義・DLC の所有チェック・体験版と製品版のセーブ共有は 480 では試せない。
  3. 登録あり・自分の AppID。管理画面で実績・DLC・Cloud を定義し、AppID と実績名を差し替えて本番確認する。
- 手元で Steam 実装を動かす条件：Steam クライアントが起動しログイン済みであること。Steam を経由せず起動するため、AppID を1行書いた `steam_appid.txt` を作業ディレクトリ（エディタならプロジェクトルート、ビルドなら exe の隣）に置く。このファイルは配布物に入れない＝Steam から起動されるときは Steam が AppID を渡す。
- 要確認（AppID 取得後に管理画面で）：体験版の AppID で Stats が使えるか（Steamworks のドキュメントは体験版について実績にしか触れていない）。実績上限100の緩和条件＝Profile Features のしきい値。

### feature-46

**タイトル画面の残り（クレジット画面）**

- 背景：タイトル画面そのものは入った（起動→扉が開く動画→店内のメニュー。仕様 → [title.md](gdd/title.md)）。残るのは、クレジット画面。置き場はタイトルのメニューから設定画面の末尾へ移した（[settings.md](gdd/settings.md) クレジット、2026-09-20）＝タイトルの板からクレジットの項目を外し、並びをマニュアル→クロニクル→設定にする作業も含む。
- クレジット：素材の権利表記。タイトルのメニューに項目だけ置いてあり、受け口が無く押せない状態。画面に出す内容は [credits.md](sales/credits.md) の「ゲーム内クレジットに出すもの」が正本で、そこを読んで並べるだけにする。台帳の整備自体は済んでいるが、根拠が取れていないライセンスが残っている（feature-54）。リリース前が締め切り。
- クレジット画面の作り（決めたこと）：新規シーン `godot/presentation/credits/` を1枚。設定画面の末尾の板から開く＝タイトルからも盤のシステムメニュー経由でも設定の中から届く。盤の上でも進行は止めない（設定画面と同じ）。戻るは左下の木の板ボタンで、位置と大きさはセレクトと同じ規則に揃える（[stage_select.md](gdd/stage_select.md)）。地は中立の暗色（起動スプラッシュと同じ `#0d1925`）＝操作の道具は酒場の物にしない（[title.md](gdd/title.md)）。押せる物だけが木の板、という様式は保つ。見た目は実物を見てから詰める。文言は `menu.csv` に足す（キーは `ui.<画面>.<項目>` → [i18n.md](tech/i18n.md)）。
- 該当：`godot/presentation/settings/settings_screen.gd`（開き口の板）・`godot/presentation/credits/`（新規）・`godot/presentation/title/title_screen.gd`（項目を外す・並べ替え）・`godot/data/i18n/menu.csv`・`doc/gdd/settings.md`。関連＝feature-66〜69（UI文言の i18n キー化）。戻るの位置は設定画面を手本にする。着手の引き金＝配布ビルドが見えてきたとき。

### feature-62

**販売チャネルごとの機能を乗せる（プラットフォーム層）**
- ゴール：本体は所有権チェック・実績・Stats をチャネル非依存の口で呼ぶだけで、どのチャネルのビルドでもその口が正しく動く。エディタ実行でも実績の動作が確認できる。
- 背景：チャネルの判定そのものは `godot/infrastructure/platform/build_info.gd` が持つ（[build.md](tech/build.md)）。その上に乗るチャネル固有の機能がまだ無い。評価ランクの実績発火（feature-40）、entitlement による DLC 解放（feature-13）が控えている。
- 設計：
  - 切り替えの鍵は `BuildInfo.channel()` と `edition()`。アダプターはチャネルと1対1で、steam / steam-demo / itch / booth / dev の5つ。「その他」のまとめ枠やフォールバックは作らない。itch と booth と dev の中身が今は同じでも、共通化せず別々に持つ。
  - アダプターは薄く、機能ごとの部品を組み合わせるだけ。部品（ローカルの実績ファイル・常に所有扱いの所有権チェック・何もしない Stats など）は複数のアダプターで使い回す。
  - 本体が見る口は3つ。所有権チェック `owns(content_id) -> bool`、実績の保管庫 `unlock(id)` / `is_unlocked(id)` / `unlocked_ids()`、Stats の記録。
  - 実績はゲーム本体の機能で、Steam はその保管先の1つ。Steam 版は Steamworks を保管庫にし（読み書きとも API で行う）、ローカルファイルを持たない。itch / booth / dev は実績専用のファイルに保存する。進捗セーブとは別のファイル。
  - Steam 体験版（`steam,demo`）は実績を Steam に立てず実績専用ファイルに溜め、製品版の初回起動でそのファイルを Steamworks に流し込む（Valve の推奨に沿う）。
  - Stats は Steam 版だけが送る。他のチャネルは送り先が無く集計も要らないので何もしない。
  - Steam 版で Steamworks の初期化に失敗したときは「Steam から起動してください」と出して終了する。
  - チャネルと機能の対応：

    | 機能 | steam | steam-demo | itch / booth / dev |
    |---|---|---|---|
    | 所有権チェック | Steam DLC に問い合わせ | 常に所有 | 常に所有 |
    | 実績の保管庫 | Steamworks | 実績専用ファイル（製品版の初回起動で Steam へ） | 実績専用ファイル |
    | Stats | Steam に送る | Steam に送る（体験版 AppID で使えれば） | 何もしない |

- 対応：(1) 上の設計を `doc/tech/platform.md` に新設して書く（狙い・切り替えの鍵・アダプターと部品の構造・チャネル×機能の表・本体が見る口・体験版からの引き継ぎ・設計の未確定）。(2) `godot/infrastructure/platform/` にインターフェース・アダプター5つ・部品を置き、`channel()` と `edition()` から選ぶ場所を1か所にする。(3) 実績専用ファイルの置き場と形式を決める。
- 設計の未確定：体験版の AppID で Stats が使えるか（AppID 取得後に管理画面で確認）。Steam Cloud のセーブ置き場をコードで切り替えるのか、Steamworks 側の設定（Auto-Cloud）だけで済むのか。
- 該当：`godot/infrastructure/platform/`・`doc/tech/platform.md`（新規）・`doc/tech/build.md`・`doc/sales/monetization.md`。前提＝feature-40（GodotSteam 導入）・feature-13（entitlement）。

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

### feature-118

**陣形スキル⑨マジックアロー（弓兵＋魔法兵・大きい方＋10・貫通0.5・射程は長い方＋1）**
- ゴール：弓兵と魔法兵が隣接しているとき、弓兵から「2体の攻撃力の大きい方＋10・貫通0.5」の単体射撃が「2体の射程上限の長い方＋1」まで届く。届かなかった相手に魔法兵級の一撃が届く。
- 背景：[formations.md](gdd/formations.md) ⑨ で仕様確定。escort（count 2）の流用だが、威力の元と射程を「発動者」ではなく「参加者の性能から引く」のが新しい。対空／対地の切り替え（`attack_vs`）と貫通の上書き（`pierce_override`）は④トリックショットで入っている。
- 対応：(1) `RECIPES` に `magic_arrow`（leader＝archer/hunter/elf、member＝wizard/witch、shape `escort`、count 2、effect `single`、`pierce_override` 0.5、`attack_vs` "target"、`attack_from` "max_plus"（値 10）、`range_from_stats` "max_plus"（値 1）、下限なし）。(2) `_skill_attack_breakdown` に「参加者の攻撃力の最大＋定数」を元にする経路（兵数・レベル・包囲・地形は発動者のもの）。(3) `available_for`／`_in_range_cells` で射程を参加者の `attack_range` の最大＋1 から求める（レシピの固定 `range` と排他）。(4) 演出は④と同じ単体シーケンス（`magic_arrow_impact.png`）。(5) `skills.csv`。(6) テスト＝威力の元の選び方（地上はウィザード40＋10／空はエルフ60＋10）・射程（アーチャー＋ウィザード＝5・エルフ＝6）。
- 演出まわり：カットイン `godot/assets/formations/magic_arrow.png`（スキルごと1枚の規約解決。射手ごとに分けるなら④と同じく `cutin_per_caster` と `magic_arrow_{skin}.png`）。効果音 `godot/assets/sfx/magic_arrow.ogg`（発動）と `magic_arrow_hit.ogg`（着弾）を置き、[audio/sfx.md](audio/sfx.md) の発火点カタログと権利台帳に載せる。クロニクルの陣形スキル章＝レシピの図は `escort` の既存配置で足りる（代表は先頭スキン＝アーチャー＋ウィザード）（`godot/presentation/chronicle/recipe_figure.gd`）。絵と音は置けば出る（無ければ飛ばす）ので実装の前提ではないが、この項目の一部として扱う。
- 該当：`godot/domain/formation/formation.gd`・`godot/domain/formation/formation_option.gd`・`godot/domain/formation/formation_resolver.gd`・`godot/presentation/board/board_impact_renderer.gd`・`godot/data/i18n/skills.csv`・`godot/tests/small/domain/test_formation.gd`。

### feature-119

**陣形スキル⑥アローレイン（弓兵3体の三角・半径2の19ヘクス・発動者ベース・貫通なし）**
- ゴール：スリンガー系を除く弓兵3体が三角になると、発動者の射程上限まで届く半径2の面攻撃が撃てる。参加者は当たらず、他の味方は当たる。飛行には対空値。
- 背景：[formations.md](gdd/formations.md) ⑥ で仕様確定。①と同型で、面の半径が2・射程が発動者の性能依存・対空／対地の切り替えあり、貫通は発動者依存（弓＝0）のまま。
- 対応：(1) `RECIPES` に `arrow_rain`（leader／member＝archer/hunter/elf、shape `triangle`、count 3、effect `area`、`radius` 2、`range_from` "any"、`range_from_stats` "leader"＝発動者の `attack_range`、`attack_vs` "target"）。(2) `blast_cells` は `radius` を読むだけで済むはず＝19ヘクスになることをテストで確認。(3) 着弾演出の順送り（中心から外へ）が半径2でも成り立つか `board_impact_renderer` を確認。プレビュー（桃の面）も半径2で出す。(4) `skills.csv`・`arrow_rain_impact.png`。(5) テスト＝三角の成立（ハンター＋アーチャー＋エルフ）・スリンガーの除外・面の広さ・参加者の除外。
- 演出まわり：カットイン `godot/assets/formations/arrow_rain.png`（スキルごと1枚の規約解決。射手ごとに分けるなら④と同じく `cutin_per_caster` と `arrow_rain_{skin}.png`）。効果音 `godot/assets/sfx/arrow_rain.ogg`（発動）と `arrow_rain_hit.ogg`（着弾）を置き、[audio/sfx.md](audio/sfx.md) の発火点カタログと権利台帳に載せる。クロニクルの陣形スキル章＝レシピの図は `triangle` の既存配置で足りる（`godot/presentation/chronicle/recipe_figure.gd`）。絵と音は置けば出る（無ければ飛ばす）ので実装の前提ではないが、この項目の一部として扱う。
- 該当：`godot/domain/formation/formation.gd`・`godot/domain/formation/formation_option.gd`・`godot/domain/formation/formation_resolver.gd`・`godot/presentation/board/board_impact_renderer.gd`・`godot/data/i18n/skills.csv`・`godot/tests/small/domain/test_formation.gd`＋`godot/presentation/board/hex_board_3d.gd`（面のプレビュー）。

### feature-120

**陣形スキル⑤シールドウォール（ノービス以外の歩兵3体以上の一列・参加者の防御 ×(1＋0.05×人数)）**
- ゴール：歩兵が3体以上一直線に並んでいるとき、列のどれからでも撃てて、列の全員の防御が人数ぶん上がる（3体 ×1.15）。次の自軍ターン開始まで。膠着の待機の上位互換で、効果は薄くてよい。
- 背景：[formations.md](gdd/formations.md) ⑤ で仕様確定。②グレイスの持続バフの器（状態補正エントリ）に、スコープ「参加者だけ」と対象「防御だけ」を足す。形は `cluster` の直線版。
- 対応：(1) `RECIPES` に `shield_wall`（leader／member＝fighter/vanguard/knight/forest_knight/dwarf/samurai/magic_knight＋lancer（type が入ったら）、shape `line`、count 3、effect `buff`、`buff_op` "mul"、`buff_scope` "participants"、`buff_target` "def"、`buff_value` 1.15、`buff_value_per_extra` 0.05、`duration_turns` 1）。(2) `FormationOption.Shape` に `LINE`：発動者を含むヘックスの3軸のどれかで途切れず連なる参加者を集める（人数は選べない）。(3) `_buff_entry`／`BattleState` の状態補正に `scope: participants`（駒の集合）と `target: def` を通す＝②は `team`・`both` のまま。(4) 見た目は列の駒の足元の光（`aura_overlay` の駒単位の光を流用）。カットインは規約解決。(5) `skills.csv`。(6) テスト＝直線の判定（3軸・折れ線は不成立・ノービス除外）・人数で伸びる補正・参加者以外に乗らないこと。
- 演出まわり：カットイン `godot/assets/formations/shield_wall.png`（スキルごと1枚の規約解決。射手ごとに分けるなら④と同じく `cutin_per_caster` と `shield_wall_{skin}.png`）。効果音 `godot/assets/sfx/shield_wall.ogg`（発動）を置き、[audio/sfx.md](audio/sfx.md) の発火点カタログと権利台帳に載せる（着弾が無いので `_hit` は置かない＝②グレイスと同じ）。クロニクルの陣形スキル章＝形 `line` は新しいので `LAYOUTS` に一直線の3ヘクスを足す（`godot/presentation/chronicle/recipe_figure.gd`）。絵と音は置けば出る（無ければ飛ばす）ので実装の前提ではないが、この項目の一部として扱う。
- 該当：`godot/domain/formation/formation.gd`・`formation_option.gd`・`formation_resolver.gd`・`godot/domain/battle_state.gd`・`godot/domain/combat/combat.gd`（集計の scope）・`godot/presentation/ui/aura_overlay.gd`・`godot/data/i18n/skills.csv`・`godot/tests/small/domain/test_formation.gd`。

### feature-121

**陣形スキル⑦マジックシールド（魔法兵＋占領兵の隣接・7ヘクスの結界・防御 +10×発動者兵数・貫通無効）**
- ゴール：ウィザード／ウィッチと占領兵が隣接しているとき、どちらからでも発動者中心の7ヘクスに結界が張れる。中に居る味方は実効防御に 10×発動者の残兵数 が足され、貫通を受けない。入れば効き、出れば切れる。次の自軍ターン開始まで。
- 背景：[formations.md](gdd/formations.md) ⑦ で仕様確定。状態補正の器に **地帯（zone）** のエントリを新設する最初の実体（[combat.md](gdd/combat.md) 状態補正に注記済み）。貫通無効は乗算・加算の外＝貫通の段で攻撃側の `pierce` を 0 にするフラグ。
- 対応：(1) `RECIPES` に `magic_shield`（leader／member＝wizard/witch × cleric/priest/bishop/paladin の両向き、shape `escort`、count 2、effect `buff`、`buff_scope` "zone"、`zone_radius` 1、`buff_op` "add"、`buff_target` "def"、`buff_value_per_troop` 10、`pierce_immune` true、`duration_turns` 1）。(2) `BattleState` の状態補正エントリに `zone`（中心ヘックス＋半径・陣営）を足し、`Combat` の集計で「対象の駒が地帯の中に居るか」を見る。(3) `Combat` の貫通の段で、防御側に `pierce_immune` の地帯が効いていれば攻撃側の `pierce` を 0 として扱う。(4) 見た目＝結界の7ヘクスに薄い光の床（`aura_overlay` に地帯の床を足す。持続の間出しておく）。(5) `skills.csv`。(6) テスト＝加算（満員で +80）・貫通無効（ウィザードの攻撃が半減しない）・出入りで効く／切れる・満了。
- 演出まわり：カットイン `godot/assets/formations/magic_shield.png`（スキルごと1枚の規約解決。射手ごとに分けるなら④と同じく `cutin_per_caster` と `magic_shield_{skin}.png`）。効果音 `godot/assets/sfx/magic_shield.ogg`（発動）を置き、[audio/sfx.md](audio/sfx.md) の発火点カタログと権利台帳に載せる（着弾が無いので `_hit` は置かない＝②グレイスと同じ）。クロニクルの陣形スキル章＝レシピの図は `escort` の既存配置で足りる（両向きなので代表は先頭スキン＝ウィザード＋クレリック）（`godot/presentation/chronicle/recipe_figure.gd`）。絵と音は置けば出る（無ければ飛ばす）ので実装の前提ではないが、この項目の一部として扱う。
- 該当：feature-120 と同じ＋`godot/domain/combat/combat.gd`（貫通の段）・`godot/presentation/ui/aura_overlay.gd`。前提＝feature-120（scope の拡張を先に）。

### feature-122

**陣形スキル⑧バックスタブ（シーフ＋対象を挟んで正反対の味方1体・貫通0.5・着弾後に元の位置へ戻る）**
- ゴール：シーフが敵に隣接し、その敵を挟んで正反対のヘックスに味方が居るとき、貫通0.5・反撃なしの一撃を刺し、シーフはこのターンの移動開始位置へ戻る。参加者はシーフとその味方だけで、幾何で決まる。
- 背景：[formations.md](gdd/formations.md) ⑧ で仕様確定。形 `backstab` は対象を挟んだ正反対（対象からの方向ベクトルが逆）を見る＝④の `spotter` の親戚。着弾後に発動者の位置を戻すのは初めての処理で、移動開始位置を `BattleState` が覚えている必要がある。
- 対応：(1) `RECIPES` に `backstab`（leader＝thief、member＝任意（`member_skins` 空＝種別不問の印）、shape `backstab`、count 2、effect `single`、`range` 1、`pierce_override` 0.5、`attack_vs` "target"、`return_to_origin` true）。(2) `FormationOption.Shape` に `BACKSTAB`：対象候補は発動者の隣接する敵のうち、`target + (target - leader_pos)` に味方が居るもの。相方はその1体。(3) `FormationResolver.resolve` の最後に、`return_to_origin` なら発動者を移動開始位置へ戻す（経路・コスト・足止め不問。`MatchController` が持つ移動前の位置を `SkillCast` に渡す）。中断セーブとリプレイで位置が一致することを確認。(4) 演出＝跳んで刺して戻る（駒の移動アニメを2回。絵は `backstab_impact.png`）。(5) `skills.csv`。(6) テスト＝対角の判定（隣り合う2体は不成立）・相方が幾何で決まる・戻り・飛行相手は対空10。
- 考慮外：他の斥候（ハーフリング等）への拡張。撃破後の再攻撃（検討して不採用）。
- 演出まわり：カットイン `godot/assets/formations/backstab.png`（スキルごと1枚の規約解決。射手ごとに分けるなら④と同じく `cutin_per_caster` と `backstab_{skin}.png`）。効果音 `godot/assets/sfx/backstab.ogg`（発動）と `backstab_hit.ogg`（着弾）を置き、[audio/sfx.md](audio/sfx.md) の発火点カタログと権利台帳に載せる。クロニクルの陣形スキル章＝形 `backstab` は新しいので `LAYOUTS` に発動者と対角の味方、`TARGETS` に間の敵ヘクス（ゴブリンの駒）を足す。相方は種別不問（`member_skins` 空）なので図と未解放の黒塗りの代表を1体決める（`godot/presentation/chronicle/recipe_figure.gd`）。絵と音は置けば出る（無ければ飛ばす）ので実装の前提ではないが、この項目の一部として扱う。
- 該当：`godot/domain/formation/formation.gd`・`godot/domain/formation/formation_option.gd`・`godot/domain/formation/formation_resolver.gd`・`godot/presentation/board/board_impact_renderer.gd`・`godot/data/i18n/skills.csv`・`godot/tests/small/domain/test_formation.gd`＋`godot/application/match_controller.gd`・`godot/domain/battle_state.gd`・`godot/domain/formation/skill_cast.gd`。

### feature-124

**陣形スキル⑩カウンター（ノービス以外の歩兵2体の隣接・参加者の攻撃 ×1.5＝反撃強化）**
- ゴール：歩兵2体が隣接しているとき、どちらからでも撃てて、2体の攻撃が次の自軍ターン開始まで ×1.5 になる。参加者は行動完了なので効くのは敵ターンの反撃だけ。
- 背景：[formations.md](gdd/formations.md) ⑩ で仕様確定。feature-120（⑤シールドウォール）の器＝状態補正のスコープ「参加者だけ」に、対象「攻だけ」を足すだけ。形は `escort`（count 2）の流用。敵AIは陣形の効果を読まない（[ai.md](gdd/ai.md) 基本方針に追記済み）ので AI 側の変更は無い。
- 対応：(1) `RECIPES` に `counter`（leader／member＝fighter/vanguard/knight/forest_knight/dwarf/samurai/magic_knight＋lancer、shape `escort`、count 2、effect `buff`、`buff_op` "mul"、`buff_scope` "participants"、`buff_target` "atk"、`buff_value` 1.5、`duration_turns` 1）。(2) `_buff_entry`／`Combat` の集計で `target: atk` を通す（⑤は def、②は both）。(3) 見た目は2体の足元の光（⑤と同じ）。(4) `skills.csv`。(5) テスト＝2体固定（3体目は参加しない）・ノービス除外・反撃に ×1.5 が乗り、自軍ターン開始で切れること・AI の戦果計算に乗らないこと。
- 演出まわり：カットイン `godot/assets/formations/counter.png`（スキルごと1枚の規約解決。射手ごとに分けるなら④と同じく `cutin_per_caster` と `counter_{skin}.png`）。効果音 `godot/assets/sfx/counter.ogg`（発動）を置き、[audio/sfx.md](audio/sfx.md) の発火点カタログと権利台帳に載せる（着弾が無いので `_hit` は置かない＝②グレイスと同じ）。クロニクルの陣形スキル章＝レシピの図は `escort` の既存配置で足りる（`godot/presentation/chronicle/recipe_figure.gd`）。絵と音は置けば出る（無ければ飛ばす）ので実装の前提ではないが、この項目の一部として扱う。
- 該当：feature-120 と同じ＋`godot/domain/ai/`（戦果計算が状態補正を除くことの確認）。前提＝feature-120。

### feature-132

**幕間の印 `damaged` のモチーフを決めて描く**
- ゴール：依頼書の幕間の印3枚が揃い、連戦の話を開いたときに「傷ついたまま次へ出る」と読める絵が1枚出る。
- 背景：`refill`（宿のベッド）と `revive`（有翼の十字）は描けたが、`damaged` だけモチーフが決まっていない。試した案と外した理由＝断ち切れた革帯（何が起きたか読めない）／刃こぼれの剣（欠けは小さくすると輪郭のノイズになる）／ひび割れた盾（`predator`（弱者狙い）の割れた盾と同じ構図）／松明（暗いだけで連戦に結びつかない）／血の染みた包帯（手当てをしたとも読める）。
- 対応：モチーフを決め、[icons.md](art/icons.md) §3 の表と SUBJECT を書いて生成する。要件＝面が広くて小さくしても輪郭が残る／`refill`（横長・木と布）・`revive`（縦長・金と白）と型と材質が分かれる／AI の特性アイコンと構図が被らない／「休んだ」「手当てをした」と読めない。
- 考慮外：`refill`・`revive` の描き直し。印に語を添える案（絵だけで通す方針を先に試す）。
- 該当：`godot/assets/icons-src/interlude/damaged/`・`godot/assets/icons/interlude/damaged.png`・[icons.md](art/icons.md) §3。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

### refactoring-22

**陣形スキルの発動者を指す `leader` を `caster` に改名する**
- ゴール：発動者を指す名前がコード全体で `caster` に揃い、同じ駒を `leader_id` と `caster` の2語で呼ぶ箇所が無い。doc の「発動者」とコードの語が1対1で対応している。
- 背景：レシピの `leader_skins`／`member_skins` の対から始まり、`FormationOption.leader_id`・`SkillResult.leader_id`・`BattleState` まで `leader` が広がった。一方で発動結果の `SkillResult.caster`・`SkillCast.caster` と演出側は `caster` で、同じ駒を2語で呼んでいる。「leader」は隊長・号令役を思わせるが、意味は「そのスキルを撃つ駒」で、doc の発動者に当たる語は `caster`。doc に `leader` という語は出てこない。
- 対応：`leader_skins` → `caster_skins`、`leader_id` → `caster_id`、`leader_pos` → `caster_pos` のように機械的に置換する。`member_skins` はそのまま。`shot_screen` の `--leader`／`--pre-leader` も `--caster`／`--pre-caster` に揃え、[tech/tools.md](tech/tools.md) の起動例を直す。テストは名前の追従だけ。
- 考慮外：挙動の変更。`member` の呼び名。
- 該当：`godot/domain/battle_state.gd`・`godot/domain/formation/formation.gd`・`godot/domain/formation/formation_choice.gd`・`godot/domain/formation/formation_option.gd`・`godot/domain/formation/formation_resolver.gd`・`godot/domain/formation/skill_result.gd`・`godot/presentation/chronicle/formations_chapter.gd`・`godot/presentation/chronicle/units_chapter.gd`・`godot/tools/marketing/shot_screen.gd`・`godot/tests/small/application/test_match_controller.gd`・`godot/tests/small/domain/test_formation.gd`・`godot/tests/small/domain/test_skill.gd`・[tech/tools.md](tech/tools.md)。

### refactoring-21

**会話の顔の `portrait` スロットを廃止する**
- ゴール：会話パネルの顔が `map` の絵だけで決まり、`portrait` という差し込み口がコードと doc から消えている。
- 背景：`portrait` は画像の差し込み口として用意してあるが、画像は置かれていない。盤に出ないキャラの顔も、会話専用のスキンを足して `map` に絵を置けば出せるので、使う見込みが無い。`UnitSkin.portrait_label()` もどこからも呼ばれていない。
- 対応：autowire のスロット一覧と会話の顔の解決順から `portrait` を外し、`portrait_label()` を消す。doc 側はスロット表・会話の顔の項・盤に出ない話者の注記・胸像の将来案を `map` 一本の説明に直す。
- 考慮外：`combat`・`combat_effect` スロット。会話パネルの見せ方（倍率・透明余白の切り抜き）。
- 該当：`godot/data/units/skin_catalog.gd`・`godot/data/units/unit_skin.gd`・`godot/presentation/ui/conversation_panel.gd`・[art/overview.md](art/overview.md)・[art/units.md](art/units.md)・[campaign/authoring.md](campaign/authoring.md)・[campaign/ancientruins1-mine-monsters.md](campaign/ancientruins1-mine-monsters.md)・[gdd/uiux.md](gdd/uiux.md)。

### refactoring-18

**兵種 `emplacement` の内部IDを `war_machine` に改名する**
- ゴール：コード・データ・ドキュメントで兵種を指す文字列が `war_machine` に統一されていて、プレイヤー向け表示名（日本語「兵器」・英語「War Machine」）と一致している。
- 背景：内部IDは `emplacement`（設置物）だが、プレイヤー向け表示名は「兵器 / War Machine」。他の兵種（infantry・archer・mage …）は内部IDと表示名が対応しているのに、ここだけずれている。IDを見ても何を指すか分かりにくい。
- 対応：`emplacement` を `war_machine` に一括置換する。CSV・JSON・GDScript・ドキュメントが対象。i18n キーも `unit_group.emplacement.name` → `unit_group.war_machine.name` に変える。
- 該当：`godot/data/units/unit_type.csv`・`unit_skin.csv`・生成物（`unit_type.json`・`unit_skin.json`）・`godot/data/i18n/units.csv`・`godot/data/i18n/manual.csv`・GDScript で `emplacement` を参照する箇所・`doc/gdd/units.md`。

### refactoring-15

**陣形スキルのドリフト検出（formations.md の一覧 ⇄ `Formation.RECIPES` ⇄ `skills.csv`）**
- ゴール：レシピが doc・code・翻訳のどれか1つにだけ増減したとき、テストが落ちて気づける。
- 背景：正本は [formations.md](gdd/formations.md)「一覧（決まった項目）」の表A/表B、実行時は `godot/domain/formation/formation.gd` の `RECIPES`（ハードコード）、表示名は `godot/data/i18n/skills.csv` の `recipe.<id>.name/desc`。3か所が別々に育つ（④〜⑨は doc だけ、陣形①〜③の `desc` が無い、混沌の2本は code に無い）。CSV/JSON 化は見送り（[architecture.md](tech/architecture.md) 入れ子データはコードが持つ）なので、照合で守る。
- 対応：(1) `godot/tools/` に formations.md の表A/表Bを読む小さなパーサ（`| # | id | …` の行を拾い、id・人数・形・射程・実装列を辞書に）。(2) GUT テスト `test_formation_catalog.gd`：表の id のうち実装列が「済」のものは `RECIPES` に在り、`count`・`shape`・`range` が一致すること／`RECIPES` の id はすべて表に在ること／`skills.csv` に `recipe.<id>.name` と `.desc` が在ること（ユニットスキルは skills.md の見出しで同様に）。(3) 陣形①〜③の `desc` を `skills.csv` に足す。(4) 表の書式を崩すと落ちるので、formations.md の一覧の冒頭に「列は固定」の注意を置く（記入済み）。
- 考慮外：効果の数値（威力・倍率）の照合＝表現が文なので見ない。CSV/JSON 化。
- 該当：`godot/tools/`・`godot/tests/small/domain/test_formation_catalog.gd`・`godot/data/i18n/skills.csv`・`doc/gdd/formations.md`・`doc/tech/testing.md`（テストの位置づけを1行）。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- **隠し駒（視線に入るまで盤に出ない敵）。** 荷の陰・物陰に潜む敵を、味方の索敵に入るまで盤に出さない。出た瞬間は動かず、次の敵ターンから襲う＝1発は必ず受けるが、受けるのは兵数だけ。確定ゲームの方針（[ai.md](gdd/ai.md) 特性と部隊はプレイヤーに見せる）に穴を開けるので、入れるなら条件を守る＝食らっても駒を失わない／覚えた後にも選択が残る／やり直しが安い／潜んでいたことが物語の絵になる／冒険譚の中で1回だけの手口にする。戦闘前の会話で警告を1行置く。実装は駒の不可視・視線で露見・露見まで AI が動かない・描画の4点。邪神三部作 第1部 st2（倉庫）の検討で出た案。今回は見送り、崩せる積み荷（既存のバリケード型）で代替した。
