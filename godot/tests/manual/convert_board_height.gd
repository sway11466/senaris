extends SceneTree
## 使い捨て変換: ステージの行・列の基準高さ（height）を、マスごとの高さ上書きに書き換える。
## 基準が0でないマスに「今の見た目と同じ高さ」（基準＋スキンの elevation / floor）を上書きとして書き、
## height キーを消す。既に上書きのあるマスは触らない。
## 書き換え後、旧式（基準＋スキン）と新式（上書き or スキン）が全マスで一致することを検算する。
## 実行: godot --headless --path . -s res://tests/manual/convert_board_height.gd
## 結果: tests/manual/out/convert_board_height.txt

const PATHS := [
	"res://data/stages/tutorial1-goblin-raid/st2.json",
	"res://data/stages/tutorial1-goblin-raid/st5.json",
	"res://data/stages/debug-skins/height.json",
]
const OUT := "res://tests/manual/out/convert_board_height.txt"


func _init() -> void:
	var lines: PackedStringArray = []
	for path: String in PATHS:
		_convert(path, lines)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()


static func _axis(arr: Array, i: int) -> float:
	return 0.0 if arr.is_empty() else float(arr[i])


func _convert(path: String, lines: PackedStringArray) -> void:
	lines.append("== " + path)
	var text := FileAccess.get_file_as_string(path)
	var doc := MapEditorDoc.from_text(text)
	if doc == null:
		lines.append("FAIL: from_text returned null")
		return
	var raw: Dictionary = JSON.parse_string(text)
	var h: Dictionary = raw.get("height", {}) if typeof(raw.get("height")) == TYPE_DICTIONARY else {}
	var rows_h: Array = h.get("row", []) if typeof(h.get("row")) == TYPE_ARRAY else []
	var cols_h: Array = h.get("col", []) if typeof(h.get("col")) == TYPE_ARRAY else []
	# 旧式の高さを全マスぶん先に控える（検算用）
	var old := {}
	for row in doc.rows():
		for col in doc.cols():
			var pair := _old_height(doc, col, row, _axis(rows_h, row) + _axis(cols_h, col))
			if pair.is_empty():
				lines.append("FAIL: skin unresolved at %d,%d" % [col, row])
				return
			old[Vector2i(col, row)] = pair
	var converted := 0
	var kept := 0
	for row in doc.rows():
		for col in doc.cols():
			var base := _axis(rows_h, row) + _axis(cols_h, col)
			if base == 0.0:
				continue
			var skin := _skin(doc, col, row)
			if not doc.height_override(col, row).is_empty():
				kept += 1
				continue
			doc.set_terrain_skin(col, row, skin.skin_id,
				{ "elevation": skin.elevation + base, "floor": skin.floor + base })
			converted += 1
	doc.data.erase("height")
	doc._keys_in_source.erase("height")
	var out_text := doc.to_text()
	# 検算：書き出したテキストを読み直し、新式の高さが旧式と全マスで一致するか
	var doc2 := MapEditorDoc.from_text(out_text)
	var mismatch := 0
	for row in doc2.rows():
		for col in doc2.cols():
			var skin := _skin(doc2, col, row)
			var ov := doc2.height_override(col, row)
			var e: float = float(ov["elevation"]) if not ov.is_empty() else skin.elevation
			var fl: float = float(ov["floor"]) if not ov.is_empty() else skin.floor
			var o: Array = old[Vector2i(col, row)]
			if not is_equal_approx(e, o[0]) or not is_equal_approx(fl, o[1]):
				mismatch += 1
				lines.append("  MISMATCH %d,%d old=%s/%s new=%s/%s" % [col, row, o[0], o[1], e, fl])
	lines.append("converted=%d kept=%d mismatch=%d has_height_key=%s"
		% [converted, kept, mismatch, str(JSON.parse_string(out_text).has("height"))])
	if mismatch == 0:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(out_text)
		f.close()
		lines.append("written")


static func _skin(doc: MapEditorDoc, col: int, row: int) -> TerrainSkin:
	var type_id := TerrainType.char_to_id(doc.terrain_char(col, row))
	return TerrainSkinCatalog.resolve(doc.terrain_skin(col, row), type_id)


## 旧式（board_terrain_renderer._skin_height と同じ規則）の [elevation, floor]。
static func _old_height(doc: MapEditorDoc, col: int, row: int, base: float) -> Array:
	var skin := _skin(doc, col, row)
	if skin == null:
		return []
	var ov := doc.height_override(col, row)
	if not ov.is_empty():
		return [float(ov["elevation"]), float(ov["floor"])]
	return [skin.elevation + base, skin.floor + base]
