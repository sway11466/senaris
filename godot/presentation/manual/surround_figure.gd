extends Control
class_name ManualSurroundFigure
## 包囲の図＝囲まれた駒を中央に置き、その周り6マスに囲みユニットを並べたもの。
## 数え方の2通り（囲みユニットのいるマス／その隣のマス）を、塗りの濃さと下げ幅の数字で見せる。
## 仕様 → doc/gdd/manual.md 絵の持ち方 ／ 数え方 → doc/gdd/combat.md 包囲効果
##
## クロニクルのレシピ図（chronicle/recipe_figure.gd）と同じ描き方＝紙に直接描く（ノードを積まない）。
## 盤の絵を撮らないのは、盤では地形や他の駒が一緒に写って、どのマスを数えているかが読めないため。
##
## 図に言葉は入れない＝言語で変わらない。入るのは下げ幅と包囲の係数の数字だけで、
## 色が何を指すかは本文（manual.csv）が言う。
##
## 受け取るのは囲みユニットの置き場だけで、その隣のマスはここで数える＝並べ方を手で二重に
## 持たない（持つと図と仕様がずれる）。

const CENTER := Vector2i(0, 0)

## 塗りは同じ色の濃淡で持つ＝別の色にすると「別のもの」に見える。数え方は同じで重みだけが
## 違う（8% と 4%）ので、濃さの差で「同じものが薄く効く」と読ませる。
const FILL_OCCUPIED := Color(0.86, 0.36, 0.30, 0.45)
const FILL_THREATENED := Color(0.86, 0.36, 0.30, 0.16)
const HEX_LINE := Color(0.82, 0.82, 0.82, 0.55)
const HEX_LINE_WIDTH := 1.5
const ART_FIT := 0.68  # 駒を収める箱＝ヘックスの内接矩形に対する比（数字を置くぶんレシピ図より小さい）

## マスに書く下げ幅。値は doc/gdd/combat.md 包囲効果の 0.08 / 0.04 と対。
const LABEL_OCCUPIED := "-8%"
const LABEL_THREATENED := "-4%"
const LABEL_COLOR := Color(0.94, 0.90, 0.84)
const LABEL_SIZE := 14
const LABEL_DROP := 0.70  # 数字を置く高さ＝ヘックスの中心から下へ、外接円半径に対する比（駒の下・辺の内側）
const PIECE_LIFT := 0.18  # 数字を置くマスの駒だけ上へ寄せる＝足元と数字が重ならない

## 図の下に置く係数（×0.76 など）＝表のどの行の形かを結ぶ。
const CAPTION_COLOR := Color(0.90, 0.82, 0.62)  # ManualScreen.ACCENT と同値
const CAPTION_SIZE := 16
const CAPTION_BAND := 26.0  # 係数のために下へ空ける高さ＝ヘックスはこの上に収める

var _occupied: Array[Vector2i] = []
var _beside: Array[Vector2i] = []  # 囲みユニットの隣のマス（setup で数える）
var _center: Texture2D = null
var _around: Array = []  # _occupied の順に置く Texture2D（null＝絵が未用意）
var _caption := ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## occupied＝囲みユニットを置くマス（中央から見た相対の axial）。around はその順の駒の絵。
## caption＝図の下に出す係数（空なら出さない）。
func setup(occupied: Array[Vector2i], center: Texture2D, around: Array, caption: String) -> void:
	_occupied = occupied
	_center = center
	_around = around
	_caption = caption
	# 隣のマス＝囲みユニットが立っておらず、囲みユニットのどれかに隣接している周り6マス。
	_beside = []
	for h in Hex.neighbors(CENTER):
		if _occupied.has(h):
			continue
		for o in _occupied:
			if Hex.neighbors(o).has(h):
				_beside.append(h)
				break
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var hexes: Array[Vector2i] = [CENTER]
	hexes.append_array(Hex.neighbors(CENTER))

	# 置くヘックスの外接矩形（単位＝ヘックスの外接円半径 1）を枠に収める倍率。レシピ図と同じ組み方。
	# 係数を出すぶんは下に空ける＝ヘックスと文字が重ならない。
	var band := CAPTION_BAND if _caption != "" else 0.0
	var box := Vector2(size.x, size.y - band)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for h in hexes:
		var c := Hex.to_pixel(h, 1.0)
		lo = lo.min(c - Vector2(1.0, Hex.SQRT3 * 0.5))
		hi = hi.max(c + Vector2(1.0, Hex.SQRT3 * 0.5))
	var span := hi - lo
	var s := minf(box.x / span.x, box.y / span.y)
	var origin := (box - span * s) * 0.5 - lo * s

	for h in hexes:
		var center := origin + Hex.to_pixel(h, s)
		var corners := PackedVector2Array()
		for k in 6:
			var a := deg_to_rad(60.0 * k)
			corners.append(center + Vector2(cos(a), sin(a)) * s)
		# 中央（囲まれている駒）は塗らない＝塗ってあるマスが「数えているマス」だと読める。
		if _occupied.has(h):
			draw_colored_polygon(corners, FILL_OCCUPIED)
		elif _beside.has(h):
			draw_colored_polygon(corners, FILL_THREATENED)
		corners.append(corners[0])
		draw_polyline(corners, HEX_LINE, HEX_LINE_WIDTH, true)
		# 数字を置くマスの駒は上へ寄せる＝足元に数字が重ならない。
		var lift := Vector2(0.0, -s * PIECE_LIFT) if _occupied.has(h) else Vector2.ZERO
		_draw_piece(_texture_at(h), center + lift, s)
		if _occupied.has(h):
			_draw_text(LABEL_OCCUPIED, center + Vector2(0.0, s * LABEL_DROP), LABEL_SIZE, LABEL_COLOR)
		elif _beside.has(h):
			_draw_text(LABEL_THREATENED, center, LABEL_SIZE, LABEL_COLOR)

	if _caption != "":
		_draw_text(_caption, Vector2(size.x * 0.5, size.y - band * 0.5), CAPTION_SIZE, CAPTION_COLOR)

## そのマスに置く駒（無ければ null）。
func _texture_at(hex: Vector2i) -> Texture2D:
	if hex == CENTER:
		return _center
	var i := _occupied.find(hex)
	return _around[i] if i >= 0 and i < _around.size() else null

## 文字1つ。渡した点を中央に置く。
func _draw_text(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_font("font")
	if font == null:
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := at - Vector2(w * 0.5, -float(font_size) * 0.35)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## 駒1つ。内接矩形（幅 1.5s・高さ √3 s）に比率を保って収める（レシピ図と同じ）。
func _draw_piece(tex: Texture2D, center: Vector2, s: float) -> void:
	if tex == null:
		return
	var box := Vector2(1.5, Hex.SQRT3) * s * ART_FIT
	var ts := tex.get_size()
	var fit := minf(box.x / ts.x, box.y / ts.y)
	var draw_size := ts * fit
	draw_texture_rect(tex, Rect2(center - draw_size * 0.5, draw_size), false)
