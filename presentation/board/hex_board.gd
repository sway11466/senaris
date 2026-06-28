extends Node2D
class_name HexBoard
## ヘックス盤面とユニットの描画・入力。flat-top。
## Presentation 層: 状態(BattleState)は読むだけ。変更はコマンドを controller に渡し、
## 結果はシグナル(unit_moved/unit_attacked/turn_changed)を受けて再描画する。

## 選択中ユニットが変わったとき発行（id<0＝選択解除）。情報パネル等が購読する。
signal selection_changed(unit_id: int)

@export var hex_size: float = 36.0
@export var board_origin: Vector2 = Vector2(120, 100)

const COLOR_LINE := Color(0.78, 0.83, 0.90, 1.0)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.30)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_DEPLOY := Color(0.65, 0.45, 0.95, 0.40)  # 出撃先候補（移動の緑と区別）
const COLOR_SELECT_RING := Color(1.00, 0.85, 0.25)
const COLOR_ATTACK_RING := Color(0.95, 0.25, 0.25)
const COLOR_SURROUNDED := Color(0.95, 0.55, 0.15)
const TEAM_COLORS: Array[Color] = [Color(0.30, 0.55, 0.95), Color(0.92, 0.40, 0.35)]
const COLOR_BASE_NEUTRAL := Color(0.80, 0.80, 0.80)  # 未占領拠点の縁取り

const COLOR_UNIT_LABEL := Color(1, 1, 1, 0.95)

var state: BattleState
var controller: MatchController
var _terrain_tex := {}    # terrain_id(String) -> Texture2D（Terrain カタログから読み込み）
var _skin_catalog := {}   # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }（名前プレースホルダ用）

const INVALID_HEX := Vector2i(-9999, -9999)

var _hover := Vector2i(-9999, -9999)
var _selected_id := -1
var _reachable := {}  # Vector2i -> true
var _targets := {}    # Vector2i -> target_id（攻撃可能な敵の位置）
var _deploy_base := INVALID_HEX  # 出撃モード中の拠点（右クリックで入る）
var _deploy_cells := {}  # Vector2i -> true（出撃先候補）
var _locked := false  # 決着・AI手番中は入力を受けない

func bind(p_state: BattleState, p_controller: MatchController, p_skin_catalog: Dictionary = {}) -> void:
	state = p_state
	controller = p_controller
	_skin_catalog = p_skin_catalog
	if _terrain_tex.is_empty():  # タイル画像は1回だけ読む
		for id in Terrain.all_ids():
			_terrain_tex[id] = load(Terrain.image_path(id))
	_reset_interaction()  # ステージ再ロードに備え、選択・出撃・ロック状態を初期化
	controller.unit_moved.connect(_on_unit_moved)
	controller.unit_attacked.connect(_on_unit_attacked)
	controller.unit_deployed.connect(_on_unit_deployed)
	controller.turn_changed.connect(_on_turn_changed)
	controller.battle_finished.connect(_on_battle_finished)
	queue_redraw()

## 選択・出撃モード・ロック・ホバーを初期状態へ（ステージ再ロード時に呼ぶ）。
func _reset_interaction() -> void:
	_selected_id = -1
	_reachable.clear()
	_targets.clear()
	_deploy_base = INVALID_HEX
	_deploy_cells.clear()
	_locked = false
	_hover = Vector2i(-9999, -9999)

func _process(_delta: float) -> void:
	if state == null:
		return
	var h := _hex_at_mouse()
	if h != _hover:
		_hover = h
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if state == null or _locked or controller.is_ai_turn():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(_hex_at_mouse())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_right_click(_hex_at_mouse())  # 自軍拠点 → 出撃モード
	elif event.is_action_pressed("ui_accept"):  # Enter / Space で手番終了
		_deselect()
		controller.end_turn()

func _on_click(hex: Vector2i) -> void:
	# 出撃モード中: 出撃先候補をクリック → 出撃。それ以外のクリックは出撃モードを抜けて通常処理。
	if _deploy_base != INVALID_HEX:
		if _deploy_cells.has(hex):
			controller.execute_deploy(DeployCommand.new(_deploy_base, 0, hex))
			return
		_clear_deploy()
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

## 自軍が占領済みで控えのある拠点を右クリック → 出撃モード（出撃先候補をハイライト）。
func _on_right_click(hex: Vector2i) -> void:
	var b := state.base_at(hex)
	if b != null and b.team == state.current_team:
		var cells := controller.deploy_cells_for(hex)
		if not cells.is_empty():
			_deselect()
			_deploy_base = hex
			_deploy_cells.clear()
			for c in cells:
				_deploy_cells[c] = true
			queue_redraw()
			return
	_clear_deploy()

func _clear_deploy() -> void:
	_deploy_base = INVALID_HEX
	_deploy_cells.clear()
	queue_redraw()

func _select(id: int) -> void:
	_selected_id = id
	_reachable.clear()
	_targets.clear()
	if state.can_still_move(id):  # まだ動けるなら（残り移動力ぶん）移動範囲を出す
		for h in controller.reachable_for(id):
			_reachable[h] = true
	for tid in controller.attack_targets_for(id):
		_targets[state.unit_by_id(tid).pos] = tid
	selection_changed.emit(id)
	queue_redraw()

