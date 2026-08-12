# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=3 / feature=55 / refactoring=9

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。優先度は各エントリ見出しに 高（設計の背骨に関わる）／中／低（飾り・潜在）で記す。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### feature-2

**敵AI: 撤退する特性**（優先度：低）

- 背景：削られた駒が自陣営の拠点へ下がり、中に入って回復し、また出てくる動き。プレイヤーは「削りきる前に逃がすと振り出し」になるので、深追いするか諦めるかの判断が生まれる。[ai.md](gdd/ai.md) の特性はどれも撤退しないので、行動ルールにも `retreat` パラメーターにも入れていない。
- 対応：行動ルールに2行を足した特性を作る（`損耗が retreat 以上で自陣営の拠点にいる → 拠点に入る` ／ `損耗が retreat 以上で移動距離が測れる自陣営の拠点がある → 拠点へ最大前進`）。位置を攻撃より上に置けば背を向けて逃げ、下に置けば殴ってから退く。パラメーター `retreat` は損耗率で持つ。回復は[map.md](gdd/map.md) の「入る」に乗る＝敵AIが初めて「入る」を使う。
- 該当：`doc/gdd/ai.md`（特性を1つ追加）・`data/ai/ai.csv`（列 `retreat` を追加）・`domain/ai/`・`tests/unit/test_ai.gd`。着手の引き金＝撤退する敵を出したい冒険譚を作るとき。

### feature-4

**敵AI: 特性の拡充（対空狙い・間合維持）**（優先度：中）

- 背景：[ai.md](gdd/ai.md) の特性は5つで、盤の遊びとして要るのに表せない動きが2つある。(1) 飛行を優先して狙う。飛行は `atk_air>0` の駒でしか触れないので、対空を持つ敵が地上の駒を殴っている間、こちらの飛行は事実上の安全地帯になる。対空持ちが「空を狙える唯一の駒」であることを AI が理解しない限り、飛行の価値が壊れたままになる（竜狩り st5＝ハーピー／グリフォンが空で絡む回で効く）。(2) 間合維持（キティング）。射程ユニットが次の敵ターンに攻撃されない位置で止まる動きで、射程の価値がここで出る。
- 対応：それぞれ特性として立てる。対空狙いは獲物・手負いと同じ形の標的語（攻撃できる飛行ユニット）を足して行動ルールを書く。間合維持は前進の種類を1つ足す（脅威圏＝敵の移動力＋射程の外へ止まる）。
- 該当：`doc/gdd/ai.md`（用語・特性を追加）・`data/ai/ai.csv`・`domain/ai/`・`tests/unit/test_ai.gd`。

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

**製品ビルドの中身を整える（開発用アセットの除外・ライセンス文の同梱）**（優先度：中）

- 背景：`tools/`（戦闘計算シミュレータ combat_sim ほか自作ツール一式）・デバッグ用ステージ（`data/stages/debug*/`）・`addons/gut/`（テストフレームワーク）は開発専用で、製品ビルドに含めるべきでない。現状 export preset が未作成のため除外設定もされておらず、このままビルドすると同梱される。GUT は本体（MIT）と同梱フォント（OFL）を抱えているので、含めたままだと不要な表記義務まで背負う（[credits.md](sales/credits.md)）。
- 背景（同梱側）：逆に、含めなければならないものが落ちる。RockSalt（Apache 2.0）はライセンス文の同梱が義務だが、`assets/fonts/RockSalt-LICENSE.txt` は Godot がリソースとして扱わない素のファイルで、非リソースファイルのフィルタに指定しない限り pck に入らない。フォント本体（`.ttf`）は `.fontdata` に変換されて入るので、フォントだけ入ってライセンス文が無い、という一番まずい形になる。
- 対応（除外）：export preset の非公開フィルタ（除外パターン）に `tools/`・デバッグステージのパス・`addons/gut/` を加える。あわせてデバッグステージが実行時参照（ステージセレクトのマニフェスト／カタログ）に載らないことも確認する。
- 対応（同梱）：ビルド出力（exe と同じ階層＝Steam のデポにそのまま上がる場所）に `THIRD-PARTY-LICENSES.txt` を置く。中身は [credits.md](sales/credits.md) の義務がある行から起こす。preset の非リソースフィルタで pck に入れる手も取れるが、`export_presets.cfg` は `.gitignore` されていて preset を作り直すたびに設定が消え、消えたことに気づけないので、そちらには頼らない。exe の隣なら pck を解凍せずに読める利点もある。
- 該当：`export_presets.cfg`（新規）・`tools/`・`data/stages/debug*/`・`addons/gut/`・ステージ一覧の参照箇所・`doc/sales/credits.md`（同梱する文面の出どころ）。関連＝feature-54（ライセンスの裏取り）。着手の引き金＝配布ビルドを作るとき（parking lot「Steam 配布の段取り」と連動）。

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

