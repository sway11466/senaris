extends SceneTree
## 【使い捨て】移動アニメの確認。駒がマスを跨いで動いているか（瞬間移動していないか）を
## ユニットノードのワールド座標のサンプルで確かめ、途中の絵を1枚撮る。
## 期待: 移動先までの距離が毎フレーム減っていき、最後に 0 になる（瞬間移動なら最初から 0）。
## 実行: godot --path . -s res://tests/manual/repro_move_anim.gd

var _frames := 0
var _main: Node = null
var _board: Node3D = null
var _uid := -1
var _to_world := Vector3.ZERO
var _samples: Array[String] = []

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_main._select.close()
		_main.load_stage("res://data/stages/debug-ai/guard.json")
	if _frames == 20:
		_start_move()
	if _frames > 20 and _uid >= 0:
		var node: Node3D = _board._unit_nodes.get(_uid)
		if node != null:
			_samples.append("%.2f" % node.position.distance_to(_to_world))
	if _frames == 26:
		root.get_texture().get_image().save_png("user://shot_move_anim.png")
		print("saved mid-move frame")
	if _frames == 60:
		print("移動先までの残り距離（フレームごと）: ", " ".join(_samples))
		return true
	return false

## 自軍の駒を1体選び、届く範囲でいちばん遠いマスへ動かす。
func _start_move() -> void:
	_board = _main.get_node("HexBoard")
	var st = _board.state
	for u in st.units():
		if u.team == 0:
			_uid = u.id
			break
	var start: Vector2i = st.unit_by_id(_uid).pos
	var best := start
	for h in _board.controller.reachable_for(_uid):
		if Hex.distance(start, h) > Hex.distance(start, best):
			best = h
	_to_world = _board._hex_world(best)
	print("move unit %d: %s -> %s (%dマス)" % [_uid, start, best, Hex.distance(start, best)])
	print("経路: ", st.path_to(_uid, best))
	_board.controller.execute(MoveCommand.new(_uid, best))
