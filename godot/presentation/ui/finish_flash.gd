extends CanvasLayer
class_name FinishFlash
## 決着の白フラッシュ（勝ちが確定した回だけ）。仕様 → doc/gdd/uiux.md 決着の合図
##
## 通常被弾のフラッシュ（駒・隊列を白く飛ばす）とは質を変え、画面全体を白く飛ばす。
## 白が覆っている間に戦闘の窓を畳んで戦果票を敷き、白が引くと票が既に出ている
## ＝決着の光がそのまま戦果票への幕になる。順番は main が持ち、ここは白の出し入れだけ。

const LAYER := 58     # 戦闘の窓(50)・戦果票(55)より前・キャンペーン完走の勝利イラスト(60)より後ろ
const RISE := 0.12    # 白が画面を覆うまで（一瞬＝弾ける光）
const FALL := 0.55    # 白が引くまで（ゆっくり＝票を浮かび上がらせる幕）
const BLEED := 32.0   # 画面揺れの直後でも縁に隙間が覗かないよう、画面より広く敷く

var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.color = Color(1, 1, 1)
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.hide()
	add_child(_rect)
	_fit()
	get_viewport().size_changed.connect(_fit)

func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size
	_rect.position = Vector2(-BLEED, -BLEED)
	_rect.size = vp + Vector2(BLEED, BLEED) * 2.0

## 白で画面を覆う。覆い切るまで待てる＝呼び出し側は白の下で画面を入れ替える。
func rise() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_rect.show()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0, RISE)
	await _tween.finished

## 白を引く。待たない＝票の溜め（印が落ちるまで）と重ねて流す。
func fall() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_rect, "modulate:a", 0.0, FALL)
	_tween.tween_callback(_rect.hide)
