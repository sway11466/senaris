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
