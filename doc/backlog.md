# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=1 / feature=12 / refactoring=5

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。優先度は各エントリ見出しに 高（設計の背骨に関わる）／中／低（飾り・潜在）で記す。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

（現在、判明済みの不具合はなし）

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### feature-1

**マップペインタ（自前の地形エディタ）**（優先度：低）

- 背景：ステージの盤面を、マウスでヘックスを塗って `data/stages/*.json` に保存するエディタ。`presentation/board/hex_board_3d.gd` が既に「マウス位置→ヘックス」判定（`_hex_at_mouse`＝地面平面へレイキャスト→`Hex.from_pixel`。ホバー／クリック）を持つので、塗りモードと保存機能を足すだけで作れる。現状は小マップを JSON 直書きで回している。
- 対応：`hex_board_3d.gd` の既存判定を土台に、(1) 地形を選んでヘックスを塗るモード、(2) `data/stages/*.json` への保存、を足す。代替として外部の Tiled（ヘックス対応・JSON 書き出し）も選択肢。
- 2レイヤーを塗る想定（refactoring-2 と対）：性能レイヤー＝terrain_type（ASCII `terrain` グリッド）／見た目レイヤー＝terrain_skin（`terrain_skins` の座標→skin_id 差分列挙）。見た目レイヤーの skin_id は一意文字列で、人間は生JSONを読まずツール経由で塗るため ASCII 1文字表記の限界を受けない（分割の動機そのもの）。未指定セルは type 既定スキンにフォールバック。
- 該当：`presentation/board/hex_board_3d.gd`（既存のヘックス判定）・`data/stages/*.json`（出力先）。着手の引き金＝大きいマップをテキスト手書きするのが辛くなったら。

### feature-2

**敵AI: retreat（撤退）軸の配線**（優先度：低）

- 背景：AI思考の6軸のうち retreat（撤退閾値＝兵数がこの値を下回ったら退く／ただし自軍拠点が無ければ退かない。[ai.md](gdd/ai.md)「3. 撤退」）は、ai.csv に列・既定（`0`＝退かない）があり `DEFAULT_PRESET` にも入っているが、`nearest_attacker_brain` がこの値を読んでいない＝**未配線**で、現状は常に退かない。既定値の設計は済んでおり、残るのは挙動の実装のみ。
- 対応：`nearest_attacker_brain` に撤退判定を足す（`_param(state, u, "retreat")` を読み、兵数 < 閾値 かつ自軍拠点あり のとき退く＝拠点方向へ後退／交戦回避）。部隊ごとの上書きは既存の `_param` 解決でそのまま効く。実装後に ai.md の「retreat は未配線」記述を更新。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`（テスト追加）・`doc/gdd/ai.md`（記述更新）。ai.csv は列既存のため変更不要。

### feature-3

**陣形スキル（システム＋レシピ）**（優先度：高）

- 背景：コンセプトの目玉。特定配置（編成レシピ）が揃うと発動する能動アクション（参加ユニットは行動完了・効果は間接扱い）。[combat.md](gdd/combat.md) §2・[formations.md](gdd/formations.md) に仕様があるが完全未実装＝`domain/formation/` は空（`.gdkeep` のみ）。発動コマンドも無い。レシピ3種（①三重詠唱＝ウィザード/ウィッチ3体・三角形／②聖なる加護＝占領兵5体隣接・全体バフ×1.3／③神の裁き＝パラディン＋占領兵2体・射程10単体）すべて未実装。
- 対応：`domain/formation/` に配置判定（三角形・隣接数）と発動解決を新設。②が要求する「ターンをまたぐ全体バフの持続」は現状 `BattleState` に無いのでバフ状態管理も要る。発動コマンドを `application/commands/` に足し、`hex_board_3d.gd` のコマンドメニューに項目を出す（uiux.md §フェーズ2「当面出さない＝ドメイン未実装」の解除）。
- 該当：`domain/formation/`（新規）・`domain/battle_state.gd`（バフ持続）・`application/commands/`（発動）・`presentation/board/hex_board_3d.gd`（メニュー項目）・`doc/gdd/combat.md` §2・`doc/gdd/formations.md`・`doc/gdd/uiux.md`。

### feature-4

**敵AI: 思考軸の残り値の配線**（優先度：中）

- 背景：AIの各軸のうち一部の値しか効いていない（[ai.md](gdd/ai.md) §4〜6・§1）。実装済みは attack=`always`/`prey`、target=`near`/`weak`、advance=`max`/`base`/`flank`、engage=`charge`/`sight`/`squad`。未実装は attack の `solo_adv`/`surround_able`/`surrounded`/`no_retal`/`kill`、target の `maxdmg`/`mindmg`/`capturer`/`ranged`/`flyer`、advance の `spacing`（間合維持＝キティング）/`squad`/`careful`、engage の `turn:N`。ai.csv には列・表記があり、読み手（Brain）が未対応。retreat 軸は別途 feature-2。
- 対応：`nearest_attacker_brain` の `_pick_target`／攻撃判定／`_advance_dest`／`_ensure_engaged` に各値の分岐を足す。射程ユニットの間合維持（spacing）は AI の質に効く本命。値ごとにテストを足す。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`・`doc/gdd/ai.md`（各軸の実装状況を更新）。ai.csv は列既存のため変更不要。

