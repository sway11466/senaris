# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=3 / feature=86 / refactoring=12

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

### feature-80

**チュートリアル２の会話の英文を書き直す**
- ゴール：チュートリアル２の会話が、英語圏のプレイヤーにとって翻訳物ではなく英語で書かれた台詞として読め、教える内容は日本語と一致している。チュートリアル２を収録する itch の更新に間に合っている。
- 背景：`dialogue.csv` の英文（チュートリアル２＝104キー・約1809語）は監修を通っていない。[i18n.md](tech/i18n.md) で「根拠にしない」と明記された側で、画面の用語（`Strength` など）と食い違う箇所が feature-66 で既に見つかっている。英語圏をメインターゲットにする方針（[marketing.md](sales/marketing.md)）では、優先度が高いのはストアページの一行目と会話パートで、UI ラベルより会話のほうが上。
- 対応：日本語を正本にしたまま英文だけを書き直す。訳ではなく英語の台詞として書く（[authoring.md](campaign/authoring.md) の英題の考え方と同じ）。用語は [i18n.md](tech/i18n.md) の「英語の用語」に従う。`t2.st6.intro.2` の "its strength, defense, and speed" は画面の `Strength` ラベルと直接ぶつかるので必ず直す。話者名（`char.*`）の英語としての質もここで見る（ユニット名との整合は修正済み）。
- 考慮外：日本語の台詞は直さない。
- 該当：`godot/data/i18n/dialogue.csv`（`t2.*`の行）・`doc/campaign/`（内容の照合先）。

### feature-81

**チュートリアル1の素材だけで組む高難度ステージ**
- ゴール：チュートリアル1に登場済みの要素だけで組んだ歯ごたえのあるステージが1本、体験版の初回ビルドで遊べる。devlog 1本目の「難易度高めも1本入れた」が実体を持っている。
- 背景：初回の体験版はチュートリアル1のみで、1ステージ1要素の教える章＝簡単。devlog 1本目（`channels/itch/devlog/2026-08-24-why-no-dice.md`）の設計で「腕試しに難易度高めのステージを1本入れた」と書くことにしたため、書く前に実体を作る。チュートリアル2の st6 に「総合①（腕試し）」があるのと同じ位置づけをチュートリアル1にも置く形。
- 対応：新ユニット・新地形・新ルールを足さず、チュートリアル1の既出要素（移動・地形・包囲・支援・間接・占領・釣り）だけで1本組む。型と難易度の表し方は [map_patterns.md](gdd/map_patterns.md) に従い、ステージ一覧へ行を足す。置き場は決定（2026-08-25）＝チュートリアル1の8本目ではなく、独立した冒険譚として Bounties ボード（ストーリー性のない高難度ステージを集める板・[stage_select.md](gdd/stage_select.md) シリーズボード）に置く。解放条件は着手時に決める。
- 考慮外：陣形スキル・輸送・魔法兵などチュートリアル2以降の要素。会話パートの規模も本編ステージ並みを求めない。
- 該当：`godot/data/stages/`（Bounties 用の冒険譚フォルダ・新設）・`doc/gdd/map_patterns.md`（ステージ一覧）・`doc/campaign/roadmap.md`（Bounties ボードの行）。

### feature-82

**pck 暗号化の導入（エクスポートテンプレートの自前ビルド）**
- ゴール：配布ビルドの pck が暗号化されており、GDRE Tools 等でのカジュアルな展開・詰め直し（ユニット超強化・データ流用）が通らない。
- 背景：方針は [ADR-0002](adr/ADR-0002-paid-data-protection.md) で決定済みだが実装は未着手（`export_presets.cfg` は `encrypt_pck=false`）。Godot の pck 暗号化は復号鍵をエクスポートテンプレートにビルド時に焼き込む方式のため、公式配布のテンプレートは使えず自前ビルドが要る（[build.md](tech/build.md) の注意）。締め切りは有料版の販売前。itch の初回体験版は暗号化なしで出してよい。
- 決めたこと（2026-08-24）：
  - 鍵は体験版と製品版で別にする（体験版は誰でも入手できる＝最も解析されやすいビルドなので、破られても失うのが体験版の中身だけになるよう分ける）。テンプレートは鍵ごとにビルドする。
  - 鍵の定期的な入れ替えはしない。鍵は各ビルドの実行ファイルに同梱されるため、入れ替えても配布済みビルドは守れない。入れ替えるのは事故時（コミット・公開漏洩）のみ。
  - 鍵はリポジトリ外（パスワードマネージャ等）で保管し、ビルド時に環境変数 `SCRIPT_AES256_ENCRYPTION_KEY` で流し込む。
  - Godot ソースの置き場は `C:\Users\tappe\godot-src`（OneDrive 外＝同期対象にしない）。バージョンはエディタと同じものを使い、エディタを上げたら再ビルドする。
