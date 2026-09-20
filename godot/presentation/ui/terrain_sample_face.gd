extends Control
class_name TerrainSampleFace
## 情報板の地形タブ・空きマスの地形表示に出す、そのマスの地形の見本（presentation）。
## 盤と同じPNGを描く：足場のヘックス1枚と、その中心に足元を合わせて立つオブジェクト（拠点・岩山
## など）の立ち絵。大小関係は盤と同じ＝ヘックスの幅 2R に対して立ち絵のキャンバス高さは
## BoardTerrainRenderer.CANVAS_TILES（3.75R）。ヘックスは盤のカメラの俯角ぶん縦に潰し、立ち絵は
## 盤と同じく正対（潰さない）＝盤で見えている姿に寄せる。
## ヘックスは面の下端に置く＝立ち絵の有無・背の高さで動かない。背の高い立ち絵は面の上へはみ出す
## （面は板の子で切り落とされない）。仕様 → doc/gdd/uiux.md タブ

const HEX_W := 96.0  # ヘックスの幅（2R）。面の幅より狭く取り、立ち絵の左右のはみ出しを面の中に収める

var _tile: Texture2D = null    # 足場のヘックス（平面タイル）。無ければ描かない
var _object: Texture2D = null  # 足場の上に立つ絵（384角キャンバス・足元が下端）。無ければ描かない

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 絵の面＝押す物ではない（掴んだら板が動く）
	resized.connect(queue_redraw)

func setup(tile: Texture2D, object: Texture2D) -> void:
	_tile = tile
	_object = object
	queue_redraw()

func has_picture() -> bool:
	return _tile != null or _object != null

func _draw() -> void:
	if not has_picture():
		return
	# ヘックスの高さ＝外接矩形 2R × √3R を俯角ぶん潰す
	var hex_h := HEX_W * sqrt(3.0) * 0.5 * sin(deg_to_rad(BoardCamera.PITCH_DEG))
	var cx := size.x * 0.5
	var hex_top := size.y - hex_h
	if _tile != null:
		draw_texture_rect(_tile, Rect2(cx - HEX_W * 0.5, hex_top, HEX_W, hex_h), false)
	if _object != null:
		var canvas_h := HEX_W * 0.5 * BoardTerrainRenderer.CANVAS_TILES
		var canvas_w := canvas_h * float(_object.get_width()) / float(_object.get_height())
		var foot_y := hex_top + hex_h * 0.5
		draw_texture_rect(_object, Rect2(cx - canvas_w * 0.5, foot_y - canvas_h, canvas_w, canvas_h), false)
