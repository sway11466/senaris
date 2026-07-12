extends Control
class_name MapEditorBoard
## マップエディタの盤面キャンバス（tools 専用）。
## MapEditorDoc の内容を flat-top ヘックス（本体と同じ odd-q オフセット＝Hex.gd）で描画し、
## セル単位のマウス操作をシグナルで通知する。描画は編集用の記号表現＝実機の見た目は本体で確認する。

signal cell_pressed(col: int, row: int, button: int)
signal cell_dragged(col: int, row: int, button: int)
signal cell_released(col: int, row: int, button: int)
signal zoom_requested(step: int)  ## Ctrl＋ホイール（+1=拡大 / -1=縮小）

const SQRT3 := 1.7320508075688772
const MARGIN := 22.0  ## 盤の余白（列/行番号の表示領域を兼ねる）

## 編集用の地形色（実機のタイル画像とは別物。区別が付けばよい）。
const TERRAIN_COLORS := {
	"road": Color(0.78, 0.70, 0.52),
	"plain": Color(0.62, 0.75, 0.42),
	"plateau": Color(0.76, 0.66, 0.40),
	"wasteland": Color(0.71, 0.63, 0.52),
	"forest": Color(0.30, 0.48, 0.23),
	"bush": Color(0.48, 0.63, 0.31),
	"mountain": Color(0.54, 0.50, 0.46),
	"fence": Color(0.63, 0.55, 0.35),
	"trap": Color(0.69, 0.42, 0.35),
	"rampart": Color(0.60, 0.64, 0.69),
	"cliff": Color(0.44, 0.48, 0.53),
	"wall": Color(0.25, 0.25, 0.28),
	"fort": Color(0.75, 0.47, 0.25),
}
const TEAM_COLORS := {
	"player": Color(0.25, 0.45, 0.85),
	"enemy": Color(0.82, 0.28, 0.28),
	"neutral": Color(0.55, 0.55, 0.55),
}

var doc: MapEditorDoc
var scroll: ScrollContainer  ## 中ボタンドラッグでパンする先（親のスクロール。main が設定）
var hex_size := 26.0:
	set(v):
		hex_size = v
		refresh()
var hover := Vector2i(-1, -1)
var selected := Vector2i(-1, -1)

var _drag_button := -1
var _last_cell := Vector2i(-1, -1)
var _panning := false


func _ready() -> void:
	mouse_exited.connect(func() -> void:
		hover = Vector2i(-1, -1)
		queue_redraw())


## doc の変更後に呼ぶ（サイズ再計算＋再描画）。
func refresh() -> void:
	if doc == null:
		return
	custom_minimum_size = Vector2(
		hex_size * (1.5 * (doc.cols() - 1) + 2.0) + MARGIN * 2.0,
		hex_size * SQRT3 * (doc.rows() + 0.5) + MARGIN * 2.0)
	queue_redraw()


func _origin() -> Vector2:
	return Vector2(hex_size + MARGIN, hex_size * SQRT3 * 0.5 + MARGIN)


func cell_center(col: int, row: int) -> Vector2:
	return _origin() + Hex.to_pixel(Hex.offset_to_axial(col, row), hex_size)


## ピクセル→セル。盤外は (-1,-1)。
func cell_at(p: Vector2) -> Vector2i:
	var off := Hex.axial_to_offset(Hex.from_pixel(p - _origin(), hex_size))
	if off.x < 0 or off.x >= doc.cols() or off.y < 0 or off.y >= doc.rows():
		return Vector2i(-1, -1)
	return off


func _gui_input(event: InputEvent) -> void:
	if doc == null:
		return
	# パン＝中ボタンドラッグ / ズーム＝Ctrl＋ホイール。素のホイール/トラックパッドのスクロールは
	# accept せず ScrollContainer に流す（＝通常のスクロールでも盤を動かせる）。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.ctrl_pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_requested.emit(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		accept_event()
		return
	if event is InputEventMouseMotion and _panning:
		if scroll != null:
			scroll.scroll_horizontal -= int(event.relative.x)
			scroll.scroll_vertical -= int(event.relative.y)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var cell := cell_at(event.position)
		if event.pressed:
			_drag_button = event.button_index
			_last_cell = cell
			if cell.x >= 0:
				cell_pressed.emit(cell.x, cell.y, event.button_index)
		elif event.button_index == _drag_button:
			_drag_button = -1
			if cell.x >= 0:
				cell_released.emit(cell.x, cell.y, event.button_index)
	elif event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != hover:
			hover = cell
			queue_redraw()
		if _drag_button != -1 and cell.x >= 0 and cell != _last_cell:
			_last_cell = cell
			cell_dragged.emit(cell.x, cell.y, _drag_button)


