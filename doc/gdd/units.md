# ユニット

ユニットの性能設計・陣営方針と、具体ステータス（対応表）。

---

## 性能設計方針

- 性能的な特性（移動力・攻撃／防御傾向・地形適性・経験値による成長など）はネクタリスを下敷きにする
- **性能にラベルを貼る**：チューニング済みの性能（ステータス・役割）が実体。そこへ名前・見た目（ラベル）を貼って、世界観に合うユニットを提供する。同じ性能に味方／敵・テーマ別の別ラベルを貼れる。**敵スキンは冒険譚ごとに必要なぶんだけ用意する**（全味方ぶんのミラーは作らない＝出てくる部隊にふさわしい名前を都度置く）。

---

## ユニット一覧

ユニットの性能・別名は **CSV正本** で管理（表はここに持たない）。

- 性能（ステータス・移動・射程など）: [`data/units/unit_type.csv`](../../data/units/unit_type.csv)
- 陣営別の名前（味方／敵の別ラベル）: [`data/units/unit_skin.csv`](../../data/units/unit_skin.csv)

生成・運用は下記「データ構成」を参照。

---

## データ構成（実装）

### 1. 性能と見た目の分離

- **性能 ＝ `UnitType`**（`data/units/unit_type.gd`）＝ステータスのみ。名前も画像も持たない。
- **見た目＋識別 ＝ `UnitSkin`**（`data/units/unit_skin.gd`）＝名前・説明・画像。1性能に複数ぶら下がる（陣営別・テーマ別の別名）。
- **同性能・別名**（プリースト↔ホブゴブリン↔スケルトン）は、その性能の `enemy`/`ally` 配列にスキンを並べるだけ。**どのスキンを使うかは冒険譚（ステージ）側が決める**＝ユニットデータは冒険譚/テーマ名を持たない（責務分離）。
- **`skin_id` が主キー**：各スキンは一意な `skin_id` を持ち、`skin_id → type` は1:1（スキンが決まれば性能も一意）。引きは `SkinCatalog.skin_by_id(catalog, skin_id)`／`type_of_skin(catalog, skin_id)`、描画は `resolve(catalog, skin_id, type_id, team)`（skin_id 優先・無ければ type_id+team の先頭へフォールバック）。従来の `skin(catalog, type_id, team, index)` も残置。

### 2. ファイル・フォルダ配置

- ユニットの型・データ・ローダーは `data/units/` に同居（機能フォルダ）。型とデータをセットで扱う。
- `UnitType`: 種別表 `data/units/unit_type.json`（テーマ非依存の原型ロスター）。`UnitCatalog`（`data/units/unit_catalog.gd`）が `id → UnitType`。
- `UnitSkin`: スキン表 `data/units/unit_skin.json`（性能とは別ファイル＝上書きレイヤー）。`SkinCatalog`（`data/units/skin_catalog.gd`）が `type_id → {ally:[UnitSkin], enemy:[UnitSkin]}` ＋ `skin_id → UnitSkin` 索引を持つ。テーマが増えたら `data/units/unit_skin/<テーマ>.json` に割ってよい。
- 画像スロットと未用意時のプレースホルダはアート準備で扱う。

### 3. CSV正本パイプライン

- **正本はCSV**（表計算で管理）: フラット/グリッドな表は CSV が正本（人間が表計算/VSCodeで編集）。CSV正本・生成JSON・変換ツールは機能フォルダに同居（`data/units/` にまるっと）。
- `data/units/convert.gd`（headless）が **CSV → コード用JSON** を生成。実行: `godot --headless --script res://data/units/convert.gd`
- **CSVは2行ヘッダ**: 1行目=英語キー（コードが使う）／2行目=日本語ラベル（人間用・変換時は読み飛ばす）／3行目以降=データ。参考用の列（兵種・備考など）を足してもよい（コードは未知キーを無視）。
- `data/units/unit_type.csv` → `data/units/unit_type.json`（**生成物・手で触らない**）。
- `data/units/unit_skin.csv`（1行=1スキン: **`skin_id, name, side, type_id, category`**。`skin_id` が主キー／`category`＝管理分類: 基準・ゴブリン・アンデッド・デモ、この順に整列。コード未使用の参考列）→ `data/units/unit_skin.json`。画像・説明は当面空で、必要時にCSVへ列追加。
- `data/movement/movement.csv` → `data/movement/movement.json`（移動タイプ×地形コスト表）。
- 表計算向き＝**ユニット性能・エイリアス・移動タイプ**の3表（1行=1レコードのフラット表）。ステージ(json) は手書きのまま。

### 4. ステージからの参照

- **ステージは見た目を `skin` で指定**: `{ "skin": "goblin", "team": 1, "col": 5, "row": 3 }`。`skin_id → type` は1:1なので、**性能(type)は自動で逆引き**される（`level`/`troops` 等は任意で上書き）。
- **`type` 指定の後方互換**: `{ "type": "cleric", ... }` と書くと、**`skin_id == type_id` の同名スキン**（＝正規スキン。多くは味方ラベル）が選ばれる。テーマ別の敵などは `skin` で明示する（例: ゴブリンは `skin:"goblin"`）。
- `StageLoader` が `SkinCatalog`（skin→type 逆引き）＋ `UnitCatalog`（type→性能）で解決し、`Unit.skin_id`/`Unit.type_id` に保持（描画でスキンを引く／占領＝寝返りに使う）。

### 5. 現状と将来

- ロスター/スキンは対応表の全27種を CSV正本に用意済み。画像・説明は当面空（プレースホルダ）で順次。
- `attack_range`(>1=間接)・`move_type`・`atk_air`(対地/対空) は実装済み。攻撃側は相手が飛行なら `atk_air`、地上なら `atk_ground` を使い、`atk_air=0` の駒は飛行を攻撃・反撃できない。防御は単一値（`defense`）。
- 【将来】移動タイプ＝地形移動コスト・地形適性（例: 森を低コストで抜ける）はマップの地形テーブルとセットで別途設計。
- 【将来】アーキ本筋の「原本＝スプレッドシート→CSV→.tres」量産パイプライン。当面は JSON で回す。

---

## 関連ドキュメント

- 戦闘解決（補正チェーン・陣形）: [combat.md](combat.md)
- 占領・拠点運用・テーマ別リスキン: [map.md](map.md)
- 移動タイプ・地形コスト: [movement.md](movement.md)
- アート準備（画像スロット・プレースホルダ）: [../art/overview.md](../art/overview.md)
- アーキテクチャ（量産パイプライン）: [../tech/architecture.md](../tech/architecture.md)
