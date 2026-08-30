# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=4 / feature=94 / refactoring=12

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

### feature-90

**保存データにバージョンを持つ**
- ゴール：版を上げても、旧版のセーブが変換されて読める。
- 背景：進捗・名簿・中断・設定の4ファイルは版番号を持つが、読み込みは一致しなければファイルごと捨てる。体験版を出した以上、版を上げた瞬間にプレイヤーの進捗と仲間が消える作りは残せない（[gamesystem.md](tech/gamesystem.md) §版と移行）。
- 対応：各ストアに旧版から新版への変換を通す経路を敷く。現行より新しい版は現行として読む。壊れて読めないファイルは無いものとして扱い起動を止めない（今のまま）。この段では版を上げないので、入るのは仕組みだけになる。変換で追随するのは構造の変化と識別子の改名で、`catalog` に無い `type` を既定性能の駒として黙って通さない点もここで潰す。
- 該当：`godot/infrastructure/save/`（`progress_store.gd`・`roster_store.gd`・`save_store.gd`・`settings_store.gd`）・`godot/domain/unit/unit.gd`・`doc/tech/gamesystem.md`。

### feature-91

**中断セーブをステージ参照＋動的差分にする**
- ゴール：ステージを直しても進行中の中断セーブが読めて、盤に効く変更が届いている。
- 背景：`BattleState.to_dict` が盤サイズ・地形・拠点・勝敗条件・部隊定義・増援の中身まで丸ごと書いている。地形は戦闘中に変化せず（`set_terrain` を呼ぶのは `stage_loader` だけ）、ステージJSONから引き直せるものをセーブが正本にしてしまっている。難易度調整が進行中のセーブに一切届かない。
- 対応：(1) 中断セーブを v3 とし、ステージJSONから引き直すもの（盤の広さ・地形・勝敗条件・ターン上限・部隊定義・拠点の位置と種別・増援の中身）を落として動的差分だけを持つ。復元はステージJSONで盤を組んでから差分を被せる。(2) ステージ定義の印（除外キー以外から算出）をセーブへ記録する。(3) v2→v3 の変換＝盤丸ごとから動的差分を抜き出し、体験版に同梱したステージの印を表から埋める（今のステージJSONから計算しない）。(4) 復元して盤に居られない駒（拠点が消えた・盤外・入れない地形）は盤へ出さない。
- 該当：`godot/domain/battle_state.gd`・`godot/domain/capture/base.gd`・`godot/application/stage_loader.gd`・`godot/infrastructure/save/save_store.gd`・`godot/presentation/main/main.gd`・`doc/tech/gamesystem.md`。前提＝feature-90。

### feature-92

**ステージが更新されている中断セーブをプレイヤーに知らせる**
- ゴール：セーブを作ったあとにステージを直した枠が、選ぶ前に見て分かり、選んだときにも一度確認が入る。
- 背景：ステージ定義が変わっても差分はそのまま適用して再開を妨げない方針だが、黙って適用すると盤が前と違う理由がプレイヤーに分からない。枠の一覧表示は `_row_text` 一本で、ロード時の確認はいまタイトルの「冒険の続き」経由では出ない（失う盤が無いため）。
- 対応：セーブの印と今のステージ定義の印を比べ、違う枠は一覧の行に更新されている旨を添える。その枠を選んだときだけ確認を挟む（印が一致する枠のロードは今のまま）。
- 該当：`godot/presentation/ui/save_slot_panel.gd`・`godot/presentation/main/main.gd`・`godot/data/i18n/`・`doc/tech/gamesystem.md`。前提＝feature-91。

### feature-89

**ホーリーアリアの効果を参加人数で伸ばす**
- ゴール：隣接クラスタが5体より多いとき、多いぶんが効果の強さになっている（頭数を集めた判断が報われる）。
- 背景：いまは5体以上で成立し、発動すると隣接クラスタ全員が行動完了になる＝人数が増えても効果は同じで、消費だけが増える。集まっているほど損をする形になっている。案は最低5体を据え置き、1体増えるごとに補正 +0.05（5体＝×1.30／8体＝×1.45）。
- 対応：`Formation.RECIPES` の `holy_aria` に人数連動の値を持たせ、`_buff_entry` が参加人数から補正を決める。`count` 固定でないレシピは初なので、他のレシピへ波及しない形で入れる。formations.md ②の表と、レシピ表の「効果」の書き方も更新する。
- 該当：`godot/domain/formation/formation.gd`・`godot/domain/battle_state.gd`（`_buff_entry`）・`godot/tests/unit/test_formation.gd`・`doc/gdd/formations.md`。

