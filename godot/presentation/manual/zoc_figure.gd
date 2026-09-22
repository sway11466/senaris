extends Control
class_name ManualZocFigure
## 足止めの図＝敵1体の周り6マスを塗り、そこへ入ろうとする味方の動きが塗ったマスで終わることを
## 矢印で見せる。仕様 → doc/gdd/manual.md 絵の持ち方 ／ 足止め → doc/gdd/movement.md
##
## 包囲の図（surround_figure.gd）と同じ描き方＝紙に直接描く（ノードを積まない）。盤の絵を撮らない
## のは、盤では地形や他の駒が一緒に写って、どのマスが足止めの範囲かが読めないため。
##
## 図に言葉は入れない＝言語で変わらない。塗りが何を指すかは本文（manual.csv）が言う。
##
## 並べ方はここが持つ。味方の行き先は敵の向こう側で、道が2本ある。まっすぐ降りる道（STOP）は
## 最初に入った塗りマスで終わり、その先の一歩（BLOCKED）には×が付く。塗りを避けて左へ回る道
## （DETOUR）は最後まで通る＝「マスには入れるがその先へは進めない／避ければ通れる」が並ぶ。

const ENEMY := Vector2i(0, 0)     # 足止めを出している敵
const START := Vector2i(-1, -1)   # 味方の出発点（塗りの外）
const STOP := Vector2i(-1, 0)     # まっすぐ降りて最初に入る塗りマス＝ここで移動が終わる
const BLOCKED := Vector2i(-1, 1)  # その先の一歩（進めない）
## 迂回路＝塗りに一度も入らない道。出発点から左へ回り、敵の脇を抜けて向こう側まで出る。
const DETOUR: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(-2, 1), Vector2i(-2, 2)]

## 塗りは包囲の図と同じ赤系＝マニュアルの中で「敵の効いている範囲」を同じ色で通す。
const FILL_ZONE := Color(0.86, 0.36, 0.30, 0.26)
const HEX_LINE := Color(0.82, 0.82, 0.82, 0.55)
const HEX_LINE_WIDTH := 1.5
const ART_FIT := 0.72  # 駒を収める箱＝ヘックスの内接矩形に対する比

const ARROW_COLOR := Color(0.90, 0.82, 0.62)        # 通る動き（ManualScreen.ACCENT と同値）
const ARROW_BLOCKED := Color(0.90, 0.82, 0.62, 0.3) # 進めない一歩＝同じ色を薄く
const CROSS_COLOR := Color(0.86, 0.36, 0.30, 0.9)   # ×＝塗りと同じ赤（止めているのは足止め）
const ARROW_WIDTH := 3.0
const ARROW_HEAD := 0.22   # 矢じりの長さ＝ヘックスの外接円半径に対する比
const ARROW_INSET := 0.45  # 矢の始点・終点をマスの中心からどれだけ手前で切るか（同じく半径比）
const CROSS_SIZE := 0.20   # ×の半分の長さ（同じく半径比）

