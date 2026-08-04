# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=2 / feature=40 / refactoring=9

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。優先度は各エントリ見出しに 高（設計の背骨に関わる）／中／低（飾り・潜在）で記す。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### bug-1

**レッドドラゴンの絵に合わせて立ち絵の枠を決める**（優先度：低）

- 背景：倍率が最大のレッドドラゴン（map 1.4・combat 1.4）が、いまの枠に収まらない。combat は 512四方・BaseHeight 384＝上限 1.333 で、538px の竜は上端26pxが欠ける。map はキャンバス384で縦は解決済みだが、`-resize "x<高さ>"` が高さしか指定していないため横幅に上限が無く、翼を広げた絵は倍率と無関係に左右が切れる。どちらも生成時に切れを検出して警告するので、黙って壊れることはない。該当ユニットの絵がまだ無く実害はゼロ。
- 順序：竜を描く → 縦横比を実測 → 枠を決める → `all` で再生成。枠だけ先に決めない。キャンバス値は master（トリム済みの原画）に影響しないので後決めでも描き直しは起きず、再生成は1コマンド数秒。必要な幅は竜の縦横比でしか決まらないため、推測で決めると二度手間になる。
- 対応（combat）：`$Canvas` 512 → 640（上限1.66）が第一候補。ただし戦闘シーンは正方キャンバスを枠へ `KEEP_ASPECT` で嵌める（`FIG_H` が画面上の大きさを決め、キャンバスのpx数は関与しない）ので、広げると全員が一律小さく見える。`FIG_H` の補正と隊列の重なり確認がセットになる。この目合わせは一番大きい絵が手元にある状態でやるのが正確で、feature-22（戦闘シーンの寸法確定）と重なる。
- 対応（map の横幅）：内接（`-resize "384x<高さ>"`）にすれば切れないが、横長ユニットは幅で頭打ちになり背が低くなる＝`map_scale` が背丈の指定でなくなる。キャンバスをさらに広げる案と併せ、竜の縦横比を見て決める。内接を選ぶなら `map_scale` の意味が変わるので `doc/art/units.md` も直す。
- 制作条件：master には全身を入れる（翼の先・尻尾を画面外で切らない）。master で欠けた部分は、後段でどう枠を広げても復元できない。
- 該当：`tools/gen_unit_combat.ps1`（`$Canvas`）・`tools/gen_unit_map.ps1`（`-resize`）・`presentation/combat/combat_scene.gd`（`FIG_H`・隊列）・`doc/art/units.md` 3.1／3.3。着手の引き金＝レッドドラゴンの master を描いたとき。

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### feature-2

**敵AI: retreat（撤退）軸の配線**（優先度：低）

- 背景：AI思考の6軸のうち retreat（撤退閾値＝兵数がこの値を下回ったら退く／ただし自軍拠点が無ければ退かない。[ai.md](gdd/ai.md)「3. 撤退」）は、ai.csv に列・既定（`0`＝退かない）があり `DEFAULT_PRESET` にも入っているが、`nearest_attacker_brain` がこの値を読んでいない＝**未配線**で、現状は常に退かない。既定値の設計は済んでおり、残るのは挙動の実装のみ。
- 対応：`nearest_attacker_brain` に撤退判定を足す（`_param(state, u, "retreat")` を読み、兵数 < 閾値 かつ自軍拠点あり のとき退く＝拠点方向へ後退／交戦回避）。部隊ごとの上書きは既存の `_param` 解決でそのまま効く。実装後に ai.md の「retreat は未配線」記述を更新。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`（テスト追加）・`doc/gdd/ai.md`（記述更新）。ai.csv は列既存のため変更不要。

### feature-4

**敵AI: 思考軸の残り値の配線**（優先度：中）

- 背景：AIの各軸のうち一部の値しか効いていない（[ai.md](gdd/ai.md) §4〜6・§1）。実装済みは attack=`always`/`prey`、target=`near`/`weak`、advance=`max`/`base`/`flank`、engage=`charge`/`sight`/`squad`。未実装は attack の `solo_adv`/`surround_able`/`surrounded`/`no_retal`/`kill`、target の `maxdmg`/`mindmg`/`capturer`/`ranged`/`flyer`、advance の `spacing`（間合維持＝キティング）/`squad`/`careful`、engage の `turn:N`。ai.csv には列・表記があり、読み手（Brain）が未対応。retreat 軸は別途 feature-2。
- 対応：`nearest_attacker_brain` の `_pick_target`／攻撃判定／`_advance_dest`／`_ensure_engaged` に各値の分岐を足す。射程ユニットの間合維持（spacing）は AI の質に効く本命。値ごとにテストを足す。
- 優先して要るのは target の `flyer`（飛行を優先して狙う）。飛行は `atk_air>0` の駒でしか触れないので、対空を持つ敵が地上の駒を殴っている間、こちらの飛行は事実上の安全地帯になる。対空持ちが「空を狙える唯一の駒」であることを AI が理解しない限り、飛行の価値が壊れたままになる（竜狩り st5＝ハーピー／グリフォンが空で絡む回で効く）。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`・`doc/gdd/ai.md`（各軸の実装状況を更新）。ai.csv は列既存のため変更不要。

### feature-5

**戦力供給の持ち越し（roster: carryover）**（優先度：高）

