extends RefCounted
class_name TavernTheme
## 酒場の依頼ボード風テーマの部品工場。方向性 → doc/gdd/stage_select.md
## 材質だけ画像・構造と光はコード（ハイブリッド）。テクスチャは autowire で差し込む：
## assets/menu/<name>.png が在れば使い、無ければプロシージャル（ベタ塗り）へフォールバック。
## ＝画像スロット制。絵を置くだけで格上げされ、セレクト画面側は無改修（UnitSkin と同思想）。
## 素材スロット: wall（木壁・タイル）／board（依頼ボード板）／list_board（ステージ一覧の背板）／
## parchment（貼り紙）／grunge（汚し）。
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

## 彫り枠の厚み＝board.png 実測（内側コーナー (82,76)-(1325,689) / 画像1408x768）。
## ナインパッチの固定幅であり、左右はそのまま内側余白にも使う（＝貼り紙の置き場が貼り付け面と一致する）。
const BOARD_EDGE_LEFT := 82
const BOARD_EDGE_TOP := 76
const BOARD_EDGE_RIGHT := 83
const BOARD_EDGE_BOTTOM := 79
## 上下の内側余白＝上梁（ボード名）・下梁に貼り紙を被せないための余裕。枠の厚みより広く取る。
const BOARD_PAD_V := 96

## 依頼ボード本体（木板＋太い枠＋影）。board.png があればテクスチャ、無ければベタ塗り。
static func board_stylebox() -> StyleBox:
	var tex := _tex("board")
	if tex != null:
		var sb := _texture_box(tex, 80, 0)  # 縁と内側余白は下で四辺個別に入れる
		# 一様なまっすぐ枠なので、辺はタイルでなく素直に引き伸ばす（節が無いので伸びても崩れない）。
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.set_texture_margin(SIDE_LEFT, BOARD_EDGE_LEFT)
		sb.set_texture_margin(SIDE_TOP, BOARD_EDGE_TOP)
		sb.set_texture_margin(SIDE_RIGHT, BOARD_EDGE_RIGHT)
		sb.set_texture_margin(SIDE_BOTTOM, BOARD_EDGE_BOTTOM)
		# 左右は枠の厚みと同値＝置き場の幅が貼り付け面ちょうど（画面1280で1099px）になる。
		# 紙との隙間はここでは足さない＝画面側（CampaignSelect）が持つ。
		sb.set_content_margin(SIDE_LEFT, BOARD_EDGE_LEFT)
		sb.set_content_margin(SIDE_RIGHT, BOARD_EDGE_RIGHT)
		sb.set_content_margin(SIDE_TOP, BOARD_PAD_V)
		sb.set_content_margin(SIDE_BOTTOM, BOARD_PAD_V)
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

## ステージ一覧の背板（縦長・四隅に鉄具）。list_board.png があればテクスチャ、無ければ依頼ボードと同じ地。
## ナインパッチの固定幅は56px＝四隅の鉄具（実測で一辺52pxまで）を割らない大きさ。枠そのものは約26pxで、
## 残りは内側の板が入る。辺は board と同じく引き伸ばす（一様なまっすぐ枠なので伸びても崩れない）。
static func list_board_stylebox() -> StyleBox:
	var tex := _tex("list_board")
	if tex != null:
		var sb := _texture_box(tex, 56, LIST_BOARD_PAD)
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		return sb
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOARD_WOOD
	sb.set_border_width_all(10)
	sb.border_color = BOARD_FRAME
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(LIST_BOARD_PAD)
	return sb

## 背板の内側余白＝行を枠に被せないための固定値（枠約26px＋余白）。
const LIST_BOARD_PAD := 36

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
		# 横だけ引き伸ばす＝紙の実寸(300)より POSTER_SIZE.x(341) が広く、タイルだと中途半端な
		# 繰り返しの継ぎ目が右寄りに出る（実測）。繊維の伸びは 1.2 倍弱で目に付かない。
		# 縦は実寸と同じなのでタイルのままで 1:1。
		sbt.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
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

## 看板の彫り枠の角の丸み（px）。枠の下に絵を敷く側（勝利イラストなど）は、
## 四隅が枠からはみ出さないよう同じ値で角を丸める。
const FRAME_CORNER_RADIUS := 6

## 枠を持たない絵（扉絵など）の角の丸み（px）。枠に合わせる必要が無いので少し強めに丸める
## ＝小さい貼り紙の絵でも丸みが見える。
const ART_CORNER_RADIUS := 8

