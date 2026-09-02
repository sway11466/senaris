# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=5 / feature=100 / refactoring=1.

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

### feature-96

**勝ち確定のフィニッシュ演出**
- ゴール：どの勝ち方（戦闘・陣形スキル・本拠占領）でも「寄る→スロー→白フラッシュ→戦果票」の同じ型で決着が締まり、勝ちの瞬間に手応えがある。
- 背景：いまはとどめの一手も通常と同じ演出で流れ、閉じた直後に戦果票が出る＝あっさり終わる。仕様 → [uiux.md](gdd/uiux.md) §決着の合図。
- 対応：domain の決着判定を演出開始前に presentation へ渡し、戦闘シーン（最後の一斉射のスロー＋寄せ）・盤の着弾（スロー＋カメラ寄せ）・占領（カメラ寄せ＋旗＋白フラッシュ）に締めの型を実装する。白フラッシュから戦果票へ繋ぐ入りも合わせて直す。
- 該当：`godot/presentation/combat/combat_scene.gd`・`godot/presentation/board/board_impact_renderer.gd`・`godot/presentation/board/hex_board_3d.gd`・`godot/presentation/ui/result_banner.gd`・`godot/presentation/main/main.gd`・[uiux.md](gdd/uiux.md)。

### feature-92

**ステージが更新されている中断セーブをプレイヤーに知らせる**
- ゴール：セーブを作ったあとにステージを直した枠が、選ぶ前に見て分かり、選んだときにも一度確認が入る。
- 背景：ステージ定義が変わっても差分はそのまま適用して再開を妨げない方針だが、黙って適用すると盤が前と違う理由がプレイヤーに分からない。枠の一覧表示は `_row_text` 一本で、ロード時の確認はいまタイトルの「冒険の続き」経由では出ない（失う盤が無いため）。
- 対応：セーブの印と今のステージ定義の印を比べ、違う枠は一覧の行に更新されている旨を添える。その枠を選んだときだけ確認を挟む（印が一致する枠のロードは今のまま）。
- 該当：`godot/presentation/ui/save_slot_panel.gd`・`godot/presentation/main/main.gd`・`godot/data/i18n/`・`doc/tech/gamesystem.md`。セーブの印は meta の `stage_digest`、今の定義の印は `StageDigest.of_file`。

### feature-89

**グレイスの効果を参加人数で伸ばす**
- ゴール：隣接クラスタが5体より多いとき、多いぶんが効果の強さになっている（頭数を集めた判断が報われる）。
- 背景：いまは5体以上で成立し、発動すると隣接クラスタ全員が行動完了になる＝人数が増えても効果は同じで、消費だけが増える。集まっているほど損をする形になっている。案は最低5体を据え置き、1体増えるごとに補正 +0.05（5体＝×1.30／8体＝×1.45）。
- 対応：`Formation.RECIPES` の `grace` に人数連動の値を持たせ、`_buff_entry` が参加人数から補正を決める。`count` 固定でないレシピは初なので、他のレシピへ波及しない形で入れる。formations.md ②の表と、レシピ表の「効果」の書き方も更新する。
- 該当：`godot/domain/formation/formation.gd`・`godot/domain/battle_state.gd`（`_buff_entry`）・`godot/tests/unit/test_formation.gd`・`doc/gdd/formations.md`。

### feature-13

**entitlement（DLC所有）判定によるステージ解放**
- 背景：ステージセレクトの解放は現状「クリア連鎖」だけで、有料DLC（冒険譚）の所有チェック（entitlement）が未配線＝販売時に「持っていれば解放」を判定できない（[stage_select.md](gdd/stage_select.md)）。Steam DLC 連携が前提。解放ゲート `_is_satisfied` は `cleared` のみ対応で、entitlement を含む未知条件は locked 扱い。表示側の `unlock_text` には entitlement 条件を「追加コンテンツ」と示す分岐が既にあるが、実際の充足判定の口が無い。
- 対応：所有判定の口を `CampaignProgress` に足し、DLC冒険譚は entitlement 充足で解放。Steam 側は GodotSteam 導入時に配線（それまではローカルで常時充足扱い等の切替）。
- 該当：`godot/application/campaign_progress.gd`・`godot/presentation/select/`・`doc/gdd/stage_select.md`。着手の引き金＝配布ビルド（parking lot「Steam 配布の段取り」と連動）。

