extends Control
class_name FormationCutin
## 陣形スキルの発動で挟む1枚絵のカットイン（presentation）。画面全体の暗転（ScreenLighting）の
## 上に絵を出し、留めて消える。本体は前面パネル層（45）＝幕より前。右の InfoPanel も同じ層で沈まない。
## 窓は戦闘演出シーンと同じ位置・大きさ・形（八角形）＝盤が完全に消えない・演出の見た目を揃える。
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

var _screen: ScreenLighting = null  # 画面の明暗の共通基盤（main が結線）。play で暗転・close で明ける
var _window: Control      # 八角形の窓。絵はこの中に描く（_draw_art）
var _edge: Control        # 窓の縁取り
var _tween: Tween = null
var _texture: Texture2D = null
var _art_scale := 1.0     # 入りのズーム（窓の中で絵だけが動く）

func _ready() -> void:
	# 親は前面パネル層（CanvasLayer）＝ Control 親ではないのでアンカーは効かない。
	# 矩形は _layout で明示的に置く（ターンバナーと同じ）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)

## 画面の明暗の共通基盤（main が結線）。カットインの出し入れに合わせて暗転を掛け外しする。
func bind_screen(screen: ScreenLighting) -> void:
	_screen = screen

func _build() -> void:
	_window = Control.new()
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.draw.connect(_draw_art)
	add_child(_window)
	_edge = Control.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.draw.connect(_draw_edge)
	add_child(_edge)

## カットインを出す。絵が在れば true（呼び手は finished を待つ）、無ければ何もせず false。
func play(recipe_id: String) -> bool:
	var tex := _load_art(recipe_id)
	if tex == null:
		return false
	_texture = tex
	if _screen != null:
		_screen.dim(self)  # 画面全体を沈めて絵に注視させる（濃さ・フェードは共通基盤持ち）
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
	_art_scale = ZOOM_FROM
	# 出し → 留め → 引き の3段。段の区切りは chain()、同時に走らせるものだけ parallel()。
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SEC)
	_tween.parallel().tween_method(_set_art_scale, ZOOM_FROM, 1.0, FADE_SEC) \
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
	if _screen != null:
		_screen.undim(self)  # 暗転を明ける（着弾＝盤の結果へ目を戻す）
	visible = false
	finished.emit()

## 出している最中なら即座に畳む（決着・ステージ切替が割り込んだとき）。
func dismiss() -> void:
	_close()

## 入りのズーム。窓の大きさは変えず、中の絵だけを寄った状態から等倍へ戻す。
func _set_art_scale(v: float) -> void:
	_art_scale = v
	_window.queue_redraw()

## 窓は戦闘演出シーンと同じ位置・大きさ・形（盤エリア中央の八角形）に合わせる。
## 暗転は共通基盤（画面全体）＝ここでは窓と縁取りだけを置く。
func _layout() -> void:
	if not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	var board := UiLayout.board_area(vp)
	var area := Vector2(minf(board.size.x * 0.90, 740.0), minf(board.size.y * 0.62, 520.0))
	var at := board.position + ((board.size - area) * 0.5).round()
	for c in [_window, _edge]:
		c.position = at
		c.size = area
	_window.queue_redraw()
	_edge.queue_redraw()

## 絵を八角形の窓に流し込む（窓を覆う最大＝はみ出しは切る）。TextureRect では角を落とせないため直に描く。
func _draw_art() -> void:
	if _texture == null:
		return
	var sz := _window.size
	var t := Vector2(_texture.get_size())
	if t.x <= 0.0 or t.y <= 0.0:
		return
	var cover := maxf(sz.x / t.x, sz.y / t.y) * _art_scale  # COVERED＝短辺を満たす（余白を作らない）
	var drawn := t * cover
	var origin := (sz - drawn) * 0.5
	var pts := _window_shape(sz)
	var uvs := PackedVector2Array()
	for p in pts:  # 窓の頂点を絵のUVへ落とす＝ポリゴンで切り抜きながらテクスチャを貼る
		uvs.append((p - origin) / drawn)
	_window.draw_colored_polygon(pts, Color.WHITE, uvs, _texture)

func _draw_edge() -> void:
	var pts := _window_shape(_edge.size)
	pts.append(pts[0])
	_edge.draw_polyline(pts, CombatScene.EDGE_COLOR, CombatScene.EDGE_WIDTH, true)

## 横長八角形（戦闘演出シーンと同じ角の落とし方）。
func _window_shape(sz: Vector2) -> PackedVector2Array:
	var c := minf(sz.x, sz.y) * CombatScene.CORNER_CUT
	return PackedVector2Array([
		Vector2(c, 0), Vector2(sz.x - c, 0), Vector2(sz.x, c), Vector2(sz.x, sz.y - c),
		Vector2(sz.x - c, sz.y), Vector2(c, sz.y), Vector2(0, sz.y - c), Vector2(0, c),
	])
