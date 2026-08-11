# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=3 / feature=50 / refactoring=9

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。優先度は各エントリ見出しに 高（設計の背骨に関わる）／中／低（飾り・潜在）で記す。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### feature-2

**敵AI: retreat（撤退）軸の配線**（優先度：低）

- 背景：AI思考の6軸のうち retreat（撤退閾値＝兵数がこの値を下回ったら退く／ただし自軍拠点が無ければ退かない。[ai.md](gdd/ai.md)「3. 撤退」）は、ai.csv に列・既定（`0`＝退かない）があり `DEFAULT_PRESET` にも入っているが、`nearest_attacker_brain` がこの値を読んでいない＝**未配線**で、現状は常に退かない。既定値の設計は済んでおり、残るのは挙動の実装のみ。
- 対応：`nearest_attacker_brain` に撤退判定を足す（`_param(state, u, "retreat")` を読み、兵数 < 閾値 かつ自軍拠点あり のとき退く＝拠点方向へ後退／交戦回避）。部隊ごとの上書きは既存の `_param` 解決でそのまま効く。実装後に ai.md の「retreat は未配線」記述を更新。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`（テスト追加）・`doc/gdd/ai.md`（記述更新）。ai.csv は列既存のため変更不要。

### feature-4

**敵AI: 思考軸の残り値の配線**（優先度：中）

- 背景：AIの各軸のうち一部の値しか効いていない（[ai.md](gdd/ai.md) §4〜6・§1）。実装済みは skill=`always`/`surround_able`/`surrounded`、skill_target=全値、attack=`always`/`prey`/`surround_able`/`surrounded`、target=`near`/`weak`、advance=`max`/`base`/`flank`、engage=`charge`/`sight`/`squad`。未実装は attack の `solo_adv`/`no_retal`/`kill`、target の `maxdmg`/`mindmg`/`capturer`/`ranged`/`flyer`、advance の `spacing`（間合維持＝キティング）/`squad`/`careful`、engage の `turn:N`。ai.csv には列・表記があり、読み手（Brain）が未対応。retreat 軸は別途 feature-2。
- 対応：`nearest_attacker_brain` の `_pick_target`／攻撃判定／`_advance_dest`／`_ensure_engaged` に各値の分岐を足す。射程ユニットの間合維持（spacing）は AI の質に効く本命。値ごとにテストを足す。
- 優先して要るのは target の `flyer`（飛行を優先して狙う）。飛行は `atk_air>0` の駒でしか触れないので、対空を持つ敵が地上の駒を殴っている間、こちらの飛行は事実上の安全地帯になる。対空持ちが「空を狙える唯一の駒」であることを AI が理解しない限り、飛行の価値が壊れたままになる（竜狩り st5＝ハーピー／グリフォンが空で絡む回で効く）。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`・`doc/gdd/ai.md`（各軸の実装状況を更新）。ai.csv は列既存のため変更不要。

### feature-6

**敵AIの乗降（輸送を使う敵）**（優先度：低）

- 背景：プレイヤー側の輸送（乗降）は実装済みだが、敵AIは乗降しない（[movement.md](gdd/movement.md)「敵AIは乗降しない（当面）」）。`domain/ai/` に board/unload/passenger 参照が無い。
- 対応：`nearest_attacker_brain` に乗車・降車の判断を足す（輸送で運ぶ／目的地付近で降ろす）。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`・`doc/gdd/movement.md`。

### feature-7

**地形・移動タイプの拡充（水辺・騎乗・水棲）**（優先度：低）

- 背景：地形は13種（`terrain_type.csv`）・移動タイプは7種（`movement.csv`）で、水辺（水系）地形と騎乗・水棲の移動タイプが未整備（[movement.md](gdd/movement.md)：水辺コスト未定・移動タイプ拡充が残作業）。水辺が無いため海/川マップが組めない。
- 対応：`terrain_type.csv` に水辺を足し、`movement.csv` に水辺コスト列と騎乗・水棲行を足す（CSV正本→JSON生成のパイプラインに乗せる）。関連する既定スキン画像も要る。
- 該当：`data/terrain/terrain_type.csv`・`data/terrain/terrain_skin.csv`・`data/movement/movement.csv`・`doc/gdd/movement.md`。

### feature-8

**タッチ操作対応（uiux フェーズ4）**（優先度：低）

- 背景：モバイルは後回し方針（CLAUDE.md）だが、[uiux.md](gdd/uiux.md) §フェーズ4 が未実装。タッチ操作一式（タップ選択・1本指パン・ピンチズーム・長押しキャンセル）のハンドラが無く、全体表示も `F` キーのみ＝キーボードの無いタッチ環境では全体表示に到達不能。
- 対応：`hex_board_3d.gd` の `_unhandled_input` に `InputEventScreenTouch`/`ScreenDrag`/長押しを足す。`hud.gd` に全体表示ボタン（タッチ用・画面ボタン必須）を足す。
- 該当：`presentation/board/hex_board_3d.gd`・`presentation/ui/hud.gd`・`doc/gdd/uiux.md`。着手の引き金＝モバイル配布を見据えたら。

### feature-9

**セーブ／ロード**（優先度：中）

- 背景：盤の状態を永続化・復元する機能（[uiux.md](gdd/uiux.md) §フェーズ3・[gamesystem.md](tech/gamesystem.md) がセーブ仕様の正本）。中断セーブの単枠クイックセーブ/ロードは実装済み（Phase 4a/4b＝下記「進捗」）。残るのは複数スロットUI（4c）とターン毎オートセーブ（Phase 5）、および live 配線の実機確認（保留）。土台の `Unit` 直列化は戦力供給の持ち越し（carryover）と共有で、そちらは実装済み。
- 対応（済・Phase 4a/4b）：`BattleState` 全状態の直列化（`to_dict/from_dict`）＋ `SaveStore`（`user://save.json`・1枠）＋ HUD の「セーブ」有効化・「ロード」を保存有無で切替。詳細は下記「進捗」。
- 対応（残・4c/Phase 5）：複数スロットUI（枠一覧・上書き確認・スロット別ファイル）と、ターン毎オートセーブ（中断セーブの応用＝ターン開始/終了で自動保存・別枠）。
- 前提：戦闘に乱数が無いので中断セーブはシード不要＝状態だけで完全再現。性能はデータ駆動なので、スナップショットは `type_id`・`skin_id`・`level`・`troops`・`max_troops` を持てば足りる（他は type から `UnitCatalog` で再構築＝数値を焼かない）。
- 該当：`domain/battle_state.gd`（直列化）・`presentation/ui/hud.gd`（項目有効化）・`application/`（保存/読込の配線）・`doc/tech/gamesystem.md`。
- 進捗（2026-07-18）：中断セーブの単枠クイックセーブ/ロードまで実装＝`BattleState.to_dict/from_dict`（全状態・盤情報つき `Unit.to_full_dict`／`Base.to_dict` 再利用）／`SaveStore`（`user://save.json`・version＋破損フォールバック）／HUD の「セーブ」有効化・「ロード」を保存有無で切替／main は `_install_state` を新規開始と復元で共有（復元は intro なし・movement 再適用）。直列化と SaveStore は round-trip テスト済み（`test_battle_state_serialization`・`test_save_store`）。残り＝複数スロットUI（4c）／ターン毎オートセーブ（Phase 5）。main/hud の live 配線（セーブ→ロードで盤が戻る）の実機確認は保留。