- 背景：[naming_decision_senaris.md](sales/naming_decision_senaris.md) でタイトル名は「Senaris」に決定済みだが、確定前の手続きが残っている。すべてオーナー側の手作業。
- 開発元（2026-08-12 決定）：屋号は `craftkobo`。法人ではなく個人事業主として出品する＝Steam の契約名義は本名、公開される表示名は屋号。開業届は提出済み。ドメイン `craftkobo.com` は空きを確認済みで取得予定＝開発元用（プロダクト用の `senaris.in` とは別。問い合わせ先メールは開発元側に置く＝ゲームが増えても窓口が1つで済む）。銀行口座は未開設で、Steam の受取名義と一致すること・海外送金を受け取れることを確認してから作る。米国向けの税務書類はマイナンバーを外国TINとして出すと源泉徴収が下がる。
- Steam の名前まわり（2026-08-12 調査）：`steamcommunity.com/id/senaris` は他者が使用中だが、これは一般ユーザーがプロフィールページに付ける短縮URLで、ゲームとは無関係＝実害なし。ゲームのストアページは `store.steampowered.com/app/<AppID>/…` の形で、AppID は Valve が採番するため他者のユーザー名に影響されない。開発元ページ `store.steampowered.com/publisher/senaris` は未使用だが、これは早い者勝ちで押さえるものではなく登録後に申請して作るページ。実際に競合しうるのはゲーム名そのもので、Steamworks 登録時の審査に掛かる＝下記 (1) の商標クリアランスと同じ話。
- ドメインの調査結果（2026-08-12）：`senaris.com` は 2002 年からスペインの個人が保持しており取得不可（先月更新済み・中身は個人ページへの iframe 転送だけ）。ゲームや技術系の商用ブランドではないので、商標クリアランスに効く材料ではない。`.net` `.org` も登録済み。`.io` は Route 53 で年 $71 と本企画の規模に釣り合わず、加えて ccTLD 存続の論点がある。`.games` は年 $37。
- ドメインの方針：`senaris.in` を取る（年 $8。R53 のホストゾーン代が別途 年 $6）。ドメインはプロダクトごとに1本取る方針で、開発元のドメインはゲーム以外の事業に使うため、その下にぶら下げる形は取らない。`.in` はインドの ccTLD だが居住制限が無く、2005 年の一般開放から外国人にも開かれたまま安定している。取得時にプレミアム価格が付いていないかだけ確認する。
- サイトの方針：ランディングは1ページ。ニュース欄やブログは作らない（更新義務だけが残り、放置されたサイトは逆効果）。例外は仕様リファレンス（feature-52）で、更新頻度が低くデータから生成できるため別ページを持つ。
  - 構成：閉じた扉の1枚絵（`assets/menu/door.png`。周囲をぼかして黒背景へ溶かす／スクショの縮小画像が扉へ吸い込まれる演出）→ 酒場の中（一行の説明と紹介動画）→ 特徴とスクリーンショット → Steamへ・併売先（BOOTH／itch）→ フッター（連絡先・プレスキット・権利表記）。Steamボタンは右上に固定表示。仕様リファレンスへのリンクを持つ。
  - 動画は自前でホストせず Steam のウィジェット埋め込みか YouTube に載せる（変換・互換・転送量を持たなくて済む）。
  - 画像は WebP へ変換して1ページ合計1MB以内を目安に。扉は 1280×720 しか無いので全画面に敷かず中央配置にする。酒場の内観は1枚絵が無いため、セレクト画面のスクリーンショットを流用する。
  - ホスティングは静的。R53 に寄せるなら S3 + CloudFront（ACM の証明書は us-east-1 で作らないと CloudFront から選べない）。手軽さなら Firebase Hosting／Cloudflare Pages。S3 単体は HTTPS が付かないので不可。
  - 中身はストアページが決まってから作る＝載せる文と絵をそのまま流用できる。
- 対応：(1) 商標クリアランス＝第9類・第41類で US(USPTO)／EU(EUIPO)／日本(J-PlatPat) の各DBを正式確認（ドメインとは別作業。ドメインが空いていても商標が先に取られていることはある）。(2) `senaris.in` を取得。(3) SNSハンドル確保（X／Bluesky／Discord 等）。(4) Steam アプリ名予約（Steamworks 登録時・Steam Direct $100）。確定したら naming_decision_senaris.md のステータスを更新。
- 該当：`doc/sales/naming_decision_senaris.md`。着手の引き金＝配布が見えてきたとき（parking lot「Steam 配布の段取り」と連動）。サイト制作はストアページ（feature-51 と同じ段）のあと。

