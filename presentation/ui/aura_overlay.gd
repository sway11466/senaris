extends TextureRect
class_name AuraOverlay
## 陣営全体バフ（ホーリーアリア等）が効いている間、画面の外周から光を差し込ませる。
## 盤の情報層（地形・駒・範囲塗り）に一切触れないのが狙い＝中央は素通しで、縁だけ明るい。
## 画面全体に敷く（右の情報ボックスも含む）。盤エリアだけに敷くと、盤の右端に光の帯が立ち、
## その真横の暗い情報ボックスとの境目で光が断ち切られて見えるため。詳細 → doc/gdd/formations.md

const HOLY_COLOR := Color(1.00, 0.88, 0.55)  # 加護の光（金）。陣営では振らない＝範囲塗りの色語彙と混ぜない
const ALPHA := 0.45       # 濃さ（明滅はしない＝盤の読み取りを揺らさない）
const EDGE_POWER := 3.5   # 縁への寄り具合。大きいほど外周に張り付く
const TEX_SIZE := 192     # 生成テクスチャの解像度（引き伸ばして使う）

# 辺ごとの強さ。上から差し込む光にする＝上が強く、左右は控えめ、下は出さない。
# 四方均一だと「囲まれた枠」に見えて、光源の向きが感じられないため。
var edge_top := 1.0
var edge_side := 0.45
var edge_bottom := 0.0

func _ready() -> void:
	rebuild()
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤のクリックを吸わない
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # 盤を暗くせず、光として足す
	material = m
	hide()

## 画面いっぱいに敷く。ビューポートのリサイズ時にも呼ぶ。
func fit_to(vp: Vector2) -> void:
	position = Vector2.ZERO
	size = vp

## 光を出す。stop() まで出しっぱなし（明滅しない）。
func play(color: Color, vp: Vector2) -> void:
	modulate = Color(color.r, color.g, color.b, ALPHA)
	fit_to(vp)
	show()

func stop() -> void:
	hide()

## 辺の重みを変えたらこれを呼ぶ（テクスチャを作り直す）。
func rebuild() -> void:
	texture = _make_edge_texture()

## 外周が明るく中央が透明なテクスチャ。辺ごとに重みを変えられる＝光の差す向きを作れる。
## 各辺の寄与を出して一番強いものを採る（足し合わせると角だけ不自然に明るくなる）。
func _make_edge_texture() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := float(TEX_SIZE) * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var a := maxf(
				maxf(_edge(float(y) / half, edge_top),
					_edge(float(TEX_SIZE - 1 - y) / half, edge_bottom)),
				maxf(_edge(float(x) / half, edge_side),
					_edge(float(TEX_SIZE - 1 - x) / half, edge_side)))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

## 1辺の寄与。d＝その辺からの距離（0＝縁・1＝中央）、weight＝辺の強さ。
func _edge(d: float, weight: float) -> float:
	if weight <= 0.0:
		return 0.0
	return weight * pow(1.0 - clampf(d, 0.0, 1.0), EDGE_POWER)
