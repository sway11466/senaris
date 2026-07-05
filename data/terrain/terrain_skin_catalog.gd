extends RefCounted
class_name TerrainSkinCatalog
## 地形スキン表(JSON) → skin_id 索引 ＋ type→既定スキン 索引。静的・遅延ロード（TerrainType と同じ流儀）。
## 詳細 → doc/gdd/units.md §1, doc/backlog.md refactoring-2（案P）
##
## スキンは性能(TerrainType)とは別ファイル(data/terrain/terrain_skin.json)で持つ＝見た目の上書きレイヤー。
## skin→type は1:1。各 type には既定スキン（skin_id == type の行、無ければ最初の行）が1枚ある。
## 見た目データなので presentation からのみ引く（domain は skin を知らない＝案P）。

const PATH := "res://data/terrain/terrain_skin.json"

static var _by_id := {}          # skin_id -> TerrainSkin
static var _default_by_type := {} # terrain_type -> TerrainSkin（既定スキン）
static var _loaded := false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_error("TerrainSkinCatalog: 読み込めない/空: %s" % PATH)
		return
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("TerrainSkinCatalog: JSON が不正: %s" % PATH)
		return
	for d in data.get("skins", []):
		var s := TerrainSkin.from_dict(d)
		if s.skin_id == "":
			continue
		_by_id[s.skin_id] = s
		# 既定スキン＝skin_id == terrain_type を優先。無ければ最初に現れた行を既定にする。
		if not _default_by_type.has(s.terrain_type) or s.skin_id == s.terrain_type:
			_default_by_type[s.terrain_type] = s

## skin_id からスキンを引く（主キー解決）。無ければ null。
static func skin_by_id(skin_id: String) -> TerrainSkin:
	_ensure()
	return _by_id.get(skin_id, null)

## 性能(terrain_type)の既定スキン。無ければ null。
static func for_type(type_id: String) -> TerrainSkin:
	_ensure()
	return _default_by_type.get(type_id, null)

## セルの見た目を解決：skin_id を優先（あれば）、無ければ terrain_type の既定スキンへフォールバック。
## ステージの terrain_skins に載らないセルは skin_id="" で来る＝type 既定になる（暫定フォールバック）。
static func resolve(skin_id: String, type_id: String) -> TerrainSkin:
	_ensure()
	if skin_id != "":
		var s: TerrainSkin = _by_id.get(skin_id, null)
		if s != null:
			return s
	return _default_by_type.get(type_id, null)

## 地形(type)の表示名（既定スキンの name。無い type は id をそのまま返す）。情報パネル用。
static func display_name(type_id: String) -> String:
	_ensure()
	var s: TerrainSkin = _default_by_type.get(type_id, null)
	return s.name if s != null else type_id
