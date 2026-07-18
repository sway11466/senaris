extends SceneTree
## 【使い捨て】VictoryScreen に tutorial1 の勝利イラストを出して実描画をスクショ確認。
## 実行: godot --path . -s res://tests/manual/shot_victory_screen.gd （headless 不可）

const OUT := "user://shot_victory/screen.png"
var _vs: VictoryScreen
var _frames := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://shot_victory/"))
	_vs = VictoryScreen.new()
	root.add_child(_vs)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_vs.play("res://assets/campaign/tutorial1-goblin-raid/tutorial1-goblin-raid_victory.png")
	if _frames == 40:  # フェードイン(0.4s)完了後に撮る
		var img := root.get_texture().get_image()
		img.save_png(OUT)
		print("shot: saved ", ProjectSettings.globalize_path(OUT), " visible=", _vs.visible)
		return true
	return false