## 四隅を丸めて描くシェーダ。角丸矩形の距離場でアルファを削る（マスク用のノードを足さない）。
## 位置は UV でなく VERTEX（＝コントロール内の px）で取る＝KEEP_ASPECT_COVERED のように
## UV が 0..1 にならない stretch_mode でも効く。smoothstep の 1px 幅がアンチエイリアス。
const _ROUNDED_SHADER := """
shader_type canvas_item;
uniform vec2 rect_px;     // 描画矩形の実寸（px）
uniform float radius_px;  // 角の半径
varying vec2 v_pos;
void vertex() {
	v_pos = VERTEX;
}
void fragment() {
	vec2 half_px = rect_px * 0.5;
	vec2 q = abs(v_pos - half_px) - (half_px - vec2(radius_px));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius_px;
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, d);
}
"""

## ctrl の四隅を radius（px）で丸めて描くようにする。コンテナが大きさを決めるノードにも、
## 自分で size を入れるノードにもそのまま掛けられる。子ノードには波及しない。
static func round_corners(ctrl: Control, radius: float) -> void:
	var sh := Shader.new()
	sh.code = _ROUNDED_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("radius_px", radius)
	ctrl.material = mat
	# 寸法は draw で渡す。resized はツリーに入る前の変更では飛ばないので取りこぼす
	# （＝絵が丸ごと消える）。描画のたびなら必ず現在の寸法で更新できる。
	ctrl.draw.connect(_feed_rect_px.bind(ctrl, mat))
	_feed_rect_px(ctrl, mat)

## 角丸シェーダに現在の寸法を渡す（round_corners が draw につなぐ）。
static func _feed_rect_px(ctrl: Control, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rect_px", ctrl.size)

## 看板の彫り枠（パネルの最前面に重ねる縁だけの飾り・クリック透過）。
static func signboard_frame() -> Control:
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(4)
	sb.border_color = BOARD_FRAME
	sb.set_corner_radius_all(FRAME_CORNER_RADIUS)
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

## アイコンを収める小さな額（板に彫った窪み＋明るい縁）。中身は content_margin ぶん内側に入る。
## 額を絵に描き込まずアプリ側で嵌めるのは、生成のたびに枠の形が揺らぐため（絵は中身だけを持つ）。
static func icon_frame_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.08, 0.04)  # 板より暗く落として窪みに見せる
	sb.set_border_width_all(2)
	sb.border_color = Color(0.38, 0.26, 0.14)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
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

## 封蝋色の主ボタン（依頼書の「出撃する」など）。
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

## 木の板ボタンを「押せるが選べない」見た目に落とす（未解放のステージ行など）。
## disabled にはしない＝入力を受け取らず拒否音を鳴らせなくなるため（doc/audio/sfx.md）。
## 押しても状態が変わらないよう、normal/hover/pressed に同じ暗い板を当てる。
static func dim_wood_button(b: Button) -> void:
	var dim := _plank_box(0.6)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, dim)
	var dim_font := b.get_theme_color("font_disabled_color", "Button")
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, dim_font)

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

## 画面を一段戻るボタン。押して何かが起きるコマンドなので、メニュー項目と同じ木の板で出す。
## 置き場は画面の左下で全画面共通＝背景の絵に合わせて動かさない（doc/gdd/stage_select.md）。
const BACK_SIZE := Vector2(150, 44)
const BACK_INSET := 24.0

static func back_button(text: String) -> Button:
	var b := wood_button(text)
	b.custom_minimum_size = BACK_SIZE
	return b

## 画面の左下（BACK_INSET の余白）へ置く。戻るボタンの位置を1箇所で決めるための共通処理。
static func place_bottom_left(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 0.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = BACK_INSET
	c.offset_right = BACK_INSET + BACK_SIZE.x
	c.offset_top = -BACK_INSET - BACK_SIZE.y
	c.offset_bottom = -BACK_INSET

## 画面を繰るための小さな道具（カルーセルの矢印）。押すたびに場面が変わるのではなく
## 同じ画面の中身を送るだけなので、コマンド（板ボタン）とは別の無機質なグレーで出す。
static func nav_button(text: String, font_size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78, 0.6))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 0.95))
	b.add_theme_color_override("font_pressed_color", Color(0.65, 0.65, 0.65, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.55, 0.2))
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	return b

## 控えめなインク縁ボタン（依頼書の「別のステージを選ぶ」など・羊皮紙の上に置く）。
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

const STAMP_FONT_PATH := "res://assets/fonts/RockSalt-Regular.ttf"  ## 印・ボード名の手書き風書体
static var _stamp_font: Font = null

## 印の書体＝ボード名と同じ手書き風（RockSalt）。ボードに並ぶ文字と同じ手で書かれた感じにする。
## ラテン文字のみのフォントなので、収録外の字（日本語など）は既定フォントへ落とす（fallbacks）
## ＝翻訳で豆腐にならない。印の文言は短い語を選ぶこと（丸印は語が長いと字が縮む）。
static func stamp_font() -> Font:
	if _stamp_font != null:
		return _stamp_font
	var f := load(STAMP_FONT_PATH) as FontFile
	if f == null:
		return ThemeDB.fallback_font
	f.fallbacks = [ThemeDB.fallback_font]
	_stamp_font = f
	return _stamp_font

