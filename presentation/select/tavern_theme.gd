extends RefCounted
class_name TavernTheme
## 酒場の依頼ボード風テーマの部品工場。方向性 → doc/gdd/stage_select.md
## 材質だけ画像・構造と光はコード（ハイブリッド）。テクスチャは autowire で差し込む：
## assets/menu/<name>.png が在れば使い、無ければプロシージャル（ベタ塗り）へフォールバック。
## ＝画像スロット制。絵を置くだけで格上げされ、セレクト画面側は無改修（UnitSkin と同思想）。
## 素材スロット: wall（木壁・タイル）／board（依頼ボード板）／parchment（貼り紙）／grunge（汚し）。
## 仕様（サイズ・シームレス条件・色味）→ doc/art/menu.md。

const SLOT_DIR := "res://assets/menu/"

## 素材テクスチャを autowire で取得（assets/menu/<name>.png）。無ければ null。
static func _tex(name: String) -> Texture2D:
	var p := "%s%s.png" % [SLOT_DIR, name]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

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

	# 木壁の材質: wall.png があればタイル敷き、無ければプロシージャルな板（_Planks）
	var wall_tex := _tex("wall")
	if wall_tex != null:
		var wall := TextureRect.new()
		wall.texture = wall_tex
		wall.stretch_mode = TextureRect.STRETCH_TILE
		wall.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		wall.set_anchors_preset(Control.PRESET_FULL_RECT)
		wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(wall)
	else:
		var planks := _Planks.new()
		planks.set_anchors_preset(Control.PRESET_FULL_RECT)
		planks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(planks)

	# 汚し/スレのオーバーレイ（grunge.png があれば壁の上に薄く重ねる＝経年感）
	var grunge_tex := _tex("grunge")
	if grunge_tex != null:
		var grunge := TextureRect.new()
		grunge.texture = grunge_tex
		grunge.stretch_mode = TextureRect.STRETCH_TILE
		grunge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		grunge.set_anchors_preset(Control.PRESET_FULL_RECT)
		grunge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grunge.modulate = Color(1.0, 1.0, 1.0, 0.5)  # 透過PNG前提でさらに薄く
		root.add_child(grunge)

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

## 依頼ボード本体（木板＋太い枠＋影）。board.png があればテクスチャ、無ければベタ塗り。
static func board_stylebox() -> StyleBox:
	var tex := _tex("board")
	if tex != null:
		var sb := _texture_box(tex, 80, 96)  # 内側余白96px（貼り紙を枠に被せない）。縁は下で四辺個別に上書き
		# 一様なまっすぐ枠なので、辺はタイルでなく素直に引き伸ばす（節が無いので伸びても崩れない）。
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		# 彫り枠の内側境界＝board.png 実測（内側コーナー (82,76)-(1325,689) / 画像1408x768）。四辺の固定幅。
		sb.set_texture_margin(SIDE_LEFT, 82)
		sb.set_texture_margin(SIDE_TOP, 76)
		sb.set_texture_margin(SIDE_RIGHT, 83)
		sb.set_texture_margin(SIDE_BOTTOM, 79)
		return sb
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOARD_WOOD
	sb.set_border_width_all(12)
	sb.border_color = BOARD_FRAME
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	sb.shadow_size = 16
	sb.set_content_margin_all(20)
	return sb

## 羊皮紙テクスチャの変種一覧（parchment.png＋parchment_2.png/_3.png…を連番プローブ・1回だけ読む）。
## カードごとに違う紙を敷いて「全部同じ貼り紙」を避ける。ポスターは固定サイズなので伸縮の心配はない。
static var _parchment_cache: Array = []
static var _parchment_loaded := false
static func _parchment_texs() -> Array:
	if _parchment_loaded:
		return _parchment_cache
	_parchment_loaded = true
	var texs: Array = []
	var base := "%sparchment.png" % SLOT_DIR
	if ResourceLoader.exists(base):
		texs.append(load(base))
	var n := 2
	while true:
		var p := "%sparchment_%d.png" % [SLOT_DIR, n]
		if not ResourceLoader.exists(p):
			break
		texs.append(load(p))
		n += 1
	_parchment_cache = texs
	return texs

## 羊皮紙の貼り紙。parchment.png（＋parchment_2/_3…）があればテクスチャ、無ければクリーム地＋薄縁＋落ち影。
## seed でカードごとに紙の変種を決定的に選ぶ（冒険譚idのhash等を渡す＝同じカードは常に同じ紙／隣とは違う紙）。
## ボタンの各状態に流用する（同じ seed を渡すこと＝hover で紙が変わらない。bright で hover を少し明るく）。
static func parchment_stylebox(seed := 0, bright := 1.0) -> StyleBox:
	var texs := _parchment_texs()
	if not texs.is_empty():
		var tex: Texture2D = texs[absi(seed) % texs.size()]
		var sbt := _texture_box(tex, 8, 0)
		sbt.modulate_color = Color(bright, bright, bright, 1.0)
		return sbt
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

