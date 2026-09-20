extends SceneTree
## 使い捨て：出撃の1歩スライドの実測（feature-16）。debug-ai の突撃ステージで敵ターンを回し、
## unit_deployed ごとに駒ノードの position を毎フレーム記録する。拠点のマスから目的マスへ距離が
## 連続的に減れば OK。盤面の演出 normal と off の2回。敵の手の間隔（出撃→次の手）も msec で残す。
## 降車も同じ物差しで測る＝debug-ai の輸送ステージで敵の荷馬車が降ろすまで敵ターンを回す。
## 起動: godot --path . -s res://tests/manual/check_deploy_slide.gd
## 出力: res://tests/manual/out/deploy_slide.txt

const CHARGE := "res://data/stages/debug-ai/charge.json"
const TRANSPORT := "res://data/stages/debug-ai/transport.json"
const RUNS := [["charge", CHARGE, "normal", 1], ["charge", CHARGE, "off", 1], ["transport", TRANSPORT, "normal", 6]]  # [stage_id, path, board_fx, 敵ターン数]
const OUT_DIR := "res://tests/manual/out"

var _main: Node = null
var _board: Node = null
var _frame := 0
var _phase := 0
var _at := 15
var _run := -1
var _enemy := false
var _enemy_turns := 0
var _tracks: Array = []       # 記録中の出撃 {handle, base, to, since, samples: [[msec, d_to, d_base]]}
var _events: Array[String] = []
var _lines: Array[String] = []

func _initialize() -> void:
	SavePaths.dir = "user://check_deploy_slide"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SavePaths.dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load("res://presentation/main/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	_sample()
	if _frame < _at:
		return false
	match _phase:
		0:
			if _main._title != null:
				_main._title.visible = false
			_main._select.visible = false
			_board = _main.get_node("HexBoard")
			_step(10)
		1:
			_run += 1
			if _run >= RUNS.size():
				_finish()
				return true
			_main._on_settings_board_fx_chosen(String(RUNS[_run][2]))
			_main._on_stage_chosen("debug-ai", String(RUNS[_run][0]), String(RUNS[_run][1]))
			_enemy_turns = 0
			_main._controller.turn_changed.connect(_on_turn_changed)
			_main._controller.unit_deployed.connect(_on_deployed)
			_main._controller.unit_unloaded.connect(_on_unloaded)
			_main._controller.unit_moved.connect(func(id: int, _f: Vector2i, to: Vector2i, _p: Array) -> void:
				if _enemy:
					_events.append("%d moved id=%d to=%s" % [Time.get_ticks_msec(), id, str(to)]))
			_step(40)
		2:
			if _main._conversation != null and _main._conversation.visible:
				_main._conversation._on_skip()
				_at = _frame + 15
				return false
			_lines.append("== stage=%s board_fx=%s" % [RUNS[_run][0], RUNS[_run][2]])
			_main._on_end_turn_requested()
			_phase = 3
			_at = _frame + 1
		3:
			pass  # 敵ターン中＝turn_changed を待つ
		4:
			_flush()
			var done: bool = _enemy_turns >= int(RUNS[_run][3]) or _main._controller.state.is_over()
			_phase = 1 if done else 2
			_at = _frame + 10
	return false

func _on_turn_changed(team: int, _turn_number: int) -> void:
	if team != 0:
		_enemy = true
		return
	if _enemy:
		_enemy = false
		_enemy_turns += 1
		_phase = 4
		_at = _frame + 5

func _on_deployed(handle: int, base: Vector2i, to: Vector2i) -> void:
	_events.append("%d deployed id=%d base=%s to=%s" % [Time.get_ticks_msec(), handle, str(base), str(to)])
	_tracks.append({"handle": handle, "base": base, "to": to, "since": Time.get_ticks_msec(), "samples": []})

func _on_unloaded(handle: int, transport_id: int, to: Vector2i) -> void:
	var tr: Unit = _main._controller.state.unit_by_handle(transport_id)
	var from: Vector2i = tr.pos if tr != null else Vector2i(-99, -99)
	_events.append("%d unloaded id=%d transport=%d at=%s to=%s" % [Time.get_ticks_msec(), handle, transport_id, str(from), str(to)])
	_tracks.append({"handle": handle, "base": from, "to": to, "since": Time.get_ticks_msec(), "samples": []})

func _sample() -> void:
	if _board == null:
		return
	for tr in _tracks:
		var samples: Array = tr["samples"]
		if samples.size() >= 12:
			continue
		var node: Node3D = _board._unit_renderer.get_unit_node(int(tr["handle"]))
		if node == null:
			continue
		var wt: Vector3 = _board._hex_world(tr["to"])
		var wb: Vector3 = _board._hex_world(tr["base"])
		var running: bool = _board._move_tween != null and _board._move_tween.is_valid() and _board._move_tween.is_running()
		samples.append([Time.get_ticks_msec() - int(tr["since"]), node.position.distance_to(wt), node.position.distance_to(wb), int(running), int(node.visible)])

func _flush() -> void:
	for tr in _tracks:
		_lines.append("slide id=%d from=%s to=%s" % [tr["handle"], str(tr["base"]), str(tr["to"])])
		for s in tr["samples"]:
			_lines.append("  t=%4dms d_to=%.3f d_from=%.3f tween=%d visible=%d" % [s[0], s[1], s[2], s[3], s[4]])
	_lines.append("events:")
	for e in _events:
		_lines.append("  " + e)
	_tracks.clear()
	_events.clear()

func _step(frames: int) -> void:
	_phase += 1
	_at = _frame + frames

func _finish() -> void:
	var f := FileAccess.open("%s/deploy_slide.txt" % OUT_DIR, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
