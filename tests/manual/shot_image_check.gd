extends SceneTree
## 【使い捨て】画像確認ツール（キャラモード）を実描画してスクショ確認。
## 実行: godot --path . -s res://tests/manual/shot_image_check.gd （headless 不可）

const OUT := "user://shot_imgcheck/character.png"
var _t: Control
var _frames := 0

func _initialize() -> void:
	root.size = Vector2i(1000, 760)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shot_imgcheck/"))
	_t = preload("res://tools/image_check/image_check.gd").new()
	root.add_child(_t)
	_t.set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var img := root.get_texture().get_image()
		img.save_png(OUT)
		print("shot: saved ", ProjectSettings.globalize_path(OUT))
		return true
	return false
