extends Node2D
class_name HexBoard
## ヘックス盤面とユニットの描画・入力。flat-top。
## Presentation 層: 状態(BattleState)は読むだけ。変更はコマンドを controller に渡し、
## 結果はシグナル(unit_moved/unit_attacked/turn_changed)を受けて再描画する。

@export var hex_size: float = 36.0
@export var board_origin: Vector2 = Vector2(120, 100)

const COLOR_LINE := Color(0.78, 0.83, 0.90, 1.0)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.30)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_SELECT_RING := Color(1.00, 0.85, 0.25)
const COLOR_ATTACK_RING := Color(0.95, 0.25, 0.25)
const TEAM_COLORS: Array[Color] = [Color(0.30, 0.55, 0.95), Color(0.92, 0.40, 0.35)]

var state: BattleState
var controller: MatchController

var _hover := Vector2i(-9999, -9999)
var _selected_id := -1
var _reachable := {}  # Vector2i -> true
var _targets := {}    # Vector2i -> target_id（攻撃可能な敵の位置）
var _locked := false  # 決着・AI手番中は入力を受けない

func bind(p_state: BattleState, p_controller: MatchController) -> void:
	state = p_state
	controller = p_controller
	controller.unit_moved.connect(_on_unit_moved)
	controller.unit_attacked.connect(_on_unit_attacked)
	controller.turn_changed.connect(_on_turn_changed)
	controller.battle_finished.connect(_on_battle_finished)
	queue_redraw()

func _process(_delta: float) -> void:
	if state == null:
		return
	var h := _hex_at_mouse()
	if h != _hover:
		_hover = h
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if state == null or _locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(_hex_at_mouse())
	elif event.is_action_pressed("ui_accept"):  # Enter / Space で手番終了
		_deselect()
		controller.end_turn()

func _on_click(hex: Vector2i) -> void:
	if _selected_id != -1:
		# 攻撃可能な敵をクリック → 攻撃。
		if _targets.has(hex):
			controller.execute_attack(AttackCommand.new(_selected_id, _targets[hex]))
			return
		# 空きの到達マスをクリック → 移動。
		if state.unit_at(hex) == null and _reachable.has(hex):
			controller.execute(MoveCommand.new(_selected_id, hex))
			return
	# 現手番で操作可能なユニットをクリック → 選択。それ以外 → 選択解除。
	var clicked := state.unit_at(hex)
	if clicked != null and state.can_select(clicked.id):
		_select(clicked.id)
	else:
		_deselect()

func _select(id: int) -> void:
	_selected_id = id
	_reachable.clear()
	_targets.clear()
	if not state.has_moved(id):  # まだ動いていなければ移動範囲を出す
		for h in controller.reachable_for(id):
			_reachable[h] = true
	for tid in controller.attack_targets_for(id):
		_targets[state.unit_by_id(tid).pos] = tid
	queue_redraw()

func _deselect() -> void:
	_selected_id = -1
	_reachable.clear()
	_targets.clear()
	queue_redraw()

func _on_unit_moved(unit_id: int, _from: Vector2i, _to: Vector2i) -> void:
	# 移動後も攻撃が残っていれば選択を維持（移動→攻撃の流れ）。使い切ったら解除。
	if unit_id == _selected_id:
		if state.is_done(unit_id):
			_deselect()
		else:
			_select(unit_id)
	else:
		queue_redraw()

func _on_unit_attacked(_attacker_id: int, _target_id: int, _damage: int, _killed: bool) -> void:
	_deselect()  # 攻撃したユニットは行動終了

func _on_turn_changed(_team: int, _turn_number: int) -> void:
	_deselect()

func _on_battle_finished(_winner: int) -> void:
	_locked = true
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
	if state.is_done(u.id):
		col = col.darkened(0.45)  # 行動終了は暗く
	draw_circle(center, hex_size * 0.55, col)
	if u.id == _selected_id:
		draw_arc(center, hex_size * 0.70, 0.0, TAU, 32, COLOR_SELECT_RING, 3.0)
	if _targets.has(u.pos):
		draw_arc(center, hex_size * 0.72, 0.0, TAU, 32, COLOR_ATTACK_RING, 3.0)
	_draw_hp_bar(u, center)

func _draw_hp_bar(u: Unit, center: Vector2) -> void:
	var w := hex_size
	var h := 5.0
	var top_left := center + Vector2(-w * 0.5, -hex_size * 0.78 - h)
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0, 0, 0, 0.6))
	var ratio := clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
	draw_rect(Rect2(top_left, Vector2(w * ratio, h)), Color(0.30, 0.90, 0.40))

func _corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
	return pts
