extends SceneTree
## 【使い捨て】画像確認ツール地形モードで plateau を敷き詰めた見え方を確認。
## 実行: godot --path . -s res://tests/manual/shot_image_check.gd （headless 不可）

const DIR := "user://shot_imgcheck/"
var _t: Control
var _frames := 0

func _initialize() -> void:
	root.size = Vector2i(1200, 760)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_t = preload("res://tools/image_check/image_check.gd").new()
	root.add_child(_t)
	_t.set_anchors_preset(Control.PRESET_FULL_RECT)

func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + name)
	print("shot: saved ", ProjectSettings.globalize_path(DIR + name))

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			_t.call("_show_terrain")
			_t.set("_terr_pattern", "fill")
			_t.set("_ta", "plateau")
			_t.call("_rebuild_terrain")
		45:
			_save("terrain_plateau_fill.png")
			return true
	return false
