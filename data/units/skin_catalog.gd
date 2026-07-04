extends RefCounted
class_name SkinCatalog
## スキン表(JSON) → { type_id: { "ally": [UnitSkin], "enemy": [UnitSkin] } }。
## 純ロジック・テスト対象。詳細 → doc/gdd/units.md
##
## スキンは性能(UnitType)とは別ファイル(data/units/unit_skin.json)で持つ＝名前/画像の上書きレイヤー。
## テーマを増やす＝スキン表を足すだけ（原型の性能には触らない）。
## ※将来テーマが増えたら data/units/unit_skin/<テーマ>.json のように割ってもよい。

const UNIT_SKIN_PATH := "res://data/units/unit_skin.json"
const BY_ID_KEY := "__by_id__"  ## skin_id 索引を入れる予約キー（type_id とは衝突しない）

## スキン表辞書（{ "skins": { type_id: { ally:[...], enemy:[...] } } }）を組み立てる。
## 併せて skin_id → UnitSkin の索引を BY_ID_KEY に格納する（ステージは skin_id で見た目を引く）。
static func build(data: Dictionary) -> Dictionary:
	var out := {}
	var by_id := {}
	var skins: Variant = data.get("skins", {})
	if typeof(skins) != TYPE_DICTIONARY:
		out[BY_ID_KEY] = by_id
		return out
	for type_id in skins:
		var sides: Dictionary = skins[type_id]
		var ally := _to_skins(sides.get("ally", []))
		var enemy := _to_skins(sides.get("enemy", []))
		out[type_id] = { "ally": ally, "enemy": enemy }
		for s in ally:
			if s.skin_id != "":
				by_id[s.skin_id] = s
		for s in enemy:
			if s.skin_id != "":
				by_id[s.skin_id] = s
	out[BY_ID_KEY] = by_id
	return out

static func _to_skins(arr: Variant) -> Array:
	var list := []
	if typeof(arr) == TYPE_ARRAY:
		for d in arr:
			var s := UnitSkin.from_dict(d)
			_autowire_images(s)
			list.append(s)
	return list

## 画像を規約で自動解決：assets/units/{skin_id}/{skin_id}_map.png があれば images.map に入れる。
## JSON に明示 images があればそちらを優先。アートを置くだけで盤がプレースホルダ→画像に切り替わる。
static func _autowire_images(s: UnitSkin) -> void:
	if s.skin_id == "":
		return
	if not s.images.has("map"):
		var p := "res://assets/units/%s/%s_map.png" % [s.skin_id, s.skin_id]
		if ResourceLoader.exists(p):
			s.images["map"] = p

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

## skin_id からスキンを引く（主キー解決）。無ければ null。
static func skin_by_id(catalog: Dictionary, skin_id: String) -> UnitSkin:
	var by_id: Dictionary = catalog.get(BY_ID_KEY, {})
	return by_id.get(skin_id, null)

## skin_id に紐づく性能(UnitType)の type_id。無ければ ""。
static func type_of_skin(catalog: Dictionary, skin_id: String) -> String:
	var s := skin_by_id(catalog, skin_id)
	return s.type_id if s != null else ""

## ユニットの見た目を解決：skin_id を優先（あれば）、無ければ type_id+team の既定スキンへフォールバック。
static func resolve(catalog: Dictionary, skin_id: String, type_id: String, team: int) -> UnitSkin:
	if skin_id != "":
		var s := skin_by_id(catalog, skin_id)
		if s != null:
			return s
	return skin(catalog, type_id, team)