### feature-88

**陣形スキルを撃った後に情報パネルが何を出すかを決める**
- ゴール：陣形スキルの発動直後に右のパネルへ出すものが決まっていて、そのとおり出ている。
- 背景：発動すると選択が外れ、パネルが「No unit selected」＋操作の説明に戻る。実機の挙動として正しいが、撃った直後に読みたいのは着弾の結果か発動者の性能のはずで、操作説明ではない。紹介画像の3枚目（カットイン）を撮ったときに、店頭に出す絵へ操作説明が写ることで気づいた。
- 対応：候補は そのまま／発動者を選択したまま残す／戦闘レポートと同じ形で着弾の損害を出す。決めてから実装する。
- 該当：`godot/presentation/main/main.gd`（`_on_formation_resolved`）・`godot/presentation/ui/unit_info_panel.gd`・`channels/screenshots/03_cutin.png`。

### feature-80

**チュートリアル２の会話の英文を書き直す**
- ゴール：チュートリアル２の会話が、英語圏のプレイヤーにとって翻訳物ではなく英語で書かれた台詞として読め、教える内容は日本語と一致している。チュートリアル２を収録する itch の更新に間に合っている。
- 背景：`dialogue.csv` の英文（チュートリアル２＝104キー・約1809語）は監修を通っていない。[i18n.md](tech/i18n.md) で「根拠にしない」と明記された側で、画面の用語（`Strength` など）と食い違う箇所が feature-66 で既に見つかっている。英語圏をメインターゲットにする方針（[marketing.md](sales/marketing.md)）では、優先度が高いのはストアページの一行目と会話パートで、UI ラベルより会話のほうが上。
- 対応：日本語を正本にしたまま英文だけを書き直す。訳ではなく英語の台詞として書く（[authoring.md](campaign/authoring.md) の英題の考え方と同じ）。用語は [i18n.md](tech/i18n.md) の「英語の用語」に従う。`t2.st6.intro.2` の "its strength, defense, and speed" は画面の `Strength` ラベルと直接ぶつかるので必ず直す。話者名（`char.*`）の英語としての質もここで見る（ユニット名との整合は修正済み）。
- 考慮外：日本語の台詞は直さない。
- 該当：`godot/data/i18n/dialogue.csv`（`t2.*`の行）・`doc/campaign/`（内容の照合先）。

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
- サイト：仕様は [site.md](sales/site.md)、配信先の決定は [ADR-0005](adr/ADR-0005-site-hosting-cloudflare-workers.md)。ドメイン取得・DNS・配信構成は済んでいる。残るのは中身で、ストアページ（feature-53）の文と絵が決まってから流用して作る。
- 対応：(1) 商標クリアランス＝第9類・第41類で US(USPTO)／EU(EUIPO)／日本(J-PlatPat) の各DBを正式確認（ドメインとは別作業。ドメインが空いていても商標が先に取られていることはある）。(2) SNSハンドル確保（X／Bluesky／Discord 等）。(3) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`・`doc/sales/site.md`・`site/`。着手の引き金＝配布が見えてきたとき（parking lot「Steam 配布の段取り」と連動）。サイトのランディングページはストアページ（feature-53 と同じ段）のあと。

### feature-48

**羽ばたきの素材を採り直す**
- 背景：`move_flight` に当てている上着の布音（Modern Cloth Foley の Whoosh Flutter）が、羽ばたきに聞こえない。素材が 0.42 秒あるのに間隔が 0.30 秒で、常に 0.12 秒ぶん重なって連続音になるため。翼を打つ一打ずつには分かれない。飛空艇（`move_propeller`）はこの連続音の性質をそのまま利用して同じ素材から作ったので、飛行側だけが宙に浮いている。
- 対応：一打で完結する素材に差し替える。Sonniss バンドルには使える羽ばたきが無いことが確認済み（[doc/audio/sfx.md](audio/sfx.md) の「バンドルに録音が無かったもの」）。外部の素材集を1本買うか、自録り（うちわ・厚紙・畳んだ布で空気を打つ）に切り替える。長さは 0.30 秒より短く収めて、重ならずに一打ずつ聞こえる形にする。ペガサスからレッドドラゴンまで1つで賄うので、翼の大きさが特定できない中庸な質感を狙う。
- 該当：`godot/assets/sfx-src/move_flight_recipe.txt`・`godot/assets/sfx/move_flight.ogg`・`godot/assets/sfx-src/credits.md`・`godot/data/audio/sfx_catalog.gd`（間隔）・`doc/audio/sfx.md`。着手の引き金＝素材を調達したとき。

### feature-36

**陣形カットインの入り方を絵の構図に合わせて詰める**
- 背景：カットインの入り方は絵が無い時期に決めた暫定で、フェード＋わずかなズーム（`ZOOM_FROM=1.06`）を3レシピ共通で掛けている。絵が揃ったいま、構図と噛み合っているかを見ていない。トリニティノヴァとディバインジャッジメントは光が上へ抜ける縦の構図、ホーリーアリアは横に広がる構図で、同じ入り方が3枚とも最適とは限らない。窓は角丸の横長矩形（最大740×520）で絵は4:3なので、上下が少し切れることも合わせて確認する。
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

### feature-52

**仕様リファレンス（ゲーム内の図鑑とサイトの仕様ページ）**
- 背景：本作は完全情報ゲーム＝戦闘に乱数が無く（中断セーブが状態だけで完全再現できる前提でもある）、敵の行動も特性ごとのルールで決まる（[ai.md](gdd/ai.md)）。負けた理由が必ず盤上にある、という設計が売りになるが、そのルールをプレイヤーが読める場所が今どこにも無い。feature-46 のメニュー項目一覧（つづきから／はじめる／設定／クレジット／おわる）にも入っていない。下地としては `unit_skin.csv` の分類が図鑑用として既に用意されている（[units.md](art/units.md)）。
- 対応：
  1. 範囲を決める。候補は 敵AIの特性と行動ルール／地形コストと移動タイプ／戦闘の補正チェーン／ユニット性能表／陣形・ユニットスキルのカタログ。どこまで見せるかは「完全情報を主張する以上、隠す理由のあるものは無い」を基準に判断する。
  2. CSV正本から生成する。敵AIも地形も移動タイプもユニット性能も `godot/data/**/*.csv` が正本なので、そこから表を機械的に起こす（CSV正本→JSON生成と同じ発想）。手書きすると必ず実装とズレる。生成先はゲーム内データとサイトのHTMLの両方。
  3. ゲーム内の画面を作る。タイトルとゲーム中のシステムメニューの両方から開く（タイトルに重ねる置き方は設定画面が先例。`godot/presentation/settings/settings_screen.gd`）。タイトル側の項目名は「マニュアル」で、受け口が無いまま押せない状態で置いてある（[title.md](gdd/title.md)）。
  4. サイト側は別ページ（`senaris.in/rules` 相当）。ランディングは1ページのまま、そこからリンクする。
  5. i18n。表の見出しと説明文は翻訳キーに載せる（feature-66〜69 と同じ扱い）。
- 該当：`godot/data/**/*.csv`・`godot/tools/`（生成スクリプト新規）・`presentation/`（図鑑画面・新規）・`doc/gdd/`（見せる範囲の記述）。着手の引き金＝サイトを作るとき、または完全情報であることを説明する必要が出たとき。

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
- 背景：マニュアル（feature-52）はタイトル専用の通読画面と決め、盤中からは開かない。盤で「弱者狙いって何」「貫通率はどこに効く」と詰まったとき、その場で引く手段が無い。
- 対応：形は未検討。情報パネルの用語から短い説明を出す類を想定。説明文をマニュアルの本文と共有するかもここで決める。
- 該当：`godot/presentation/ui/`（情報パネル）・feature-52（マニュアル本文）。着手の引き金＝マニュアルの本文が書けたとき、または実プレイで用語に詰まったとき。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- 茂み（brush）の高さの詰め：見た目の高さ（`terrain_skin.csv` の `elevation`）を 0.12 で仮置きしている（駒の足元 `floor` は地面＝0）。茂みの絵そのものが仮のため、いま詰めても絵の差し替えでやり直しになる。本番の茂みタイルができたら実機で見て決める（→ [terrain.md](art/terrain.md)）。
- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
