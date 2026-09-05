extends SceneTree
## 使い捨ての実機検証：情報板の状態で盤エリアが切り替わるかを測り、絵も撮る。
## 板が既定の場所で開いているとき／畳んでいるとき／動かしてあるときの3状態で、
## 盤エリア・カメラの可視域・ターン終了ボタンの x を並べる。
## 起動: godot --path . -s res://tests/manual/repro_board_area.gd

const STAGE := "res://data/stages/debug-ai/standoff.json"
const OUT := "user://repro_board_area.txt"
const SHOT_OPEN := "user://board_area_open.png"
const SHOT_FOLDED := "user://board_area_folded.png"

var _main: Node = null
var _lines: PackedStringArray = []
var _frames := 0
var _panel: Control = null
var _was_minimized := false
var _done := false

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		30: _open_default()
		200: _shoot(SHOT_OPEN, "板＝既定の場所で開いている")
		210: _fold()
		330: _shoot(SHOT_FOLDED, "板＝畳んでいる")
		340: _move_panel()
		350: _finish()
	if _done:
		var f := FileAccess.open(OUT, FileAccess.WRITE)
		f.store_string("\n".join(_lines))
		return true
	return _frames > 700  # 保険＝進まなくてもハングさせない

func _open_default() -> void:
	_panel = _main.get_node("Front/InfoPanel")
	_was_minimized = _panel.is_minimized()
	_main._select.close()
	if _main._title != null and _main._title.visible:
		_main._title_pending = false
		_main._title.close()  # 扉の動画を畳んで盤を出す
	_panel.set_minimized(false)
	_main._on_info_panel_reset_requested()  # 既定の場所へ戻す＝動かしていない状態
	_main.load_stage(STAGE)

func _fold() -> void:
	_panel.set_minimized(true)
	_main.load_stage(STAGE)  # 読み込み時にカメラを合わせ直す

func _move_panel() -> void:
	_panel.set_minimized(false)
	_main._settings_store.set_info_panel_position(Vector2(300.0, 200.0))
	_main._sync_board_area()
	_say("板を動かしてある: 盤エリア=%s" % str(_area()))

func _shoot(path: String, label: String) -> void:
	var board: Node = _main.get_node("HexBoard")
	_say("%s: 盤エリア=%s / カメラ可視域=%s / ターン終了ボタン x=%.0f"
		% [label, str(_area()), str(board._vis_rect()), _main._hud._end_btn.position.x])
	_say("  盤の画面上の広がり=%s（可視域に収まっていれば OK）" % str(_board_on_screen(board)))
	root.get_texture().get_image().save_png(path)

## 盤の四隅をカメラで画面へ投影し、実際に画面のどこからどこまで占めるかを測る
## （fit_to_bounds は傾いたカメラを線形近似しているので、収まっているかは投影して確かめる）。
func _board_on_screen(board: Node) -> Rect2:
	# _board_bounds はヘックスの中心の外周＝実際に描かれる盤はタイル半径ぶん外まで広がる。
	var b: Rect2 = (board._board_bounds() as Rect2).grow(float(board.TILE))
	var cam: Camera3D = board._board_cam.camera
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in [b.position, Vector2(b.end.x, b.position.y), Vector2(b.position.x, b.end.y), b.end]:
		var s := cam.unproject_position(Vector3(p.x, 0.0, p.y))
		mn = mn.min(s)
		mx = mx.max(s)
	return Rect2(mn, mx - mn)

func _area() -> Rect2:
	return UiLayout.board_area(root.get_visible_rect().size)

func _finish() -> void:
	# 触った設定は戻す（実機の user://settings.json を共有しているため）。
	_main._settings_store.clear_info_panel_position()
	_panel.set_minimized(_was_minimized)
	_main._sync_board_area()
	_done = true

func _say(line: String) -> void:
	_lines.append(line)
