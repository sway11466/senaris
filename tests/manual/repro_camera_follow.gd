extends SceneTree
## 【使い捨て】AI手番のカメラ追従を検証する。寄せた状態で敵手番を回し、各行動の前に
## focus_pace が来るのを横取りして「その主体が既に見えていたか／カメラが動いたか／
## パン後に見えるようになったか」を記録する。
## 期待:
##   - 既に安全域に見えている主体 → カメラは動かない（無駄に揺らさない）
##   - 画面外／端の主体 → カメラが動き、パン後は見えている（全行動を見せる）
## 実行: godot --path . -s res://tests/manual/repro_camera_follow.gd

var _frames := 0
var _main: Node = null
var _board = null
var _ctrl = null
var _log: Array[String] = []
var _done := false

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

## focus_camera_on と同じ安全域判定（複製）。主体が安全域内にあるか。
func _in_safe_area(hex: Vector2i) -> bool:
	var cam: Camera3D = _board._cam
	var w = _board._hex_world(hex)
	if cam.is_position_behind(w):
		return false
	var sp := cam.unproject_position(w)
	var vp := root.get_viewport().get_visible_rect().size
	var m := 96.0  # FOCUS_MARGIN
	return sp.x >= 16.0 + m and sp.x <= 800.0 - 16.0 - m and sp.y >= 96.0 + m and sp.y <= vp.y - m

## focus_pace の横取り: 本物の focus_camera_on を挟んで前後を観測する。
func _observe_focus(hex: Vector2i) -> void:
	var before := _in_safe_area(hex)
	var t0: Vector3 = _board._cam_target
	await _board.focus_camera_on(hex)
	var moved: bool = _board._cam_target.distance_to(t0) > 0.01
	var after := _in_safe_area(hex)
	_log.append("hex=%s  見えていた=%s  カメラ動いた=%s  パン後に見える=%s" % [hex, before, moved, after])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_main._select.close()
		_main.load_stage("res://data/stages/tutorial1-goblin-raid/st4.json")
	if _frames == 20:
		_board = _main.get_node("HexBoard")
		_ctrl = _board.controller
		_board._cam_dist = 20.0  # プレイヤーが寄せた状態を再現（全体フィットより寄る）
		_board._update_camera()
		_ctrl.focus_pace = _observe_focus  # main の結線を観測ラッパで上書き
		_ctrl.end_turn()
	if _frames == 900 and not _done:
		_done = true
		root.get_texture().get_image().save_png("user://shot_camera_follow.png")  # 最後に追従した位置の絵
		print("--- AI手番のカメラ追従（寄せた状態 dist=20）---")
		for l in _log:
			print("  ", l)
		var bad := 0
		for l in _log:
			if l.ends_with("パン後に見える=false"):
				bad += 1  # 寄せても見えない＝追従の失敗
		print("合計 %d手 / 追従に失敗（見せられなかった）= %d手 / current_team=%d（0なら固まらず手番が返った）"
			% [_log.size(), bad, _ctrl.state.current_team])
		return true
	return false