### feature-28

**ユニットスキル第2弾（貫通追加・再行動）**（優先度：中）

- 背景：ユニットスキルの器（単独発動・味方1体へ状態補正・移動後発動）は①ピクシーダストで実装済み（[skills.md](gdd/skills.md)）。カタログを増やす段で、次に入れる2つの方向まで決まっている＝(1) 貫通追加＝対象の攻撃に貫通率を乗せる、(2) 再行動＝行動を終えた味方をもう一度動かす。どちらもレシピは未設計（発動者・値・持続・射程が未定）でカタログにも載っていない。
- 対応：(1) 貫通追加は既存の状態補正で足りるか要確認＝`StatusMod` は攻防への add/mul は持つが、貫通率（`Unit.pierce`）に効く経路が無いため、補正チェーンに貫通の口を足すかどうかから決める。(2) 再行動は「1ターンに各ユニット1回まで」の縛りを入れる方針まで決定済み（無制限だと1体を延々動かせて崩壊する）。縛りの持ち場は駒側のフラグ＝`BattleState` に再行動回数を持たせ、中断セーブの直列化にも載せる。レシピが固まったら skills.md のカタログへ②③として追記する。
- 該当：`domain/formation/formation.gd`（RECIPES）・`domain/battle_state.gd`（再行動フラグ・直列化）・`domain/status/status_mod.gd`／`domain/combat/combat.gd`（貫通の口）・`tests/unit/test_skill.gd`・`doc/gdd/skills.md`。

### feature-29

**敵AIの陣形スキル使用（複数人）**（優先度：中）

- 背景：ユニットスキル（発動者1体）は敵も撃つようになった（特性の行動ルール＝[ai.md](gdd/ai.md)）。残るのは複数人の陣形スキルで、敵陣営向けのレシピが1つも無い。実行経路は `AiAction.SKILL` で共通なので、レシピを足せば同じ仕組みで飛ぶ。成立条件はスキンID照合（未指定は種別へフォールバック）＝データ面の下地はできている。
- 対応：(1) 敵陣営向けのレシピをカタログに足す（どの敵に何を持たせるかは冒険譚側の設計）。(2) 撃つ価値の評価を足す＝ユニットスキルは「対象1体」で選べたが、面の陣形は着弾中心の選び方（面に入る敵の数・味方の巻き込み）が要る。`_pick_skill_target` は対象1体を前提にしているのでここを広げる。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`domain/formation/formation.gd`（敵レシピ）・`tests/unit/test_ai.gd`・`doc/gdd/ai.md`・`doc/gdd/formations.md`（発動主体の記述を更新）。着手の引き金＝敵に陣形を持たせたい冒険譚を作るとき。

### feature-31

**体験版ビルドの素材選別（収録ステージから必要素材を導出して除外）**（優先度：低）

- 背景：体験版はチュートリアル3本のみを収録し、本編の冒険譚は入れない（[monetization.md](sales/monetization.md) 体験版の収録範囲）。収録しない冒険譚のユニット・地形・BGM・会話まで同梱するとサイズが無駄で、未収録分のネタバレにもなる。Godot のエクスポートプリセットは除外フィルタ（glob）・カスタム機能タグ（`OS.has_feature("demo")`）・CLI ビルドを備えるので機構は足りる。ただし素材は `skin_id` から文字列でパスを組み立てて `load()` する（`skin_catalog.gd`・`combat_scene.gd`・`hex_board_3d.gd`）ため、Godot の依存解決＝「選択したシーンと依存だけ」モードは効かない。必要素材の集合はこちらで計算して渡す必要がある。
- 対応：収録ステージJSON → 出現ユニット/地形の `skin_id`・BGM の `track_id` → 必要な `assets/**` パス集合、を導出して差集合を除外フィルタとして `export_presets.cfg` に書き出すスクリプトを足す（CSV正本→JSON生成と同じ発想＝正本から機械的に導出するので、収録ステージを足し引きしても壊れない）。代替は `EditorExportPlugin._export_file()` + `skip()` でエクスポート中に弾く方式＝フィルタ生成は不要だが何が落ちたか見えにくい。除外すると `ResourceLoader.exists()` が false になるので、未収録ステージがステージセレクトに載らないこと・参照が残る経路のフォールバックを併せて確認する。`data/i18n` の翻訳と未収録の会話テキストも同じ仕組みに乗せられる。
- 該当：`export_presets.cfg`（新規）・`tools/`（フィルタ生成スクリプト新規）・`doc/tech/tools.md`・`doc/sales/monetization.md`。着手の引き金＝体験版ビルドを作るとき（feature-10＝製品ビルドの中身を整えるのと同じ段・parking lot「Steam 配布の段取り」と連動）。

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

