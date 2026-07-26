extends Control
class_name TurnPlate
## 手番表示の板（presentation）。盤エリアの上端中央に置き、[味方][turn n / limit][敵] を横に並べる。
## 手番側の枠を活性化する（非活性は暗く落とし、活性は陣営色の縁）。状態は持たず main から set_* で流し込む。
## 左右の絵は冒険譚マニフェストの emblem（skin_id）。未指定なら枠を出さず中央だけ見せる。
## 仕様 → doc/gdd/uiux.md（手番表示）

const FRAME := 64.0      # 左右の枠（正方形）
const CENTER_W := 168.0  # 中央のターン数の札
const CENTER_H := 44.0
const GAP := 8.0
const TOP := 12.0        # 画面上端からの余白
const DIM := Color(0.62, 0.62, 0.62)  # 非活性側の暗さ（活性側は縁の色でも分かるので、絵が潰れない程度に留める）
const BUST_TOP := 0.08   # 立ち絵のどこから切るか（高さ比）＝頭の上に少し余白を残す
const BUST_SIZE := 0.58  # 切り出す正方形の一辺（幅比）＝頭と肩が入る大きさ

var _ally: Panel
var _enemy: Panel
var _ally_art: TextureRect
var _enemy_art: TextureRect
var _ally_ring: Panel
var _enemy_ring: Panel
var _center: Panel
var _label: Label
var _has_emblem := false  # 左右の枠を出すか（emblem が両陣営そろったときだけ）

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤の入力を邪魔しない
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _build() -> void:
	_ally = _make_side(0)
	_ally_art = _ally.get_child(0)
	_ally_ring = _ally.get_child(1)
	add_child(_ally)
	_center = Panel.new()
	_center.add_theme_stylebox_override("panel", TavernTheme.plaque_stylebox())
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_child(_label)
	_enemy = _make_side(1)
	_enemy_art = _enemy.get_child(0)
	_enemy_ring = _enemy.get_child(1)
	add_child(_enemy)

## 片側の枠（木の看板＋胸像＋活性時の陣営色の縁）。子は [0]=絵 [1]=縁 の順で入れる。
func _make_side(team: int) -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", TavernTheme.signboard_stylebox())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.clip_contents = true  # 胸像が枠からはみ出さない
	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	var ring := Panel.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(3)
	sb.border_color = HexBoard3D.TEAM_COLORS[team]  # 陣営色は盤と同じ値を使う（青=味方／赤=敵）
	sb.set_corner_radius_all(4)
	ring.add_theme_stylebox_override("panel", sb)
	ring.hide()
	panel.add_child(ring)
	return panel

## 代表ユニット（skin_id）を差す。両陣営そろわなければ枠は出さない＝中央のターン数だけになる。
func set_emblem(skin_catalog: Dictionary, ally_id: String, enemy_id: String) -> void:
	var a := _bust(skin_catalog, ally_id)
	var e := _bust(skin_catalog, enemy_id)
	_has_emblem = a != null and e != null
	_ally_art.texture = a
	_enemy_art.texture = e
	_ally.visible = _has_emblem
	_enemy.visible = _has_emblem
	_layout()

## 手番と経過ターンを反映。turn_limit が 0（無制限）なら上限は出さない。
func set_turn(team: int, turn_number: int, turn_limit: int) -> void:
	_label.text = "turn %d / %d" % [turn_number, turn_limit] if turn_limit > 0 else "turn %d" % turn_number
	var player := team == 0
	_ally.modulate = Color.WHITE if player else DIM
	_enemy.modulate = DIM if player else Color.WHITE
	_ally_ring.visible = player
	_enemy_ring.visible = not player

## 立ち絵（map スロット）の頭〜肩を切り出した胸像。skin/画像が無ければ null。
func _bust(skin_catalog: Dictionary, skin_id: String) -> Texture2D:
	if skin_id.is_empty():
		return null
	var s: UnitSkin = SkinCatalog.skin_by_id(skin_catalog, skin_id)
	if s == null:
		return null
	var path := s.image("map")
	if path.is_empty():
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var side := w * BUST_SIZE
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2((w - side) * 0.5, h * BUST_TOP, side, side)
	return at

## 盤エリア（右の情報ボックスを除いた領域）の上端中央へ置き直す。リサイズでも呼ばれる。
func _layout() -> void:
	var area := UiLayout.board_area(get_viewport().get_visible_rect().size)
	var w := CENTER_W + (FRAME + GAP) * 2.0 if _has_emblem else CENTER_W
	position = Vector2(area.position.x + (area.size.x - w) * 0.5, TOP)
	size = Vector2(w, FRAME)
	var x := 0.0
	if _has_emblem:
		_ally.position = Vector2.ZERO
		_ally.size = Vector2(FRAME, FRAME)
		_enemy.position = Vector2(w - FRAME, 0.0)
		_enemy.size = Vector2(FRAME, FRAME)
		x = FRAME + GAP
	_center.position = Vector2(x, (FRAME - CENTER_H) * 0.5)
	_center.size = Vector2(CENTER_W, CENTER_H)