- 背景：キャンペーンの背骨。前ステージの生存ユニット（経験Lv・残兵）を次ステージへ持ち越す供給モデル（[map.md](gdd/map.md) §戦力供給）。エンジン側（Phase 1〜2d）は実装済み＝下記「進捗」。残るのは tutorial3 実データ制作（3a・コンテンツ＝[campaign/roadmap.md](campaign/roadmap.md) 側）とセレクトの連戦区間可視化（3b・下記「対応（可視化）」）、および live 配線の実機確認（保留）。
- 対応（済・Phase 1〜2d）：ステージJSONの `roster` を `StageLoader` が解釈し、carryover 時は前ステージ勝利時の生存ユニット（type/skin/level/残兵）を `carryover_slots` に順に配置。永続化は `RosterStore`。詳細は下記「進捗」。
- 対応（セレクトでの可視化）：fresh か carryover かは戦い方を変える（carryover は主力を死なせられない＝温存プレイ／fresh は使い切ってよい）ため、挑む前に分かるようにする。知らずに連戦の初戦で主力を失う理不尽を避ける。carryover は単体ステージの属性というより連続するステージのつながりなので、ステージ一覧で carryover が繋がる区間をグループ化して見せる（酒場ボードのメタファなら「同じ依頼の続き物＝節が鎖でつながる」）＋区間の入口に「ここから戦力を持ち越す連戦」の印。冒険譚カード（上位）に出すのは冒険譚まるごとが連戦のときだけで足りる（roster はステージ単位＝冒険譚内で fresh/carryover が混在しうる）。
- 該当：`application/stage_loader.gd`・`presentation/main/main.gd`（ステージ間の受け渡し）・`presentation/select/stage_select.gd`（連戦区間の可視化）・`doc/gdd/map.md`・`doc/gdd/stage_select.md`。
- ロードマップ（feature-9 と共有・carryover 先／中断セーブ後）：土台は `Unit` 直列化で、本項（持ち越し）と feature-9（中断）が共有する。前提＝戦闘に乱数なし＝中断セーブはシード不要で状態だけで完全再現／性能はデータ駆動でスナップショットは `type_id`・`skin_id`・`level`・`troops`・`max_troops` だけ持てば足りる（他は type から `UnitCatalog` で再構築＝数値を焼かない）／`ProgressStore`（素JSON＋`user://`）が雛形・`garrison`/`deploy` 機構は既存（案Bはそのまま乗る）。
  1. Unit 直列化：`Unit.to_dict`/`from_dict`（上記5フィールド＋復元は catalog）＋テスト。以降すべての土台（規模：小）。
  2. carryover 本体：(2a) `StageLoader` が `roster:"fresh"|"carryover"` を読む／(2b) 戦力スナップショットの保存・読出（`RosterStore`・ProgressStore の隣）／(2c) 継承スロット配置（案A＝配置スロットに順に嵌める）／(2d) ステージ間受け渡し（勝利→生存抽出→保存／次ステージ→読出→配置）。ここで tutorial3 が生存戦力で繋がる＝連戦が動く（規模：小〜中）。
  3. 見せ方：tutorial3 データ（各話 `roster:carryover`＋継承スロット＋新規勧誘）／セレクトの連戦区間可視化（規模：中）。中断セーブ（BattleState 全状態）は feature-9。
- 進捗（2026-07-18）：Phase 1〜2 実装＋テスト済み＝`Unit.to_dict/from_dict`／`StageLoader` の `roster` 解釈・`_apply_carryover`・`survivors_snapshot`／`RosterStore`（`user://roster.json`）／main の勝利フック（生存保存）・開始フック（継承読込）。ロジック経路は統合テスト `tests/unit/test_carryover_flow.gd` で担保（勝利→保存→継承・リトライは前勝利の戦力）。残り＝Phase 3（tutorial3 実データ＋セレクト可視化）。main の live 配線の実機確認は、最初の carryover ステージ（tutorial3 か debug 連戦）を組んだ時に行う＝それまで保留。

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

- 背景：盤の状態を永続化・復元する機能（[uiux.md](gdd/uiux.md) §フェーズ3・[gamesystem.md](tech/gamesystem.md) がセーブ仕様の正本）。中断セーブの単枠クイックセーブ/ロードは実装済み（Phase 4a/4b＝下記「進捗」）。残るのは複数スロットUI（4c）とターン毎オートセーブ（Phase 5）、および live 配線の実機確認（保留）。feature-5（戦力供給の持ち越し）と `Unit` 直列化を共有。
- 対応（済・Phase 4a/4b）：`BattleState` 全状態の直列化（`to_dict/from_dict`）＋ `SaveStore`（`user://save.json`・1枠）＋ HUD の「セーブ」有効化・「ロード」を保存有無で切替。詳細は下記「進捗」。
- 対応（残・4c/Phase 5）：複数スロットUI（枠一覧・上書き確認・スロット別ファイル）と、ターン毎オートセーブ（中断セーブの応用＝ターン開始/終了で自動保存・別枠）。
- 実装順：feature-5 の「ロードマップ」に集約（`Unit` 直列化を共有土台とし、carryover を先・中断セーブ＝本項を後）。
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

### feature-14

**themed 拠点（教会・魔法ギルド・墓地・回復の泉）**（優先度：中）

- 背景：拠点地形は汎用 `fort` のみで、冒険譚2・3 が要求する見た目・名前つきの拠点（墓地＝湧き元／泉＝回復 等）が無い。機構的には fort＋garrison で「湧き元」「占領で停止」は成立するが、テーマ別の見た目・名前と、回復の泉のような特殊効果が未整備。
- 対応：拠点に skin（見た目・名前）レイヤーを持たせる（terrain_skin と同方式）か、拠点種別を足す。回復の泉など特殊効果が要るものは効果を設計。まずは見た目・名前から。
- 該当：`data/terrain/`（拠点スキン）・`domain/capture/`・`presentation/board/hex_board_3d.gd`・`doc/gdd/map.md`。着手の引き金＝冒険譚2/3 のステージ制作時。

