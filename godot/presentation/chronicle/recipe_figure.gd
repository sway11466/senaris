extends Control
class_name ChronicleRecipeFigure
## レシピの図＝形どおりのヘックス配置に要るスキンの盤の絵を置いたもの（拡大カードの上段）。
## 仕様 → doc/gdd/chronicle.md 陣形スキル
##
## 形ごとに配置を1つ決めて描く。盤と同じフラットトップの axial（Hex.to_pixel）。対象の周りを見る形
## （斥候型・背後型）は対象の敵ヘクスも描き、敵の代表の駒（ゴブリン）を置く。絵は紙に直接描く
## （ノードを積まない）。

## 形 → 置く axial の並び。先頭が発動者。
## triangle＝相互隣接の3つ／escort＝発動者に隣接する2つ（位置は問わないので一例）／cluster＝発動者を囲む4つ（5体の最低人数）
## ／spotter＝発動者（弓兵）は対象から距離2、斥候は対象に隣接し発動者には隣接しない（2人が隣り合わなくてよいことが読める）。
## ／line＝一直線の3つ。発動者を真ん中に置く＝列のどこからでも発動できることが読める。
const LAYOUTS := {
	"triangle": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
	"escort": [Vector2i(0, 0), Vector2i(-1, 1), Vector2i(1, 0)],
	"cluster": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 0)],
	"spotter": [Vector2i(0, 0), Vector2i(2, 0)],
	"line": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0)],
}
## 対象を取る形 → 対象の敵ヘクスの axial。無い形は載せない。
const TARGETS := {
	"spotter": Vector2i(2, -1),
}
const HEX_FILL := Color(0.24, 0.16, 0.09, 0.07)  # インクを薄く
const HEX_LINE := Color(0.40, 0.30, 0.20, 0.9)   # TavernTheme.INK_SOFT
const HEX_LINE_WIDTH := 1.5
const ART_FIT := 0.78  # 絵を収める箱＝ヘックスの内接矩形に対する比

var _shape := ""
var _textures: Array = []  # Texture2D の並び（null＝絵が未用意）。LAYOUTS の順に置く
var _target: Texture2D = null  # 対象の敵ヘクスに置く駒の絵（TARGETS に無い形では使わない）

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## target＝対象の敵ヘクスに置く駒の絵。呼び手は常に渡し、使うかは形（TARGETS）が決める。
func setup(shape: String, textures: Array, target: Texture2D) -> void:
	_shape = shape
	_textures = textures
	_target = target
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var hexes: Array = (LAYOUTS.get(_shape, []) as Array).duplicate()
	var textures: Array = _textures.duplicate()
	var n := mini(hexes.size(), textures.size())
	if n == 0:
		return
	# 対象を取る形は敵ヘクスを末尾に足す（参加者と同じ描き方＝ヘックス＋駒の絵）。
	if TARGETS.has(_shape):
		hexes = hexes.slice(0, n)
		textures = textures.slice(0, n)
		hexes.append(TARGETS[_shape])
		textures.append(_target)
		n += 1
	# 置くヘックスの外接矩形（単位＝ヘックスの外接円半径 1）を枠に収める倍率
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in n:
		var c := Hex.to_pixel(hexes[i], 1.0)
		lo = lo.min(c - Vector2(1.0, Hex.SQRT3 * 0.5))
		hi = hi.max(c + Vector2(1.0, Hex.SQRT3 * 0.5))
	var span := hi - lo
	var s := minf(size.x / span.x, size.y / span.y)
	var origin := (size - span * s) * 0.5 - lo * s

	for i in n:
		var center := origin + Hex.to_pixel(hexes[i], s)
		var corners := PackedVector2Array()
		for k in 6:
			var a := deg_to_rad(60.0 * k)
			corners.append(center + Vector2(cos(a), sin(a)) * s)
		draw_colored_polygon(corners, HEX_FILL)
		corners.append(corners[0])
		draw_polyline(corners, HEX_LINE, HEX_LINE_WIDTH, true)
		var tex: Texture2D = textures[i]
		if tex == null:
			continue
		# 内接矩形（幅 1.5s・高さ √3 s）に比率を保って収める
		var box := Vector2(1.5, Hex.SQRT3) * s * ART_FIT
		var ts := tex.get_size()
		var fit := minf(box.x / ts.x, box.y / ts.y)
		var draw_size := ts * fit
		draw_texture_rect(tex, Rect2(center - draw_size * 0.5, draw_size), false)
