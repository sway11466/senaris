extends SceneTree
## 使い捨て：敵ターンのカメラ追従の実測（doc/gdd/uiux.md 敵ターンのカメラ）。
## 広い盤で移動力の大きい敵（グリフォン・charge）を突っ込ませ、ズームした画角で敵ターンを回す。
## - 歩いている間、駒の画面座標が安全域（可視域の内側 FOCUS_MARGIN）からどれだけはみ出したかを毎フレーム測る。
## - 攻撃の瞬間（unit_attacked）に攻撃側と相手の両方が可視域／安全域に入っているかを測る。
## 起動: godot --path . -s res://tests/manual/check_camera_follow.gd
## 出力: res://tests/manual/out/camera_follow.txt

const STAGE := "res://tests/manual/stage_camera_follow.json"
const RUNS := [  # [注視距離（ズーム）, 敵ターン数]
	[12.0, 3],
	[BoardCamera.MIN_DIST, 3],
]
const OUT_DIR := "res://tests/manual/out"
const TOL := 1.0  # 縁の判定の許容(px)

var _main: Node = null
var _board: Node3D = null
var _frame := 0
var _phase := 0
var _at := 15
var _run := -1
var _enemy := false
var _enemy_turns := 0
var _lines: Array[String] = []

# 1回の敵ターンぶんの集計
var _move_frames := 0        # 駒が歩いていたフレーム数
var _out_frames := 0         # うち安全域からはみ出していたフレーム数
var _max_overflow := 0.0     # はみ出しの最大(px)
var _offscreen_frames := 0   # 可視域そのものから出ていたフレーム数
var _cam_moves := 0          # 注視点が動いたフレーム数
var _last_target := Vector3.INF
var _walk_hexes := 0

func _initialize() -> void:
	SavePaths.dir = "user://check_camera_follow"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SavePaths.dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load("res://presentation/main/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	if _enemy and _board != null:
		_measure_frame()
	if _frame < _at:
		return false
	match _phase:
		0:
			if _main._title != null:
				_main._title.visible = false
			_main._select.visible = false
			_step(10)
		1:
			_run += 1
			if _run >= RUNS.size():
				_finish()
				return true
			_main._on_settings_combat_fx_chosen("off")   # 攻撃は盤で見せる＝相手が画面に要る
			_main._on_settings_board_fx_chosen("normal")
			_enemy_turns = 0
			_main._on_stage_chosen("debug-ai", "stage_camera_follow", STAGE)
			_board = _main.get_node("HexBoard")
			_main._controller.turn_changed.connect(_on_turn_changed)
			_main._controller.unit_moved.connect(_on_unit_moved)
			_main._controller.unit_attacked.connect(_on_unit_attacked)
			_step(40)
		2:
			if _main._conversation != null and _main._conversation.visible:
				_main._conversation._on_skip()
				_at = _frame + 15
				return false
			# プレイヤーの駒のあたりへズーム＝敵は画面の外から来る
			var cam: BoardCamera = _board._board_cam
			cam.dist = float(RUNS[_run][0])
			cam.target = _board._hex_world(Hex.offset_to_axial(2, 3))
			cam.update_rig()
			_lines.append("run=%d dist=%.1f vis=%s safe=%s" % [_run, cam.dist, str(_board._vis_rect()), str(_safe())])
			_reset_counters()
			_main._on_end_turn_requested()
			_phase = 3
			_at = _frame + 1
		3:
			pass
		4:
			if _enemy_turns >= int(RUNS[_run][1]) or _main._controller.state.is_over():
				_phase = 1
				_at = _frame + 10
			else:
				_phase = 2
				_at = _frame + 10
	return false

func _safe() -> Rect2:
	return _board._vis_rect().grow(-BoardCamera.FOCUS_MARGIN)

func _reset_counters() -> void:
	_move_frames = 0
	_out_frames = 0
	_max_overflow = 0.0
	_offscreen_frames = 0
	_cam_moves = 0
	_walk_hexes = 0
	_last_target = Vector3.INF

## はみ出し量(px)。矩形の内側なら 0。
func _overflow(sp: Vector2, r: Rect2) -> float:
	var o := 0.0
	o = maxf(o, r.position.x - sp.x)
	o = maxf(o, sp.x - r.end.x)
	o = maxf(o, r.position.y - sp.y)
	o = maxf(o, sp.y - r.end.y)
	return o

func _measure_frame() -> void:
	var cam: BoardCamera = _board._board_cam
	if _last_target.is_finite() and not cam.target.is_equal_approx(_last_target):
		_cam_moves += 1
	_last_target = cam.target
	var node: Node3D = _board._move_node
	if node == null or not is_instance_valid(node):
		return
	_move_frames += 1
	var sp := cam.camera.unproject_position(node.position)
	var o := _overflow(sp, _safe())
	if o > TOL:
		_out_frames += 1
	_max_overflow = maxf(_max_overflow, o)
	if _overflow(sp, _board._vis_rect()) > TOL:
		_offscreen_frames += 1

func _on_unit_moved(_handle: int, _from: Vector2i, _to: Vector2i, path: Array[Vector2i]) -> void:
	if _enemy:
		_walk_hexes += maxi(path.size() - 1, 0)

func _on_unit_attacked(attacker_id: int, target_id: int, _damage: int, _killed: bool) -> void:
	if not _enemy:
		return
	var cam: BoardCamera = _board._board_cam
	var a: Unit = _main._controller.state.unit_by_handle(attacker_id)
	var t: Unit = _main._controller.state.unit_by_handle(target_id)
	if a == null or t == null:
		return
	var sa := cam.camera.unproject_position(_board._hex_world(a.pos))
	var st := cam.camera.unproject_position(_board._hex_world(t.pos))
	_lines.append("  attack turn=%d attacker=%s in_vis=%s in_safe=%s target=%s in_vis=%s in_safe=%s dist_hex=%d" % [
		_enemy_turns + 1, str(sa), _overflow(sa, _board._vis_rect()) <= TOL, _overflow(sa, _safe()) <= TOL,
		str(st), _overflow(st, _board._vis_rect()) <= TOL, _overflow(st, _safe()) <= TOL,
		Hex.distance(a.pos, t.pos)])

func _on_turn_changed(team: int, _turn_number: int) -> void:
	if team != 0:
		_enemy = true
		_reset_counters()
		return
	if _enemy:
		_enemy = false
		_enemy_turns += 1
		_lines.append("  turn=%d walk_hexes=%d move_frames=%d out_of_safe_frames=%d max_overflow=%.1fpx offscreen_frames=%d cam_moved_frames=%d" % [
			_enemy_turns, _walk_hexes, _move_frames, _out_frames, _max_overflow, _offscreen_frames, _cam_moves])
		_phase = 4
		_at = _frame + 5

func _step(frames: int) -> void:
	_phase += 1
	_at = _frame + frames

func _finish() -> void:
	var f := FileAccess.open("%s/camera_follow.txt" % OUT_DIR, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