### feature-16

**移動/カメラ演出の速度設定・敵ターンスキップ・演出の適用範囲拡張**（優先度：低）

- 背景：敵の全行動を見せる（移動アニメ＋カメラ追従）ぶん、敵が多いターンは総時間が伸びる。アニメ速度の設定（高速／標準／オフ）と敵ターンのスキップは SLG の定番だが、設定画面もスキップ導線も未実装（[uiux.md](gdd/uiux.md) システムメニュー・敵ターンのカメラ）。また演出には未対応の隙間がいくつかある。
- 対応：(1) 設定画面を作る段で、移動アニメ速度（`MOVE_ANIM_SEC_PER_HEX`／`MOVE_ANIM_MAX_SEC`）とカメラ追従（`FOCUS_PAN_SEC`）を設定値から引く。(2) 敵ターンのスキップ（キー／ボタンで残りを一気に最終状態へ）。(3) 出撃・降車は経路を持たずポップして現れる＝拠点／輸送から目的マスへの1歩スライドで見せる（経路探索は不要）。(4) カメラ追従は行動主体の現在位置だけを見る＝長距離移動でアニメ中に終点が画面外へ出るケースの追随、攻撃で対象も画面に含める配慮は未対応（現状は移動距離が短く実害小）。
- 該当：`presentation/board/hex_board_3d.gd`（`focus_camera_on`／移動アニメ）・`application/match_controller.gd`（ターンのテンポ・スキップ）・設定の永続化（feature-9 のセーブと同居）・`doc/gdd/uiux.md`。着手の引き金＝設定画面を作るとき／敵ターンが長く感じ始めたら。

### feature-18

**名簿（パーティ）・帰属の確定・会話の分岐**（優先度：高）

- 背景：冒険譚3が初の carryover 型で、中立拠点の勧誘によって仲間が増減する。現状の持ち越しは「盤上の生存者リスト」で、(1) 兵力ゼロで撃破された仲間は消える＝離脱として会話に出せない、(2) 中立から解放した駒は `native` が中立のままなので、拠点を奪われると敵が出撃させられる＝寝返る（仕様は捕虜）、(3) `Unit` がキャラの同一性を持たず同 type が複数いると区別できない、(4) 会話に条件分岐が無く仲間の有無を反映できない。設計は [map.md](gdd/map.md)（帰属・名簿・actor）と [authoring.md](campaign/authoring.md)（会話の分岐）に記載。
- 対応：(a) `Unit.recruited_team`（帰属先。既定＝`native_team`、中立駒の出撃時に出した側で確定・以後不変）を追加し、`can_deploy_garrison`／`_base_has_deployable_garrison`／`_heal_garrisons` の native 判定を帰属で見るよう差し替え。(b) `Unit.actor`（冒険譚をまたいで一意な永続キャラ識別子）を追加し `to_dict`/`from_dict` に載せる。(c) 持ち越しを名簿へ意味変え＝クリア時に前名簿と突き合わせ、欠けた `actor` を `troops:0` で残し、帰属が自軍の `actor` 駒を加える。配置は `troops > 0` の者だけ。(d) `_apply_carryover` を順詰めから `actor` 指名＋残り順詰めへ。(e) `parse_dialogue` に `when`（`joined:<actor>` / 否定）の評価を足す。
- 置き場所：carryover の保存・読出は現在 presentation の `main.gd`（保存 :120／読出 :54-59）に直書きで、application に差配役がない。名簿の更新規則はゲームルールなので application に薄いサービスを新設し、main はそれを呼ぶだけにする（`CampaignProgress` の隣）。
- 該当：`domain/unit/unit.gd`・`domain/battle_state.gd`（帰属ゲート）・`application/stage_loader.gd`（`_apply_carryover`・`parse_dialogue`）・`application/roster_service.gd`（名簿サービス）・`presentation/main/main.gd`（呼び出しの差し替え）・`tests/unit/`（`test_recruit`・`test_roster_service`・`test_carryover_slots`・`test_dialogue_when` ほか）・`doc/gdd/map.md`・`doc/campaign/authoring.md`・`doc/tech/gamesystem.md`。
- 進捗（2026-08-03）：(a)〜(e) 実装＋テスト済み（GUT 540）。`Unit.set_native_team` で native と帰属を揃える口を用意し、直接代入で片方だけ動く事故を防いだ。名簿に載るのは `actor` を持つ駒だけ＝名前のない雑兵は持ち越さない。main の配線もコード上は完了確認済み（勝利時の名簿保存＝`RosterService.update_after_clear` → `_roster_store.save_roster`、開始時の継承読込＝`_load_roster`、会話の `when` 条件フィルタ＝`StageLoader.load_dialogue` にロスター渡し）。**コーディング作業は完了**。残りは冒険譚3データ制作時の実機通しテストのみ（依存先＝tutorial3 ステージデータ）。
- 前提：冒険譚3のステージデータ制作では、ベテラン5＋新米4＋加入組すべてに `actor` を振る（味方に名前のない駒はいない）。

### feature-19

**戦果票の評価ランク（S/A/B/C）**（優先度：中）

