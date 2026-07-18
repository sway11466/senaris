extends SceneTree
## 【使い捨て】AI手番が移動アニメの完了を待っても固まらないこと（move_pace の await が必ず返る）。
## 期待: 手番終了 → 敵AIが動く → 自軍へ手番が返り、ターンが 2 に進む。
## 実行: godot --path . -s res://tests/manual/repro_ai_turn_pace.gd

var _frames := 0
var _main: Node = null
var _ctrl = null

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_main._select.close()
		_main.load_stage("res://data/stages/debug-ai/sight.json")
	if _frames == 20:
		_ctrl = _main.get_node("HexBoard").controller
		print("move_pace 注入済み: ", _ctrl.move_pace.is_valid())
		_ctrl.end_turn()  # 自軍→敵軍。AIが動き終えたら自軍へ返るはず
	if _frames == 400:  # 十分待つ（アニメ最長0.6s＋間0.35s × 手数）
		var st = _ctrl.state
		print("結果: current_team=%d turn_number=%d" % [st.current_team, st.turn_number])
		if st.current_team == 0 and st.turn_number == 2:
			print("OK: AI手番が完了して自軍へ返った（固まらない）")
		else:
			print("NG: AI手番が返っていない＝待ちで固まった疑い")
		return true
	return false
