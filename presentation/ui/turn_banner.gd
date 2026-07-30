extends Control
class_name TurnBanner
## 手番の切り替わりを見せる横帯（presentation）。画面中央へ左右から差し込み、少し留めて消える。
## 手番板（turn_plate.gd）は状態の常時表示なので、切り替わりの瞬間はこちらが担う。
## とくに敵が1手も動かない手番は、これが無いと1フレームも見えずに手番が戻ってくる。
## 立ち絵は冒険譚の emblem（combat スロット優先）。状態は持たず main から play() で流し込む。
## 仕様 → doc/gdd/uiux.md（手番の切り替わり）

## 出し入れが終わった（留めも含めて完了）。敵手番はこれを待ってから最初の行動に入る。
signal finished

const BAND_H := 120.0     # 帯の高さ
const SLIDE_SEC := 0.18   # 差し込み／引き上げの秒数（片道）
const HOLD_SEC := 0.34    # 留める秒数。SLIDE*2+HOLD = 0.7 秒（仕様）
const ART_H := 168.0      # 立ち絵の高さ（帯より大きく＝上下にはみ出させる）
const ART_INSET := 56.0   # 立ち絵を帯の端からどれだけ内側に置くか
const LABEL_SIZE := 40

var _band_ally: Panel      # 左から差し込む半分
var _band_enemy: Panel     # 右から差し込む半分
var _label: Label
var _art: TextureRect
var _tween: Tween = null
var _skippable := false    # 自分の手番＝クリック／キーで即座に消せる

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤の入力を邪魔しない（自分の手番は操作を受け付ける）
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)

func _build() -> void:
	_band_ally = Panel.new()
	_band_enemy = Panel.new()
	for p in [_band_ally, _band_enemy]:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", LABEL_SIZE)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 8)
	add_child(_label)

## 手番バナーを出す。team=0 味方（青）／1 敵（赤）。skippable＝クリック等で消せるか（自分の手番）。
## skin_catalog と emblem_skin が揃っていれば立ち絵を重ねる（combat → map → 絵なし）。
func play(team: int, text: String, skin_catalog: Dictionary, emblem_skin: String, skippable: bool) -> void:
	_skippable = skippable
	_label.text = text
	var col: Color = HexBoard3D.TEAM_COLORS[team % HexBoard3D.TEAM_COLORS.size()]
	_band_ally.add_theme_stylebox_override("panel", _band_style(col, false))
	_band_enemy.add_theme_stylebox_override("panel", _band_style(col, true))
	_art.texture = _figure(skin_catalog, emblem_skin)
	_art.visible = _art.texture != null
	visible = true
	_layout()
	_animate()

## 出ている途中でも即座に閉じる（自分の手番のみ）。finished は必ず1回出す。
func skip() -> void:
	if not visible or not _skippable:
		return
	_close()

## 呼び出し側の都合で強制的に閉じる（決着の戦果票と重ねない等）。skippable でなくても閉じる。
func dismiss() -> void:
	if visible:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _skippable:
		return
	var pressed := (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed)
	if pressed:
		_close()

func _close() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	visible = false
	finished.emit()

func _animate() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var w := size.x
	var y := (size.y - BAND_H) * 0.5
	var half := w * 0.5
	_band_ally.position = Vector2(-half, y)          # 画面外（左）から
	_band_enemy.position = Vector2(w, y)             # 画面外（右）から
	_label.modulate.a = 0.0
	_art.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_band_ally, "position:x", 0.0, SLIDE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_band_enemy, "position:x", half, SLIDE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, "modulate:a", 1.0, SLIDE_SEC)
	_tween.tween_property(_art, "modulate:a", 1.0, SLIDE_SEC)
	_tween.set_parallel(false)
	_tween.tween_interval(HOLD_SEC)
	_tween.set_parallel(true)
	_tween.tween_property(_band_ally, "position:x", -half, SLIDE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_band_enemy, "position:x", w, SLIDE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_label, "modulate:a", 0.0, SLIDE_SEC)
	_tween.tween_property(_art, "modulate:a", 0.0, SLIDE_SEC)
	_tween.chain().tween_callback(_close)

func _layout() -> void:
	if not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	size = vp
	var y := (vp.y - BAND_H) * 0.5
	var half := vp.x * 0.5
	_band_ally.size = Vector2(half, BAND_H)
	_band_enemy.size = Vector2(half, BAND_H)
	_label.size = Vector2(vp.x, BAND_H)
	_label.position = Vector2(0, y)
	if _art.texture != null:
		var t := _art.texture.get_size()
		var w := ART_H * (t.x / maxf(1.0, t.y))
		_art.size = Vector2(w, ART_H)
		# 立ち絵は帯の端寄り＝文字と重ねない。足元を帯の下辺に合わせる（上へはみ出させる）。
		_art.position = Vector2(ART_INSET, y + BAND_H - ART_H)

## 帯の見た目。中央（文字の後ろ）を濃く、外側へ向けて薄く抜く＝画面を塞がずに視線を集める。
func _band_style(col: Color, mirrored: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.92)
	# 左半分は右端が中央＝そちらを濃く。右半分はその逆。
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = col
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_right = 0
	if mirrored:
		sb.corner_radius_top_right = 0
	return sb

## emblem の立ち絵。combat スロット優先・無ければ map・どちらも無ければ null（絵なしで帯だけ出す）。
## 立ち絵はキャンバスに余白を焼き込んである（下寄せ・上に透明）ので、非透過部分を切り出してから使う。
## 固定位置で切ると図が下に沈む。手番板の胸像と同じ考え方（turn_plate.gd の _bust）。
func _figure(skin_catalog: Dictionary, skin_id: String) -> Texture2D:
	if skin_id.is_empty() or skin_catalog.is_empty():
		return null
	var s: UnitSkin = SkinCatalog.skin_by_id(skin_catalog, skin_id)
	if s == null:
		return null
	var path := s.image("combat")
	if path.is_empty():
		path = s.image("map")  # 戦闘立ち絵が未制作のスキンは map で代用
	if path.is_empty():
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return tex
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(used.position, used.size)
	return at