- 対応：(1) ビルド環境の構築＝VS Build Tools 2022（C++ ワークロード）と SCons。(2) Godot ソースを取得し、鍵を環境変数に入れて Windows 用リリーステンプレートを鍵ごとにビルド。(3) `export_presets.cfg` に `encrypt_pck=true` とカスタムテンプレートを設定（鍵自体はファイルに書かない）。(4) 暗号化ビルドを実際に起動して確認し、手順を [build.md](tech/build.md) に記す。
- 考慮外：ADR-0002 の残り2層（デジタル署名・所有権チェック）はこの作業に含めない。CI 化はローカルで一度通ってから。
- 該当：`godot/export_presets.cfg`・`doc/tech/build.md`・`C:\Users\tappe\godot-src`（リポジトリ外・新規）。着手の引き金＝オーナーの合図。



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

### feature-21

**BGM のたたき台仕上げと拡充**
- 背景：BGM の制作方針は [bgm.md](audio/bgm.md) で確定。たたき台のうち `graveyard`・`boss` は仕上げて `.ogg` 化済み（投入済みは afterglow／boss／defeat／dungeon／graveyard／journey／menu／raid／title／victory）。残りの下書き（`forest`／`ruins`／`temple`／`ritual`／`boss2`／`crisis`）が `.mscz` のまま仕上げ待ち。全体既定（`BgmDirector.DEFAULT_STAGE_TRACK`＝`map_calm`）は ID に対応する曲が無い＝ステージにも冒険譚にも `bgm` 指定が無いと無音になる（チュートリアル1は全ステージに指定済みのため現在は該当なし）。
- 対応：(1) 残りの下書きの MuseScore 仕上げ（強弱・味付け・ループ点整備）と `.ogg` 化。`crisis` は切替機構を撤去したため当てる先が無い＝feature-44（イベント経由の切替）を入れるまで急がない。(2) 全体既定を投入済みの曲に変えるか `campaign.json` に既定を書くかを決定し反映。
- 該当：`godot/assets/bgm-src/`・`godot/assets/bgm/`・`godot/application/bgm_director.gd`（`DEFAULT_STAGE_TRACK`）・`doc/audio/bgm.md`（ライブラリ表更新）。着手の引き金＝ステージに曲を当てたくなったとき。

### feature-26

**デバッグステージの構成見直しと拡充**
- 背景：デバッグ冒険譚は機能別6カテゴリに分かれており、既存ステージは計18枚（台帳＝[debug-stages.md](tech/debug-stages.md)）。カテゴリの分け方と既存ステージの役割は見直し済み（旧 siege.json は base.json＝拠点と勝敗に統合、旧 debug.json の総合マップは廃止して各カテゴリへ吸収）ので、残るのはカバーの隙間を埋める追加のみ。戦闘の補正チェーンを1つずつ切り分ける盤がまだ無く、そこが一番厚い。
- 対応：不足しているデバッグステージを追加する。対象は以下。
  - combat: 地形補正／間接／魔法／対空・対地／包囲／支援／レベル補正（7件）
  - ai: charge／raid（2件。起動トリガー見本は sight.json が担う）
  - victory: 殲滅／自軍hq喪失で敗北／複数条件OR（3件。既存 defend_two は AND）
  - mapops: 陣形②③／飛空艇・初期搭乗（2件。拠点は base.json で済）
  - skins: 構造物系タイル（1件）
  - misc: 追加の演出・UI検証（1件）