var _enemy: Texture2D = null
var _mover: Texture2D = null

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(enemy: Texture2D, mover: Texture2D) -> void:
	_enemy = enemy
	_mover = mover
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var zone := Hex.neighbors(ENEMY)
	var hexes: Array[Vector2i] = [ENEMY]
	hexes.append_array(zone)
	hexes.append(START)
	hexes.append_array(DETOUR)

	# 置くヘックスの外接矩形（単位＝ヘックスの外接円半径 1）を枠に収める倍率。包囲の図と同じ組み方。
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for h in hexes:
		var c := Hex.to_pixel(h, 1.0)
		lo = lo.min(c - Vector2(1.0, Hex.SQRT3 * 0.5))
		hi = hi.max(c + Vector2(1.0, Hex.SQRT3 * 0.5))
	var span := hi - lo
	var s := minf(size.x / span.x, size.y / span.y)
	var origin := (size - span * s) * 0.5 - lo * s

	for h in hexes:
		var center := origin + Hex.to_pixel(h, s)
		var corners := PackedVector2Array()
		for k in 6:
			var a := deg_to_rad(60.0 * k)
			corners.append(center + Vector2(cos(a), sin(a)) * s)
		# 敵のマスは塗らない＝塗ってあるマスが「足止めの範囲」だと読める。
		if zone.has(h):
			draw_colored_polygon(corners, FILL_ZONE)
		corners.append(corners[0])
		draw_polyline(corners, HEX_LINE, HEX_LINE_WIDTH, true)

	var at := func(h: Vector2i) -> Vector2: return origin + Hex.to_pixel(h, s)
	# 塗りへ入る道＝入ったところで終わる。矢じりはマスの中心まで届かせる＝そこで移動が終わることを
	# 矢じりの位置で見せる。その先の一歩は薄い矢印に×。
	_draw_arrow(at.call(START), at.call(STOP), s, ARROW_COLOR, ARROW_INSET, 0.0)
	_draw_arrow(at.call(STOP), at.call(BLOCKED), s, ARROW_BLOCKED, ARROW_INSET, ARROW_INSET)
	_draw_cross((at.call(STOP) + at.call(BLOCKED)) * 0.5, s)
	# 迂回路＝塗りに入らないので最後まで続く。1本の折れ線で引く＝途中で止まっていないと読める。
	var detour: Array[Vector2] = [at.call(START)]
	for h in DETOUR:
		detour.append(at.call(h))
	_draw_path(detour, s, ARROW_COLOR)

	_draw_piece(_enemy, at.call(ENEMY), s)
	_draw_piece(_mover, at.call(START), s)

## 何マスも続く道。折れ線で引き、矢じりは終点にだけ付ける。始点は駒と重ならないよう手前で切る。
func _draw_path(points: Array[Vector2], s: float, color: Color) -> void:
	if points.size() < 2:
		return
	var line := PackedVector2Array()
	var head_dir := (points[0] - points[1]).normalized()
	line.append(points[0] + (points[1] - points[0]).normalized() * s * ARROW_INSET)
	for i in range(1, points.size()):
		line.append(points[i])
		head_dir = (points[i] - points[i - 1]).normalized()
	draw_polyline(line, color, ARROW_WIDTH, true)
	var b: Vector2 = points[points.size() - 1]
	var head := s * ARROW_HEAD
	var side := Vector2(-head_dir.y, head_dir.x)
	draw_line(b, b - head_dir * head + side * head * 0.6, color, ARROW_WIDTH, true)
	draw_line(b, b - head_dir * head - side * head * 0.6, color, ARROW_WIDTH, true)

## マスからマスへの矢印。両端を中心よりどれだけ手前で切るかは呼ぶ側が決める（駒と重ねない・
## 止まるマスでは中心まで届かせる、を撃ち分ける）。
func _draw_arrow(from: Vector2, to: Vector2, s: float, color: Color,
		inset_from: float, inset_to: float) -> void:
	var dir := (to - from).normalized()
	var a := from + dir * s * inset_from
	var b := to - dir * s * inset_to
	draw_line(a, b, color, ARROW_WIDTH, true)
	var head := s * ARROW_HEAD
	var side := Vector2(-dir.y, dir.x)
	draw_line(b, b - dir * head + side * head * 0.6, color, ARROW_WIDTH, true)
	draw_line(b, b - dir * head - side * head * 0.6, color, ARROW_WIDTH, true)

## 進めない印。辺の上に置く。
func _draw_cross(at: Vector2, s: float) -> void:
	var d := s * CROSS_SIZE
	draw_line(at + Vector2(-d, -d), at + Vector2(d, d), CROSS_COLOR, ARROW_WIDTH, true)
	draw_line(at + Vector2(-d, d), at + Vector2(d, -d), CROSS_COLOR, ARROW_WIDTH, true)

## 駒1つ。内接矩形（幅 1.5s・高さ √3 s）に比率を保って収める（包囲の図と同じ）。
func _draw_piece(tex: Texture2D, center: Vector2, s: float) -> void:
	if tex == null:
		return
	var box := Vector2(1.5, Hex.SQRT3) * s * ART_FIT
	var ts := tex.get_size()
	var fit := minf(box.x / ts.x, box.y / ts.y)
	var draw_size := ts * fit
	draw_texture_rect(tex, Rect2(center - draw_size * 0.5, draw_size), false)