### feature-10

**製品ビルドから開発用アセットを除外（ツール・デバッグステージ）**（優先度：低）

- 背景：`tools/`（戦闘計算シミュレータ combat_sim ほか自作ツール一式）とデバッグ用ステージ（`data/stages/debug*/`）は開発専用で、製品ビルドに含めるべきでない。現状 export preset が未作成のため除外設定もされておらず、このままビルドすると同梱される。
- 対応：export preset を作る段で、非公開フィルタ（除外パターン）に `tools/` とデバッグステージのパスを加える。あわせてデバッグステージが実行時参照（ステージセレクトのマニフェスト／カタログ）に載らないことも確認する。
- 該当：`export_presets.cfg`（新規）・`tools/`・`data/stages/debug*/`・ステージ一覧の参照箇所。着手の引き金＝配布ビルドを作るとき（parking lot「Steam 配布の段取り」と連動）。

### feature-12

**表示名・UI文言の i18n キー化移行**（優先度：高）

- 背景：多言語対応の方針は [i18n.md](tech/i18n.md) で確定（海外販売必須のため ja+en）。会話・冒険譚名は翻訳キー化済みだが、(1) ユニット・地形・移動タイプの表示名がデータCSVの `name` 列（日本語直書き）のまま情報パネル等に表示され、(2) HUD・情報パネル・勝敗表示など GDScript 直書きの UI 文言が `tr()` を通っていない。この2系統は現状英語にできない。
- 対応：(1) `data/i18n/units.csv` を新設し、規約キー（`unit.{skin_id}.name`・`terrain.{skin_id}.name`・`movement.{id}.name`）で表示名を解決。`UnitSkin`/`TerrainSkin`/`Movement` の表示名参照を `tr()` 経由に差し替え、データCSVの `name` 列は開発用メモに降格。(2) `data/i18n/ui.csv` を新設し、presentation の直書き文言（`ui.*` キー）を一括キー化。test_i18n_translation の検出範囲に新CSVを加える。
- 該当：`data/i18n/`（units.csv・ui.csv 新規）・`data/units/unit_skin.gd`・`data/terrain/terrain_skin.gd`・`data/movement/movement.gd`・`presentation/ui/`（hud・unit_info_panel ほか）・`project.godot`（translation 登録）・`tests/unit/test_i18n_translation.gd`・`doc/tech/i18n.md`。

### feature-13

**entitlement（DLC所有）判定によるステージ解放**（優先度：低）

- 背景：ステージセレクトの解放は現状「クリア連鎖」だけで、有料DLC（冒険譚）の所有チェック（entitlement）が未配線＝販売時に「持っていれば解放」を判定できない（[stage_select.md](gdd/stage_select.md)）。Steam DLC 連携が前提。解放ゲート `_is_satisfied` は `cleared` のみ対応で、entitlement を含む未知条件は locked 扱い。表示側の `unlock_text` には entitlement 条件を「追加コンテンツ」と示す分岐が既にあるが、実際の充足判定の口が無い。
- 対応：所有判定の口を `CampaignProgress` に足し、DLC冒険譚は entitlement 充足で解放。Steam 側は GodotSteam 導入時に配線（それまではローカルで常時充足扱い等の切替）。
- 該当：`application/campaign_progress.gd`・`presentation/select/`・`doc/gdd/stage_select.md`。着手の引き金＝配布ビルド（parking lot「Steam 配布の段取り」と連動）。

### feature-16

**移動/カメラ演出の速度設定・敵ターンスキップ・演出の適用範囲拡張**（優先度：低）

- 背景：敵の全行動を見せる（移動アニメ＋カメラ追従）ぶん、敵が多いターンは総時間が伸びる。アニメ速度の設定（高速／標準／オフ）と敵ターンのスキップは SLG の定番だが、設定画面もスキップ導線も未実装（[uiux.md](gdd/uiux.md) システムメニュー・敵ターンのカメラ）。また演出には未対応の隙間がいくつかある。
- 対応：(1) 設定画面を作る段で、移動アニメ速度（`MOVE_ANIM_SEC_PER_HEX`／`MOVE_ANIM_MAX_SEC`）とカメラ追従（`FOCUS_PAN_SEC`）を設定値から引く。戦闘演出の速度（[combat_scene.md](tech/combat_scene.md) テンポ・スキップの「フル／短縮／オフ」3段）も同じ設定に乗せる＝置き場所が決まっていないのはこれだけで、AIターンの短縮は仕様だけあって未実装。(2) 敵ターンのスキップ（キー／ボタンで残りを一気に最終状態へ）。(3) 出撃・降車は経路を持たずポップして現れる＝拠点／輸送から目的マスへの1歩スライドで見せる（経路探索は不要）。(4) カメラ追従は行動主体の現在位置だけを見る＝長距離移動でアニメ中に終点が画面外へ出るケースの追随、攻撃で対象も画面に含める配慮は未対応（現状は移動距離が短く実害小）。
- 該当：`presentation/board/hex_board_3d.gd`（`focus_camera_on`／移動アニメ）・`application/match_controller.gd`（ターンのテンポ・スキップ）・設定の永続化（feature-9 のセーブと同居）・`doc/gdd/uiux.md`。着手の引き金＝設定画面を作るとき／敵ターンが長く感じ始めたら。