- 背景：[tutorial3 st6](campaign/tutorial3-dragon-hunt.md) の手負いのローグ一味は「殴り合いに付き合わず泉へ走る」動きが芯で、追いつけないから部屋を回り込んで挟み撃ちにする、という盤の遊びがそこから出る。[ai.md](gdd/ai.md) の特性はどれも攻撃の行を持つので、射程に敵が入ると立ち止まって「逃げている」感じが濁る。撤退（損耗したら退く。feature-2）とは別物で、こちらは最初から戦う気が無い側。
- 対応：攻撃の行を持たない特性を1つ足す。行動ルールは占領と前進だけで、前進は回り込み（敵ZOCを避けて目的地へ）。目的地を拠点にするか別の地点にするかは冒険譚側の設計と合わせて決める。
- 該当：`doc/gdd/ai.md`（特性を1つ追加）・`data/ai/ai.csv`＋`ai.json`・`domain/ai/`・`tests/unit/test_ai.gd`。着手の引き金＝tutorial3 st6 を組むとき。

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
- 対応：単色の地に Senaris ロゴ、その下に小さく開発元名（`craftkobo`）を入れた PNG を1枚作り、`boot_splash/image` に指定する。地の色は画像に焼かず `boot_splash/bg_color` に持たせ、`fullsize=false`（原寸中央）で置く＝解像度が変わってもロゴが歪まない。ブートスプラッシュはエンジン起動前の静止画でフェード等は不可なので、動きを付けたくなった場合はタイトルシーン側の演出として作る（feature-46）。`minimum_display_time` はエディタ実行とエクスポート版で効き方が異なる可能性があるため実機で確認する。あわせて `application/config/icon`（ウィンドウ／タスクバー）と Windows export preset の exe アイコン（.ico）も差し替える。
- 前提：解消済み。開発元名は屋号 `craftkobo` に決まった（2026-08-12。feature-27 に経緯）。Steam のパブリッシャー表示名も同じ名前になる。Senaris のロゴ本体も作成済み（[promo.md](art/promo.md)・`assets/promo-src/logo/`）。残るのは、ロゴの下に開発元名を入れたスプラッシュ用の1枚を組むこと（`tools/logo/build_logo.py` に出力を1つ足す形になる）と、原寸 PNG の書き出し、アイコンの差し替え。
- 関連：Senaris のロゴは Steam のカプセル画像（一覧・検索結果に出る看板画像）にも要る。カプセルはタイトル文字が載っていないと何のゲームか分からないため、[direction.md](art/direction.md) の「絵に文字を入れない」ルールはストア素材では例外にする必要がある。ロゴを起こす作業はスプラッシュとストア素材で共通なので、まとめて進める。
- 該当：`project.godot`（`boot_splash/*`・`application/config/icon`）・`export_presets.cfg`（exe アイコン・feature-10 で新規作成）・`assets/`（スプラッシュ画像・アイコン）・`doc/art/`（ロゴの作画方針）。着手の引き金＝ロゴを起こすとき（ストアページの素材と同じ段）、または配布ビルドを作るとき。

### feature-46

**タイトル画面（酒場の入口）**

