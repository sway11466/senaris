# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。冒険譚の中身を作る作業（クロニクルの本文・ステージ実装）は [backlog_scenario.md](backlog_scenario.md) に分けてある。

## index

次回採番: bug=12 / feature=136 / refactoring=23.

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。ゴールは、その作業で何が達成されていれば終わりなのかを1文で書く。手段ではなく到達点を書く（「タグを決める」ではなく「棚に並んだとき誰の隣に出るかが決まっている」）。作業の途中で軸がずれるのを防ぐために置く。

考慮外は、外したい軸があるときだけ足す。「この作業では○○は考えない」と書く。書いていなければ制限は無い。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

### feature-13

**entitlement（DLC所有）判定によるステージ解放**
- 背景：ステージセレクトの解放は現状「クリア連鎖」だけで、有料DLC（冒険譚）の所有チェック（entitlement）が未配線＝販売時に「持っていれば解放」を判定できない（[stage_select.md](gdd/stage_select.md)）。Steam DLC 連携が前提。解放ゲート `_is_satisfied` は `cleared` のみ対応で、entitlement を含む未知条件は locked 扱い。表示側の `unlock_text` には entitlement 条件を「追加コンテンツ」と示す分岐が既にあるが、実際の充足判定の口が無い。
- 対応：所有判定の口を `CampaignProgress` に足し、DLC冒険譚は entitlement 充足で解放。Steam 側は GodotSteam 導入時に配線する。口は `Platform.ownership.owns(content_id)`（[tech/platform.md](tech/platform.md)）。本体は main が持つ `Platform` を受け取って呼ぶ。
- 該当：`godot/application/campaign_progress.gd`・`godot/presentation/select/`・`doc/gdd/stage_select.md`。着手の引き金＝Steam の体験版に向けて Steamworks に登録するとき（[monetization.md](sales/monetization.md) 出す順序）。

### feature-40

**Steam 実績・Stats の配線（GodotSteam 導入）**
- 背景：実績と計測の方針は [monetization.md](sales/monetization.md)（実績・計測）で決めたが、実装側の入り口が無い。GodotSteam は未導入（`godot/infrastructure/platform/` は空）で、実績を立てる呼び出しも Stats を刻む発火点も置き場所が決まっていない。実績はリリース後に削除・改名できない（解除済みの記録が消える）ため、セットの確定は 1.0 のストア提出前が締め切りになる。
- 対応：(1) GodotSteam を導入し `godot/infrastructure/platform/` の裏に隔離する（feature-13 の entitlement 配線と同じ層・同じ段）。アダプターと部品の構造は [tech/platform.md](tech/platform.md) にあり、Steam の3部品（`SteamDlcOwnership`・`SteamAchievements`・`SteamStats`）は呼ばれたらエラーを出す仮の形で置いてある。その中身と、Steamworks の初期化に失敗したときの終了、体験版の実績ファイルの流し込みをここで書く。(2) 実績の発火点＝冒険譚の完走判定。完走判定は `CampaignProgress` にあり、ランクも進捗セーブに入る（[stage_select.md](gdd/stage_select.md) クリア記録）ので判定はここに寄せる。最上位ランク達成時は下2段も同時に付与（取りこぼし防止）。(3) Stats の発火点＝ステージの開始とクリア。全ステージではなくチュートリアルに絞って刻む（見たいのは最初の1時間の離脱）。(4) 体験版のセーブを本体と共有 Steam Cloud に置き、購入後の本体初回起動でまとめて付与する経路（Valve 推奨。体験版では実績を発火させない）。
- 該当：`godot/infrastructure/platform/`（GodotSteam の隔離・新規）・`godot/application/campaign_progress.gd`（完走判定・ランク記録）・`godot/infrastructure/save/progress_store.gd`（Cloud 配置）・`doc/sales/monetization.md`。着手の引き金＝下の段階1と2は登録前から進められる。段階3は Steamworks に AppID を登録したとき（[monetization.md](sales/monetization.md) 出す順序）。前提＝ランクの評価式（[rank.md](gdd/rank.md)）は実装済み。
- 導入の形：GodotSteam は GDExtension 版（`godot/addons/` に置くアドオン）を採る。GodotSteam 同梱のエディタは使わない＝手元の Godot エディタと二重管理になる。
- 進め方（登録前に進められる範囲）：
  1. 登録なし・Steam なし。dev アダプター（[tech/platform.md](tech/platform.md)）の上で、実績の発火点・所有チェックの呼び出し・Stats の刻む場所を全部作る。エディタと GUT はここで回る。GUT は Steam 実装を通さず、アダプターの選択と部品の挙動だけを見る。
  2. 登録なし・テスト用 AppID 480（Valve が公開している Spacewar）。GodotSteam を入れ steam アダプターを書き、480 に繋いで初期化・実績の読み書き・Stats の送信が通ることを確認する。実績名は Spacewar に定義済みのものを仮に使う。Senaris 固有の実績の定義・DLC の所有チェック・体験版と製品版のセーブ共有は 480 では試せない。
  3. 登録あり・自分の AppID。管理画面で実績・DLC・Cloud を定義し、AppID と実績名を差し替えて本番確認する。
- 手元で Steam 実装を動かす条件：Steam クライアントが起動しログイン済みであること。Steam を経由せず起動するため、AppID を1行書いた `steam_appid.txt` を作業ディレクトリ（エディタならプロジェクトルート、ビルドなら exe の隣）に置く。このファイルは配布物に入れない＝Steam から起動されるときは Steam が AppID を渡す。
- 要確認（AppID 取得後に管理画面で）：体験版の AppID で Stats が使えるか（Steamworks のドキュメントは体験版について実績にしか触れていない）。Steam Cloud のセーブ置き場（実績ファイルを含む）をコードで切り替えるのか、Steamworks 側の設定（Auto-Cloud）だけで済むのか。実績上限100の緩和条件＝Profile Features のしきい値。

