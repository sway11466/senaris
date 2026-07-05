extends RefCounted
class_name TavernTheme
## 酒場の依頼ボード風テーマの部品工場。方向性 → doc/gdd/stage_select.md
## 本番アート差し替え前のプロシージャル・プレースホルダ（木壁・木板・羊皮紙・封蝋・焼き印）。
## 画像アセットに依存しない＝ColorRect/StyleBox/グラデ/記号で"それっぽさ"を出す。
## 本番はここが返す部品を画像ベースに差し替えればセレクト画面側は無改修。

# --- 色（暖色の木＋クリーム羊皮紙＋蝋の赤＋焼き印の茶） ---
const WOOD_BASE := Color(0.22, 0.14, 0.09)
const WOOD_SEAM := Color(0.10, 0.06, 0.03)
const BOARD_WOOD := Color(0.30, 0.19, 0.11)
const BOARD_FRAME := Color(0.15, 0.09, 0.04)
const PARCHMENT := Color(0.87, 0.79, 0.62)
const PARCHMENT_EDGE := Color(0.60, 0.48, 0.32)
const INK := Color(0.24, 0.16, 0.09)
const INK_SOFT := Color(0.40, 0.30, 0.20)
const WAX := Color(0.56, 0.13, 0.11)
const BRAND := Color(0.72, 0.50, 0.20)  # 焼き印（危険度など）

# --- 酒場の壁（木の板＋暖色グロー＋ビネット） ---
## 全画面の背景ノードを返す（コーディネーターが最背面に置く）。クリックは透過。
static func wall_background() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var planks := _Planks.new()
	planks.set_anchors_preset(Control.PRESET_FULL_RECT)
	planks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(planks)

	# 上中央の暖色グロー（ランタン）＝加算合成でふわっと明るく
	var glow := TextureRect.new()
	glow.texture = _radial(Color(1.0, 0.82, 0.48, 0.22), Color(1.0, 0.82, 0.48, 0.0))
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_top = -0.35 * 720.0  # 上に寄せてランタン光を上方から落とす
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	root.add_child(glow)

	# 四隅ビネット（中央透明→周辺を暗く）で奥行き
	var vig := TextureRect.new()
	vig.texture = _radial(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.55))
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(vig)
	return root

## 中央→外周のラジアルグラデーション（ビネット・グロー用）。
static func _radial(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 256
	t.height = 256
	return t

# --- StyleBox 部品 ---

## 依頼ボード本体（木板＋太い枠＋影）。
static func board_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOARD_WOOD
	sb.set_border_width_all(12)
	sb.border_color = BOARD_FRAME
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	sb.shadow_size = 16
	sb.set_content_margin_all(20)
	return sb

## 羊皮紙の貼り紙（クリーム地＋薄縁＋落ち影）。ボタンの各状態に流用する。
static func parchment_stylebox(bright := 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCHMENT * Color(bright, bright, bright, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = PARCHMENT_EDGE
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(3, 5)
	sb.set_content_margin_all(0)
	return sb

## 小さな木の看板（見出し用プレート）。
static func plaque_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.11, 0.06)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.34, 0.23, 0.12)
	sb.set_corner_radius_all(5)
	sb.set_content_margin(SIDE_LEFT, 18)
	sb.set_content_margin(SIDE_RIGHT, 18)
	sb.set_content_margin(SIDE_TOP, 6)
	sb.set_content_margin(SIDE_BOTTOM, 6)
	return sb

# --- 装飾パーツ ---

## 封蝋のピン（貼り紙を留める赤い蝋）。
static func wax_seal(diameter := 26.0) -> Control:
	var seal := Panel.new()
	seal.custom_minimum_size = Vector2(diameter, diameter)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = WAX
	sb.set_corner_radius_all(int(diameter / 2.0))
	sb.set_border_width_all(2)
	sb.border_color = Color(0.34, 0.06, 0.05)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	sb.shadow_size = 3
	seal.add_theme_stylebox_override("panel", sb)
	return seal

## 焼き印スタンプ（討伐済／危険度など）。傾けて押した風。
static func stamp(text: String, color: Color, tilt := -7.0) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.12)
	sb.set_border_width_all(2)
	sb.border_color = color
	sb.set_corner_radius_all(4)
	sb.set_content_margin(SIDE_LEFT, 8)
	sb.set_content_margin(SIDE_RIGHT, 8)
	sb.set_content_margin(SIDE_TOP, 2)
	sb.set_content_margin(SIDE_BOTTOM, 2)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 18)
	p.add_child(l)
	p.rotation_degrees = tilt
	return p

## タグの蝋チップ（羊皮紙になじむ茶系）。
static func tag_chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.42, 0.30, 0.16, 0.35)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.42, 0.30, 0.16, 0.7)
	sb.set_corner_radius_all(6)
	sb.set_content_margin(SIDE_LEFT, 8)
	sb.set_content_margin(SIDE_RIGHT, 8)
	sb.set_content_margin(SIDE_TOP, 2)
	sb.set_content_margin(SIDE_BOTTOM, 2)
	chip.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", INK)
	chip.add_child(label)
	return chip

## 木の板を縦の板材＋継ぎ目で描く内部クラス（プロシージャル木壁）。
class _Planks extends Control:
	const PLANK_W := 196.0
	const SHADES := [
		Color(0.22, 0.14, 0.09), Color(0.25, 0.16, 0.10),
		Color(0.20, 0.12, 0.075), Color(0.24, 0.15, 0.095),
	]

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var x := 0.0
		var i := 0
		while x < w:
			draw_rect(Rect2(x, 0.0, PLANK_W, h), SHADES[i % SHADES.size()])
			draw_rect(Rect2(x + PLANK_W - 2.0, 0.0, 2.0, h), Color(0.10, 0.06, 0.03))  # 継ぎ目
			x += PLANK_W
			i += 1