- 背景：画面と場面の繋ぎは入った（`presentation/title/title_screen.gd`）。起動すると酒場の扉が外から映り、入力で扉が開く動画に切り替わり、くぐるとセレクト画面へ渡る。まだ載っていないのは文字と項目で、終了・設定・クレジットの置き場が無い。
- 入っているもの：閉じた扉の1枚絵（`assets/menu/door.png`）と、扉が開いて店内へ入る動画（`assets/menu/door_open.ogv`・10秒・扉の軋みと焚き火の音込み）。素材の作り方と落とし穴は [menu.md](art/menu.md) §5。BGM は曲ではなく店のざわめき（`title`）で、扉が閉じている間はこもらせ、扉が開くのに合わせて開く（[bgm.md](audio/bgm.md)）。動画は再生中の入力でスキップできる。
- 仕様から変えたこと：吊り看板は作らなかった。絵に文字を入れないのが全アセット共通のルールなので、タイトルは UI 側で載せる。またタイトルにメインテーマは置かず、作品の顔となる旋律は `menu`（セレクト画面の曲）が担うことにした。
- 対応（残り）：背景の上にメニュー項目を重ねる。ボタンは既存の `plank`（木の板ボタン）を流用＝セレクトと同族の手触りになる。Press any key の一拍は挟まず最初からメニューを出す（PC では無意味なクリックが1回増えるだけ）。いまは項目が無いぶん任意の入力で先へ進む暫定状態なので、ここは実装時に置き換える。「はじめる」で扉の動画を再生してセレクトへ。
- 決めていないこと：タイトルロゴを画面のどこに置くか（扉の右手前が暗く空いている）。「つづきから」は盤へ直行するが、そのとき扉の動画を挟むか（酒場に入る画と、戦場へ戻る動きが噛み合わない）。
- メニュー項目：つづきから（`SaveStore.has_save()` が真のときだけ出し、押したら盤へ直行。実装済みの中断セーブをそのまま使う）／はじめる（セレクトへ）／設定（feature-47）／クレジット／おわる。
- クレジット：素材の権利表記。画面に出す内容は [credits.md](sales/credits.md) の「ゲーム内クレジットに出すもの」が正本で、そこを読んで並べるだけにする。台帳の整備自体は済んでいるが、根拠が取れていないライセンスが残っている（feature-54）。決めていないのは、制作に使った道具（MuseScore・ImageMagick・FFmpeg・Inkscape ほか）を画面にも出すか＝台帳には義務の有無に関わらず載せてあるが、画面に載せる範囲は未決。リリース前が締め切り。
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

### feature-50

**敵AI: 新仕様（特性ベース）への作り直し**（優先度：高）

- 背景：[ai.md](gdd/ai.md) を軸の組み合わせから特性単位へ書き直した（旧版は `doc/gdd/ai_old.md`）。実装は旧仕様のまま＝`nearest_attacker_brain` が engage/skill/attack/target/advance の各軸を読む作り。距離の定義（盤上距離・移動距離・迂回距離・視線距離）、前進の種類（最大前進・回り込み・直線寄せ）、stack 条件、獲物・手負いの選び方が新仕様で変わっている。
- 対応：特性ごとの行動ルールを上から当てる形へ作り直す。ai.csv の列を `ai` / `name` / `sight` / `stack` に絞る（旧列は全廃）。テストは特性ごとに「どの行が成立するか」で書く。旧実装で効いていた挙動との差分（stack の全特性適用、weak の sight、swarm の行順、raid が敵を追わない）を回帰で押さえる。完了時に `ai_old.md` を消し、コード内の ai.md 参照コメントを更新する。
- 該当：`domain/ai/`・`data/ai/ai.csv`＋`convert.gd`＋`ai_catalog.gd`・`application/stage_loader.gd`・`data/stages/`（部隊定義）・`tests/unit/test_ai.gd`・`tests/unit/test_data_integrity.gd`・`doc/gdd/ai_old.md`（削除）。
- 段取り（2026-08-12 の読み合わせで決定。仕様は ai.md 更新済み・以降は ai.md が正本）：
  1. データ層＝`ai.csv` を4列化（主キー列 `label`→`ai`）・`convert.gd` の必須列・`ai_catalog`。`sight` の記号は `-`（その特性は使わない）／`*`（上限なし・壁は遮る）／数値。`test_data_integrity` に「敵駒は必ず部隊に属する」の検証を追加。
  2. 距離の基盤＝`BattleState` に地形距離・迂回距離・攻撃可能なマス集合を足す（移動距離は既存の `travel_cost_field_avoiding_units`）。攻撃可能なマスは対空・対地まで見る。
  3. 特性エンジン＝行動ルールを表として持つ Brain へ作り直し。特性ごとに「どの行が成立するか」でテストを書く。
  4. 配線＝ステージ直下の `ai`（`BattleState.enemy_ai`）と `NearestAttackerBrain.from_preset` を廃止。`main.gd`・`match_controller`・`stage_loader` を新しい組み立てに合わせる。敵駒は必ず部隊に属する（テストも部隊で書く）。
  5. 行動順・拠点出撃を新仕様へ（部隊 order → 部隊内は盤上距離、拠点は1部隊）。
  6. 検知域の表示に weak を含める（`*` は十分大きい予算として扱う）。`presentation/board/hex_board_3d.gd`・`match_controller.detection_radius`。
  7. 後片付け＝`ai_old.md` 削除・コード内の参照コメント更新・本エントリ削除。
- 依存は一直線（2 は 1、3 は 2、…）。並行に走らせず順に消化する。

### feature-51

**プロモーション映像の制作**（優先度：低）

