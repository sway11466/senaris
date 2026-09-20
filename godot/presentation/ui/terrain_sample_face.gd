extends Control
class_name TerrainSampleFace
## 情報板の地形タブに出す、立っているマスの地形の見本（presentation）。
## 盤と同じPNGを描く：足場のヘックス1枚と、その中心に足元を合わせて立つオブジェクト（拠点・岩山
## など）の立ち絵。大小関係は盤と同じ＝ヘックスの幅 2R に対して立ち絵のキャンバス高さは
## BoardTerrainRenderer.CANVAS_TILES（3.75R）。ヘックスは盤のカメラの俯角ぶん縦に潰し、立ち絵は
## 盤と同じく正対（潰さない）＝盤で見えている姿に寄せる。
## 描く物は面の上端から詰める＝立ち絵があればその頭が上端、無ければヘックスの上辺が上端。
## 立ち絵のキャンバスは上に余白があるので、絵の実体の上端（used_rect）で詰める。
## 仕様 → doc/gdd/uiux.md タブ

const HEX_W := 120.0  # ヘックスの幅（2R）。面の幅より狭く取り、立ち絵の左右のはみ出しを面の中に収める

## テクスチャ → 絵の実体の上端（キャンバスの上端から px）。画像を読むのは重いので1枚ごとに覚える。
static var _art_top := {}

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

## 描く物の高さ（立ち絵の頭からヘックスの下辺まで）。面の高さはこれに合わせてもらう。
func picture_height() -> float:
	if not has_picture():
		return 0.0
	return _foot_y() + _hex_h() * 0.5

func _draw() -> void:
	if not has_picture():
		return
	var hex_h := _hex_h()
	var cx := size.x * 0.5
	var foot_y := _foot_y()
	if _tile != null:
		draw_texture_rect(_tile, Rect2(cx - HEX_W * 0.5, foot_y - hex_h * 0.5, HEX_W, hex_h), false)
	if _object != null:
		var canvas_h := _canvas_h()
		var canvas_w := canvas_h * float(_object.get_width()) / float(_object.get_height())
		draw_texture_rect(_object, Rect2(cx - canvas_w * 0.5, foot_y - canvas_h, canvas_w, canvas_h), false)

## ヘックスの高さ＝外接矩形 2R × √3R を俯角ぶん潰す。
func _hex_h() -> float:
	return HEX_W * sqrt(3.0) * 0.5 * sin(deg_to_rad(BoardCamera.PITCH_DEG))

## 立ち絵のキャンバスの高さ（面の px）。
func _canvas_h() -> float:
	return HEX_W * 0.5 * BoardTerrainRenderer.CANVAS_TILES

## 足元（＝ヘックスの中心）の y。立ち絵があれば絵の実体の頭が面の上端に来る位置、無ければ
## ヘックスの上辺が上端に来る位置。
func _foot_y() -> float:
	if _object == null:
		return _hex_h() * 0.5
	var top_px := _art_top_px(_object)
	return _canvas_h() * (1.0 - top_px / float(_object.get_height()))

## 絵の実体の上端（キャンバス上端からの px）。透明な余白を飛ばして頭の位置を取る。
static func _art_top_px(tex: Texture2D) -> float:
	if _art_top.has(tex):
		return _art_top[tex]
	var top := 0.0
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		top = float(img.get_used_rect().position.y)
	_art_top[tex] = top
	return top
