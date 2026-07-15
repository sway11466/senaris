extends SceneTree
## 【使い捨て】盤のユニット表示（立ち絵・影・兵数バー・ラベル）を1枚PNGに撮る。
## 「1体＝1親ノードに集約」の見た目回帰確認用（集約前後で絵が変わらないこと）。
## 実行: godot --path . -s res://tests/manual/shot_board_units.gd

var _frames := 0
var _main: Node = null

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_main._select.close()  # 起動時セレクトを閉じて盤を出す
		_main.load_stage("res://data/stages/debug-skins/units.json")
	if _frames == 40:
		root.get_texture().get_image().save_png("user://shot_board_units.png")
		print("saved board units view")
		return true
	return false