- 背景：ストアページに置く映像がまだ無い。1本目はプレイ映像（何のゲームか数秒で伝わるもの）、2本目に世界観のティザー、という並びを想定している。ティザー用の素材は 2026-08-12 の Gemini の無料枠で確保した（枠は同日で終了。以後の生成は有料）。生成でしか作れないカットは押さえてあるので、残りは手持ちの素材と実機録画で組める。
- 手元にあるもの：
  - ドラゴンのキービジュアル2枚（`assets/promo-src/dragon_breath/`）。炎あり `dragon_breath_b_03_master.png` と、その直前＝炎なし `dragon_breath_pre_b_03_master.png`。1376×768・透かし除去済み。生成に使った文面は同フォルダの `*_prompt.txt`（自己完結・再生成可）。
  - 上記から起こした動画2本（`dragon_breath_video_b1_01_raw.mp4` / `b2_01_raw.mp4`。各10秒・1280×720・24fps・音声つき）。b2 が良いほうで、使えるのは 5.0〜10.0 秒（それ以前は炎がバリアの内側に入る）。b1 は 0〜7 秒（溜めが長く空転する）。
  - 酒場の扉が開くカット（`assets/menu/door_open.ogv`＝タイトル画面で使用中。採用しなかったテイクが `assets/menu-src/door/`）。ティザーの掴みに流用できる。
- 対応：
  1. 手持ち映像の整形。透かしは 1280×720 のフレームで中心 (1158, 600)・約55px角。`crop=1130:636:0:0` で左上基準に切れば16:9のまま枠外に出る（右と下を12%落とす。ドラゴンの尻尾の先が少し切れる）。あわせて使える区間だけ切り出す。
  2. プレイ映像の録画。ティザーの着地にも、ストア1本目にも要る。盤・戦闘演出・陣形カットインが揃ってから撮る。
  3. 構成を決めて編集。ティザーの想定は 掴み＝扉が開く／山場＝ドラゴンの炎／着地＝盤面。生成映像はイラスト調のまま使い、最後に実機の絵で落とすことで「本編と地続き」に見せる。
  4. 音。生成映像に付いてくる音声は捨てて、投入済みの BGM から当てる（[bgm.md](audio/bgm.md)）。
  5. Steam の AI 生成コンテンツ開示。生成物を使う以上、提出フォームでの申告が要る（[direction.md](art/direction.md) の配布注意）。
- 該当：`assets/promo-src/dragon_breath/`・`assets/menu-src/door/`・`doc/sales/monetization.md`。着手の引き金＝ストアページを作るとき（parking lot「Steam 配布の段取り」と連動）。

### feature-52

**仕様リファレンス（ゲーム内の図鑑とサイトの仕様ページ）**（優先度：中）

- 背景：本作は完全情報ゲーム＝戦闘に乱数が無く（feature-9 の前提）、敵の行動も特性ごとのルールで決まる（[ai.md](gdd/ai.md)）。負けた理由が必ず盤上にある、という設計が売りになるが、そのルールをプレイヤーが読める場所が今どこにも無い。feature-46 のメニュー項目一覧（つづきから／はじめる／設定／クレジット／おわる）にも入っていない。下地としては `unit_skin.csv` の分類が図鑑用として既に用意されている（[units.md](art/units.md)）。
- 対応：
  1. 範囲を決める。候補は 敵AIの特性と行動ルール／地形コストと移動タイプ／戦闘の補正チェーン／ユニット性能表／陣形・ユニットスキルのカタログ。どこまで見せるかは「完全情報を主張する以上、隠す理由のあるものは無い」を基準に判断する。
  2. CSV正本から生成する。敵AIも地形も移動タイプもユニット性能も `data/**/*.csv` が正本なので、そこから表を機械的に起こす（CSV正本→JSON生成と同じ発想）。手書きすると必ず実装とズレる。生成先はゲーム内データとサイトのHTMLの両方。
  3. ゲーム内の画面を作る。タイトルとゲーム中のシステムメニューの両方から開く（設定画面＝feature-47 と同じ置き方）。メニュー項目の名前は未決＝決まったら feature-46 の項目一覧に足す。
  4. サイト側は別ページ（`senaris.in/rules` 相当）。ランディングは1ページのまま、そこからリンクする。
  5. i18n。表の見出しと説明文は翻訳キーに載せる（feature-12 と同じ扱い）。
- 該当：`data/**/*.csv`・`tools/`（生成スクリプト新規）・`presentation/`（図鑑画面・新規）・`doc/gdd/`（見せる範囲の記述）・feature-46（メニュー項目の追加）・feature-47（同じ開き方）。着手の引き金＝サイトを作るとき、または完全情報であることを説明する必要が出たとき。