### feature-16

**移動/カメラ演出の速度設定・敵ターンスキップ・演出の適用範囲拡張**
- 背景：敵の全行動を見せる（移動アニメ＋カメラ追従）ぶん、敵が多いターンは総時間が伸びる。アニメ速度の設定（高速／標準／オフ）と敵ターンのスキップは SLG の定番だが、速度はどれもコード内の定数のままで、スキップ導線も無い（[uiux.md](gdd/uiux.md) システムメニュー・敵ターンのカメラ）。設定画面と設定の永続化（`SettingsStore`）は言語だけを持つ形で入っているので、値の置き場はできている（[settings.md](gdd/settings.md)）。また演出には未対応の隙間がいくつかある。
- 対応：(1) 設定画面に演出速度の項目を足し、移動アニメ速度（`MOVE_ANIM_SEC_PER_HEX`／`MOVE_ANIM_MAX_SEC`）とカメラ追従（`FOCUS_PAN_SEC`）を設定値から引く。戦闘演出の速度（[combat_scene.md](tech/combat_scene.md) テンポ・スキップの「フル／短縮／オフ」3段）も同じ設定に乗せる＝置き場所が決まっていないのはこれだけで、AIターンの短縮は仕様だけあって未実装。(2) 敵ターンのスキップ（キー／ボタンで残りを一気に最終状態へ）。(3) 出撃・降車は経路を持たずポップして現れる＝拠点／輸送から目的マスへの1歩スライドで見せる（経路探索は不要）。(4) カメラ追従は行動主体の現在位置だけを見る＝長距離移動でアニメ中に終点が画面外へ出るケースの追随、攻撃で対象も画面に含める配慮は未対応（現状は移動距離が短く実害小）。
- 該当：`godot/presentation/board/hex_board_3d.gd`（`focus_camera_on`／移動アニメ）・`godot/application/match_controller.gd`（ターンのテンポ・スキップ）・`godot/infrastructure/save/settings_store.gd`・`godot/presentation/settings/settings_screen.gd`・`doc/gdd/uiux.md`。着手の引き金＝敵ターンが長く感じ始めたら。

### feature-27

