extends SceneTree
## 使い捨ての実機検証：情報板を掴んで動かせるか。押す→動かす→離す を板の _gui_input へ直に流し、
## 位置・moved シグナル・設定への書き込み・盤エリアの切り替わりを測る。
## 起動: godot --path . -s res://tests/manual/repro_panel_drag.gd

const STAGE := "res://data/stages/debug-ai/standoff.json"
const OUT := "user://repro_panel_drag.txt"
const SHOT := "user://panel_dragged.png"

var _main: Node = null
var _panel: Control = null
var _lines: PackedStringArray = []
var _frames := 0
var _moved_at: Array = []
var _had_position := false
var _done := false

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		30: _open()
		200: _drag()
		230: _after()
		260: _finish()
	if _done:
		FileAccess.open(OUT, FileAccess.WRITE).store_string("\n".join(_lines))
		return true
	return _frames > 500

func _open() -> void:
	_panel = _main.get_node("Front/InfoPanel")
	_had_position = _main._settings_store.has_info_panel_position()
	_main._select.close()
	if _main._title != null and _main._title.visible:
		_main._title_pending = false
		_main._title.close()
	_panel.set_minimized(false)
	_main._on_info_panel_reset_requested()
	_main.load_stage(STAGE)
	_panel.moved.connect(func(p: Vector2) -> void: _moved_at.append(p))
	_say("板の中で押下を吸うノード（＝ここを掴んでも板は動かない）:")
	_dump_stoppers(_panel, "")

func _drag() -> void:
	var from := _panel.position
	_say("掴む前の位置: %s / 盤エリア=%s" % [str(from), str(_area())])
	_press(from + Vector2(20.0, 400.0), true)   # 板の木の地（タブやページャーを避けた下のほう）
	_say("押した直後 _dragging=%s" % str(_panel._dragging))
	_motion(from + Vector2(-180.0, 300.0))
	_motion(from + Vector2(-380.0, 180.0))
	_release(from + Vector2(-380.0, 180.0))
	_say("離した後の位置: %s（動いた=%s）" % [str(_panel.position), str(_panel.position != from)])
	_say("moved シグナル: %s" % str(_moved_at))
	_say("設定に位置が書かれた: %s / 盤エリア=%s" % [str(_main._settings_store.has_info_panel_position()), str(_area())])

## 数フレーム置いてから撮る＝描画は1フレーム遅れるので、離した直後に撮ると前の絵が写る。
func _after() -> void:
	_say("30フレーム後の位置: %s / 画面上の矩形=%s" % [str(_panel.position), str(_panel.get_global_rect())])
	root.get_texture().get_image().save_png(SHOT)

## 板の子で mouse_filter=STOP のものを列挙する。タブ・ページャーのボタンは仕様どおり
## （doc/gdd/uiux.md 移動）。それ以外が出てきたら、そこを掴んだときに板が動かない。
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
	root.push_input(e)  # 画面全体へ流す＝板が実際に入力を受け取れるかまで見る

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
