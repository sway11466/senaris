# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=1 / feature=3 / refactoring=4

項目（バグ bug / 機能追加 feature / リファクタリング refactoring）を追加するときは、該当カテゴリの採番を +1 して ID を継ぐ。完了した項目は本書から削除し、番号は再利用しない（過去の使用済み番号は `git log -p -- doc/backlog.md | grep -oE '(bug|feature|refactoring)-[0-9]+' | sort -u` で確認できる）。状態は「本書に載っていれば未完了／消えていれば完了」で表す（状態列は持たない）。優先度は各エントリ見出しに 高（設計の背骨に関わる）／中／低（飾り・潜在）で記す。

## バグ

判明済みの不具合。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

（現在、判明済みの不具合はなし）

## 機能追加

実装済みコードに足す機能。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### feature-1

**マップペインタ（自前の地形エディタ）**（優先度：低）

- 背景：ステージの盤面を、マウスでヘックスを塗って `data/stages/*.json` に保存するエディタ。`presentation/board/hex_board.gd` が既に「マウス位置→ヘックス」判定（`from_pixel`／ホバー／クリック）を持つので、塗りモードと保存機能を足すだけで作れる。現状は小マップを JSON 直書きで回している。
- 対応：`hex_board.gd` の既存判定を土台に、(1) 地形を選んでヘックスを塗るモード、(2) `data/stages/*.json` への保存、を足す。代替として外部の Tiled（ヘックス対応・JSON 書き出し）も選択肢。
- 2レイヤーを塗る想定（refactoring-2 と対）：性能レイヤー＝terrain_type（ASCII `terrain` グリッド）／見た目レイヤー＝terrain_skin（`terrain_skins` の座標→skin_id 差分列挙）。見た目レイヤーの skin_id は一意文字列で、人間は生JSONを読まずツール経由で塗るため ASCII 1文字表記の限界を受けない（分割の動機そのもの）。未指定セルは type 既定スキンにフォールバック。
- 該当：`presentation/board/hex_board.gd`（既存のヘックス判定）・`data/stages/*.json`（出力先）。着手の引き金＝大きいマップをテキスト手書きするのが辛くなったら。

### feature-2

**敵AI: retreat（撤退）軸の配線**（優先度：低）

- 背景：AI思考の6軸のうち retreat（撤退閾値＝兵数がこの値を下回ったら退く／ただし自軍拠点が無ければ退かない。[ai.md](gdd/ai.md)「3. 撤退」）は、ai.csv に列・既定（`0`＝退かない）があり `DEFAULT_PRESET` にも入っているが、`nearest_attacker_brain` がこの値を読んでいない＝**未配線**で、現状は常に退かない。既定値の設計は済んでおり、残るのは挙動の実装のみ。
- 対応：`nearest_attacker_brain` に撤退判定を足す（`_param(state, u, "retreat")` を読み、兵数 < 閾値 かつ自軍拠点あり のとき退く＝拠点方向へ後退／交戦回避）。部隊ごとの上書きは既存の `_param` 解決でそのまま効く。実装後に ai.md の「retreat は未配線」記述を更新。
- 該当：`domain/ai/nearest_attacker_brain.gd`・`tests/unit/test_ai.gd`（テスト追加）・`doc/gdd/ai.md`（記述更新）。ai.csv は列既存のため変更不要。

## リファクタリング

挙がった改善項目。採番は本書冒頭「index」。各エントリは 背景／対応／該当 で記す。

### refactoring-1

**ステージJSONの「個別キー上書き」の存廃検討**（優先度：低）

- 背景：StageLoader はユニット1体ごとに `troops`/`atk`/`def`/`move` 等のキーで catalog（unit_type.csv）のステータスを上書きできる。「性能は type が唯一の出どころ」という設計と緊張関係にあり、ステージ側で数値が散らばるとバランス調整の見通しが悪くなる懸念。一方、ボス個体の微調整・弱った増援などの表現には便利。現状の実ステージでは未使用（デモ検証時に一度使いかけて取りやめ）。
- 対応：残す（＝使い所のガイドラインを決める）か、削る（＝type 追加で表現に統一）かを決める。決めるまで実ステージでは使わない。
- 該当：`application/stage_loader.gd`（`_make_unit` の `u.get("atk", ...)` 系）・`data/stages/*.json`（利用箇所は現状なし）。

### refactoring-3

**ユニットも skin を純ロジックから切り離す（案P 化）**（優先度：低）

- 背景：地形は refactoring-2 で見た目(skin)を domain から完全に外した（案P＝skin は presentation のみ・`BattleState` は skin を持たない）。一方ユニットは domain の `Unit.skin_id` に skin を同乗させている（`battle_state.gd` のセーブ列にも乗る）。純ロジック（combat/surround/movement/AI）は skin_id を読まない不変条件は満たしているが、地形と方針が揃っていない。
- 対応：ユニットの skin 解決も presentation 側に寄せられるか検討する（`Unit` から `skin_id` を外し、描画は `unit_id → skin_id` の対応を presentation で持つ）。占領＝寝返り（team 反転時のスキン再解決）とセーブ（skin をどこに永続化するか）が論点＝地形セルは静的なので単純だったが、ユニットは移動・寝返り・直列化があるため単純移設にはならない。方針だけ先に決め、実装は影響範囲を見てから。
- 該当：`domain/unit/unit.gd`（`skin_id`）・`domain/battle_state.gd`（シリアライズ列）・`application/stage_loader.gd`（skin 解決）・`presentation/`（skin の持ち場所）。参考＝refactoring-2 の案P。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
