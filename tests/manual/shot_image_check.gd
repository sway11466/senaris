extends SceneTree
## 【使い捨て】画像確認ツールを実描画してスクショ確認（キャラ／地形変種／地形境界）。
## 実行: godot --path . -s res://tests/manual/shot_image_check.gd （headless 不可）

const DIR := "user://shot_imgcheck/"
var _t: Control
var _frames := 0

func _initialize() -> void:
	root.size = Vector2i(1000, 760)
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
		20:
			_save("character.png")
			_t.call("_show_terrain")  # 既定=変種(variation)
		55:
			_save("terrain_variation.png")
			_t.call("_set_terr_sub", "boundary")
		90:
			_save("terrain_boundary.png")
			return true
	return false
