# バックログ

未完了の作業（バグ・機能追加・リファクタリング）を追跡する統合リスト。

## index

次回採番: bug=1 / feature=3 / refactoring=3

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

### refactoring-2

**地形も性能と見た目を分離（terrain_type / terrain_skin）**（優先度：中）

- 背景：ユニットは性能(`UnitType`)と見た目(`UnitSkin`)を分離済み（[units.md](gdd/units.md) §1・skin_id 方式）。地形は今 `data/terrain/terrain.csv` 1枚に性能(char・atk・def・移動コスト連携)と見た目(name・image)が同居。同じ性能に別の見た目を貼りたい（例：平地→草地/砂地/雪原、洞窟の床）・冒険譚やテーマで地形をリスキンしたい（[architecture.md](tech/architecture.md) の Data「地形・テーマ」）需要があり、分離したい。
- 対応：`terrain_type.csv`（性能＝id・char・atk・def・通過/占領可否・移動タイプ連携）と `terrain_skin.csv`（見た目＝skin_id・terrain_type・表示名・画像ベース・テーマ・変種）に分割。ステージの地形grid は char→terrain_type、見た目はテーマ/campaign で解決（`SkinCatalog` 相当の TerrainSkinCatalog）。ユニットの skin_id 方式・画像 autowire・`convert.gd`(CSV→JSON) を踏襲。タイルの変種/回転/反転の敷き分けは既に `hex_board` にあるので、skin 側が変種パスを持てば乗る。
- 該当：`data/terrain/terrain.csv`（→分割）・`data/terrain/terrain.gd`・`data/terrain/convert.gd`・`presentation/board/hex_board.gd`（`_load_terrain_variants` の解決を skin 経由へ）・`assets/terrain/`。参考モデル＝[units.md](gdd/units.md) §1。着手の注意＝terrain.csv/convert は他作業と競合しやすいので、進行中の CSV 系リファクタ完了後に着手する。

## parking lot

後回し・いつかやる候補の置き場（特定の作業に紐付かない将来アイデア）。着手が決まった段で機能追加・リファクタリングへ引き上げる。

- Steam 配布の段取り（費用・スケジュール）：まず Steam（PC）で出す。**Steam Direct** $100/タイトル（売上 $1,000 で返金）・ストアページは公開の 2 週間以上前から表示可・登録〜審査〜公開で約 30 日。**GodotSteam** アドオンは必要になった段階で導入。配布費用・税・所有権チェックの設計は [monetization.md](sales/monetization.md) が正本。着手は配布できるビルドが見えてきたら逆算して。
