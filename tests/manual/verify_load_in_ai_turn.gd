extends SceneTree
## 使い捨て：敵ターンの最中にロードしても壊れないかを見る（doc/tech/gamesystem.md「いつでも操作できる」）。
## 旧 controller は _install_state が free する＝走っている AI のコルーチンが宙に浮かないかの確認。
## 実行: godot --path . -s res://tests/manual/verify_load_in_ai_turn.gd

const CAMPAIGN := "debug-ai"
const STAGE_ID := "weak"
const STAGE := "res://data/stages/debug-ai/weak.json"

var _main: Node
var _frames := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		20:
			_main._title.close()
			_main._select.close()
			for slot in SaveSlots.slot_ids():
				_main._saves.clear_slot(slot)
			_main._on_stage_chosen(CAMPAIGN, STAGE_ID, STAGE)
		35:
			if _main._conversation != null:
				_main._conversation._on_skip()
			_main._on_save_requested()
		40:
			_main._slot_panel._on_row_pressed("1", false)
			print("[準備] 枠1に保存 有=", _main._saves.has("1"))
			_main._controller.end_turn()  # 敵ターンへ
		55:
			print("[敵ターン中] 手番=", _main._controller.state.current_team,
				" ターン=", _main._controller.state.turn_number)
			_main._on_load_requested()
		60:
			_main._slot_panel._on_row_pressed("1", true)
		64:
			_main._slot_panel._on_confirm_yes()
		80:
			var state = _main._controller.state
			print("[ロード後] 手番=", state.current_team, " ターン=", state.turn_number,
				" 駒数=", state.units().size())
		110:
			var state = _main._controller.state
			print("[15フレーム後] 手番=", state.current_team, " ターン=", state.turn_number,
				" 駒数=", state.units().size(), " 決着=", _main._controller._finished)
			print("[確認] 旧AIが動き続けていなければ、手番0・ターン1のまま止まっているはず")
			return true
	return false