## 依頼書（出撃確認ダイアログの紙）。parchment_sheet.png があればテクスチャ、無ければクリーム地。
## テクスチャは QuestSheet.SHEET_SIZE と同寸で焼く（中央タイルが1:1）→ doc/art/menu.md
static func sheet_stylebox() -> StyleBox:
	var tex := _tex("parchment_sheet")
	if tex != null:
		return _texture_box(tex, 8, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCHMENT
	sb.set_border_width_all(2)
	sb.border_color = PARCHMENT_EDGE
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(4, 6)
	return sb

## 常設パネル（戦闘画面の右情報エリアなど）＝暗い木の看板。
## 材質ルール: 羊皮紙＝手渡される紙（ダイアログ・依頼書）／木＝常設の面（ボード・パネル）。
## wall.png を暗めに沈めてタイル敷き、無ければベタ塗り木色へフォールバック。
static func signboard_stylebox() -> StyleBox:
	var tex := _tex("wall")
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.modulate_color = Color(0.62, 0.58, 0.55)  # 盤面より一段暗く沈める
		return sb
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.11, 0.07)
	sb.set_corner_radius_all(6)
	return sb

## 看板の彫り枠（パネルの最前面に重ねる縁だけの飾り・クリック透過）。
static func signboard_frame() -> Control:
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(4)
	sb.border_color = BOARD_FRAME
	sb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", sb)
	return frame

## ナインパッチのテクスチャ StyleBox（縁は固定・中央はタイルで伸ばす＝素材が歪まない）。
static func _texture_box(tex: Texture2D, edge: int, content: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, edge)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.set_content_margin_all(content)
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

## 封蝋色の主ボタン（依頼書の「出撃」など）。
static func wax_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.96, 0.90, 0.76))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
	b.add_theme_color_override("font_pressed_color", Color(0.90, 0.82, 0.68))
	b.add_theme_stylebox_override("normal", _wax_box(WAX))
	b.add_theme_stylebox_override("hover", _wax_box(WAX.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _wax_box(WAX.darkened(0.2)))
	return b

static func _wax_box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = Color(0.34, 0.06, 0.05)
	sb.set_corner_radius_all(6)
	sb.set_content_margin(SIDE_LEFT, 24)
	sb.set_content_margin(SIDE_RIGHT, 24)
	sb.set_content_margin(SIDE_TOP, 8)
	sb.set_content_margin(SIDE_BOTTOM, 8)
	return sb

## 木の板ボタン（看板・HUD用）。plank.png があれば1枚板、無ければベタ塗り木色。
## ナインパッチ縁幅（L6/T5/R6/B5）は plank.png（256x96）のベベル実測
## ＝master（1376x768・L31/T41/R39/B39）を縮小した値。絵を差し替えたら測り直す。
static func wood_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color(0.90, 0.82, 0.62))
	b.add_theme_color_override("font_hover_color", Color(0.98, 0.92, 0.74))
	b.add_theme_color_override("font_pressed_color", Color(0.80, 0.72, 0.54))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.50, 0.42))
	b.add_theme_stylebox_override("normal", _plank_box(1.0))
	b.add_theme_stylebox_override("hover", _plank_box(1.12))
	b.add_theme_stylebox_override("pressed", _plank_box(0.85))
	b.add_theme_stylebox_override("disabled", _plank_box(0.65))
	return b

static func _plank_box(bright: float) -> StyleBox:
	var tex := _tex("plank")
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.set_texture_margin(SIDE_LEFT, 6)
		sb.set_texture_margin(SIDE_TOP, 5)
		sb.set_texture_margin(SIDE_RIGHT, 6)
		sb.set_texture_margin(SIDE_BOTTOM, 5)
		# ベベルはまっすぐ・低コントラストの木目なので、辺も中央も素直に引き伸ばす
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.modulate_color = Color(bright, bright, bright, 1.0)
		sb.set_content_margin(SIDE_LEFT, 16)
		sb.set_content_margin(SIDE_RIGHT, 16)
		sb.set_content_margin(SIDE_TOP, 6)
		sb.set_content_margin(SIDE_BOTTOM, 6)
		return sb
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.16, 0.10) * Color(bright, bright, bright, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.13, 0.08, 0.05)
	sb.set_corner_radius_all(4)
	sb.set_content_margin(SIDE_LEFT, 16)
	sb.set_content_margin(SIDE_RIGHT, 16)
	sb.set_content_margin(SIDE_TOP, 6)
	sb.set_content_margin(SIDE_BOTTOM, 6)
	return sb

## 控えめなインク縁ボタン（依頼書の「戻る」など・羊皮紙の上に置く）。
static func ink_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK_SOFT)
	b.add_theme_stylebox_override("normal", _ink_box(Color(INK, 0.0)))
	b.add_theme_stylebox_override("hover", _ink_box(Color(INK, 0.08)))
	b.add_theme_stylebox_override("pressed", _ink_box(Color(INK, 0.15)))
	return b

static func _ink_box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = INK_SOFT
	sb.set_corner_radius_all(6)
	sb.set_content_margin(SIDE_LEFT, 24)
	sb.set_content_margin(SIDE_RIGHT, 24)
	sb.set_content_margin(SIDE_TOP, 8)
	sb.set_content_margin(SIDE_BOTTOM, 8)
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
