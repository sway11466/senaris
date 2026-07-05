extends RefCounted
class_name Movement
## 移動タイプ×地形コスト表（純データ＋コスト引き）。詳細 → doc/gdd/movement.md
##
## 表は { move_type: { 地形名: コスト } }。コストは進入コスト（その地形に入る歩数）。
## "x"（文字列）＝進入不可。表は完全表（差分なし）＝各移動タイプに全地形が並ぶ。

const MOVEMENT_PATH := "res://data/movement/movement.json"
const IMPASSABLE := -1  ## 進入不可（reachable はこれを通行不能として扱う）

static var _names := {}          # move_type -> 表示名（movement.csv の name 列）
static var _names_loaded := false

## 表辞書（{ "movement_types": {...} }）→ { move_type: {地形:コスト} }。
static func build(data: Dictionary) -> Dictionary:
	var types: Variant = data.get("movement_types", {})
	return types if typeof(types) == TYPE_DICTIONARY else {}

## 既定の移動表を読み込む。
static func load_default() -> Dictionary:
	var text := FileAccess.get_file_as_string(MOVEMENT_PATH)
	if text.is_empty():
		push_error("Movement: 読み込めない/空: %s" % MOVEMENT_PATH)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Movement: JSON が不正: %s" % MOVEMENT_PATH)
		return {}
	return build(data)

## move_type の表示名（movement.csv の name 列。不明idは id をそのまま返す）。
## コスト表とは別に movement.json の move_type_names から遅延ロードする（TerrainType と同じ流儀）。
static func display_name(move_type: String) -> String:
	_ensure_names()
	return String(_names.get(move_type, move_type))

static func _ensure_names() -> void:
	if _names_loaded:
		return
	_names_loaded = true
	var text := FileAccess.get_file_as_string(MOVEMENT_PATH)
	if text.is_empty():
		return
	var data: Variant = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		var n: Variant = data.get("move_type_names", {})
		if typeof(n) == TYPE_DICTIONARY:
			_names = n

## move_type が terrain_name に入る進入コスト。"x" は IMPASSABLE。
## 表に無い組み合わせは既定コスト1（表が空＝全地形1＝従来の一律移動と等価）。
static func cost(table: Dictionary, move_type: String, terrain_name: String) -> int:
	var costs: Dictionary = table.get(move_type, {})
	var c: Variant = costs.get(terrain_name, 1)
	if typeof(c) == TYPE_STRING:
		return IMPASSABLE
	return int(c)
