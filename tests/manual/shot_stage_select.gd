extends SceneTree
## 【使い捨て】分割後のセレクト2画面を各1枚PNGに撮る（見た目確認用）。
## 実行: godot --path . -s res://tests/manual/shot_stage_select.gd

var _frames := 0
var _main: Node = null

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _find(node: Node, klass: String) -> Node:
	for c in node.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == klass:
			return c
		var hit := _find(c, klass)
		if hit != null:
			return hit
	return null

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		root.get_texture().get_image().save_png("user://shot_campaigns.png")
		print("saved campaigns view")
		_find(_main, "SelectScreen")._on_campaign_chosen("tutorial1-goblin-raid")
	if _frames == 50:
		root.get_texture().get_image().save_png("user://shot_stages.png")
		print("saved stages view")
	if _frames == 60:
		print("done")
		return true
	return false