- 背景：決着の戦果票（[uiux.md](gdd/uiux.md) §決着の演出・`presentation/ui/result_banner.gd`）は ターン数／生存／撃破 の3行を出すところまで実装済み。ジャンルの定番である**評価ランク**（Advance Wars の S/A/B/C 型）が無い。ランクは「同じ勝ちでも上手い勝ちがある」を一目で示す指標で、再挑戦の動機になる（速攻を狙う・主力を死なせない）。実装より**評価式の設計**が本体で、ステージごとの妥当な閾値決めはバランス調整＝ステージが揃ってからでないと決められないため後回しにした。
- 対応：評価式を決めてから実装する。(1) 指標の選定＝ターン数（速さ）・損害（生存率）・撃破率あたりの合成。(2) 閾値の持ち方＝ステージJSONに `rank` として書く（ステージごとに適正ターン数が違う）か、`turn_limit` からの相対で自動算出するか。データに書くならステージ数ぶんの調整作業が要るので、まずは相対算出で始めるのが軽い。(3) 表示＝戦果票の3行の下にランクを大きく出す（`_fill` に行を足すだけの構造にしてある）。印とは別要素なので、印の下に重ねない位置を選ぶ。
- 該当：`presentation/ui/result_banner.gd`（`_fill` にランク行）・`presentation/main/main.gd`（`_result_rows` の隣に評価の算出）・評価式の置き場所は `application/`（ゲームルール＝presentation に式を持たせない）・`data/stages/*.json`（閾値をデータに置く場合）・`doc/gdd/uiux.md`。着手の引き金＝ステージが揃ってバランス調整に入るとき。
- 関連：撃破数の集計は現状 presentation 側で「開始時の敵数 − 残存」で採っており、拠点の控え（garrison）が出撃してから倒された分を数え落とす（`main._result_rows` のコメント）。ランクの入力に撃破を使うなら、先に `domain` 側で撃破を正確に数える必要がある。

### feature-20

**ドリフト検出の自動化（doc↔コードの突き合わせ）**（優先度：中）

- 背景：仕様駆動（spec-anchored・[development.md](tech/development.md)）で進めるが、doc（gdd/tech/campaign）とコードの一致を機械的に検証する手段が無く、現状は目視頼み。自動テストが守るのはコード同士と CSV正本↔生成物の整合まで（[testing.md](tech/testing.md)）で、doc の記述が実装とずれても誰も気づかない。doc が嘘を含むと、以後の設計判断とAIの参照がまとめて汚染される＝doc 量が増えるほど被害が効く。
- 対応：このゲーム専用のスキルを作り、doc と該当コードを AI に突き合わせさせて食い違いを報告させる。CI/CD には組み込まず、任意のタイミングで手動起動して報告を読む運用（単独開発＋探索の多い進め方にマージゲートは合わない）。設計の本体は対象範囲の与え方＝doc の章と該当コードの対応をどう持つか（各 doc に参照先を書く／スキル側に対応表を持つ／全文突き合わせ）、報告の粒度、誤検知の抑え方。全 doc を一度に見るより、gdd の1ファイルと対応する domain/ を突き合わせる最小構成から始めるのが軽い。
- 該当：`.claude/skills/`（新規スキル）・`doc/tech/development.md`（運用の記述）。突き合わせ対象＝`doc/gdd/`・`doc/tech/`・`doc/campaign/` と `domain/`・`application/`・`data/`。着手の引き金＝doc とコードのズレで手戻りが出たとき、または doc 量が目視で追えなくなったとき。

### feature-21

**BGM のたたき台仕上げと拡充**（優先度：低）

- 背景：BGM の制作方針は [bgm.md](audio/bgm.md) で確定。たたき台8曲（`.musicxml`／`.mid`）が MuseScore での仕上げ待ち。ライブラリ表のうち `title` が未着手。全体既定（`BgmDirector.DEFAULT_STAGE_TRACK`＝`map_calm`）は ID に対応する曲が無い＝ステージにも冒険譚にも `bgm` 指定が無いと無音になる（チュートリアル1は全ステージに指定済みのため現在は該当なし）。
- 対応：(1) たたき台8曲（`forest`／`ruins`／`graveyard`／`temple`／`ritual`／`boss`／`boss2`／`crisis`）の MuseScore 仕上げ（強弱・味付け・ループ点整備）と `.ogg` 化。(2) `title` 曲の制作（`menu` と共用するか検討含む）。(3) 全体既定を投入済みの曲に変えるか `campaign.json` に既定を書くかを決定し反映。
- 該当：`assets/bgm-src/`・`assets/bgm/`・`presentation/audio/bgm_director.gd`（`DEFAULT_STAGE_TRACK`）・`doc/audio/bgm.md`（ライブラリ表更新）。着手の引き金＝ステージに曲を当てたくなったとき。

### feature-22

**戦闘演出シーンの未決仕様確定**（優先度：低）

- 背景：戦闘演出シーンの設計は [combat_scene.md](tech/combat_scene.md) で左右固定・隊列・エフェクトまで確定済み。実装着手に必要な3点の数値／仕様が未確定。
- 対応：(1) 隊列スロットの実px（シーン解像度・立ち絵サイズ確定後）とアニメのタイミング値を決める。(2) 演出速度設定のUI配置（システムメニュー／オプション）を決める。確定したら combat_scene.md に反映。背景は3Dの地面（マップ絵の流用）に決着＝背景絵の作画スペックは不要になった。
- 該当：`doc/tech/combat_scene.md`（確定後に反映）・`presentation/combat/`（実装時）。着手の引き金＝戦闘演出シーンの実装に入るとき。

