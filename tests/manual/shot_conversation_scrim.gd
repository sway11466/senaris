extends SceneTree
## 【使い捨て】会話シーンの暗幕（feature-17）を確認する。会話中に盤が沈み、会話パネルが
## 明るく残ること／会話終了で暗幕が消えることを撮る。
## 実行: godot --path . -s res://tests/manual/shot_conversation_scrim.gd

var _frames := 0
var _main: Node = null

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_main._select.close()
		_main.load_stage("res://data/stages/tutorial1-goblin-raid/st4.json")  # intro 会話あり
	if _frames == 40:
		# 会話中（intro）の絵＝暗幕が出て会話パネルが明るいはず
		var scrim = _main._scrim
		print("会話中: scrim.visible=%s modulate.a=%.2f" % [scrim.visible, scrim.modulate.a])
		root.get_texture().get_image().save_png("user://shot_scrim_on.png")
	if _frames == 50:
		# 会話をスキップ＝暗幕がフェードアウトし始める
		_main._conversation._on_skip()
	if _frames == 80:
		var scrim = _main._scrim
		print("会話後: scrim.visible=%s modulate.a=%.2f" % [scrim.visible, scrim.modulate.a])
		root.get_texture().get_image().save_png("user://shot_scrim_off.png")
		return true
	return false