### feature-5

**戦力供給の持ち越し（roster: carryover）**（優先度：高）

- 背景：キャンペーンの背骨。前ステージの生存ユニット（経験Lv・残兵）を次ステージへ持ち越す供給モデル（[map.md](gdd/map.md) §戦力供給・未決）。ステージに `roster:"fresh"|"carryover"` を宣言する想定だが、`StageLoader` が `roster` キーを読まず、持ち越しロジックも無い（全ステージ fresh 相当）。
- 対応：ステージJSONに `roster` を足し、`StageLoader` が解釈。carryover 時は前ステージ終了時の生存ユニット（type・level・残兵）を引き継いで配置する受け渡し口を用意。セーブ／ロード（feature-9）と持ち越し状態の永続化で論点が絡む。
- 該当：`application/stage_loader.gd`・`presentation/main/main.gd`（ステージ間の受け渡し）・`doc/gdd/map.md`。

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

- 背景：システムメニューに枠はあるが無効表示（[uiux.md](gdd/uiux.md) §フェーズ3・[gamesystem.md](tech/gamesystem.md) がセーブ仕様の正本）。盤の状態を永続化・復元する機能が未実装。feature-5（戦力供給の持ち越し）とステージ間状態の永続化で論点が絡む。
- 対応：`gamesystem.md` のセーブ仕様に沿って `BattleState` の直列化＋ファイル保存/読込を実装し、HUD の無効項目を有効化。
- 該当：`domain/battle_state.gd`（直列化）・`presentation/ui/hud.gd`（項目有効化）・`application/`（保存/読込の配線）・`doc/tech/gamesystem.md`。

### feature-10

**製品ビルドから開発用アセットを除外（ツール・デバッグステージ）**（優先度：低）

- 背景：`tools/`（戦闘計算シミュレータ combat_sim ほか自作ツール一式）とデバッグ用ステージ（`data/stages/debug*/`）は開発専用で、製品ビルドに含めるべきでない。現状 export preset が未作成のため除外設定もされておらず、このままビルドすると同梱される。
- 対応：export preset を作る段で、非公開フィルタ（除外パターン）に `tools/` とデバッグステージのパスを加える。あわせてデバッグステージが実行時参照（ステージセレクトのマニフェスト／カタログ）に載らないことも確認する。
- 該当：`export_presets.cfg`（新規）・`tools/`・`data/stages/debug*/`・ステージ一覧の参照箇所。着手の引き金＝配布ビルドを作るとき（parking lot「Steam 配布の段取り」と連動）。

### feature-11

**陣形①三重詠唱の威力モデル見直し（合算がオーバーキル）**（優先度：中）

- 背景：現状①三重詠唱の威力は「参加3体の実効攻撃力を合算して1発の打撃」（`domain/formation/formation.gd` `_formation_hit`）。実機で3ウィザードが対低防御（ゴブリン）を一撃全滅＝オーバーキルだった。1発に合算するとダメージ式 `A²/(A²+D²)` が飽和し、割合がほぼ1に張り付く。
- 対応（案）：合算をやめ「3人がそれぞれ攻撃した扱い」＝各参加者が個別に対象へ打撃を解決し損害を積む（対象1体あたり最大でも兵数上限までしか削れないので、単純合算より緩い＝オーバーキルしにくい）。他案＝合算に係数を掛ける／距離減衰。数値は実プレイで詰める（[formations.md](gdd/formations.md) §未決「各レシピの数値チューニング」と連動）。②③の威力式も揃える。
- 該当：`domain/formation/formation.gd`（`_formation_hit`）・`tests/unit/test_formation.gd`（威力の検証を差し替え）・`doc/gdd/formations.md`。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### refactoring-1

**ステージJSONの「個別キー上書き」の存廃検討**（優先度：低）

- 背景：StageLoader はユニット1体ごとに `troops`/`atk`/`def`/`move` 等のキーで catalog（unit_type.csv）のステータスを上書きできる。「性能は type が唯一の出どころ」という設計と緊張関係にあり、ステージ側で数値が散らばるとバランス調整の見通しが悪くなる懸念。一方、ボス個体の微調整・弱った増援などの表現には便利。現状の実ステージでは未使用（デモ検証時に一度使いかけて取りやめ）。
- 対応：残す（＝使い所のガイドラインを決める）か、削る（＝type 追加で表現に統一）かを決める。決めるまで実ステージでは使わない。
- 該当：`application/stage_loader.gd`（`_make_unit` の `u.get("atk", ...)` 系）・`data/stages/*.json`（利用箇所は現状なし）。

### refactoring-4

**garrison の native 整合バリデーション（ドラゴン除外）**（優先度：低）

- 背景：対応する味方がいないユニット（ドラゴン等）は解放対象＝garrison にできないルール（[map.md](gdd/map.md) 出撃・未決）。現状 `StageLoader._apply_bases` は garrison の type/native 整合を検証せず、任意 type を積めてしまう＝ステージ作成時のミスを検出できない。
- 対応：garrison 生成時に「その native で解放できる type か」を検証し、不整合は生成時警告で弾く（CSV→データ生成のバリデーション方針の一適用）。ルールの線引き（どの type が garrison 不可か）を先に決める。
- 該当：`application/stage_loader.gd`（`_apply_bases`）・`doc/gdd/map.md`。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
