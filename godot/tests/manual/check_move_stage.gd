extends SceneTree
## 使い捨て検証: debug-map/move.json が読め、全マス（外周込み）の地形スキンが引けることを確かめる。
## 実行: godot --headless --path . -s res://tests/manual/check_move_stage.gd → tests/manual/out/move_check.txt

const STAGE := "res://data/stages/debug-map/move.json"
const OUT := "res://tests/manual/out/move_check.txt"

func _init() -> void:
	var lines: PackedStringArray = []
	var state := StageLoader.load_file(STAGE)
	if state == null:
		lines.append("FAIL: load_file returned null")
	else:
		lines.append("board %dx%d units=%d" % [state.cols, state.rows, state.units().size()])
		for u in state.units():
			var o := Hex.axial_to_offset(u.pos)
			lines.append("  unit team=%d type=%s skin=%s at (%d,%d) move_type=%s" % [u.team, u.type_id, u.skin_id, o.x, o.y, u.move_type])
		var skins := StageLoader.load_terrain_skins(STAGE)
		var margin_terrain := StageLoader.parse_margin_terrain(JSON.parse_string(FileAccess.get_file_as_string(STAGE)))
		var bad := 0
		var counted := {}
		for r in range(-1, state.rows + 1):
			for c in range(-1, state.cols + 1):
				var hex := Hex.offset_to_axial(c, r)
				var type_id: String = margin_terrain.get(hex, "") if (c < 0 or r < 0 or c >= state.cols or r >= state.rows) else state.terrain_at(hex)
				var skin_id: String = String(skins.get(hex, ""))
				var s = TerrainSkinCatalog.resolve(skin_id, type_id)
				var key := "%s/%s" % [type_id, skin_id if skin_id != "" else "(default)"]
				counted[key] = int(counted.get(key, 0)) + 1
				if s == null:
					bad += 1
					lines.append("  NO SKIN at (%d,%d) type=%s skin=%s" % [c, r, type_id, skin_id])
		for k in counted.keys():
			lines.append("  %s x%d" % [k, counted[k]])
		lines.append("unresolved skins: %d" % bad)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	quit(0)
