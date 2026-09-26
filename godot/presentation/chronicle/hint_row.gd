extends Control
class_name ChronicleHintRow
## 未解放の陣形スキルの面＝要るユニットの黒塗りを人数ぶん横に並べる。仕様 → doc/gdd/chronicle.md 陣形スキル
##
## 絵は実体で切り抜いたもの（ArtCrop）を渡す。全員を同じ高さに揃え、並びの幅が面に収まる最大の高さで
## 描く＝縦横比の違う駒が並んでも背丈はそろい、5人並んでも重ならない。並びは面の中央に置く。
## 絵が未用意の駒は PLACEHOLDER_ASPECT の枠に「？」を描く。

const PLACEHOLDER_ASPECT := 0.5  # 絵が未用意の駒の枠の幅÷高さ

var _texes: Array = []  # Texture2D か null（未用意）
var _gap := 0.0
var _placeholder := ""

func setup(texes: Array, gap: float, placeholder: String) -> void:
	_texes = texes
	_gap = gap
	_placeholder = placeholder
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate = ChronicleStyle.SILHOUETTE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	queue_redraw()

func _aspect(tex: Texture2D) -> float:
	if tex == null:
		return PLACEHOLDER_ASPECT
	return float(tex.get_width()) / float(tex.get_height())

func _draw() -> void:
	if _texes.is_empty():
		return
	var sum := 0.0
	for t in _texes:
		sum += _aspect(t)
	var gaps := _gap * (_texes.size() - 1)
	var h := minf(size.y, (size.x - gaps) / sum)
	if h <= 0.0:
		return
	var x := (size.x - (sum * h + gaps)) * 0.5
	var y := (size.y - h) * 0.5
	for t in _texes:
		var w := _aspect(t) * h
		if t == null:
			var font := get_theme_default_font()
			var fs := get_theme_default_font_size()
			var ts := font.get_string_size(_placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, Vector2(x + (w - ts.x) * 0.5, y + (h + ts.y) * 0.5 - font.get_descent(fs)),
				_placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		else:
			draw_texture_rect(t, Rect2(x, y, w, h), false)
		x += w + _gap
