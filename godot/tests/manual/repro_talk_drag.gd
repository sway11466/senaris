extends SceneTree
## 使い捨ての実機検証：板は1枚（doc/gdd/uiux.md 移動）。intro 会話のあるステージを開き、
## 会話板を吹き出しの上から掴んで動かす → 会話を飛ばして出る情報板が同じ場所に出る →
## 「情報板の位置を戻す」で両方が既定へ戻る、を測る。
## 起動: godot --path . -s res://tests/manual/repro_talk_drag.gd

const STAGE := "res://data/stages/tutorial3-dragon-hunt/st2.json"
const OUT := "user://repro_talk_drag.txt"
const SHOT_TALK := "user://talk_dragged.png"
const SHOT_INFO := "user://talk_dragged_info.png"

var _main: Node = null
var _info: Control = null
var _talk: Control = null
var _lines: PackedStringArray = []
var _frames := 0
var _had_position := false
var _done := false

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		30: _open()
		120: _drag_talk()
		150: _shoot(SHOT_TALK, "会話板を動かした直後")
		160: _skip_talk()
		200: _shoot(SHOT_INFO, "会話を飛ばして情報板が出た")
		210: _reset()
		240: _finish()
	if _done:
		FileAccess.open(OUT, FileAccess.WRITE).store_string("\n".join(_lines))
		return true
	return _frames > 600

func _open() -> void:
	_info = _main.get_node("Front/InfoPanel")
	_talk = _main._conversation
	_had_position = _main._settings_store.has_info_panel_position()
	_main._select.close()
	if _main._title != null and _main._title.visible:
		_main._title_pending = false
		_main._title.close()
	_info.set_minimized(false)
	_main._on_info_panel_reset_requested()
	_main._on_stage_chosen("tutorial3-dragon-hunt", "st2", STAGE)

func _drag_talk() -> void:
	_say("会話板 visible=%s 情報板 visible=%s" % [str(_talk.visible), str(_info.visible)])
	_say("会話板の中で押下を吸うノード（＝ここを掴んでも板は動かない）:")
	_dump_stoppers(_talk, "")
	var from := _talk.position
	_say("掴む前: 会話板=%s 情報板=%s 盤エリア=%s" % [str(from), str(_info.position), str(_area())])
	var bubble := _talk._messages.get_child(0) as Control
	var at := bubble.get_global_rect().get_center()  # 1行目の吹き出しの上
	_say("掴む点=%s（1行目の矩形 %s）" % [str(at), str(bubble.get_global_rect())])
	_press(at, true)
	_say("押した直後 _dragging=%s" % str(_talk._dragging))
	_motion(at + Vector2(-200.0, 100.0))
	_motion(at + Vector2(-400.0, 200.0))
	_release(at + Vector2(-400.0, 200.0))
	_say("離した後: 会話板=%s 情報板=%s（動いた=%s / 同じ=%s）" % [str(_talk.position), str(_info.position), str(_talk.position != from), str(_talk.position == _info.position)])
	_say("設定に位置が書かれた: %s / 盤エリア=%s" % [str(_main._settings_store.has_info_panel_position()), str(_area())])

func _skip_talk() -> void:
	_talk._on_skip()

func _reset() -> void:
	_say("戻す前: 会話板=%s 情報板=%s visible(会話=%s 情報=%s)" % [str(_talk.position), str(_info.position), str(_talk.visible), str(_info.visible)])
	_main._on_info_panel_reset_requested()
	_say("戻した後: 会話板=%s 情報板=%s 設定=%s 盤エリア=%s" % [str(_talk.position), str(_info.position), str(_main._settings_store.has_info_panel_position()), str(_area())])

func _shoot(path: String, label: String) -> void:
	_say("%s: 会話板=%s(visible=%s) 情報板=%s(visible=%s)" % [label, str(_talk.position), str(_talk.visible), str(_info.position), str(_info.visible)])
	root.get_texture().get_image().save_png(path)

func _dump_stoppers(node: Node, indent: String) -> void:
	for c in node.get_children():
		if c is Control and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			var src := (c.get_script() as Script)
			var who := src.resource_path.get_file() if src != null else c.get_class()
			_say("%s  %s <- 親 %s" % [indent, who, c.get_parent().name])
		_dump_stoppers(c, indent + " ")

func _press(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	root.push_input(e)

func _release(at: Vector2) -> void:
	_press(at, false)

func _motion(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	root.push_input(e)

func _area() -> Rect2:
	return UiLayout.board_area(root.get_visible_rect().size)

func _finish() -> void:
	if not _had_position:
		_main._settings_store.clear_info_panel_position()
	_main._on_info_panel_reset_requested()
	_done = true

func _say(line: String) -> void:
	_lines.append(line)
