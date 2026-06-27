extends Node2D
class_name HexBoard
## ヘックス盤面の最小描画。flat-top。マウス下のヘックスをハイライトする。
## Presentation 層: domain/hex.gd の座標変換を使うだけで、状態は持たない。

@export var cols: int = 12
@export var rows: int = 8
@export var hex_size: float = 36.0
@export var board_origin: Vector2 = Vector2(120, 100)

const COLOR_LINE := Color(0.78, 0.83, 0.90, 1.0)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.45)

var _hover := Vector2i(-9999, -9999)

func _process(_delta: float) -> void:
	var local := get_local_mouse_position() - board_origin
	var h := Hex.from_pixel(local, hex_size)
	if h != _hover:
		_hover = h
		queue_redraw()

func _draw() -> void:
	for col in cols:
		for row in rows:
			var hex := Hex.offset_to_axial(col, row)
			var center := board_origin + Hex.to_pixel(hex, hex_size)
			_draw_hex(center, hex == _hover)

func _draw_hex(center: Vector2, hovered: bool) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
	if hovered:
		draw_colored_polygon(pts, COLOR_HOVER)
	pts.append(pts[0])
	draw_polyline(pts, COLOR_LINE, 1.5, true)
