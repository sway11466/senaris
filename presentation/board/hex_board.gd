extends Node2D
class_name HexBoard
## ヘックス盤面の最小描画。flat-top。
## マウス下をハイライトし、クリックした起点からの移動可能範囲を塗る。
## Presentation 層: domain/hex.gd の座標変換・探索を使うだけで状態は持たない（選択は表示用の一時状態）。

@export var cols: int = 12
@export var rows: int = 8
@export var hex_size: float = 36.0
@export var board_origin: Vector2 = Vector2(120, 100)
@export var move_range: int = 4

const COLOR_LINE := Color(0.78, 0.83, 0.90, 1.0)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.45)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_START := Color(1.00, 0.80, 0.25, 0.55)

var _hover := Vector2i(-9999, -9999)
var _selected := Vector2i(-9999, -9999)
var _reachable := {}  # Vector2i -> true（描画時の塗り判定用）

func _process(_delta: float) -> void:
	var h := _hex_at_mouse()
	if h != _hover:
		_hover = h
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _hex_at_mouse()
		if _in_field(h):
			_select(h)

func _select(start: Vector2i) -> void:
	_selected = start
	_reachable.clear()
	for h in Hex.flood_reach(start, move_range, _in_field):
		_reachable[h] = true
	queue_redraw()

func _hex_at_mouse() -> Vector2i:
	return Hex.from_pixel(get_local_mouse_position() - board_origin, hex_size)

## 矩形フィールド内かどうか（通行判定）。flood_reach に Callable として渡す。
func _in_field(hex: Vector2i) -> bool:
	var off := Hex.axial_to_offset(hex)
	return off.x >= 0 and off.x < cols and off.y >= 0 and off.y < rows

func _draw() -> void:
	for col in cols:
		for row in rows:
			var hex := Hex.offset_to_axial(col, row)
			var center := board_origin + Hex.to_pixel(hex, hex_size)
			_draw_hex(center, hex)

func _draw_hex(center: Vector2, hex: Vector2i) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
	if hex == _selected:
		draw_colored_polygon(pts, COLOR_START)
	elif _reachable.has(hex):
		draw_colored_polygon(pts, COLOR_REACH)
	if hex == _hover:
		draw_colored_polygon(pts, COLOR_HOVER)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, COLOR_LINE, 1.5, true)
