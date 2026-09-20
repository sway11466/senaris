extends Control
class_name ChronicleFigureFace
## 盤の絵を盤と同じ大小関係で紙に載せる面（ユニット章の格子）。
## 仕様 → doc/gdd/chronicle.md ユニット 見せ方
##
## 盤の絵は 384 角のキャンバスに足元を下端・左右中央で焼いてあり、絵の高さ＝200×倍率
## （doc/art/units.md キャンバスが大きさの基準）。非透過部分で切り抜いて枠に伸ばすと全員が
## 同じ背丈になるので、切り抜かずにキャンバスの下端 WINDOW_H px を面の高さに当て、足元を面の
## 下端に揃えて描く。倍率 WINDOW_H/200 までの駒が面に収まり、超える駒は面＝紙からはみ出す。
## はみ出しは切らない（載せる側は clip_contents を切っておく）。

const WINDOW_H := 260.0  # 面の高さに当てるキャンバスの下端からの px（200×1.3）

var _tex: Texture2D = null

## 情報板は面を1つ作って駒ごとに setup を呼び直す＝接続は1回だけ・絵を差し替えたら描き直す。
func setup(tex: Texture2D, silhouette: bool) -> void:
	_tex = tex
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if silhouette:
		modulate = ChronicleStyle.SILHOUETTE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	var s := size.y / WINDOW_H
	var w := _tex.get_width() * s
	var h := _tex.get_height() * s
	draw_texture_rect(_tex, Rect2((size.x - w) * 0.5, size.y - h, w, h), false)