### feature-19

**戦果票の評価ランク（S/A/B/C）**（優先度：中）

- 背景：決着の戦果票（[uiux.md](gdd/uiux.md) §決着の演出・`presentation/ui/result_banner.gd`）は ターン数／生存／撃破 の3行を出すところまで実装済み。ジャンルの定番である**評価ランク**（Advance Wars の S/A/B/C 型）が無い。ランクは「同じ勝ちでも上手い勝ちがある」を一目で示す指標で、再挑戦の動機になる（速攻を狙う・主力を死なせない）。実装より**評価式の設計**が本体で、ステージごとの妥当な閾値決めはバランス調整＝ステージが揃ってからでないと決められないため後回しにした。
- 対応：評価式を決めてから実装する。(1) 指標の選定＝ターン数（速さ）・損害（生存率）・撃破率あたりの合成。(2) 閾値の持ち方＝ステージJSONに `rank` として書く（ステージごとに適正ターン数が違う）か、`turn_limit` からの相対で自動算出するか。データに書くならステージ数ぶんの調整作業が要るので、まずは相対算出で始めるのが軽い。(3) 表示＝戦果票の3行の下にランクを大きく出す（`_fill` に行を足すだけの構造にしてある）。印とは別要素なので、印の下に重ねない位置を選ぶ。
- 該当：`presentation/ui/result_banner.gd`（`_fill` にランク行）・`presentation/main/main.gd`（`_result_rows` の隣に評価の算出）・評価式の置き場所は `application/`（ゲームルール＝presentation に式を持たせない）・`data/stages/*.json`（閾値をデータに置く場合）・`doc/gdd/uiux.md`。着手の引き金＝ステージが揃ってバランス調整に入るとき。
- 関連：撃破数の集計は現状 presentation 側で「開始時の敵数 − 残存」で採っており、拠点の控え（garrison）が出撃してから倒された分を数え落とす（`main._result_rows` のコメント）。ランクの入力に撃破を使うなら、先に `domain` 側で撃破を正確に数える必要がある。
- 関連（実績）：Steam 実績を冒険譚単位×3段（踏破／全ステージを上位ランク以上／全ステージを最上位ランク）で出す方針になった（[monetization.md](sales/monetization.md) 実績・計測）。ランクが実績の入力になるため、ここで決めることが増える：(1) 段の数と呼び方（S/A/B/C のままか、ブロンズ／シルバー／ゴールド系にするか）、(2) 実績が参照する段＝どこ以上を「上位」とするか。実績はリリース後に削除・改名できないので、評価式は 1.0 までに固める必要がある＝着手の引き金に「1.0 のストア提出前」が加わる。

### feature-20

**ドリフト検出の自動化（doc↔コードの突き合わせ）**（優先度：中）

- 背景：仕様駆動（spec-anchored・[development.md](tech/development.md)）で進めるが、doc（gdd/tech/campaign）とコードの一致を機械的に検証する手段が無く、現状は目視頼み。自動テストが守るのはコード同士と CSV正本↔生成物の整合まで（[testing.md](tech/testing.md)）で、doc の記述が実装とずれても誰も気づかない。doc が嘘を含むと、以後の設計判断とAIの参照がまとめて汚染される＝doc 量が増えるほど被害が効く。
- 対応：このゲーム専用のスキルを作り、doc と該当コードを AI に突き合わせさせて食い違いを報告させる。CI/CD には組み込まず、任意のタイミングで手動起動して報告を読む運用（単独開発＋探索の多い進め方にマージゲートは合わない）。設計の本体は対象範囲の与え方＝doc の章と該当コードの対応をどう持つか（各 doc に参照先を書く／スキル側に対応表を持つ／全文突き合わせ）、報告の粒度、誤検知の抑え方。全 doc を一度に見るより、gdd の1ファイルと対応する domain/ を突き合わせる最小構成から始めるのが軽い。
- 該当：`.claude/skills/`（新規スキル）・`doc/tech/development.md`（運用の記述）。突き合わせ対象＝`doc/gdd/`・`doc/tech/`・`doc/campaign/` と `domain/`・`application/`・`data/`。着手の引き金＝doc とコードのズレで手戻りが出たとき、または doc 量が目視で追えなくなったとき。

### feature-21

**BGM のたたき台仕上げと拡充**（優先度：低）

- 背景：BGM の制作方針は [bgm.md](audio/bgm.md) で確定。たたき台のうち `graveyard`・`boss` は仕上げて `.ogg` 化済み（投入済みは afterglow／boss／defeat／dungeon／graveyard／journey／menu／raid／title／victory）。残りの下書き（`forest`／`ruins`／`temple`／`ritual`／`boss2`／`crisis`）が `.mscz` のまま仕上げ待ち。全体既定（`BgmDirector.DEFAULT_STAGE_TRACK`＝`map_calm`）は ID に対応する曲が無い＝ステージにも冒険譚にも `bgm` 指定が無いと無音になる（チュートリアル1は全ステージに指定済みのため現在は該当なし）。
- 対応：(1) 残りの下書きの MuseScore 仕上げ（強弱・味付け・ループ点整備）と `.ogg` 化。`crisis` は切替機構を撤去したため当てる先が無い＝feature-44（イベント経由の切替）を入れるまで急がない。(2) 全体既定を投入済みの曲に変えるか `campaign.json` に既定を書くかを決定し反映。
- 該当：`assets/bgm-src/`・`assets/bgm/`・`application/bgm_director.gd`（`DEFAULT_STAGE_TRACK`）・`doc/audio/bgm.md`（ライブラリ表更新）。着手の引き金＝ステージに曲を当てたくなったとき。