### feature-53

**Steam ストアページの作成**（優先度：中）

- 背景：配布はまず Steam（[monetization.md](sales/monetization.md)）だが、ストアページを作る段取りが未整理だった。埋めるスロットが多く一度に全部は動かせないので、購入判断への効き方で順序を付ける。作画の方針は [promo.md](art/promo.md) が正本で、ここには段取りだけ置く。
- 埋めるスロット：
  - 画像＝カプセル5種（ヘッダー 460×215／小 231×87／メイン 616×353／縦 374×448／ページ背景 1438×810。寸法は提出時に Steamworks で最終確認）・ライブラリ用一式・スクリーンショット（1920×1080・5枚以上）
  - 動画＝順番付きで、1本目が自動再生される。ページ公開の必須要件ではない
  - テキスト＝ゲーム名／開発元・パブリッシャー名（craftkobo）／短い説明（〜300字）／本文（このゲームについて）／タグ（最大20・開発者の設定後にユーザー投票で並び替わる）／対応言語（ja・en をインターフェース／字幕／音声の別で申告）
  - 手続き＝価格（¥1,000）・リリース日・動作環境・年齢区分と表現の申告・AI生成コンテンツの開示
- 購入判断への効き方（この順で作る価値がある）：カプセル画像 ＞ スクリーンショット ＞ 短い説明 ＞ タグ ＞ 1本目の動画 ＞ 本文。判断は2段階で、一覧で開くかどうかを決めるのがカプセル・タイトル・タグ・価格、開いてから欲しくなるかを決めるのが動画・スクショ・短い説明・本文。発売前はレビューが無いぶん、前者の比重が大きい。
- 作る順序（上から依存している）：
  1. ロゴ（feature-45）。カプセル全種の前提。**作成済み**（2026-08-12。`assets/promo-src/logo/` に暗背景版・明背景版・小サイズ版の SVG、`tools/logo/` に生成スクリプト2本、方針と寸法は [promo.md](art/promo.md)）。残るのは用途ごとの PNG 書き出し
  2. カプセル画像。ロゴ＋背景の絵。背景は冒険者＋竜の構図が候補で、王道ゆえに1秒で伝わる。ジャンル（戦術SLG）はロゴのヘックスとタグと短い説明で伝える分担にする
  3. 短い説明・タグ。素材が要らないので並行して進められる
  4. スクリーンショット。盤・戦闘演出・陣形カットインが揃ってから撮る
  5. 本文。スクショと一緒に組む
  6. 動画（1本目＝プレイ映像、2本目＝ティザー。feature-51）
- Steamworks への登録（$100）は思ったより前に来る可能性がある。登録しないとページの入力欄が開かないため、素材を揃えてから登録するより、早めに登録して実際の入力欄を見たほうが作るものが具体的になる。[monetization.md](sales/monetization.md) の「体験版を先に出して出荷工程をリハーサルする」方針とも合う。前提＝支払い手段と本人確認、公開までに税務書類と銀行口座（feature-27 の開発元の項）。
- カプセルの検討結果（2026-08-12）：手持ちのドラゴンのキービジュアルを 460×215 に切って確認した。全幅を使って上下を16%落とす形なら構図がそのまま生きる。ただし小カプセル（231×87）まで縮めると読めるのは竜と炎だけで人物は潰れる＝5種を同じ絵から切り出すにしても、寄せ方は枠ごとに変えてよい。カプセル専用に絵を起こす場合は、最初から 460:215 の比で生成し、ロゴを置く余白（上部の空）を空けた構図にする。
- タグの調査（2026-08-12。Into the Breach／Wargroove／Panzer Corps 2 の実際のタグを取得して比較）：
  - 3本に共通＝`ストラテジー` `ターン制ストラテジー` `ターン制戦略` `ターン制` `戦術` `シングルプレイヤー`。
  - 日本語タグに「ターン制タクティクス」は存在しない。英語の Turn-Based Tactics に対応する日本語表記が `ターン制戦略` で、`ターン制ストラテジー`（Turn-Based Strategy）とは別タグ。3本とも両方付けている＝日本語だけ見て同義と判断せず両方付ける。
  - `ヘクス` タグが実在する（Panzer Corps 2）。母数は小さいがヘックス戦術を探している層へまっすぐ届くので、本作では効きが大きいと見る。
  - たたき台＝`ストラテジー` `ターン制ストラテジー` `ターン制戦略` `ターン制` `戦術` `ヘクス` `ファンタジー` `シングルプレイヤー` `インディー` `2D` `ターン制コンバット` `戦争ゲーム` `リプレイ性`。
  - 判断が要るもの＝`パズル`。乱数の無い完全情報という性質は Into the Breach に近く刺さる層はいるが、カジュアルなパズルを期待した客が来ると期待違いになる。
  - 外すもの＝ローグライク・自動生成（該当しない）、マルチプレイヤー系（無い）、ドット絵（絵柄が違う）。
  - 表示順は最終的にユーザー投票で並び替わる。開発者が設定した順が効くのは投票が溜まるまでの初期だけ。