### feature-27

**タイトル名「Senaris」の確定手続き**
- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済み。確定前の手続きが残っている。すべてオーナー側の手作業。商標の一次スクリーニングと Bluesky ハンドルは済み（結果は同 doc の事前チェック結果サマリ）。Discord は作品名義で取らず、開発元のサーバーで持つ（[marketing.md](sales/marketing.md) Discord）。
- 対応：(1) X のハンドル。X は使わない方針（[marketing.md](sales/marketing.md) SNS）で、名前の予約だけするかは未決。(2) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`。着手の引き金＝Steam の体験版に向けて Steamworks に登録するとき（[monetization.md](sales/monetization.md) 出す順序）。

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

### feature-46

**タイトル画面の残り（クレジット画面）**

- 背景：タイトル画面そのものは入った（起動→扉が開く動画→店内のメニュー。仕様 → [title.md](gdd/title.md)）。残るのは、クレジット画面。置き場はタイトルのメニューから設定画面の末尾へ移した（[settings.md](gdd/settings.md) クレジット、2026-09-20）＝タイトルの板からクレジットの項目を外し、並びをマニュアル→クロニクル→設定にする作業も含む。
- クレジット：素材の権利表記。タイトルのメニューに項目だけ置いてあり、受け口が無く押せない状態。画面に出す内容は [credits.md](sales/credits.md) の「ゲーム内クレジットに出すもの」が正本で、そこを読んで並べるだけにする。台帳の整備自体は済んでいるが、根拠が取れていないライセンスが残っている（feature-54）。リリース前が締め切り。
- クレジット画面の作り（決めたこと）：新規シーン `godot/presentation/credits/` を1枚。設定画面の末尾の板から開く＝タイトルからも盤のシステムメニュー経由でも設定の中から届く。盤の上でも進行は止めない（設定画面と同じ）。戻るは左下の木の板ボタンで、位置と大きさはセレクトと同じ規則に揃える（[stage_select.md](gdd/stage_select.md)）。地は中立の暗色（起動スプラッシュと同じ `#0d1925`）＝操作の道具は酒場の物にしない（[title.md](gdd/title.md)）。押せる物だけが木の板、という様式は保つ。見た目は実物を見てから詰める。文言は `menu.csv` に足す（キーは `ui.<画面>.<項目>` → [i18n.md](tech/i18n.md)）。
- 該当：`godot/presentation/settings/settings_screen.gd`（開き口の板）・`godot/presentation/credits/`（新規）・`godot/presentation/title/title_screen.gd`（項目を外す・並べ替え）・`godot/data/i18n/menu.csv`・`doc/gdd/settings.md`。関連＝feature-66〜69（UI文言の i18n キー化）。戻るの位置は設定画面を手本にする。着手の引き金＝配布ビルドが見えてきたとき。

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

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／ゴール／対応／該当 で記す。

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
- 背景：正本は [formations.md](gdd/formations.md)「一覧（決まった項目）」の表A/表B、実行時は `godot/domain/formation/formation.gd` の `RECIPES`（ハードコード）、表示名は `godot/data/i18n/skills.csv` の `recipe.<id>.name/desc`。3か所が別々に育つ（トリックショット〜マジックアローは doc だけ、トリニティノヴァ・グレイス・ディバインジャッジメントの `desc` が無い、混沌の2本は code に無い）。CSV/JSON 化は見送り（[architecture.md](tech/architecture.md) 入れ子データはコードが持つ）なので、照合で守る。
- 対応：(1) `godot/tools/` に formations.md の表A/表Bを読む小さなパーサ（`| id | 名前 | …` の行を拾い、id・人数・形・射程・実装列を辞書に）。(2) GUT テスト `test_formation_catalog.gd`：表の id のうち実装列が「済」のものは `RECIPES` に在り、`count`・`shape`・`range` が一致すること／`RECIPES` の id はすべて表に在ること／`skills.csv` に `recipe.<id>.name` と `.desc` が在ること（ユニットスキルは skills.md の見出しで同様に）。(3) トリニティノヴァ・グレイス・ディバインジャッジメントの `desc` を `skills.csv` に足す。(4) 表の書式を崩すと落ちるので、formations.md の一覧の冒頭に「列は固定」の注意を置く（記入済み）。
- 考慮外：効果の数値（威力・倍率）の照合＝表現が文なので見ない。CSV/JSON 化。
- 該当：`godot/tools/`・`godot/tests/small/domain/test_formation_catalog.gd`・`godot/data/i18n/skills.csv`・`doc/gdd/formations.md`・`doc/tech/testing.md`（テストの位置づけを1行）。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- **隠し駒（視線に入るまで盤に出ない敵）。** 荷の陰・物陰に潜む敵を、味方の索敵に入るまで盤に出さない。出た瞬間は動かず、次の敵ターンから襲う＝1発は必ず受けるが、受けるのは兵数だけ。確定ゲームの方針（[ai.md](gdd/ai.md) 特性と部隊はプレイヤーに見せる）に穴を開けるので、入れるなら条件を守る＝食らっても駒を失わない／覚えた後にも選択が残る／やり直しが安い／潜んでいたことが物語の絵になる／冒険譚の中で1回だけの手口にする。戦闘前の会話で警告を1行置く。実装は駒の不可視・視線で露見・露見まで AI が動かない・描画の4点。邪神三部作 第1部 st2（倉庫）の検討で出た案。今回は見送り、崩せる積み荷（既存のバリケード型）で代替した。