**タイトル名「Senaris」の確定手続き**
- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済みだが、確定前の手続きが残っている。すべてオーナー側の手作業。
- 開発元（2026-08-12 決定）：屋号は `craftkobo`。法人ではなく個人事業主として出品する＝Steam の契約名義は本名、公開される表示名は屋号。開業届は提出済み。ドメイン `craftkobo.com` は空きを確認済みで取得予定＝開発元用（プロダクト用の `senaris.in` とは別。問い合わせ先メールは開発元側に置く＝ゲームが増えても窓口が1つで済む）。銀行口座は未開設で、Steam の受取名義と一致すること・海外送金を受け取れることを確認してから作る。米国向けの税務書類はマイナンバーを外国TINとして出すと源泉徴収が下がる。
- Steam の名前まわり（2026-08-12 調査）：`steamcommunity.com/id/senaris` は他者が使用中だが、これは一般ユーザーがプロフィールページに付ける短縮URLで、ゲームとは無関係＝実害なし。ゲームのストアページは `store.steampowered.com/app/<AppID>/…` の形で、AppID は Valve が採番するため他者のユーザー名に影響されない。開発元ページ `store.steampowered.com/publisher/senaris` は未使用だが、これは早い者勝ちで押さえるものではなく登録後に申請して作るページ。実際に競合しうるのはゲーム名そのもので、Steamworks 登録時の審査に掛かる＝下記 (1) の商標クリアランスと同じ話。
- サイト：仕様は [site.md](sales/site.md)、配信先の決定は [ADR-0005](adr/ADR-0005-site-hosting-cloudflare-workers.md)。ドメイン取得・DNS・配信構成は済んでいる。中身を作るのは feature-95。
- 対応：(1) 商標クリアランス＝第9類・第41類で US(USPTO)／EU(EUIPO)／日本(J-PlatPat) の各DBを正式確認（ドメインとは別作業。ドメインが空いていても商標が先に取られていることはある）。(2) SNSハンドル確保（X／Bluesky／Discord 等）。(3) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`・`doc/sales/site.md`・`site/`。着手の引き金＝配布が見えてきたとき（parking lot「Steam 配布の段取り」と連動）。サイトのランディングページはストアページ（feature-53 と同じ段）のあと。

### feature-48

**羽ばたきの素材を採り直す**
- 背景：`move_flight` に当てている上着の布音（Modern Cloth Foley の Whoosh Flutter）が、羽ばたきに聞こえない。素材が 0.42 秒あるのに間隔が 0.30 秒で、常に 0.12 秒ぶん重なって連続音になるため。翼を打つ一打ずつには分かれない。飛空艇（`move_propeller`）はこの連続音の性質をそのまま利用して同じ素材から作ったので、飛行側だけが宙に浮いている。
- 対応：一打で完結する素材に差し替える。Sonniss バンドルには使える羽ばたきが無いことが確認済み（[doc/audio/sfx.md](audio/sfx.md) の「バンドルに録音が無かったもの」）。外部の素材集を1本買うか、自録り（うちわ・厚紙・畳んだ布で空気を打つ）に切り替える。長さは 0.30 秒より短く収めて、重ならずに一打ずつ聞こえる形にする。ペガサスからレッドドラゴンまで1つで賄うので、翼の大きさが特定できない中庸な質感を狙う。
- 該当：`godot/assets/sfx-src/move_flight_recipe.txt`・`godot/assets/sfx/move_flight.ogg`・`godot/assets/sfx-src/credits.md`・`godot/data/audio/sfx_catalog.gd`（間隔）・`doc/audio/sfx.md`。着手の引き金＝素材を調達したとき。

### feature-36

**陣形カットインの入り方を絵の構図に合わせて詰める**
- 背景：カットインの入り方は絵が無い時期に決めた暫定で、フェード＋わずかなズーム（`ZOOM_FROM=1.06`）を3レシピ共通で掛けている。絵が揃ったいま、構図と噛み合っているかを見ていない。トリニティノヴァとディバインジャッジメントは光が上へ抜ける縦の構図、グレイスは横に広がる構図で、同じ入り方が3枚とも最適とは限らない。窓は角丸の横長矩形（最大740×520）で絵は4:3なので、上下が少し切れることも合わせて確認する。
- 対応：3枚を実機で通しで見て、寄りの量・向き・秒数（`FADE_SEC`／`HOLD_SEC`）を詰める。レシピごとに変えるならレシピ側に持たせる。絵を差し替えたら見直す前提の調整なので、凝りすぎない。
- 該当：`godot/presentation/formation/formation_cutin.gd`・`doc/gdd/formations.md`（発動の演出）。着手の引き金＝演出を通しで見て気になったとき。

### feature-40

**Steam 実績・Stats の配線（GodotSteam 導入）**
- 背景：実績と計測の方針は [monetization.md](sales/monetization.md)（実績・計測）で決めたが、実装側の入り口が無い。GodotSteam は未導入（`godot/infrastructure/platform/` は空）で、実績を立てる呼び出しも Stats を刻む発火点も置き場所が決まっていない。実績はリリース後に削除・改名できない（解除済みの記録が消える）ため、セットの確定は 1.0 のストア提出前が締め切りになる。
- 対応：(1) GodotSteam を導入し `godot/infrastructure/platform/` の裏に隔離する（feature-13 の entitlement 配線と同じ層・同じ段。Steam が居ない環境＝エディタ実行・BOOTH 版でも落ちないダミー実装を用意）。(2) 実績の発火点＝冒険譚の完走判定。完走判定は `CampaignProgress` にあり、ランクも進捗セーブに入る（[stage_select.md](gdd/stage_select.md) クリア記録）ので判定はここに寄せる。最上位ランク達成時は下2段も同時に付与（取りこぼし防止）。(3) Stats の発火点＝ステージの開始とクリア。全ステージではなくチュートリアルに絞って刻む（見たいのは最初の1時間の離脱）。(4) 体験版のセーブを本体と共有 Steam Cloud に置き、購入後の本体初回起動でまとめて付与する経路（Valve 推奨。体験版では実績を発火させない）。
- 該当：`godot/infrastructure/platform/`（GodotSteam の隔離・新規）・`godot/application/campaign_progress.gd`（完走判定・ランク記録）・`godot/infrastructure/save/progress_store.gd`（Cloud 配置）・`doc/sales/monetization.md`。着手の引き金＝Steamworks に AppID を登録したとき（parking lot「Steam 配布の段取り」と連動）。前提＝ランクの評価式（[rank.md](gdd/rank.md)）は実装済み。
- 要確認（AppID 取得後に管理画面で）：体験版の AppID で Stats が使えるか（Steamworks のドキュメントは体験版について実績にしか触れていない）。実績上限100の緩和条件＝Profile Features のしきい値。

### feature-46

**タイトル画面の残り（クレジット画面）**

- 背景：タイトル画面そのものは入った（起動→扉が開く動画→店内のメニュー。仕様 → [title.md](gdd/title.md)）。残るのは、メニューに項目だけ置いてあるクレジット画面。
- クレジット：素材の権利表記。タイトルのメニューに項目は置いてあるが、受け口が無く押せない状態。画面に出す内容は [credits.md](sales/credits.md) の「ゲーム内クレジットに出すもの」が正本で、そこを読んで並べるだけにする。台帳の整備自体は済んでいるが、根拠が取れていないライセンスが残っている（feature-54）。リリース前が締め切り。
- クレジット画面の作り（決めたこと）：新規シーン `godot/presentation/credits/` を1枚。タイトルのメニューからのみ開く（ゲーム中のシステムメニューには足さない＝盤を止めてまで読むものではない）。戻るは左下の木の板ボタンで、位置と大きさはセレクトと同じ規則に揃える（[stage_select.md](gdd/stage_select.md)）。地は中立の暗色（起動スプラッシュと同じ `#0d1925`）＝操作の道具は酒場の物にしない（[title.md](gdd/title.md)）。押せる物だけが木の板、という様式は保つ。見た目は実物を見てから詰める。文言は `ui.csv` に足す（キーは `ui.<画面>.<項目>` → [i18n.md](tech/i18n.md)）。
- 該当：`godot/presentation/title/title_screen.gd`・`godot/presentation/credits/`（新規）・`doc/gdd/title.md`。関連＝feature-66〜69（UI文言の i18n キー化）。開き方と戻るの位置は設定画面（`godot/presentation/settings/settings_screen.gd`）を手本にする。着手の引き金＝配布ビルドが見えてきたとき。