func _deselect() -> void:
	var had := _selected_id
	_selected_id = -1
	_reachable.clear()
	_targets.clear()
	if had != -1:
		selection_changed.emit(-1)
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

func _on_unit_deployed(_unit_id: int, base_hex: Vector2i, _to: Vector2i) -> void:
	# 控えと出撃先が残っていれば出撃モードを継続（候補を更新）、尽きたら解除。
	var cells := controller.deploy_cells_for(base_hex)
	if cells.is_empty():
		_clear_deploy()
		return
	_deploy_base = base_hex
	_deploy_cells.clear()
	for c in cells:
		_deploy_cells[c] = true
	queue_redraw()

func _on_turn_changed(_team: int, _turn_number: int) -> void:
	_deselect()
	_clear_deploy()

func _on_battle_finished(_winner: int) -> void:
	_locked = true
	_deselect()
	_clear_deploy()

func _hex_at_mouse() -> Vector2i:
	return Hex.from_pixel(get_local_mouse_position() - board_origin, hex_size)

func _draw() -> void:
	if state == null:
		return
	for col in state.cols:
		for row in state.rows:
			_draw_tile(Hex.offset_to_axial(col, row))
	for b in state.bases():
		_draw_base(b)
	for u in state.units():
		_draw_unit(u)

## 拠点の所属（縁取りの色）と控え数（garrison）を描く。地形タイルの上・ユニットの下。
func _draw_base(b: Base) -> void:
	var center := board_origin + Hex.to_pixel(b.hex, hex_size)
	var col := COLOR_BASE_NEUTRAL
	if b.team >= 0:
		col = TEAM_COLORS[b.team % TEAM_COLORS.size()]
	# 所属を示す六角の縁取り（地形タイルの淵に沿わせる）。
	var ring := _corners(center)
	ring.append(ring[0])
	draw_polyline(ring, col, 3.0, true)
	# 控え数（出撃できる人数）を左上に小さく。
	if not b.garrison.is_empty():
		var font := ThemeDB.fallback_font
		var fs := int(hex_size * 0.42)
		var pos := center + Vector2(-hex_size * 0.5, -hex_size * 0.30)
		draw_string(font, pos, "+%d" % b.garrison.size(), HORIZONTAL_ALIGNMENT_LEFT, hex_size, fs, col)

func _draw_tile(hex: Vector2i) -> void:
	var center := board_origin + Hex.to_pixel(hex, hex_size)
	var pts := _corners(center)
	_draw_terrain(hex, center)  # 地形タイル（一番下）
	if _reachable.has(hex):
		draw_colored_polygon(pts, COLOR_REACH)
	if _deploy_cells.has(hex):
		draw_colored_polygon(pts, COLOR_DEPLOY)
	if hex == _hover:
		draw_colored_polygon(pts, COLOR_HOVER)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, COLOR_LINE, 1.5, true)

## hex の地形タイル画像を、ヘックス寸法にフィットさせて描く。
func _draw_terrain(hex: Vector2i, center: Vector2) -> void:
	var tex: Texture2D = _terrain_tex.get(state.terrain_at(hex))
	if tex == null:
		return
	var w := hex_size * 2.0          # 頂点〜頂点
	var h := hex_size * Hex.SQRT3     # 上下の平辺間
	draw_texture_rect(tex, Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)), false)

func _draw_unit(u: Unit) -> void:
	var center := board_origin + Hex.to_pixel(u.pos, hex_size)
	var col: Color = TEAM_COLORS[u.team % TEAM_COLORS.size()]
	if state.is_done(u.id):
		col = col.darkened(0.45)  # 行動終了は暗く
	if Surround.factor(state, u) < 1.0:  # 包囲中（攻防に係数<1.0）を明示
		draw_arc(center, hex_size * 0.86, 0.0, TAU, 24, COLOR_SURROUNDED, 2.5)
	draw_circle(center, hex_size * 0.55, col)
	_draw_unit_label(u, center)
	if u.id == _selected_id:
		draw_arc(center, hex_size * 0.70, 0.0, TAU, 32, COLOR_SELECT_RING, 3.0)
	if _targets.has(u.pos):
		draw_arc(center, hex_size * 0.72, 0.0, TAU, 32, COLOR_ATTACK_RING, 3.0)
	_draw_troops_bar(u, center)

## ユニットのマップ表示プレースホルダ（スキン名の先頭2文字）。画像が来たら差し替え予定。
func _draw_unit_label(u: Unit, center: Vector2) -> void:
	var s: UnitSkin = SkinCatalog.skin(_skin_catalog, u.type_id, u.team)
	var label := s.map_label() if s != null else u.type_id.substr(0, 2)
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs := int(hex_size * 0.5)
	var w := hex_size * 1.6
	var pos := center + Vector2(-w * 0.5, fs * 0.36)  # ざっくり中央寄せ
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, w, fs, COLOR_UNIT_LABEL)

func _draw_troops_bar(u: Unit, center: Vector2) -> void:
	# 兵数バー（残存兵数 / 満員）。
	var w := hex_size
	var h := 5.0
	var top_left := center + Vector2(-w * 0.5, -hex_size * 0.78 - h)
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0, 0, 0, 0.6))
	var ratio := clampf(float(u.troops) / float(u.max_troops), 0.0, 1.0)
	draw_rect(Rect2(top_left, Vector2(w * ratio, h)), Color(0.30, 0.90, 0.40))

func _corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
	return pts
