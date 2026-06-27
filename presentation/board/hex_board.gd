extends Node2D
class_name HexBoard
## ヘックス盤面とユニットの描画・入力。flat-top。
## Presentation 層: 状態(BattleState)は読むだけ。変更は MoveCommand を controller に渡し、
## 結果は controller のシグナル(unit_moved)を受けて再描画する（直接 state を書き換えない）。

@export var hex_size: float = 36.0
@export var board_origin: Vector2 = Vector2(120, 100)

const COLOR_LINE := Color(0.78, 0.83, 0.90, 1.0)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.30)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_SELECT_RING := Color(1.00, 0.85, 0.25)
const TEAM_COLORS: Array[Color] = [Color(0.30, 0.55, 0.95), Color(0.92, 0.40, 0.35)]

var state: BattleState
var controller: MatchController

var _hover := Vector2i(-9999, -9999)
var _selected_id := -1
var _reachable := {}  # Vector2i -> true

func bind(p_state: BattleState, p_controller: MatchController) -> void:
	state = p_state
	controller = p_controller
	controller.unit_moved.connect(_on_unit_moved)
	controller.turn_changed.connect(_on_turn_changed)
	queue_redraw()

func _process(_delta: float) -> void:
	if state == null:
		return
	var h := _hex_at_mouse()
	if h != _hover:
		_hover = h
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(_hex_at_mouse())
	elif event.is_action_pressed("ui_accept"):  # Enter / Space で手番終了
		_deselect()
		controller.end_turn()

func _on_click(hex: Vector2i) -> void:
	var clicked := state.unit_at(hex)
	# 選択中のユニットがいて、空きの到達マスをクリック → 移動コマンドを投げる。
	if _selected_id != -1 and clicked == null and _reachable.has(hex):
		controller.execute(MoveCommand.new(_selected_id, hex))
		return
	# 現手番の未行動ユニットをクリック → 選択。それ以外 → 選択解除。
	if clicked != null and state.can_select(clicked.id):
		_select(clicked.id)
	else:
		_deselect()

func _select(id: int) -> void:
	_selected_id = id
	_reachable.clear()
	for h in controller.reachable_for(id):
		_reachable[h] = true
	queue_redraw()

func _deselect() -> void:
	_selected_id = -1
	_reachable.clear()
	queue_redraw()

func _on_unit_moved(_unit_id: int, _from: Vector2i, _to: Vector2i) -> void:
	# 移動したユニットは行動済み。選択を解いて再描画する。
	_deselect()

func _on_turn_changed(_team: int, _turn_number: int) -> void:
	_deselect()

func _hex_at_mouse() -> Vector2i:
	return Hex.from_pixel(get_local_mouse_position() - board_origin, hex_size)

func _draw() -> void:
	if state == null:
		return
	for col in state.cols:
		for row in state.rows:
			_draw_tile(Hex.offset_to_axial(col, row))
	for u in state.units():
		_draw_unit(u)

func _draw_tile(hex: Vector2i) -> void:
	var center := board_origin + Hex.to_pixel(hex, hex_size)
	var pts := _corners(center)
	if _reachable.has(hex):
		draw_colored_polygon(pts, COLOR_REACH)
	if hex == _hover:
		draw_colored_polygon(pts, COLOR_HOVER)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, COLOR_LINE, 1.5, true)

func _draw_unit(u: Unit) -> void:
	var center := board_origin + Hex.to_pixel(u.pos, hex_size)
	var col: Color = TEAM_COLORS[u.team % TEAM_COLORS.size()]
	if state.has_moved(u.id):
		col = col.darkened(0.45)  # 行動済みは暗く
	draw_circle(center, hex_size * 0.55, col)
	if u.id == _selected_id:
		draw_arc(center, hex_size * 0.7, 0.0, TAU, 32, COLOR_SELECT_RING, 3.0)

func _corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
	return pts
