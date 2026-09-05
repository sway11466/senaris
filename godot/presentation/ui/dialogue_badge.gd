extends Control
class_name DialogueBadge
## 情報板を畳んでいる間に会話が起きたことを知らせる漫画の吹き出し。情報板ボタンの右上角に
## 半分ほど重ね、しっぽをボタンへ向ける＝この板が喋った、と読ませる。
## 押せない（読む道はシステムメニューの「ストーリーを確認」）・一定時間で消え、未読の印は残さない。
## 仕様 → doc/gdd/uiux.md 畳んでいるときの会話
##
## 中身の「…」は点3つを図形で描く＝三点リーダの文字は書体で形が変わり、言語も選ぶ。
## 色は酒場の設え（doc/art/menu.md）から借りて、地は羊皮紙・点と輪郭は焦げ茶にする。

const SIZE := Vector2(58.0, 34.0)  # 吹き出し本体（しっぽを含まない）
const TAIL_W := 12.0               # しっぽの付け根の幅
const TAIL_H := 9.0                # しっぽの高さ（本体の下辺から下へ伸びる）
const TAIL_X := 14.0               # しっぽの付け根の左端（本体の左端から）
const TAIL_TIP := 0.35             # 先端の位置（付け根の幅に対する比＝左寄りに倒して吹き出しらしくする）
const RADIUS := 9
const OUTLINE := 2
const DOT_R := 3.0
const DOT_GAP := 13.0              # 点の間隔

const POP_SEC := 0.15   # 出るときの弾み
const HOLD_SEC := 3.5   # 出したままにする時間
const FADE_SEC := 0.4   # 消えるときのフェード

var _box: StyleBoxFlat
var _tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 押せない＝盤のクリックも吸わない
	custom_minimum_size = Vector2(SIZE.x, SIZE.y + TAIL_H)
	size = custom_minimum_size
	pivot_offset = _tail_tip()  # しっぽの先＝ボタンとの接点を基点に弾む
	_box = StyleBoxFlat.new()
	_box.bg_color = TavernTheme.PARCHMENT
	_box.border_color = TavernTheme.INK
	_box.set_border_width_all(OUTLINE)
	_box.set_corner_radius_all(RADIUS)
	visible = false

## 会話が起きた＝出して、一定時間で消す。続けて起きたら出し直す＝数は示さない
## （知らせるのは「会話があった」ことだけで、いくつ溜まったかは催促になる）。
func pop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = true
	modulate.a = 1.0
	scale = Vector2(0.8, 0.8)
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD_SEC)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SEC)
	_tween.tween_callback(func() -> void: visible = false)

## 出したまま消す（ステージを離れる・会話を読んだ）。次に pop するまで出ない。
func dismiss() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false

func _tail_tip() -> Vector2:
	return Vector2(TAIL_X + TAIL_W * TAIL_TIP, SIZE.y + TAIL_H)

func _draw() -> void:
	# 本体 → しっぽの順。しっぽの塗りが本体の下辺の線を消して、地続きに見える。
	draw_style_box(_box, Rect2(Vector2.ZERO, SIZE))
	var base_l := Vector2(TAIL_X, SIZE.y - OUTLINE)
	var base_r := Vector2(TAIL_X + TAIL_W, SIZE.y - OUTLINE)
	var tip := _tail_tip()
	draw_colored_polygon(PackedVector2Array([base_l, base_r, tip]), TavernTheme.PARCHMENT)
	draw_line(base_l, tip, TavernTheme.INK, OUTLINE)
	draw_line(base_r, tip, TavernTheme.INK, OUTLINE)
	var center := Vector2(SIZE.x * 0.5, SIZE.y * 0.5)
	for i in [-1.0, 0.0, 1.0]:
		draw_circle(center + Vector2(DOT_GAP * float(i), 0.0), DOT_R, TavernTheme.INK)
