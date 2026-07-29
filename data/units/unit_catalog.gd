extends RefCounted
class_name UnitCatalog
## ロスター表(JSON) → { id: UnitType } の組み立て（純ロジック・テスト対象）。
## 詳細 → doc/gdd/units.md
##
## ステータスはテーマ非依存（標準ロスター＝テーマ0が唯一の出どころ）。
## テーマはユニットの「名前」だけを切り替える（UnitType.names）。

const UNIT_TYPE_PATH := "res://data/units/unit_type.json"

## ロスター辞書（{ "types": [ {...}, ... ] }）から { id: UnitType } を作る。
static func build(data: Dictionary) -> Dictionary:
	var out := {}
	var types: Variant = data.get("types", [])
	if typeof(types) != TYPE_ARRAY:
		return out
	for d in types:
		var t := UnitType.from_dict(d)
		if t.id == "":
			push_warning("UnitCatalog: id 無しの種別をスキップ")
			continue
		out[t.id] = t
	return out

## res:// パスの JSON を読み込んで { id: UnitType } を返す。失敗時は空。
static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("UnitCatalog: 読み込めない/空: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("UnitCatalog: JSON が不正: %s" % path)
		return {}
	return build(data)

## 既定のユニット種別表（unit_type.json）を読み込む。テーマ非依存の原型ロスター。
static func load_default() -> Dictionary:
	return load_file(UNIT_TYPE_PATH)

static var _categories := {}      # type_id -> 兵種名（unit_type.csv の category 列）
static var _categories_loaded := false

## 種別IDの兵種名（歩兵・弓兵・占領兵…）。表示専用＝ゲームロジックから参照しない。
## 不明id・空欄は ""。ロスター本体とは別に遅延ロードする（Movement.display_name と同じ流儀）。
static func display_category(type_id: String) -> String:
	if not _categories_loaded:
		_categories_loaded = true
		var text := FileAccess.get_file_as_string(UNIT_TYPE_PATH)
		if not text.is_empty():
			var data: Variant = JSON.parse_string(text)
			if typeof(data) == TYPE_DICTIONARY:
				_categories = build_categories(data)
	return String(_categories.get(type_id, ""))

## ロスター辞書 → { id: 兵種名 }。category 列が無い/空の種別は落とす。純関数＝IOなし。
static func build_categories(data: Dictionary) -> Dictionary:
	var out := {}
	var types: Variant = data.get("types", [])
	if typeof(types) != TYPE_ARRAY:
		return out
	for d in types:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var id := String(d.get("id", ""))
		var cat := String(d.get("category", ""))
		if id != "" and cat != "":
			out[id] = cat
	return out
