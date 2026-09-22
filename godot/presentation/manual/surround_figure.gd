extends Control
class_name ManualSurroundFigure
## 包囲の図＝囲まれた駒を中央に置き、囲んでいる2体を向かい合わせ（最小包囲）に並べたもの。
## 数え方の2通り（敵がいるマス／空きだが敵に隣接しているマス）を塗りの濃さで見せる。
## 仕様 → doc/gdd/manual.md 絵の持ち方 ／ 数え方 → doc/gdd/combat.md 包囲効果
##
## クロニクルのレシピ図（chronicle/recipe_figure.gd）と同じ描き方＝紙に直接描く（ノードを積まない）。
## 盤の絵を撮らないのは、盤では地形や他の駒が一緒に写って、どのマスを数えているかが読めないため。
##
## 図に文字は入れない＝言語で変わらない。色が何を指すかは本文（manual.csv）が言う。

const CENTER := Vector2i(0, 0)
## 囲む2体を置くマス＝中央を挟んで正反対（対角2体＝包囲が成立する最小の形）。
const OCCUPIED := [Vector2i(-1, 0), Vector2i(1, 0)]
## 残りの4マス＝空きだが、置いた2体のどちらかに隣接している。
const THREATENED := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(-1, 1)]

## 塗りは同じ色の濃淡で持つ＝別の色にすると「別のもの」に見える。数え方は同じで重みだけが
## 違う（8% と 4%）ので、濃さの差で「同じものが薄く効く」と読ませる。
const FILL_OCCUPIED := Color(0.86, 0.36, 0.30, 0.45)
const FILL_THREATENED := Color(0.86, 0.36, 0.30, 0.16)
const HEX_LINE := Color(0.82, 0.82, 0.82, 0.55)
const HEX_LINE_WIDTH := 1.5
const ART_FIT := 0.78  # 駒を収める箱＝ヘックスの内接矩形に対する比（レシピ図と同値）

var _center: Texture2D = null
var _around: Array = []  # OCCUPIED の順に置く Texture2D（null＝絵が未用意）

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## center＝囲まれている駒、around＝囲んでいる駒（OCCUPIED の順）。
func setup(center: Texture2D, around: Array) -> void:
	_center = center
	_around = around
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var hexes: Array[Vector2i] = [CENTER]
	hexes.append_array(OCCUPIED)
	hexes.append_array(THREATENED)

	# 置くヘックスの外接矩形（単位＝ヘックスの外接円半径 1）を枠に収める倍率。レシピ図と同じ組み方。
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
		# 中央（囲まれている駒）は塗らない＝塗ってあるマスが「数えているマス」だと読める。
		if OCCUPIED.has(h):
			draw_colored_polygon(corners, FILL_OCCUPIED)
		elif THREATENED.has(h):
			draw_colored_polygon(corners, FILL_THREATENED)
		corners.append(corners[0])
		draw_polyline(corners, HEX_LINE, HEX_LINE_WIDTH, true)
		_draw_piece(_texture_at(h), center, s)

## そのマスに置く駒（無ければ null）。
func _texture_at(hex: Vector2i) -> Texture2D:
	if hex == CENTER:
		return _center
	var i := OCCUPIED.find(hex)
	return _around[i] if i >= 0 and i < _around.size() else null

## 駒1つ。内接矩形（幅 1.5s・高さ √3 s）に比率を保って収める（レシピ図と同じ）。
func _draw_piece(tex: Texture2D, center: Vector2, s: float) -> void:
	if tex == null:
		return
	var box := Vector2(1.5, Hex.SQRT3) * s * ART_FIT
	var ts := tex.get_size()
	var fit := minf(box.x / ts.x, box.y / ts.y)
	var draw_size := ts * fit
	draw_texture_rect(tex, Rect2(center - draw_size * 0.5, draw_size), false)