## ゴム印スタンプ（DONE／VICTORY・DEFEAT など）。傾けて叩きつけた風＝二重の丸枠＋太らせた字。
## 丸は認印の形＝酒場で押される判子らしさが出る（角印より柔らかく、傾きも自然に見える）。
## インクは半透明で乗せる＝実際の印影と同じく、線の隙間から下地の字が読める（紙を覆っても潰さない）。
## 大きさは font_size で決まり、枠の太さ・余白も比例する。箱は文字から自動算出して正方形にするが、
## 呼び出し側が size/custom_minimum_size を広げれば円もそこまで大きくなる（短辺に内接して描く）。
## 回転・拡縮の軸は中心（叩きつけアニメで中心から落ちる）。
## ink_alpha は下地に応じて選ぶ：紙の字に重ねるなら薄く（既定 0.66＝字が透ける）、
## 絵の上に押すなら濃く（0.9 前後＝絵に負けない）。実測で詰めた値。
## max_diameter > 0 なら円がそこに収まるまで字を縮める。丸印は直径が文字の長さで決まるので、
## 語が伸びても箱を割らないための歯止め（翻訳で "VICTORY"→"SIEG"/"勝利" と長さが変わる）。
## font は既定フォント以外を使いたいとき（null＝既定）。
static func stamp(text: String, color: Color, tilt := -7.0, font_size := 44, ink_alpha := 0.66, max_diameter := 0.0, font: Font = null) -> Control:
	var f: Font = font if font != null else stamp_font()
	var fs := font_size
	if max_diameter > 0.0:
		while fs > 8 and _stamp_metrics(f, text, fs)["d"] > max_diameter:
			fs -= 2
	var m := _stamp_metrics(f, text, fs)
	var s := _Stamp.new()
	s.text = text
	s.ink = Color(color.r, color.g, color.b, ink_alpha)
	s.font_size = fs
	s.font = f
	s.ring_w = m["w"]
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Vector2(m["d"], m["d"])
	s.custom_minimum_size = box
	s.size = box
	s.pivot_offset = box / 2.0
	s.rotation_degrees = tilt
	return s

## 丸印の寸法：直径 d と枠の太さ w。
## 文字は内枠に触ってはいけないので、文字の外接円（横幅と高さの両方を見る）から内半径を決め、
## 枠の太さは直径に比例させる＝長い語で字が縮んでも枠は細らない（枠の迫力を保つ）。
static func _stamp_metrics(font: Font, text: String, font_size: int) -> Dictionary:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var half_w := ts.x * 0.5 + font_size * 0.18  # 文字幅の半分＋左右の余白
	# 高さは行送りではなく大文字の高さで見る。行送りで採ると（手書き書体は特に行間が広い）
	# 円が無駄に膨らみ、上限に当たって字だけ小さくなる＝中身が空いた輪に見える。
	var half_h := font_size * 0.36
	var r_text := maxf(sqrt(half_w * half_w + half_h * half_h), font_size * 0.7)
	var w := maxf(2.0, r_text * 0.09)
	# 内枠（外周から 1.7w 内側）が文字の外接円のさらに外に来るよう余白 1.2w を足す。
	# 足さないと内枠の半径が文字の外接円と一致し、字が枠に必ず触る。
	return { "d": 2.0 * (r_text + w * 3.4), "w": w }

## ゴム印の描画（二重の丸枠＋太字）。円は箱の短辺に内接＝箱を広げれば印も大きくなる。
## 既定フォントに太字が無いので、輪郭を膨らませて（draw_string_outline）字を太らせる。
class _Stamp extends Control:
	var text := ""
	var ink := Color.WHITE
	var font_size := 44
	var font: Font = null
	var ring_w := 0.0  # 外枠の太さ（stamp() が直径から決める。0＝字の大きさから導く）

	func _draw() -> void:
		var w := ring_w if ring_w > 0.0 else maxf(2.0, font_size * 0.11)
		var center := size / 2.0
		var outer_r := minf(size.x, size.y) * 0.5 - w * 0.5
		draw_arc(center, outer_r, 0.0, TAU, 72, ink, w, true)
		draw_arc(center, outer_r - w * 1.7, 0.0, TAU, 72, ink, maxf(1.0, w * 0.38), true)  # 内側の細枠
		if font == null:
			font = ThemeDB.fallback_font
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pos := Vector2((size.x - ts.x) * 0.5, (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
		var ci := get_canvas_item()
		font.draw_string_outline(ci, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(maxf(1.0, font_size * 0.05)), ink)
		font.draw_string(ci, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)

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