### feature-47

**設定画面の項目を増やす・ゲーム中からも開く**
- 背景：設定画面は言語だけを持ち、タイトルのメニューからしか開かない（[settings.md](gdd/settings.md)）。`godot/presentation/ui/hud.gd` のシステムメニューの「設定」は受け口が無いまま押せない状態で置いてある。feature-16（演出速度・敵ターンスキップ）が設定値の置き場をここに見込んでいる。
- ゴール：音量・画面モード・演出速度を設定画面から変えられ、盤の中からも開いて戻ってこられる。
- 対応：(1) 項目を足す＝音量（マスター／BGM／SE。AudioServer のバスへ反映）・画面モード（全画面／ウィンドウ）・演出速度（移動アニメ／カメラ追従／敵ターンスキップ＝feature-16）。値は `SettingsStore` に足す。(2) HUD のシステムメニューから開く＝`settings_requested` を出し、`main` が盤の上に重ねる。あわせて、盤の中で言語を変えたときに追従しない画面（ターンバナー・戦果票など、盤に入ってから作って残る物）を洗い出し、`refresh_labels()` を持たせる（[i18n.md](tech/i18n.md) 言語の切り替え）。
- 該当：`godot/presentation/settings/settings_screen.gd`・`godot/infrastructure/save/settings_store.gd`・`godot/presentation/ui/hud.gd`・`godot/presentation/main/main.gd`・`godot/presentation/ui/bgm_player.gd`／`sfx_player.gd`・`doc/gdd/settings.md`。関連＝feature-16（移動・カメラ・戦闘演出の速度の設定値化）。着手の引き金＝敵ターンが長く感じ始めたとき、または音量を触りたくなったとき。

