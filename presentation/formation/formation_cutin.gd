extends Control
class_name FormationCutin
## 陣形スキルの発動で挟む1枚絵のカットイン（presentation）。暗幕の上に絵を出し、少し留めて消える。
## 絵はレシピIDで規約解決＝assets/formations/{recipe_id}.png。無ければ何もせず false を返す
## （カットインを飛ばして盤の結果だけ見せる。音は main が鳴らす）。
## クリック／キーで即座に飛ばせる。頭はロックしない＝1ステージに何度も出るため。
## 仕様 → doc/gdd/formations.md（発動の演出）／絵の置き場 → doc/art/keyvisual.md

## 出し入れが終わった（飛ばされた場合も含む）。main はこれを待ってから着弾音へ進む。
signal finished

const ART_DIR := "res://assets/formations"
const EXTS := [".png", ".webp"]
const FADE_SEC := 0.15    # 出し／引きの秒数（片道）
const HOLD_SEC := 0.70    # 留める秒数。FADE*2+HOLD = 1.0 秒（仕様の「約1秒」）
const ZOOM_FROM := 1.06   # 絵の入り＝わずかに寄った状態から等倍へ。動きを感じさせるだけの幅に留める
const SCRIM_ALPHA := 0.72 # 暗幕。盤を完全には消さない（戻り先が見えていた方が復帰が早い）

var _scrim: ColorRect
var _art: TextureRect
var _tween: Tween = null

func _ready() -> void:
	# 親が Node2D（main）なのでアンカーは効かない＝矩形は _layout で明示的に置く（ターンバナーと同じ）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)

func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, SCRIM_ALPHA)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.pivot_offset = Vector2.ZERO  # 拡縮の中心は _layout で絵の中心に置き直す
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

## カットインを出す。絵が在れば true（呼び手は finished を待つ）、無ければ何もせず false。
func play(recipe_id: String) -> bool:
	var tex := _load_art(recipe_id)
	if tex == null:
		return false
	_art.texture = tex
	visible = true
	_layout()
	_animate()
	return true

## assets/formations/{recipe_id}.png（無ければ .webp）。置いてあれば出る＝コード不変で絵を足せる。
func _load_art(recipe_id: String) -> Texture2D:
	if recipe_id.is_empty():
		return null
	for ext in EXTS:
		var path := "%s/%s%s" % [ART_DIR, recipe_id, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

func _animate() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_art.scale = Vector2(ZOOM_FROM, ZOOM_FROM)
	# 出し → 留め → 引き の3段。段の区切りは chain()、同時に走らせるものだけ parallel()。
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SEC)
	_tween.parallel().tween_property(_art, "scale", Vector2.ONE, FADE_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(HOLD_SEC)
	_tween.chain().tween_property(self, "modulate:a", 0.0, FADE_SEC)
	_tween.chain().tween_callback(_close)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# InputEvent 基底に pressed は無いので、型を絞ってから読む（Variant だと推論できない）。
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		pressed = (event as InputEventKey).pressed
	if pressed:
		get_viewport().set_input_as_handled()  # 飛ばした操作が盤に抜けない（誤って駒を選ばせない）
		_close()

func _close() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if not visible:
		return
	visible = false
	finished.emit()

## 出している最中なら即座に畳む（決着・ステージ切替が割り込んだとき）。
func dismiss() -> void:
	_close()

func _layout() -> void:
	if not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	_scrim.position = Vector2.ZERO
	_scrim.size = vp
	# 絵は画面に収まる最大＝はみ出させない（縦横比はエンジンが保つ）。
	_art.position = Vector2.ZERO
	_art.size = vp
	_art.pivot_offset = vp * 0.5