func _hex_points(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(a), sin(a)) * size)
	return pts


func _draw() -> void:
	if doc == null:
		return
	var font := get_theme_default_font()
	# 列/行番号（JSONの col/row と突き合わせるため）
	for col in doc.cols():
		var c := cell_center(col, 0)
		draw_string(font, Vector2(c.x - hex_size, MARGIN - 8.0), str(col),
			HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, 10, Color(1, 1, 1, 0.45))
	for row in doc.rows():
		var c := cell_center(0, row)
		draw_string(font, Vector2(1.0, c.y + 4.0), str(row),
			HORIZONTAL_ALIGNMENT_LEFT, MARGIN - 2.0, 10, Color(1, 1, 1, 0.45))
	# 地形
	for row in doc.rows():
		for col in doc.cols():
			var center := cell_center(col, row)
			var ch := doc.terrain_char(col, row)
			var tid := TerrainType.char_to_id(ch)
			var color: Color = TERRAIN_COLORS.get(tid, Color(0.5, 0.5, 0.5))
			draw_colored_polygon(_hex_points(center, hex_size * 0.96), color)
			var border := _hex_points(center, hex_size * 0.96)
			border.append(border[0])
			draw_polyline(border, Color(0, 0, 0, 0.35), 1.0)
			if ch != MapEditorDoc.DEFAULT_CHAR:
				draw_string(font, center + Vector2(-hex_size, hex_size * -0.35),
					ch, HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0,
					maxi(8, int(hex_size * 0.42)), Color(0, 0, 0, 0.55))
	# 拠点（リング＋種別＋控え数）
	for b in doc.data["bases"]:
		var center := cell_center(int(b.get("col", 0)), int(b.get("row", 0)))
		var color: Color = TEAM_COLORS.get(String(b.get("team", "neutral")), TEAM_COLORS["neutral"])
		draw_arc(center, hex_size * 0.74, 0.0, TAU, 32, color, 3.0)
		var label := "HQ" if String(b.get("kind", "fort")) == "hq" else "F"
		var g: Variant = b.get("garrison", [])
		var g_count := 0
		if typeof(g) == TYPE_ARRAY:
			for e in g:
				g_count += maxi(int(e.get("count", 1)), 1)
		if g_count > 0:
			label += " x%d" % g_count
		draw_string(font, center + Vector2(-hex_size, hex_size * 0.9),
			label, HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, maxi(8, int(hex_size * 0.36)), color.lightened(0.3))
	# ユニット（丸＋名前。敵は部隊番号、明示idはボス印）
	var font_size := maxi(8, int(hex_size * 0.32))
	for u in doc.data["player"]:
		_draw_unit(font, u, TEAM_COLORS["player"], "", font_size)
	var squads: Array = doc.data["enemy"]
	for s in squads.size():
		for u in squads[s].get("units", []):
			_draw_unit(font, u, TEAM_COLORS["enemy"], str(s), font_size)
	# ホバー・選択
	if hover.x >= 0:
		var pts := _hex_points(cell_center(hover.x, hover.y), hex_size * 0.96)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.8), 2.0)
	if selected.x >= 0:
		var pts := _hex_points(cell_center(selected.x, selected.y), hex_size * 0.96)
		pts.append(pts[0])
		draw_polyline(pts, Color(1.0, 0.9, 0.2, 0.95), 2.5)


func _draw_unit(font: Font, u: Dictionary, color: Color, squad_tag: String, font_size: int) -> void:
	var center := cell_center(int(u.get("col", 0)), int(u.get("row", 0)))
	draw_circle(center, hex_size * 0.5, color)
	draw_arc(center, hex_size * 0.5, 0.0, TAU, 24, color.darkened(0.4), 1.5)
	var label := String(u.get("type", u.get("skin", "?")))
	if u.has("skin"):
		label = String(u["skin"])
	draw_string(font, center + Vector2(-hex_size, font_size * 0.4),
		label.substr(0, 8), HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, font_size, Color.WHITE)
	if squad_tag != "":
		draw_string(font, center + Vector2(-hex_size, -hex_size * 0.55),
			"部" + squad_tag, HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, font_size, Color(1, 0.85, 0.5))
	if u.has("id"):
		draw_string(font, center + Vector2(-hex_size, hex_size * 0.75),
			"id" + str(int(u["id"])), HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, font_size, Color(1, 0.9, 0.2))
	if u.has("passengers") and typeof(u["passengers"]) == TYPE_ARRAY and not u["passengers"].is_empty():
		draw_string(font, center + Vector2(-hex_size, hex_size * 0.75),
			"乗%d" % u["passengers"].size(), HORIZONTAL_ALIGNMENT_CENTER, hex_size * 2.0, font_size, Color(0.8, 1, 0.8))
