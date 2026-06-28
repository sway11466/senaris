extends RefCounted
class_name SkinCatalog
## スキン表(JSON) → { type_id: { "ally": [UnitSkin], "enemy": [UnitSkin] } }。
## 純ロジック・テスト対象。詳細 → doc/gdd/units.md
##
## スキンは性能(UnitType)とは別ファイル(data/units/unit_skin.json)で持つ＝名前/画像の上書きレイヤー。
## テーマを増やす＝スキン表を足すだけ（原型の性能には触らない）。
## ※将来テーマが増えたら data/units/unit_skin/<テーマ>.json のように割ってもよい。

const UNIT_SKIN_PATH := "res://data/units/unit_skin.json"

## スキン表辞書（{ "skins": { type_id: { ally:[...], enemy:[...] } } }）を組み立てる。
static func build(data: Dictionary) -> Dictionary:
	var out := {}
	var skins: Variant = data.get("skins", {})
	if typeof(skins) != TYPE_DICTIONARY:
		return out
	for type_id in skins:
		var sides: Dictionary = skins[type_id]
		out[type_id] = {
			"ally": _to_skins(sides.get("ally", [])),
			"enemy": _to_skins(sides.get("enemy", [])),
		}
	return out

static func _to_skins(arr: Variant) -> Array:
	var list := []
	if typeof(arr) == TYPE_ARRAY:
		for d in arr:
			list.append(UnitSkin.from_dict(d))
	return list

## res:// パスの JSON を読み込んで組み立てる。失敗時は空。
static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SkinCatalog: 読み込めない/空: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SkinCatalog: JSON が不正: %s" % path)
		return {}
	return build(data)

## 既定のスキン表（unit_skin.json）。
static func load_standard() -> Dictionary:
	return load_file(UNIT_SKIN_PATH)

## type_id・陣営(0=味方/1=敵)・index からスキンを引く。無ければ null。
## 範囲外 index は先頭にフォールバック。
static func skin(catalog: Dictionary, type_id: String, team: int, index: int = 0) -> UnitSkin:
	if not catalog.has(type_id):
		return null
	var side := "ally" if team == 0 else "enemy"
	var list: Array = catalog[type_id].get(side, [])
	if list.is_empty():
		return null
	if index < 0 or index >= list.size():
		index = 0
	return list[index]