- 該当：`doc/art/promo.md`（作画方針）・`assets/promo-src/`・`doc/sales/monetization.md`。関連＝feature-45（ロゴ）・feature-51（映像）・feature-52（仕様リファレンスへのリンク）・feature-27（サイトへ文と絵を流用）。着手の引き金＝配布ビルドが見えてきたとき（parking lot「Steam 配布の段取り」と連動）。

### feature-54

**クレジット正本のライセンス裏取り**（優先度：中）

- 背景：[credits.md](sales/credits.md) を起こしたが、ライセンスの裏が取れているのはリポジトリ内に根拠ファイルがあるものだけ（Rock Salt・GUT とその同梱フォント・EB Garamond・Sonniss）。残りは一般知識で分類しただけで、正本の「根拠」列が空欄になっている。表記を確定する前に公式の記載で確認する必要がある。
- 対応：空欄の行について公式サイトのライセンス記載を当たり、根拠列を埋める。対象は Godot Engine・MuseScore Studio・Muse Sounds／MS Basic・FFmpeg・ImageMagick・Inkscape・fontTools・Pillow・NumPy・OpenCV・Google Gemini。とくに注意する点：
  - FFmpeg はビルドによって LGPL と GPL が変わる。使っているバイナリがどちらかを確認する
  - Muse Sounds と MS Basic は、書き出した音声を商用作品に載せてよいかが規約本文の確認事項。ここが崩れると自作曲が全部影響を受ける
  - Google Gemini は出力物の権利帰属と商用利用条件。Steam の AI 開示（[monetization.md](sales/monetization.md)）とは別の論点
  - Godot は同梱サードパーティを含めた表示義務の範囲。`Engine.get_copyright_info()` の内容で足りるかを確認する
  - Pillow はバージョンによってライセンス表記が変わっている
- 該当：`doc/sales/credits.md`（根拠列）。関連＝feature-46（クレジット画面）・feature-10（ライセンス文の同梱）。着手の引き金＝配布ビルドを作る前。

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
- 進捗（2026-08-11）：ステップ1完了（`3d72eab`・2254→2041行・-213行）。ステップ2完了（`65c3499`・2041→1910行・-131行・`board_camera.gd` 167行・`test_board_camera.gd` 97行）。ステップ3完了（`844a061`・1910→1567行・-343行・`board_unit_renderer.gd` 374行・`test_board_unit_renderer.gd` 116行）。ステップ4完了（1567→944行・-623行・`board_terrain_renderer.gd` 300行・`test_board_terrain_renderer.gd` 68行）。
- 該当：`presentation/board/hex_board_3d.gd`・`presentation/board/board_mesh_factory.gd`・`presentation/board/board_camera.gd`・`presentation/board/board_unit_renderer.gd`・`presentation/board/board_terrain_renderer.gd`・`tests/unit/test_board_mesh_factory.gd`・`tests/unit/test_board_camera.gd`・`tests/unit/test_board_unit_renderer.gd`・`tests/unit/test_board_terrain_renderer.gd`。5の切り出し先ファイル名は着手時に決める。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- 茂み（bush）の沈め量の詰め：立ち絵を沈める量（`terrain_skin.csv` の `sprite_sink`）を 0.12 で仮置きしている。茂みの絵そのものが仮のため、いま詰めても絵の差し替えでやり直しになる。本番の茂みタイルができたら実機で見て決める（→ [terrain.md](art/terrain.md)）。
- SVG を絵にする道具の導入：ロゴを SVG で持つようになったが、この環境には SVG のラスタライザが無い。今は svglib → PDF → pypdfium2 という遠回りで確認しており、これは SVG のマスク（文字と剣をタイルから抜く処理）を描画できないため、抜きの確認だけ `assets/promo-src/logo/preview.html` をブラウザで開いて目視している。入れるなら cairo より **resvg**（実行ファイル1つ・SVG の対応度が高くマスクも描ける）が軽い。必須ではないので、SVG を触る作業が増えたら検討する。
- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