- 該当：`godot/data/stages/debug-*/`・`doc/tech/debug-stages.md`（台帳更新）。着手の引き金＝機能を足してデバッグステージが欲しくなったとき。

### feature-27

**タイトル名「Senaris」の確定手続き**
- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済みだが、確定前の手続きが残っている。すべてオーナー側の手作業。
- 開発元（2026-08-12 決定）：屋号は `craftkobo`。法人ではなく個人事業主として出品する＝Steam の契約名義は本名、公開される表示名は屋号。開業届は提出済み。ドメイン `craftkobo.com` は空きを確認済みで取得予定＝開発元用（プロダクト用の `senaris.in` とは別。問い合わせ先メールは開発元側に置く＝ゲームが増えても窓口が1つで済む）。銀行口座は未開設で、Steam の受取名義と一致すること・海外送金を受け取れることを確認してから作る。米国向けの税務書類はマイナンバーを外国TINとして出すと源泉徴収が下がる。
- Steam の名前まわり（2026-08-12 調査）：`steamcommunity.com/id/senaris` は他者が使用中だが、これは一般ユーザーがプロフィールページに付ける短縮URLで、ゲームとは無関係＝実害なし。ゲームのストアページは `store.steampowered.com/app/<AppID>/…` の形で、AppID は Valve が採番するため他者のユーザー名に影響されない。開発元ページ `store.steampowered.com/publisher/senaris` は未使用だが、これは早い者勝ちで押さえるものではなく登録後に申請して作るページ。実際に競合しうるのはゲーム名そのもので、Steamworks 登録時の審査に掛かる＝下記 (1) の商標クリアランスと同じ話。
- サイト：仕様は [site.md](sales/site.md)、配信先の決定は [ADR-0005](adr/ADR-0005-site-hosting-cloudflare-workers.md)。ドメイン取得・DNS・配信構成は済んでいる。残るのは中身で、ストアページ（feature-51）の文と絵が決まってから流用して作る。
- 対応：(1) 商標クリアランス＝第9類・第41類で US(USPTO)／EU(EUIPO)／日本(J-PlatPat) の各DBを正式確認（ドメインとは別作業。ドメインが空いていても商標が先に取られていることはある）。(2) SNSハンドル確保（X／Bluesky／Discord 等）。(3) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`・`doc/sales/site.md`・`site/`。着手の引き金＝配布が見えてきたとき（parking lot「Steam 配布の段取り」と連動）。サイトのランディングページはストアページ（feature-51 と同じ段）のあと。

### feature-28

**ユニットスキル第2弾（貫通追加・再行動）**
- 背景：ユニットスキルの器（単独発動・味方1体へ状態補正・移動後発動）は①ピクシーダストで実装済み（[skills.md](gdd/skills.md)）。カタログを増やす段で、次に入れる2つの方向まで決まっている＝(1) 貫通追加＝対象の攻撃に貫通率を乗せる、(2) 再行動＝行動を終えた味方をもう一度動かす。どちらもレシピは未設計（発動者・値・持続・射程が未定）でカタログにも載っていない。
- 対応：(1) 貫通追加は既存の状態補正で足りるか要確認＝`StatusMod` は攻防への add/mul は持つが、貫通率（`Unit.pierce`）に効く経路が無いため、補正チェーンに貫通の口を足すかどうかから決める。(2) 再行動は「1ターンに各ユニット1回まで」の縛りを入れる方針まで決定済み（無制限だと1体を延々動かせて崩壊する）。縛りの持ち場は駒側のフラグ＝`BattleState` に再行動回数を持たせ、中断セーブの直列化にも載せる。レシピが固まったら skills.md のカタログへ②③として追記する。
- 該当：`godot/domain/formation/formation.gd`（RECIPES）・`godot/domain/battle_state.gd`（再行動フラグ・直列化）・`godot/domain/status/status_mod.gd`／`godot/domain/combat/combat.gd`（貫通の口）・`godot/tests/unit/test_skill.gd`・`doc/gdd/skills.md`。

### feature-29

**敵AIの陣形スキル使用（複数人）**
- 背景：ユニットスキル（発動者1体）は敵も撃つようになった（特性の行動ルール＝[ai.md](gdd/ai.md)）。残るのは複数人の陣形スキルで、敵陣営向けのレシピが1つも無い。実行経路は `AiAction.SKILL` で共通なので、レシピを足せば同じ仕組みで飛ぶ。成立条件はスキンID照合（未指定は種別へフォールバック）＝データ面の下地はできている。
- 対応：(1) 敵陣営向けのレシピをカタログに足す（どの敵に何を持たせるかは冒険譚側の設計）。(2) 撃つ価値の評価を足す＝ユニットスキルは「対象1体」で選べたが、面の陣形は着弾中心の選び方（面に入る敵の数・味方の巻き込み）が要る。`_pick_skill_target` は対象1体を前提にしているのでここを広げる。
- 該当：`godot/domain/ai/trait_brain.gd`・`godot/domain/formation/formation.gd`（敵レシピ）・`godot/tests/unit/test_ai.gd`・`doc/gdd/ai.md`・`doc/gdd/formations.md`（発動主体の記述を更新）。着手の引き金＝敵に陣形を持たせたい冒険譚を作るとき。

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

### feature-41

**ユニットスキルの演出の手応え（シェイク・フラッシュの出し分け）**
- 背景：ユニットスキルの演出（[combat_scene.md](tech/combat_scene.md) ユニットスキルの演出）は兵量バーが動かないので、戦闘から「減る」という一番大きな動きが抜ける。残るのはシェイク・フラッシュ・数値だけで、弱体（ドレッドタッチ・ヴェノムファング）と強化（ピクシーダスト・ピュリファイ）に同じ動きを当てると、強化されたのに殴られたように見えるおそれがある。
- 対応：レシピの `buff_harmful` で動きを分ける。有害なら被対象がひるむ（シェイク＋暗いフラッシュ）、そうでなければ光る（明るいフラッシュのみ・シェイクなし）、という向きが素直。数値の色も同じ基準で分けられる。分ける軸を新設せず既存のフラグを使うのは、値の符号から推測しないという [skills.md](gdd/skills.md) の方針と揃えるため。
- 該当：ユニットスキルの演出モジュール（`godot/presentation/combat/`）・`doc/tech/combat_scene.md`。着手の引き金＝実際に動くものを見て、手応えが足りないと感じたとき（先に数値を決めても当たらないので、通しで見てから調整する）。

### feature-44

**ステージ途中のBGM切替（イベント経由）**
- 背景：曲を途中で切り替える仕組みを `bgm` の `crisis` スロット＋永続フラグ＋`BgmDirector.enter_crisis()` として持っていたが、ゲームに配線されず使うステージも無かったため撤去した。BGM専用に状態をもう1本立てるより、既にあるイベント（`events`＝Nターン目に起きること・[map.md](gdd/map.md) イベント）の `type` を1つ足すほうが、状態の置き場もJSONの書き場所も1か所に寄る。
- 対応：`events` に BGM 切替の type を足す（`turn` で発生・トラックIDを指定）。曲はライブラリの `crisis`（警報型・たたき台あり）が候補。必殺技やボス出現のような盤面イベントを引き金にしたくなったら、BGM専用の抜け道を作らず、イベント側に条件トリガーを足す形で設計する。
- 該当：`doc/gdd/map.md`（イベント表）・`godot/domain/battle_state.gd`（`fire_due_events`）・`godot/application/stage_loader.gd`（`_apply_events`）・`godot/presentation/main/main.gd`（曲の張り替え）・`doc/audio/bgm.md`。着手の引き金＝ステージ途中で曲を変えたくなったとき。

### feature-45

**アプリアイコンの差し替え**

- 背景：ウィンドウ／タスクバーのアイコン（`godot/application/config/icon`）が未設定で Godot のアイコンのまま。Godot は MIT でロゴの表示義務が無いため、フォークやカスタムビルドは不要＝プロジェクト設定と画像の差し替えだけで済む。起動スプラッシュは差し替え済み（2026-08-13。[menu.md](art/menu.md) §6）。
- 対応：文字を落とした紋章だけの版を `godot/tools/logo/build_logo.py` に足し、PNG へ焼いて `godot/application/config/icon` に指定する。変換は `godot/tools/rasterize_svg.gd`、`.ico`（16/24/32/48/64/128/256 を1ファイルに束ねる）は ImageMagick で組む。あわせて Windows export preset の exe アイコンも差し替える。
- 小さいアイコンはヘックス1枚に剣が刺さっているだけの版にする。7枚のクラスタは 32px 以下で塊に潰れる。どの寸法から切り替えるかは焼いて見て決める。
- 紋章版は、タイルから文字を抜いているマスクを剣と杖だけに絞って組み直す。文字のレイヤーを消すだけだと、タイルに文字型の切り欠きが残る。
- 紋章は横 500 に対して縦 約530（剣と杖が上に伸びる分）で正方形ではない。左右に余白を足すか、アイコン版だけ武器を短くするかを選ぶ。
- 該当：`project.godot`（`godot/application/config/icon`）・`godot/export_presets.cfg`（exe アイコンの `application/icon`）・`godot/assets/`（アイコン画像）。着手の引き金＝配布ビルドを作るとき。

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

### feature-49

**ステージ開始の区切り音（`menu_sortie`）**
- 背景：ステージに入る経路が2種類ある。連戦（outro 会話 → `_advance_or_select` → 次ステージ）と、文脈の外から入る経路（ステージセレクト、およびタイトルの「冒険の続き」）。連戦では会話でステージ同士が繋がっており、区切りの音を入れると繋がっているものを切ってしまうので鳴らさない（現状すでに無音で、これが正しい）。外から入る経路にだけ区切りが要る。
- 対応：`menu_sortie` を作り、外から入る経路でだけ鳴らす。いまセレクト経由では `menu_stage`（`ui_confirm`）が鳴っているので、置き換えるか後ろに重ねるかを決める。外から入る経路は2つ揃っている（セレクト経由とロード経由）＝比べる材料はある。
- 該当：`godot/assets/sfx-src/menu_sortie.mscz`（新規・MuseScore で短いファンファーレ）・`godot/data/audio/sfx_catalog.gd`（BIND）・`godot/presentation/select/stage_select.gd`（セレクト経由）・`godot/presentation/main/main.gd`（`_load_slot`＝ロードで盤へ入る経路）・`doc/audio/sfx.md`（発火点カタログ）。

### feature-51

**プロモーション映像の制作**
- 背景：ストアページに置く映像がまだ無い。1本目はプレイ映像（何のゲームか数秒で伝わるもの）、2本目に世界観のティザー、という並びを想定している。ティザー用の素材は 2026-08-12 の Gemini の無料枠で確保した（枠は同日で終了。以後の生成は有料）。生成でしか作れないカットは押さえてあるので、残りは手持ちの素材と実機録画で組める。
- 手元にあるもの：
  - ドラゴンのキービジュアル2枚（`godot/assets/promo-src/dragon_breath/`）。炎あり `dragon_breath_b_03_master.png` と、その直前＝炎なし `dragon_breath_pre_b_03_master.png`。1376×768・透かし除去済み。生成に使った文面は同フォルダの `*_prompt.txt`（自己完結・再生成可）。
  - 上記から起こした動画2本（`dragon_breath_video_b1_01_raw.mp4` / `b2_01_raw.mp4`。各10秒・1280×720・24fps・音声つき）。b2 が良いほうで、使えるのは 5.0〜10.0 秒（それ以前は炎がバリアの内側に入る）。b1 は 0〜7 秒（溜めが長く空転する）。
  - 酒場の扉が開くカット（`godot/assets/menu/door_open.ogv`＝タイトル画面で使用中。採用しなかったテイクが `godot/assets/menu-src/door/`）。ティザーの掴みに流用できる。
- 対応：
  1. 手持ち映像の整形。透かしは 1280×720 のフレームで中心 (1158, 600)・約55px角。`crop=1130:636:0:0` で左上基準に切れば16:9のまま枠外に出る（右と下を12%落とす。ドラゴンの尻尾の先が少し切れる）。あわせて使える区間だけ切り出す。
  2. プレイ映像の録画。ティザーの着地にも、ストア1本目にも要る。盤・戦闘演出・陣形カットインが揃ってから撮る。
  3. 構成を決めて編集。ティザーの想定は 掴み＝扉が開く／山場＝ドラゴンの炎／着地＝盤面。生成映像はイラスト調のまま使い、最後に実機の絵で落とすことで「本編と地続き」に見せる。
  4. 音。生成映像に付いてくる音声は捨てて、投入済みの BGM から当てる（[bgm.md](audio/bgm.md)）。
  5. Steam の AI 生成コンテンツ開示。生成物を使う以上、提出フォームでの申告が要る（[direction.md](art/direction.md) の配布注意）。
- 該当：`godot/assets/promo-src/dragon_breath/`・`godot/assets/menu-src/door/`・`doc/sales/monetization.md`。着手の引き金＝ストアページを作るとき（parking lot「Steam 配布の段取り」と連動）。

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
- 背景：配布はまず Steam（[monetization.md](sales/monetization.md)）だが、ストアページを作る段取りが未整理だった。埋めるスロットが多く一度に全部は動かせないので、購入判断への効き方で順序を付ける。素材の方針は [marketing.md](sales/marketing.md)、ページへの入力は [steam_page.md](sales/steam_page.md) が正本で、ここには段取りだけ置く。
- 埋めるスロット：
  - 画像＝カプセル5種（ヘッダー 460×215／小 231×87／メイン 616×353／縦 374×448／ページ背景 1438×810。寸法は提出時に Steamworks で最終確認）・ライブラリ用一式・スクリーンショット（1920×1080・5枚以上）
  - 動画＝順番付きで、1本目が自動再生される。ページ公開の必須要件ではない
  - テキスト＝ゲーム名／開発元・パブリッシャー名（craftkobo）／短い説明（〜300字）／本文（このゲームについて）／タグ（最大20・開発者の設定後にユーザー投票で並び替わる）／対応言語（ja・en をインターフェース／字幕／音声の別で申告）
  - 手続き＝価格（¥1,000）・リリース日・動作環境・年齢区分と表現の申告・AI生成コンテンツの開示
- 購入判断への効き方（この順で作る価値がある）：カプセル画像 ＞ スクリーンショット ＞ 短い説明 ＞ タグ ＞ 1本目の動画 ＞ 本文。判断は2段階で、一覧で開くかどうかを決めるのがカプセル・タイトル・タグ・価格、開いてから欲しくなるかを決めるのが動画・スクショ・短い説明・本文。発売前はレビューが無いぶん、前者の比重が大きい。
- 作る順序（上から依存している）：
  1. ロゴ。カプセル全種の前提。**作成済み**（2026-08-12。`godot/assets/promo-src/logo/` に暗背景版・明背景版・小サイズ版の SVG、`godot/tools/logo/` に生成スクリプト3本、方針と寸法は [logo.md](art/logo.md)）。PNG への変換は `godot/tools/rasterize_svg.gd`。残るのは用途ごとの書き出し
  2. カプセル画像。ロゴ＋背景の絵。背景は冒険者＋竜の構図が候補で、王道ゆえに1秒で伝わる。ジャンル（戦術SLG）はロゴのヘックスとタグと短い説明で伝える分担にする
  3. 短い説明・タグ。素材が要らないので並行して進められる
  4. スクリーンショット。盤・戦闘演出・陣形カットインが揃ってから撮る
  5. 本文。スクショと一緒に組む
  6. 動画（1本目＝プレイ映像、2本目＝ティザー。feature-51）
- Steamworks への登録（$100）は思ったより前に来る可能性がある。登録しないとページの入力欄が開かないため、素材を揃えてから登録するより、早めに登録して実際の入力欄を見たほうが作るものが具体的になる。[monetization.md](sales/monetization.md) の「体験版を先に出して出荷工程をリハーサルする」方針とも合う。前提＝支払い手段と本人確認、公開までに税務書類と銀行口座（feature-27 の開発元の項）。
- カプセルの検討結果（2026-08-12）：手持ちのドラゴンのキービジュアルを 460×215 に切って確認した。全幅を使って上下を16%落とす形なら構図がそのまま生きる。ただし小カプセル（231×87）まで縮めると読めるのは竜と炎だけで人物は潰れる＝5種を同じ絵から切り出すにしても、寄せ方は枠ごとに変えてよい。カプセル専用に絵を起こす場合は、最初から 460:215 の比で生成し、ロゴを置く余白（上部の空）を空けた構図にする。
- 該当：`doc/sales/steam_page.md`・`doc/sales/marketing.md`・`godot/assets/promo-src/`・`doc/sales/monetization.md`。関連＝feature-45（アプリアイコン）・feature-51（映像）・feature-52（仕様リファレンスへのリンク）・feature-27（サイトへ文と絵を流用）。着手の引き金＝配布ビルドが見えてきたとき（parking lot「Steam 配布の段取り」と連動）。

### feature-55

**ウィザードの絵を描き直す（＋冒険譚2のキービジュアル2枚）**
- 背景：元のウィザードの絵は顔が若く、見習いのメイジに流用した（`godot/assets/units/mage/`）。ベテラン5の一員としてのウィザードは、年季の入った術者として描き直す必要がある。いまウィザードは絵が無く、盤でも戦闘でも陣営色の板で出る（冒険譚2 全7話・冒険譚3 全7話・デバッグステージ4本・会話の顔＝portrait 未用意で map を流用）。あわせて冒険譚2のキービジュアル2枚（cover・victory）は、プロンプトで術者を「a YOUNG mage（NOT an old man）」と名指して描いてあるため、ウィザードを大人にすると絵の中の術者だけ旧デザインで残る。
- 対応：ウィザードの map と combat を同じ生成セッションで作る（[art/units.md](art/units.md) §3.3。テキストアンカーだけでは別セッションで同一キャラにならない）。プロンプトは `godot/assets/units-src/player/wizard/wizard_prompt.txt` を新規に起こす（見習いのメイジと並べて別人に見えること＝年齢・杖・ローブの格で差を付ける）。書き出しは `tools\gen_unit_map.ps1 wizard` と `tools\gen_unit_combat.ps1 wizard`。続けて冒険譚2の cover・victory も新しいウィザードで作り直す。
- 該当：`godot/assets/units-src/player/wizard/`・`godot/assets/units/wizard/`・`godot/assets/campaign-src/tutorial2-undead-rush/`・`godot/assets/campaign/tutorial2-undead-rush/`。着手の引き金＝絵を生成する回。

### feature-62

**販売チャネルごとの機能を乗せる**
- 背景：チャネルの判定そのものは `godot/infrastructure/platform/build_info.gd` が持つ（[build.md](tech/build.md)）。その上に乗るチャネル固有の機能がまだ無い。評価ランクの実績発火（feature-40）、entitlement による DLC 解放（feature-13）が控えている。
- 対応：`channel()` の戻り値で実装を選ぶ形にし、チャネルを持たない環境（エディタ実行・itch）には何もしない実装を置く。所有権チェックは `owns(content_id) -> bool` だけを本体に見せる（[monetization.md](sales/monetization.md) のチャネル差を隔離する）。
- 該当：`godot/infrastructure/platform/`・`doc/sales/monetization.md`。前提＝feature-40（GodotSteam 導入）・feature-13（entitlement）。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- 茂み（brush）の高さの詰め：見た目の高さ（`terrain_skin.csv` の `elevation`）を 0.12 で仮置きしている（駒の足元 `floor` は地面＝0）。茂みの絵そのものが仮のため、いま詰めても絵の差し替えでやり直しになる。本番の茂みタイルができたら実機で見て決める（→ [terrain.md](art/terrain.md)）。
- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
