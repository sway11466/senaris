extends SceneTree
## 移動プレビュー（移動先クリックで駒が先に歩く／キャンセルで戻る／確定で歩き直さない）の実機検証（使い捨て）。
## 実行: godot --path . -s res://tests/manual/repro_move_preview.gd（--headless 不可）
## 結果: tests/manual/out/move_preview.txt（座標の推移）・move_preview.png（メニューが開いた瞬間）

const STAGE := "res://data/stages/debug-ai/standoff.json"
const ORIGIN := Vector2i(2, 3)  # fighter
const DEST := Vector2i(5, 3)
var _main: Node
var _board: Node
var _frame := 0
var _log: Array[String] = []
var _uid := -1
var _phase := 0

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _dist(to: Vector2i) -> float:
	var node: Node3D = _board._unit_renderer.get_unit_node(_uid)
	if node == null:
		return -1.0
	return node.position.distance_to(_board._hex_world(to))

func _state_pos() -> Vector2i:
	return _board.state.unit_by_id(_uid).pos

func _say(s: String) -> void:
	_log.append("[f%03d] %s" % [_frame, s])
	_flush()

func _flush() -> void:
	var f := FileAccess.open("res://tests/manual/out/move_preview.txt", FileAccess.WRITE)
	f.store_string("
".join(_log))
	f.close()

func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _frame < 10:
				return false
			_main._title.close()
			_main._select.close()
			_main.load_stage(STAGE)
			_board = _main.get_node("HexBoard")
			_uid = _board.state.unit_at(ORIGIN).id
			_say("stage loaded. uid=%d state=%s" % [_uid, _state_pos()])
			_phase = 1
		1:
			if _frame < 30:
				return false
			# A: 選択→移動先でメニュー。駒が歩き始めるはず。
			_board._select(_uid)
			_board._open_command_menu(DEST)
			_say("A open menu at %s. dist_to_dest=%.3f state=%s" % [DEST, _dist(DEST), _state_pos()])
			_phase = 2
		2:
			_say("A walking dist_to_dest=%.3f" % _dist(DEST))
			if _frame >= 30 + 45:
				root.get_texture().get_image().save_png("res://tests/manual/out/move_preview.png")
				_say("A arrived? dist_to_dest=%.3f state=%s (state must still be origin)" % [_dist(DEST), _state_pos()])
				# B: キャンセル → 元の位置へ瞬時に戻る
				_board._on_cancel(false)
				_phase = 3
		3:
			if _frame < 30 + 45 + 3:
				return false
			_say("B after cancel dist_to_origin=%.3f state=%s menu_visible=%s" % [_dist(ORIGIN), _state_pos(), _board._menu.visible])
			# C: もう一度開いて、歩き切ってから待機で確定 → 歩き直さない
			_board._select(_uid)
			_board._open_command_menu(DEST)
			_phase = 4
		4:
			if _frame < 30 + 45 + 3 + 45:
				return false
			_say("C arrived dist_to_dest=%.3f state=%s" % [_dist(DEST), _state_pos()])
			_board._on_menu_id(_board.MENU_WAIT)
			_say("C wait pressed. dist_to_dest=%.3f state=%s" % [_dist(DEST), _state_pos()])
			_phase = 5
		5:
			_say("C after commit dist_to_dest=%.3f (must stay 0, no re-walk)" % _dist(DEST))
			if _frame >= 30 + 45 + 3 + 45 + 6:
				# D: 別の駒（novice 2,4）で歩き途中にキャンセル
				var units_desc: Array[String] = []
				for u in _board.state.units():
					units_desc.append("%s@%s" % [u.type_id, u.pos])
				_say("units: " + ", ".join(units_desc))
				var nov = _board.state.unit_at(Vector2i(2, 2))
				if nov == null:
					_say("D skipped: no unit at (2,2)")
					_flush()
					quit()
					return true
				_uid = nov.id
				_board._select(_uid)
				_board._open_command_menu(Vector2i(5, 2))
				_phase = 6
		6:
			_say("D walking dist_to_origin=%.3f" % _dist(Vector2i(2, 2)))
			if _frame >= 30 + 45 + 3 + 45 + 6 + 8:
				_board._on_cancel(false)
				_phase = 7
		7:
			if _frame < 30 + 45 + 3 + 45 + 6 + 8 + 3:
				return false
			_say("D after mid-walk cancel dist_to_origin=%.3f state=%s" % [_dist(Vector2i(2, 2)), _state_pos()])
			var f := FileAccess.open("res://tests/manual/out/move_preview.txt", FileAccess.WRITE)
			f.store_string("\n".join(_log))
			f.close()
			quit()
			return true
	return false