### feature-26

**デバッグステージの構成見直しと拡充**（優先度：低）

- 背景：デバッグ冒険譚は機能別6カテゴリに分かれており、既存ステージは計18枚（台帳＝[debug-stages.md](tech/debug-stages.md)）。カテゴリの分け方と既存ステージの役割は見直し済み（旧 siege.json は base.json＝拠点と勝敗に統合、旧 debug.json の総合マップは廃止して各カテゴリへ吸収）ので、残るのはカバーの隙間を埋める追加のみ。戦闘の補正チェーンを1つずつ切り分ける盤がまだ無く、そこが一番厚い。
- 対応：不足しているデバッグステージを追加する。対象は以下。
  - combat: 地形補正／間接／魔法／対空・対地／包囲／支援／レベル補正（7件）
  - ai: charge／raid（2件。起動トリガー見本は sight.json が担う）
  - victory: 殲滅／自軍hq喪失で敗北／複数条件OR（3件。既存 defend_two は AND）
  - mapops: 陣形②③／飛空艇・初期搭乗（2件。拠点は base.json で済）
  - skins: 構造物系タイル（1件）
  - misc: 追加の演出・UI検証（1件）
- 該当：`data/stages/debug-*/`・`doc/tech/debug-stages.md`（台帳更新）。着手の引き金＝機能を足してデバッグステージが欲しくなったとき。

### feature-27

**タイトル名「Senaris」の確定手続き**（優先度：低）

- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済みだが、確定前の手続き4件が残っている。すべてオーナー側の手作業で、いずれも未着手＝ドメインもハンドルも1つも取得していない。`.net` は第三者（Senaris Network＝ルーマニアの小規模コミュニティ）が使用中、Steamコミュニティ `id/senaris` も他者が使用（いずれも要再確認）。
- 対応：(1) 商標クリアランス＝第9類・第41類で US(USPTO)／EU(EUIPO)／日本(J-PlatPat) の各DBを正式確認。(2) `senaris.com` ドメイン取得（`.com` を主軸に）。(3) SNSハンドル確保（X／Bluesky／Discord 等）。(4) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`。着手の引き金＝配布が見えてきたとき（parking lot「Steam 配布の段取り」と連動）。

### feature-28

**ユニットスキル第2弾（貫通追加・再行動）**（優先度：中）

- 背景：ユニットスキルの器（単独発動・味方1体へ状態補正・移動後発動）は①ピクシーダストで実装済み（[skills.md](gdd/skills.md)）。カタログを増やす段で、次に入れる2つの方向まで決まっている＝(1) 貫通追加＝対象の攻撃に貫通率を乗せる、(2) 再行動＝行動を終えた味方をもう一度動かす。どちらもレシピは未設計（発動者・値・持続・射程が未定）でカタログにも載っていない。
- 対応：(1) 貫通追加は既存の状態補正で足りるか要確認＝`StatusMod` は攻防への add/mul は持つが、貫通率（`Unit.pierce`）に効く経路が無いため、補正チェーンに貫通の口を足すかどうかから決める。(2) 再行動は「1ターンに各ユニット1回まで」の縛りを入れる方針まで決定済み（無制限だと1体を延々動かせて崩壊する）。縛りの持ち場は駒側のフラグ＝`BattleState` に再行動回数を持たせ、中断セーブの直列化にも載せる。レシピが固まったら skills.md のカタログへ②③として追記する。
- 該当：`domain/formation/formation.gd`（RECIPES）・`domain/battle_state.gd`（再行動フラグ・直列化）・`domain/status/status_mod.gd`／`domain/combat/combat.gd`（貫通の口）・`tests/unit/test_skill.gd`・`doc/gdd/skills.md`。

### feature-29

**敵AIの陣形スキル使用（複数人）**（優先度：中）

- 背景：ユニットスキル（発動者1体）は敵も撃つようになった（思考軸 `skill` / `skill_target`＝[ai.md](gdd/ai.md) §4・§5）。残るのは複数人の陣形スキルで、敵陣営向けのレシピが1つも無い。実行経路は `AiAction.SKILL` で共通なので、レシピを足せば同じ仕組みで飛ぶ。成立条件はスキンID照合（未指定は種別へフォールバック）＝データ面の下地はできている。
- 対応：(1) 敵陣営向けのレシピをカタログに足す（どの敵に何を持たせるかは冒険譚側の設計）。(2) 撃つ価値の評価を足す＝ユニットスキルは「対象1体」で選べたが、面の陣形は着弾中心の選び方（面に入る敵の数・味方の巻き込み）が要る。`_pick_skill_target` は対象1体を前提にしているのでここを広げる。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`domain/formation/formation.gd`（敵レシピ）・`tests/unit/test_ai.gd`・`doc/gdd/ai.md`・`doc/gdd/formations.md`（発動主体の記述を更新）。着手の引き金＝敵に陣形を持たせたい冒険譚を作るとき。

### feature-31

**体験版ビルドの素材選別（収録ステージから必要素材を導出して除外）**（優先度：低）

- 背景：体験版はチュートリアル3本のみを収録し、本編の冒険譚は入れない（[monetization.md](sales/monetization.md) 体験版の収録範囲）。収録しない冒険譚のユニット・地形・BGM・会話まで同梱するとサイズが無駄で、未収録分のネタバレにもなる。Godot のエクスポートプリセットは除外フィルタ（glob）・カスタム機能タグ（`OS.has_feature("demo")`）・CLI ビルドを備えるので機構は足りる。ただし素材は `skin_id` から文字列でパスを組み立てて `load()` する（`skin_catalog.gd`・`combat_scene.gd`・`hex_board_3d.gd`）ため、Godot の依存解決＝「選択したシーンと依存だけ」モードは効かない。必要素材の集合はこちらで計算して渡す必要がある。
- 対応：収録ステージJSON → 出現ユニット/地形の `skin_id`・BGM の `track_id` → 必要な `assets/**` パス集合、を導出して差集合を除外フィルタとして `export_presets.cfg` に書き出すスクリプトを足す（CSV正本→JSON生成と同じ発想＝正本から機械的に導出するので、収録ステージを足し引きしても壊れない）。代替は `EditorExportPlugin._export_file()` + `skip()` でエクスポート中に弾く方式＝フィルタ生成は不要だが何が落ちたか見えにくい。除外すると `ResourceLoader.exists()` が false になるので、未収録ステージがステージセレクトに載らないこと・参照が残る経路のフォールバックを併せて確認する。`data/i18n` の翻訳と未収録の会話テキストも同じ仕組みに乗せられる。
- 該当：`export_presets.cfg`（新規）・`tools/`（フィルタ生成スクリプト新規）・`doc/tech/tools.md`・`doc/sales/monetization.md`。着手の引き金＝体験版ビルドを作るとき（feature-10＝開発用アセットの除外と同じ段・parking lot「Steam 配布の段取り」と連動）。

### feature-48

**羽ばたきの素材を採り直す**（優先度：中）

- 背景：`move_flight` に当てている上着の布音（Modern Cloth Foley の Whoosh Flutter）が、羽ばたきに聞こえない。素材が 0.42 秒あるのに間隔が 0.30 秒で、常に 0.12 秒ぶん重なって連続音になるため。翼を打つ一打ずつには分かれない。飛空艇（`move_propeller`）はこの連続音の性質をそのまま利用して同じ素材から作ったので、飛行側だけが宙に浮いている。
- 対応：一打で完結する素材に差し替える。Sonniss バンドルには使える羽ばたきが無いことが確認済み（[doc/audio/sfx.md](audio/sfx.md) の「バンドルに録音が無かったもの」）。外部の素材集を1本買うか、自録り（うちわ・厚紙・畳んだ布で空気を打つ）に切り替える。長さは 0.30 秒より短く収めて、重ならずに一打ずつ聞こえる形にする。ペガサスからレッドドラゴンまで1つで賄うので、翼の大きさが特定できない中庸な質感を狙う。
- 該当：`assets/sfx-src/move_flight_recipe.txt`・`assets/sfx/move_flight.ogg`・`assets/sfx-src/credits.md`・`data/audio/sfx_catalog.gd`（間隔）・`doc/audio/sfx.md`。着手の引き金＝素材を調達したとき。

### feature-35

**ユニットスキル ヴェノムファングのレシピ**（優先度：中）

- 背景：[skills.md](gdd/skills.md) の②ヴェノムファングだけレシピが無い。仕組みはもう通っている＝敵を対象にする指定（`buff_side: "enemy"`）はドレッドタッチで、有害な補正の解除はピュリファイ（効果の型 `cleanse`・`kind: "debuff"`）で実装済み。残るのはカタログにレシピを1本足すことだけ。[tutorial3 st3](campaign/tutorial3-dragon-hunt.md)（鉱脈の争奪）で、ロックサーペントの群れが重ねた毒を聖職のピュリファイが落とす形で出る。
- 対応：`RECIPES` に `venom_fang` を足す。ドレッドタッチとの違いは効き方で、あちらが加算（残兵数×-10）なのに対しヴェノムファングは係数（`op: "mul"`・値 1.0 未満）＝重ねても 0 にならず、行動不能にはならない。持続の数え方は共通。敵が撃つ思考側（`skill` / `skill_target`）は配線済み。
- 該当：`domain/formation/formation.gd`（レシピ）・`tests/unit/test_skill.gd`・`doc/gdd/skills.md`（持続の行を実装値に合わせる）。着手の引き金＝tutorial3 st3 を組むとき。

### feature-36

**陣形カットインの入り方を絵の構図に合わせて詰める**（優先度：低）

- 背景：カットインの入り方は絵が無い時期に決めた暫定で、フェード＋わずかなズーム（`ZOOM_FROM=1.06`）を3レシピ共通で掛けている。絵が揃ったいま、構図と噛み合っているかを見ていない。トリニティスペルとディバインジャッジメントは光が上へ抜ける縦の構図、ホーリーアリアは横に広がる構図で、同じ入り方が3枚とも最適とは限らない。窓は横長八角形（最大740×520）で絵は4:3なので、上下が少し切れることも合わせて確認する。
- 対応：3枚を実機で通しで見て、寄りの量・向き・秒数（`FADE_SEC`／`HOLD_SEC`）を詰める。レシピごとに変えるならレシピ側に持たせる。絵を差し替えたら見直す前提の調整なので、凝りすぎない。
- 該当：`presentation/formation/formation_cutin.gd`・`doc/gdd/formations.md`（発動の演出）。着手の引き金＝演出を通しで見て気になったとき。

### feature-37

**駒を生成するスキル効果（スライムの分裂）と新 type `slime`**（優先度：中）

- 背景：いまのユニットスキル・陣形スキルは「対象に状態補正を掛ける」効果しか持たず、盤に駒を増やせない。[tutorial3 st6](campaign/tutorial3-dragon-hunt.md)（洞窟）のスライムが、放置すると分裂して増える魔獣として要る＝「元から絶つか、無視して先を急ぐか」という選択を作る役。駒が増える機構は拠点の出撃（deploy）にしか無く、あちらは garrison の頭数が上限で拠点に紐づくため、盤上の駒が自分で増える形には使えない。
- 対応：スキル効果に「隣接する空きマスへ発動者の複製を1体置く」種別を足す。生成した駒の id 採番（既存の通し番号を継ぐ）・初期兵数（分裂で半減するか満員かは要設計）・増殖の上限（無いと殲滅勝利が終わらない＝盤上の同 type 上限か、分裂回数の世代上限）を決める。中断セーブに乗るので、生成された駒が `to_dict`/`from_dict` を往復することも確認する。あわせて `slime` 20/0/防20/移2/ground/射1 を unit_type に足す（弱く遅い地上の雑魚。`cleric` は数値が近いが占領可なので泉を取られてしまい使えない）。
- 該当：`domain/formation/formation.gd`（効果種別）・`domain/battle_state.gd`（駒の追加・直列化）・`data/units/unit_type.csv`＋`unit_type.json`（`slime` 行）・`data/units/unit_skin.csv`（スライムのスキン）・`doc/gdd/skills.md`（レシピ）・`doc/gdd/units.md`（対応表）・`tests/unit/test_skill.gd`。着手の引き金＝tutorial3 st6 を組むとき。関連＝feature-38（3ターンに1回に抑えるクールダウン）・feature-29（敵AIがスキルを撃つ）。

### feature-38

**スキルの再使用間隔（クールダウン）**（優先度：中）

- 背景：スキルは1ターンに1回という制限しか無く、「Nターンに1回しか撃てない」を表せない。[tutorial3 st6](campaign/tutorial3-dragon-hunt.md) のスライムの分裂は「3ターンに1回」で増えすぎないよう抑える設計で、これが無いと毎ターン倍々に増えて盤が埋まる。強力なスキルを設計する余地としても効く（いまは強すぎるレシピを載せられない）。
- 対応：レシピに再使用間隔を持たせ、駒ごとに「最後に撃ったターン」を記録して判定する。記録は中断セーブに乗せる（`_moved` 等と同じ扱い）。UIは撃てない理由の表示まで（残りターン数を出すかは要検討）。敵専用スキルなら表示は要らないが、プレイヤー側のレシピにも将来効くので器は共通にする。
- 該当：`domain/formation/formation.gd`（レシピの間隔）・`domain/battle_state.gd`（記録・直列化）・`presentation/ui/`（撃てない表示）・`doc/gdd/skills.md`・`tests/unit/test_skill.gd`。着手の引き金＝feature-37 と同時（分裂の抑制に要る）。

### feature-39

**逃走AI（交戦を避けて目的地へ走る）**（優先度：中）

- 背景：attack 軸に「殴らない」値が無く、`always`（射程内なら必ず殴る）か `prey`（獲物と確殺だけ殴る）しか選べない（[ai.md](gdd/ai.md) §4）。[tutorial3 st6](campaign/tutorial3-dragon-hunt.md) の手負いのローグ一味は「殴り合いに付き合わず泉へ走る」動きが芯で、追いつけないから部屋を回り込んで挟み撃ちにする、という盤の遊びがそこから出る。`raid`＋`prey` で近い動きは出るが、脆い駒が射程に入ると立ち止まってしまい「逃げている」感じが濁る。撤退（retreat＝兵数が減ったら退く。feature-2）とは別物で、こちらは最初から戦う気が無い側。
- 対応：attack 軸に `none`（撃たない）を足す。あわせて、逃走中は敵ZOCへ自分から入らない詰め方（`flank` の安全マス優先を目的地へ向けて流用）を検討する。ai.csv に `flee` プリセット（engage=charge／attack=none／advance=base）を1行足す。前進の道のり計算は実装済みなので、通路を塞げば回り込む挙動はそのまま乗る。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`data/ai/ai.csv`＋`ai.json`・`doc/gdd/ai.md`（§4 と プリセット表）・`tests/unit/test_ai.gd`。着手の引き金＝tutorial3 st6 を組むとき。関連＝feature-4（思考軸の残り値の配線）。

### feature-40

**Steam 実績・Stats の配線（GodotSteam 導入）**（優先度：低）

- 背景：実績と計測の方針は [monetization.md](sales/monetization.md)（実績・計測）で決めたが、実装側の入り口が無い。GodotSteam は未導入（`infrastructure/platform/` は空）で、実績を立てる呼び出しも Stats を刻む発火点も置き場所が決まっていない。実績はリリース後に削除・改名できない（解除済みの記録が消える）ため、セットの確定は 1.0 のストア提出前が締め切りになる。
- 対応：(1) GodotSteam を導入し `infrastructure/platform/` の裏に隔離する（feature-13 の entitlement 配線と同じ層・同じ段。Steam が居ない環境＝エディタ実行・BOOTH 版でも落ちないダミー実装を用意）。(2) 実績の発火点＝冒険譚の完走判定。完走判定は `CampaignProgress` にあり、ランクも進捗セーブに入る（[stage_select.md](gdd/stage_select.md) クリア記録）ので判定はここに寄せる。最上位ランク達成時は下2段も同時に付与（取りこぼし防止）。(3) Stats の発火点＝ステージの開始とクリア。全ステージではなくチュートリアルに絞って刻む（見たいのは最初の1時間の離脱）。(4) 体験版のセーブを本体と共有 Steam Cloud に置き、購入後の本体初回起動でまとめて付与する経路（Valve 推奨。体験版では実績を発火させない）。
- 該当：`infrastructure/platform/`（GodotSteam の隔離・新規）・`application/campaign_progress.gd`（完走判定・ランク記録）・`infrastructure/save/progress_store.gd`（Cloud 配置）・`doc/sales/monetization.md`。着手の引き金＝Steamworks に AppID を登録したとき（parking lot「Steam 配布の段取り」と連動）。前提＝feature-19（ランクの評価式）が先に要る。
- 要確認（AppID 取得後に管理画面で）：体験版の AppID で Stats が使えるか（Steamworks のドキュメントは体験版について実績にしか触れていない）。実績上限100の緩和条件＝Profile Features のしきい値。

### feature-41

**ユニットスキルの演出の手応え（シェイク・フラッシュの出し分け）**（優先度：低）

- 背景：ユニットスキルの演出（[combat_scene.md](tech/combat_scene.md) ユニットスキルの演出）は兵量バーが動かないので、戦闘から「減る」という一番大きな動きが抜ける。残るのはシェイク・フラッシュ・数値だけで、弱体（ドレッドタッチ・ヴェノムファング）と強化（ピクシーダスト・ピュリファイ）に同じ動きを当てると、強化されたのに殴られたように見えるおそれがある。
- 対応：レシピの `buff_harmful` で動きを分ける。有害なら被対象がひるむ（シェイク＋暗いフラッシュ）、そうでなければ光る（明るいフラッシュのみ・シェイクなし）、という向きが素直。数値の色も同じ基準で分けられる。分ける軸を新設せず既存のフラグを使うのは、値の符号から推測しないという [skills.md](gdd/skills.md) の方針と揃えるため。
- 該当：ユニットスキルの演出モジュール（`presentation/combat/`）・`doc/tech/combat_scene.md`。着手の引き金＝実際に動くものを見て、手応えが足りないと感じたとき（先に数値を決めても当たらないので、通しで見てから調整する）。

### feature-44

**ステージ途中のBGM切替（イベント経由）**（優先度：低）

- 背景：曲を途中で切り替える仕組みを `bgm` の `crisis` スロット＋永続フラグ＋`BgmDirector.enter_crisis()` として持っていたが、ゲームに配線されず使うステージも無かったため撤去した。BGM専用に状態をもう1本立てるより、既にあるイベント（`events`＝Nターン目に起きること・[map.md](gdd/map.md) イベント）の `type` を1つ足すほうが、状態の置き場もJSONの書き場所も1か所に寄る。
- 対応：`events` に BGM 切替の type を足す（`turn` で発生・トラックIDを指定）。曲はライブラリの `crisis`（警報型・たたき台あり）が候補。必殺技やボス出現のような盤面イベントを引き金にしたくなったら、BGM専用の抜け道を作らず、イベント側に条件トリガーを足す形で設計する。
- 該当：`doc/gdd/map.md`（イベント表）・`domain/battle_state.gd`（`fire_due_events`）・`application/stage_loader.gd`（`_apply_events`）・`presentation/main/main.gd`（曲の張り替え）・`doc/audio/bgm.md`。着手の引き金＝ステージ途中で曲を変えたくなったとき。

### feature-45

**起動スプラッシュとアプリアイコンの差し替え**

- 背景：`project.godot` に `boot_splash` の項目が一つも無く、デバッグ実行でもエクスポート版でもデフォルトの Godot ロゴが出る。ウィンドウ／タスクバーのアイコン（`application/config/icon`）も未設定で Godot のアイコンのまま。Godot は MIT でロゴの表示義務が無いため、フォークやカスタムビルドは不要＝プロジェクト設定と画像の差し替えだけで済む。
- 対応：単色の地に Senaris ロゴ、その下に小さく開発元名を入れた PNG を1枚作り、`boot_splash/image` に指定する。地の色は画像に焼かず `boot_splash/bg_color` に持たせ、`fullsize=false`（原寸中央）で置く＝解像度が変わってもロゴが歪まない。ブートスプラッシュはエンジン起動前の静止画でフェード等は不可なので、動きを付けたくなった場合はタイトルシーン側の演出として作る（feature-46）。`minimum_display_time` はエディタ実行とエクスポート版で効き方が異なる可能性があるため実機で確認する。あわせて `application/config/icon`（ウィンドウ／タスクバー）と Windows export preset の exe アイコン（.ico）も差し替える。
- 前提：ロゴに焼き込む開発元名（サークル名／会社名）が未決。絵を起こす前に決まっている必要がある。Steam のパブリッシャー名にもなるため feature-27（タイトル名の確定手続き）と同じ段で決めるのが自然。
- 該当：`project.godot`（`boot_splash/*`・`application/config/icon`）・`export_presets.cfg`（exe アイコン・feature-10 で新規作成）・`assets/`（スプラッシュ画像・アイコン）・`doc/art/`（ロゴの作画方針）。着手の引き金＝開発元名が決まったとき、または配布ビルドを作るとき。

### feature-46

**タイトル画面（酒場の入口）**

- 背景：画面と場面の繋ぎは入った（`presentation/title/title_screen.gd`）。起動すると酒場の扉が外から映り、入力で扉が開く動画に切り替わり、くぐるとセレクト画面へ渡る。まだ載っていないのは文字と項目で、終了・設定・クレジットの置き場が無い。
- 入っているもの：閉じた扉の1枚絵（`assets/menu/door.png`）と、扉が開いて店内へ入る動画（`assets/menu/door_open.ogv`・10秒・扉の軋みと焚き火の音込み）。素材の作り方と落とし穴は [menu.md](art/menu.md) §5。BGM は曲ではなく店のざわめき（`title`）で、扉が閉じている間はこもらせ、扉が開くのに合わせて開く（[bgm.md](audio/bgm.md)）。動画は再生中の入力でスキップできる。
- 仕様から変えたこと：吊り看板は作らなかった。絵に文字を入れないのが全アセット共通のルールなので、タイトルは UI 側で載せる。またタイトルにメインテーマは置かず、作品の顔となる旋律は `menu`（セレクト画面の曲）が担うことにした。
- 対応（残り）：背景の上にメニュー項目を重ねる。ボタンは既存の `plank`（木の板ボタン）を流用＝セレクトと同族の手触りになる。Press any key の一拍は挟まず最初からメニューを出す（PC では無意味なクリックが1回増えるだけ）。いまは項目が無いぶん任意の入力で先へ進む暫定状態なので、ここは実装時に置き換える。「はじめる」で扉の動画を再生してセレクトへ。
- 決めていないこと：タイトルロゴを画面のどこに置くか（扉の右手前が暗く空いている）。「つづきから」は盤へ直行するが、そのとき扉の動画を挟むか（酒場に入る画と、戦場へ戻る動きが噛み合わない）。
- メニュー項目：つづきから（`SaveStore.has_save()` が真のときだけ出し、押したら盤へ直行。実装済みの中断セーブをそのまま使う）／はじめる（セレクトへ）／設定（feature-47）／クレジット／おわる。
- クレジット：素材の権利表記。作業の本体は画面ではなく権利台帳の整備（[bgm.md](audio/bgm.md)・[sfx.md](audio/sfx.md)・[sonniss.md](audio/sonniss.md)）で、どの素材が表記を要求するかの確認が要る。`title`（ざわめき）は表記不要のライセンスだが自作ではないため台帳に明記済み。リリース前が締め切り。
- 該当：`presentation/title/title_screen.gd`（実装済み。ここに項目を足す）・`presentation/main/main.gd`（結線済み）・`presentation/select/tavern_theme.gd`（`plank` 流用）・`doc/gdd/title.md`（新規。実装時に書く）。関連＝feature-12（メニュー文言の i18n キー化）。着手の引き金＝配布ビルドが見えてきたとき。

### feature-47

**設定画面**

- 背景：`presentation/ui/hud.gd` のシステムメニューに「設定」項目があるが、`main.gd` 側に受け口が無く現状は空振り。設定値を持つ機構も永続化も無い。feature-16（演出速度・敵ターンスキップ）が「設定画面を作る段で」を前提にしており、この項目が先に要る。
- 対応：1枚の設定シーンを作り、タイトル画面（feature-46）とゲーム中のシステムメニューの両方から開く。項目は 音量（マスター／BGM／SE）・言語（ja／en。翻訳は投入済み）・画面モード（全画面／ウィンドウ）・演出速度（移動アニメ／カメラ追従／敵ターンスキップ＝feature-16）。永続化は `user://settings.json`（`ProgressStore` の隣・セーブデータとは別枠。設定は中断セーブに含めない）。音量は AudioServer のバスに反映、言語は `TranslationServer.set_locale`。
- 該当：`presentation/settings/`（新規）・`presentation/ui/hud.gd`（`settings_requested` シグナル）・`presentation/main/main.gd`（結線）・`infrastructure/save/settings_store.gd`（新規）・`presentation/ui/bgm_player.gd`／`sfx_player.gd`（音量反映）・`doc/tech/gamesystem.md`（設定の永続化を追記）。関連＝feature-16（移動・カメラ・戦闘演出の速度の設定値化）・feature-12（項目名の i18n）。着手の引き金＝タイトル画面を作るとき、または敵ターンが長く感じ始めたとき。

### feature-49

**ステージ開始の区切り音（`menu_sortie`）**（優先度：低）

- 背景：ステージに入る経路が2種類ある。連戦（outro 会話 → `_advance_or_select` → 次ステージ）と、文脈の外から入る経路（ステージセレクト、および未実装の「つづきから」）。連戦では会話でステージ同士が繋がっており、区切りの音を入れると繋がっているものを切ってしまうので鳴らさない（現状すでに無音で、これが正しい）。外から入る経路にだけ区切りが要る。
- 対応：`menu_sortie` を作り、外から入る経路でだけ鳴らす。いまセレクト経由では `menu_stage`（`ui_confirm`）が鳴っているので、置き換えるか後ろに重ねるかを決める。判断材料は入口が2つに増えてからのほうが揃う＝ロード機能（feature-9 の中断セーブ復元）ができて「つづきから」が動くようになってから着手する。入口が1つの現状では、決定音との違いを検討する材料が足りない。
- 該当：`assets/sfx-src/menu_sortie.mscz`（新規・MuseScore で短いファンファーレ）・`data/audio/sfx_catalog.gd`（BIND）・`presentation/select/stage_select.gd`（セレクト経由）・ロード経路（feature-9 で決まる箇所）・`doc/audio/sfx.md`（発火点カタログ）。関連＝feature-9（中断セーブのロード）。着手の引き金＝「つづきから」が動くようになったとき。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### refactoring-5

**hex_board_3d の段階分割**（優先度：中）

- 背景：`presentation/board/hex_board_3d.gd` は元2254行で、(a) カメラリグ＋picking、(b) 選択→移動→コマンドメニューのインタラクション状態機械、(c) 盤の3D描画同期、(d) メッシュ/材質生成ヘルパー、(e) 駒の描画、(f) 地形タイル構築、(g) 着弾演出の責務が同居している。(b) と (c) はオーバーレイ状態（`_reachable`/`_targets`/`_formation_cells` 等）を共有する密結合なので、外側の疎な責務から段階的に剥がし、hex_board_3d をイベント配線と入力→状態遷移の専任にする。
- 対応：切り出しやすい順に進める。各段でテスト先行・全テスト合格・実機確認を経てからコミットする。
  1. メッシュ/材質生成 → `board_mesh_factory.gd`（純関数・static クラス）。
  2. カメラリグ → `board_camera.gd`（パン/ズーム/fit/追従/揺れ。入力の受け口は盤に残し委譲）。
  3. 駒の描画（`_build_unit_node`・影・兵数バー・リング・マーカー）。
  4. 地形タイル構築（`_build_tiles`・スキン解決・スカート・グリッド・下地）。
  5. 着弾演出（`play_formation_impact` 一連）。
  6. 1〜5を剥がした状態でインタラクション分割の要否を再評価する。切る場合は「オーバーレイ表示モデル（インタラクションが書き・描画が読む素データ）」を定義してから。
- 進捗（2026-08-10）：ステップ1完了（`3d72eab`・2254→2041行・-213行）。ステップ2のコード変更とテスト作成が完了、未コミット（`board_camera.gd` 167行・`test_board_camera.gd` 97行・hex_board_3d の差し替え済み）。
- 該当：`presentation/board/hex_board_3d.gd`・`presentation/board/board_mesh_factory.gd`・`presentation/board/board_camera.gd`・`tests/unit/test_board_mesh_factory.gd`・`tests/unit/test_board_camera.gd`。3〜5の切り出し先ファイル名は着手時に決める。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- 茂み（bush）の沈め量の詰め：立ち絵を沈める量（`terrain_skin.csv` の `sprite_sink`）を 0.12 で仮置きしている。茂みの絵そのものが仮のため、いま詰めても絵の差し替えでやり直しになる。本番の茂みタイルができたら実機で見て決める（→ [terrain.md](art/terrain.md)）。
- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