### feature-53

**Steam ストアページの作成**
- ゴール：Steam のストアページが公開できる状態で埋まっている。
- 背景：配布はまず Steam（[monetization.md](sales/monetization.md)）。ページの入力欄は Steamworks への登録（$100）をしないと開かないので、素材を揃えてから登録するより先に登録して実物の欄を見る。素材の方針は [marketing.md](sales/marketing.md)、入力する内容は [steam_page.md](sales/steam_page.md) が正本。
- 対応：Steamworks に登録し、ストアページのスロットを埋める。素材はカプセル画像→スクリーンショット→本文の順（上から依存している）。
- 該当：`doc/sales/steam_page.md`・`doc/sales/marketing.md`・`godot/assets/promo-src/`。関連＝feature-27（サイトへ文と絵を流用）。着手の引き金＝配布ビルドが見えてきたとき。

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
- 対応：(1) ランディングは1ページ。ストアページ（feature-53）の文と絵が決まってから流用して作る。(2) ルールのページ（`senaris.in/rules` 相当）をランディングからリンクする。マニュアルの構造定数と `manual.csv` から生成できる想定で、範囲と見せ方は未検討。
- 該当：`site/`・`doc/sales/site.md`・`godot/data/i18n/manual.csv`。着手の引き金＝配布が見えてきたとき。

### feature-98

**情報パネルを小さくする（コンパクトモードの検討含む）**
- ゴール：右の情報パネルが盤を狭めず、読みたい情報は今までどおり読める。
- 背景：右の情報パネルは固定寸法（`UiLayout.RIGHT_BOX`＝464×608）で、盤エリアの右側を常時占めている。盤を広く見たい場面で大きさが気になる。常時小さくするほか、畳む・縮める切り替え式（コンパクトモード）も候補。パネルの矩形から位置を算出している物（タイトルロゴ）は矩形を動かせば追従する作りになっている（[uiux.md](gdd/uiux.md) タイトルロゴ）。
- 対応：未検討。まず「常時小さくする」か「切り替え式」かを決める。縮めた場合にタブ／ページャー構成（[uiux.md](gdd/uiux.md) ユニット情報パネル）のページ割りがどう変わるかも合わせて見る。
- 該当：`godot/presentation/ui/ui_layout.gd`・`godot/presentation/ui/unit_info_panel.gd`・`doc/gdd/uiux.md`。

### feature-99

**プレスキットを用意する**
- ゴール：紹介したい人に「ここを見て」と1つ渡せば、本物のロゴ・スクリーンショット・説明文・権利表記が揃う。
- 背景：体験版の公開後、こちらの許可なく紹介動画が出た（[sales/youtube.md](sales/youtube.md) の記録）。使われたサムネイルは実際の画面ではない生成画像で、期待と実物の落差が視聴者コメントに出た。渡せる素材が手元に無いと、第一接触の絵を他人の生成物に握られる。[site.md](sales/site.md) はランディングページのフッターに置くリンク項目として名前を挙げているだけで、中身も置き場も決めていない。
- 対応：中身と置き場を決める。素材は3面と共通のものを流用できる（[marketing.md](sales/marketing.md) の素材の置き場）。ストアページ（feature-53）を待たずに出せる範囲で先に組む。【未決】置き場（`senaris.in/press` か itch のページ内か）・同梱物（ロゴ・スクリーンショット・キービジュアル・説明文・権利表記・連絡先）・配り方（zip か個別ダウンロードか）。
- 該当：`channels/`・`doc/sales/site.md`・`doc/sales/marketing.md`・`doc/sales/youtube.md`。着手の引き金＝次に紹介の話が来たとき、またはサイトの中身を作るとき（feature-95）。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- 茂み（brush）の高さの詰め：見た目の高さ（`terrain_skin.csv` の `elevation`）を 0.12 で仮置きしている（駒の足元 `floor` は地面＝0）。茂みの絵そのものが仮のため、いま詰めても絵の差し替えでやり直しになる。本番の茂みタイルができたら実機で見て決める（→ [terrain.md](art/terrain.md)）。
- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