### feature-23

**戦闘の決定性（乱数の有無）の確定**（優先度：中）

- 背景：[architecture.md](tech/architecture.md) の未決・保留。戦闘が決定的（乱数なし）か確率的（乱数あり）かの設計判断。中断セーブの正確さと将来のリプレイに影響する＝乱数があるならシード／状態もセーブ対象になる。[combat.md](gdd/combat.md) は決定的を前提に書かれている（「中断セーブはシード不要・リプレイ完全一致・AI先読みも正確」）。
- 対応：決定的で確定するか、確率要素を入れるかを決める。確定したら architecture.md の未決を閉じ、関連する doc（combat.md・gamesystem.md）との整合を確認。
- 該当：`doc/tech/architecture.md`・`doc/gdd/combat.md`・`doc/tech/gamesystem.md`。

### feature-24

**獲得用キービジュアルの制作**（優先度：低）

- 背景：[keyvisual.md](art/keyvisual.md) の未決事項。冒険譚クリア時に表示する獲得イラストが未制作。扉絵・カード用とは別で、「機構が動く瞬間」を描く。
- 対応：冒険譚1「細道で少数 vs 群れ」／冒険譚2「三重詠唱が屍の波を薙ぐ」のキービジュアルを制作。作画方針は keyvisual.md（ILLUST STYLE・透かし対策）に従う。
- 該当：`assets/`（画像）・`data/stages/*/campaign.json`（`victory_path`）・`doc/art/keyvisual.md`。着手の引き金＝冒険譚の仕上げに入るとき。

### feature-25

**ステージセレクトの設計未確定事項**（優先度：中）

- 背景：[stage_select.md](gdd/stage_select.md) の設計の未確定。ステージセレクト画面の2つの設計論点が決まっていない。
- 対応：(1) ステージ詳細（ブリーフィング）に何を出すか決める（勝利条件・推奨戦力・シナリオ導入など。羊皮紙の依頼書ダイアログ `quest_sheet.gd` が器）。(2) クリア評価（ターン数・ランク）を記録するか決める（feature-19「戦果票の評価ランク」と関連＝ランクを出すなら記録も要る）。確定したら stage_select.md に反映。
- 該当：`doc/gdd/stage_select.md`（確定後に反映）・`presentation/select/quest_sheet.gd`（ブリーフィング実装時）・`application/campaign_progress.gd`（記録時）。

### feature-26

**デバッグステージの構成見直しと拡充**（優先度：低）

- 背景：デバッグ冒険譚は機能別6カテゴリに分かれているが、既存ステージは計11枚で、カテゴリ内の機能カバーに隙間がある。また既存ステージの役割も実装の進展に伴い変わってきている（例：siege.json は閉じ込め判定だけでなく中立寝返り・拠点スキンも兼ねる）。拡充の前にカテゴリ分けと既存ステージの役割を見直し、整理した上で不足分を足す。
- 対応：(1) 6カテゴリの分け方と既存ステージの役割を再評価し、必要なら再編する。(2) 不足しているデバッグステージを追加する。対象は以下（旧 [debug-stages.md](tech/debug-stages.md) の「あるべき」から移植）:
  - combat: 地形補正／間接／魔法／対空・対地／包囲／支援／経験Lv（7件）
  - ai: charge／raid／起動トリガー見本（3件）
  - victory: 殲滅／自軍hq喪失で敗北／複数条件OR（3件）
  - mapops: 拠点（占領・出撃・回復）／陣形②③／飛空艇・初期搭乗（3件）
  - skins: 構造物系タイル（1件）
  - misc: 追加の演出・UI検証（1件）
- 該当：`data/stages/debug-*/`・`doc/tech/debug-stages.md`（台帳更新）。着手の引き金＝機能を足してデバッグステージが欲しくなったとき、またはカテゴリの見通しが悪くなったとき。

### feature-27

**タイトル名「Senaris」の確定手続き**（優先度：低）

- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済みだが、確定前の手続き4件が残っている。すべてオーナー側の手作業。`.net` ドメインと Steamコミュニティ `id/senaris` は取得済み。
- 対応：(1) 商標クリアランス＝第9類・第41類で US(USPTO)／EU(EUIPO)／日本(J-PlatPat) の各DBを正式確認。(2) `senaris.com` ドメイン取得（`.com` を主軸に）。(3) SNSハンドル確保（X／Bluesky／Discord 等）。(4) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`。着手の引き金＝配布が見えてきたとき（parking lot「Steam 配布の段取り」と連動）。

### feature-28

**ユニットスキル第2弾（貫通追加・再行動）**（優先度：中）

- 背景：ユニットスキルの器（単独発動・味方1体へ状態補正・移動後発動）は①妖精の粉で実装済み（[skills.md](gdd/skills.md)）。カタログを増やす段で、次に入れる2つの方向まで決まっている＝(1) 貫通追加＝対象の攻撃に貫通率を乗せる、(2) 再行動＝行動を終えた味方をもう一度動かす。どちらもレシピは未設計（発動者・値・持続・射程が未定）でカタログにも載っていない。
- 対応：(1) 貫通追加は既存の状態補正で足りるか要確認＝`StatusMod` は攻防への add/mul は持つが、貫通率（`Unit.pierce`）に効く経路が無いため、補正チェーンに貫通の口を足すかどうかから決める。(2) 再行動は「1ターンに各ユニット1回まで」の縛りを入れる方針まで決定済み（無制限だと1体を延々動かせて崩壊する）。縛りの持ち場は駒側のフラグ＝`BattleState` に再行動回数を持たせ、中断セーブの直列化にも載せる。レシピが固まったら skills.md のカタログへ②③として追記する。
- 該当：`domain/formation/formation.gd`（RECIPES）・`domain/battle_state.gd`（再行動フラグ・直列化）・`domain/status/status_mod.gd`／`domain/combat/combat.gd`（貫通の口）・`tests/unit/test_skill.gd`・`doc/gdd/skills.md`。

### feature-29

**敵AIの陣形スキル／ユニットスキル使用**（優先度：中）

- 背景：陣形スキルとユニットスキルは当面プレイヤー専用で、敵AIは移動・攻撃・占領しかしない（[formations.md](gdd/formations.md) 実装方針・[skills.md](gdd/skills.md) 共通ルール）。看板機能を敵が使わないと、プレイヤーだけが持つ特権のままになる。成立条件はスキンID照合になった（未指定は種別へフォールバック）ので、敵側スキンをレシピに書けば成立させられる＝データ面の下地はできている。残るのはAIの思考。
- 対応：(1) 敵陣営向けのレシピをカタログに足す（どの敵に何を持たせるかは冒険譚側の設計）。(2) `nearest_attacker_brain` に発動判断を足す＝成立している選択肢を `Formation.available_for` で採り、撃つ価値（面に入る敵の数・バフの効き）で評価して選ぶ。思考軸として ai.csv に列を足すか、部隊単位の指定にするかを先に決める（[ai.md](gdd/ai.md) の「ロジック＝コード／組合せ＝データ」に従う）。feature-4（思考軸の残り値の配線）の隣。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`domain/formation/formation.gd`（敵レシピ）・`data/ai/ai.csv`（軸を足す場合）・`tests/unit/test_ai.gd`・`doc/gdd/ai.md`・`doc/gdd/formations.md`／`doc/gdd/skills.md`（発動主体の記述を更新）。着手の引き金＝敵に陣形を持たせたい冒険譚を作るとき。

### feature-30

**冒険譚2のステージ盤面をマップ設計に合わせて作り直す**（優先度：中）

- 背景：[tutorial2-undead-rush.md](campaign/tutorial2-undead-rush.md) の各話に盤の形を書き、型・難易度を [map_patterns.md](gdd/map_patterns.md) のステージ一覧へ載せた（doc 先行）。既存のステージJSONがこれに追いついていない。st1（荒地の広野）と st3（壁の通路）は骨格ができているが、st2・st5・st6・st7 は**全面平地**で盤の設計が入っていない。加えて doc と食い違っている点が3つある。
- 対応：st1 → st7 の順に盤を組み直す。doc との食い違い3件は先に潰す。
  - **湧き口が2hexになっていない**（st4・st6・st7）：崖が拠点の東側にしか無く、`(12,5)` の隣接6hexのうち4hexが開いていて、しかも味方側に開口している。doc は「湧くのは2ヘックスだけ」。隣接6hexのうち4hexを崖で塞ぎ、残す2hexは互いに隣接する組にする。
  - **st3 のバリケード初期配置**：関門（col10,11）に最初から置いてあり、馬車で運ぶ必然性がない。戦闘前会話「馬車でバリケードを運んで」と食い違うので、味方側後方へ移す。
  - **st1 の術者が道の上**：wizard(col3,row1)・priest(col3,row3) が `L`（道＝防0.8）に立っている。撃たれ弱い駒が防御-20%の床にいるのは意図と逆。初期配置を平地側へずらすか道の位置を変える。
  - **勝利条件の追加**（st4・st6・st7）：墓地の拠点に `"kind": "hq"`（team/native は敵）を足し、ステージの `victory` 配列に `{ "type": "capture_hq" }` を入れる。st7 は既存の `defeat_unit` と併記＝OR評価。判定機構は実装済み（[map.md](gdd/map.md) 勝敗条件）なのでデータだけで足りる。
  - 盤の作り直し：st2＝道1本＋南北の荒地＋柵で囲った集落／st3＝関門を幅2・詠唱部屋を幅3〜4／st4＝墓地間に荒地の帯・道は墓地の正面から外す／st5＝柵で囲った廃墟の中庭＋背後の迂回路／st6＝墓地を上下に離し中央に斜めの帯／st7＝st6＋崖に囲まれたネクロの高台・崖の縁の降車点。
- 該当：`data/stages/tutorial2-undead-rush/st1〜st7.json`・`doc/campaign/tutorial2-undead-rush.md`（実装後に差分があれば反映）。着手の引き金＝冒険譚2の制作に入るとき。関連＝feature-14（themed 拠点＝墓地の見た目）。

### feature-31

**体験版ビルドの素材選別（収録ステージから必要素材を導出して除外）**（優先度：低）

- 背景：体験版はチュートリアルを絞って配布する（[monetization.md](sales/monetization.md)）が、収録しないステージのユニット・地形・BGM・会話まで同梱するとサイズが無駄で、未収録分のネタバレにもなる。Godot のエクスポートプリセットは除外フィルタ（glob）・カスタム機能タグ（`OS.has_feature("demo")`）・CLI ビルドを備えるので機構は足りる。ただし素材は `skin_id` から文字列でパスを組み立てて `load()` する（`skin_catalog.gd`・`combat_scene.gd`・`hex_board_3d.gd`）ため、Godot の依存解決＝「選択したシーンと依存だけ」モードは効かない。必要素材の集合はこちらで計算して渡す必要がある。
- 対応：収録ステージJSON → 出現ユニット/地形の `skin_id`・BGM の `track_id` → 必要な `assets/**` パス集合、を導出して差集合を除外フィルタとして `export_presets.cfg` に書き出すスクリプトを足す（CSV正本→JSON生成と同じ発想＝正本から機械的に導出するので、収録ステージを足し引きしても壊れない）。代替は `EditorExportPlugin._export_file()` + `skip()` でエクスポート中に弾く方式＝フィルタ生成は不要だが何が落ちたか見えにくい。除外すると `ResourceLoader.exists()` が false になるので、未収録ステージがステージセレクトに載らないこと・参照が残る経路のフォールバックを併せて確認する。`data/i18n` の翻訳と未収録の会話テキストも同じ仕組みに乗せられる。
- 該当：`export_presets.cfg`（新規）・`tools/`（フィルタ生成スクリプト新規）・`doc/tech/tools.md`・`doc/sales/monetization.md`。着手の引き金＝体験版ビルドを作るとき（feature-10＝開発用アセットの除外と同じ段・parking lot「Steam 配布の段取り」と連動）。

### feature-32

**陣形スキル・ユニットスキルの効果音を作る**（優先度：中）

- 背景：発火点（`map_formation`＝発動の頭／`map_formation_hit`＝効果が届いた瞬間／`map_skill`＝ユニットスキル発動）を呼ぶ配線は入っているが、素材が無い。`sfx_catalog.gd` の `BIND` は「素材がある発火点だけ載せる」表で、載っていない発火点は無音で進む設計なので、いまは黙って何も鳴らない（壊れてはいない）。看板機能の発動が無音なのは手応えとして弱い。
- 対応：MuseScore ＋ Muse Sounds で自作 → `tools/gen_sfx.ps1` で `.ogg` 化（`victory`／`defeat` スティンガーで実証済みの手順）。作ったら `BIND` に1行ずつ足すだけで鳴る。音の性格は、陣形＝詠唱が結実する重い一撃、`map_formation_hit`＝着弾（陣形は戦闘演出シーンを通らないので `cmb_hit` は借りない）、`map_skill`＝陣形より軽く短い（毎ターン飛ぶため）。
- 該当：`assets/sfx-src/`・`assets/sfx/`・`data/audio/sfx_catalog.gd`（`BIND`）・`doc/audio/sfx.md`。着手の引き金＝音を作れる時間が取れたとき。

### feature-34

**陣形スキルの着弾を盤で光らせる**（優先度：低）

- 背景：陣形スキルが解決しても、盤は `_sync()` で駒を消して兵数を書き換えるだけで、どのヘックスに当たったのかを示す表示が無い（`hex_board_3d.gd` `_on_formation_resolved`）。三重詠唱は7ヘクスに当たる面の広さが売りなので、当たった範囲が見えないと手応えが伝わらない。カットインは華を担うが「どこに当たったか」は担えない。
- 対応：`formation_resolved` の結果（着弾ごとの hex）を受けて、そのヘックスを一瞬光らせる。盤にヘックス単位のフラッシュ表示が無いので新設が要る（既存のオーバーレイ＝`_reachable`／`_targets` と同じ層に、時間で消える一時的なハイライトを足す形）。カットインが閉じた後に出す＝順番は main が持つ（発動音 → カットイン → 着弾音＋光）。
- 該当：`presentation/board/hex_board_3d.gd`・`presentation/main/main.gd`（順番）・`doc/gdd/formations.md`（発動の演出）。着手の引き金＝演出を通しで見て、当たった範囲が分からないと感じたとき。

### feature-35

**敵を対象にするユニットスキル（毒牙）と、状態異常の解除（浄化）**（優先度：中）

- 背景：[skills.md](gdd/skills.md) にレシピ②毒牙・③浄化を載せたが、いまのユニットスキルは味方1体を強化するものしか撃てない。対象の絞り込みは `Formation.can_target` が `buff_scope == "unit"` のとき「味方の居る hex だけ」に固定しており、敵を選べない。解除の操作自体も無い。この2つは [tutorial3 st3](campaign/tutorial3-dragon-hunt.md)（鉱脈の争奪）で組になって出る＝ロックサーペントの群れが毒牙を重ね、聖職の浄化が落とす。
- 対応：(1) レシピに対象陣営の指定を足し、`can_target` の絞り込みを味方／敵で切り替える。状態補正エントリ自体は既存の器のまま（`scope: unit`・`op: mul`・値 1.0 未満）で、新しい演算は要らない。(2) 状態補正エントリに有害フラグを足し、浄化＝対象に効いている有害エントリを `_status_mods` から取り除く効果を新設する。値の符号から有害性を推測しない（攻撃だけ下げて防御を上げるスキルが出たときに破綻する）。中断セーブに乗るので旧セーブの既定値も決める。
- 該当：`domain/formation/formation.gd`（レシピ・`can_target`）・`domain/battle_state.gd`（解除・直列化）・`domain/combat/status_mod.gd`（有害フラグ）・`presentation/board/hex_board_3d.gd`（対象選択の絞り込み）・`tests/unit/test_skill.gd`・`doc/gdd/skills.md`。着手の引き金＝tutorial3 st3 を組むとき。関連＝feature-29（敵AIのスキル使用。毒牙を敵が撃つには思考側も要る）。

### feature-36

**陣形カットインの入り方を絵の構図に合わせて詰める**（優先度：低）

- 背景：カットインの入り方は絵が無い時期に決めた暫定で、フェード＋わずかなズーム（`ZOOM_FROM=1.06`）を3レシピ共通で掛けている。絵が揃ったいま、構図と噛み合っているかを見ていない。三重詠唱と神の裁きは光が上へ抜ける縦の構図、ホーリーアリアは横に広がる構図で、同じ入り方が3枚とも最適とは限らない。窓は横長八角形（最大740×520）で絵は4:3なので、上下が少し切れることも合わせて確認する。
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

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### refactoring-5

**hex_board_3d の段階分割（メッシュ生成→カメラ→インタラクション再評価）**（優先度：中）

- 背景：`presentation/board/hex_board_3d.gd` はプロダクト最大の約1500行で、(a) カメラリグ＋picking、(b) 選択→移動→コマンドメニューのインタラクション状態機械（約480行・コマンド追加のたび成長する中心）、(c) 盤の3D描画同期、(d) メッシュ/材質生成ヘルパーの4責務が同居している。ただし一括分割は危険：(b) と (c) はオーバーレイ状態（`_reachable`/`_targets`/`_formation_cells` 等）を共有する密結合で、素朴に切るとシグナルの往復や状態の二重持ちを生む。外側の疎な責務から段階的に剥がす。
- 対応：(1) メッシュ/材質生成（`_make_*` 系・材質/テクスチャキャッシュ）を `board_mesh_factory.gd` へ抽出（純関数中心・最小リスク）。(2) カメラ数学（リグ・パン/ズーム/fit/追従 Tween・picking）を `board_camera_rig.gd` へ抽出。入力イベントの受け口（`_unhandled_input`）は盤に1本のまま残してリグへ委譲＝イベント処理順の罠を避ける。`fit_to_view` の state 直読みはやめ、盤の外接矩形を引数で渡す。(3) 約1100行へ減った状態でインタラクション分割の要否を再評価する。切る場合は「オーバーレイ表示モデル（インタラクションが書き・描画が読む素データ）」を先に定義してから。より小さい代替として PopupMenu の組み立てだけの抽出（メニュービルダー）も可。
- 該当：`presentation/board/hex_board_3d.gd`・`presentation/board/board_mesh_factory.gd`（新規）・`presentation/board/board_camera_rig.gd`（新規）。挙動を変えないリファクタリングのため各段で実機確認（tests/manual の流儀）。

### refactoring-8

**デッドコードの整理（未接続シグナル・テスト専用関数）**（優先度：低）

- 背景：コード全体を走査し、本番コードから参照されていないシグナル・関数を検出した。未参照の .gd ファイルや未使用の定数は無い。デッドコードは2種類：(1) 発火するが誰も接続していないシグナル、(2) テストからしか呼ばれない public 関数。後者は「テスト容易性のために残す」か「本番と同じ経路でテストすべき」かの判断を含む。
- 対応（2026-08-03 全件判断済み）：項目ごとに削除・残置を判断した。削除4件・残置7件。削除対象はリモートエージェントで実施可能（テストの機械的置換＋関数削除＋GUT回帰確認）。
  - シグナル（2件）: `MatchController.move_rejected`・`unit_died`＝発火するが presentation が未接続。→ **残置**（将来 SFX／視覚フィードバックに使う可能性）。
  - BgmDirector（2件）: `enter_crisis()`・`in_crisis()`＝危機BGM切替。実装済みだがゲームに未配線。→ **残置**（将来配線する可能性）。
  - BattleState（2件）: `can_move()`・`can_deploy()`＝テスト用クエリ。本体は別経路で判定。→ **削除**（テストは `move_unit()` 戻り値・`deploy_cells().is_empty()` で代替。影響3か所・機械的置換）。
  - Combat（2件）: `effective_attack()`・`effective_defense()`＝breakdown のラッパー。テスト専用。→ **削除**（テストは `attack_breakdown(...)["total"]`・`defense_breakdown(...)["total"]` で代替。影響5ファイル24か所・機械的置換）。
  - Hex（2件）: `ring()`・`flood_reach()`＝本番は `within_range`・`flood_reach_cost_map` を使用。→ **残置**（テストの代替APIでは可読性・検証力が下がるため。テスト専用ユーティリティとして維持）。
  - TerrainSkinCatalog（1件）: `for_type()`＝`resolve()` と重複。→ **削除**（テストは `resolve("", type_id)` で代替。影響1ファイル9か所・機械的置換）。
  - Store 系（3件）: `RosterStore.has_roster()`＝テスト専用クエリ → **削除**（テストは `load_roster() == []` で代替。影響1ファイル12か所・機械的置換）。`RosterStore.clear_roster()`・`SaveStore.clear()`＝テスト対象そのもの（削除動作の検証） → **残置**。
- 該当：`application/match_controller.gd`・`application/bgm_director.gd`・`domain/battle_state.gd`・`domain/combat/combat.gd`・`domain/hex/hex.gd`・`data/terrain/terrain_skin_catalog.gd`・`infrastructure/save/roster_store.gd`・`infrastructure/save/save_store.gd`。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- 茂み（bush）の沈め量の詰め：立ち絵を沈める量（`terrain_skin.csv` の `sprite_sink`）を 0.12 で仮置きしている。茂みの絵そのものが仮のため、いま詰めても絵の差し替えでやり直しになる。本番の茂みタイルができたら実機で見て決める（→ [terrain.md](art/terrain.md)）。
- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
