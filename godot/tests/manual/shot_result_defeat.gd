extends SceneTree
## feature-104 検証用（使い捨て）: 敗北の戦果票に行き先（もう一度挑む／依頼ボードへ戻る）を出し、
## ja/en でスクショと寸法を採る。見るのは (1) ボタンが紙に収まり明細・印と重ならないか
## (2) 焦点が「もう一度挑む」に当たっているか (3) 押した行き先が finished で返るか。
## 実行: godot --path . -s res://tests/manual/shot_result_defeat.gd（--headless 不可）

const OUT_DIR := "res://tests/manual/out"

var _frame := 0
var _banner: ResultBanner
var _shots: Array = [["ja", "result_defeat_ja.png"], ["en", "result_defeat_en.png"]]
var _idx := -1
var _got := []  # finished で返った行き先

func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.10, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_banner = ResultBanner.new()
	_banner.finished.connect(func(a: String) -> void: _got.append(a))
	root.add_child(_banner)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 20 != 0:  # 印が落ちきってから撮る
		return false
	if _idx >= 0:
		_measure(_shots[_idx])
		root.get_texture().get_image().save_png(OUT_DIR.path_join(String(_shots[_idx][1])))
	_idx += 1
	if _idx >= _shots.size():
		_press()
		return true
	var s: Array = _shots[_idx]
	_banner._dismiss()  # 前の票を片付ける（本番は入力で閉じてから次が出る）
	TranslationServer.set_locale(String(s[0]))
	_banner.play("森の追撃", "DEFEAT", false, _rows(), "", tr("ui.result.note_weapons"), false, true)
	return false

## main.gd の _result_rows（敗北）と同じ組み立て＝基準の行は無く、所要時間にベストも付かない。
func _rows() -> Array:
	var mark := tr("ui.result.note_mark")
	return [
		{"label": tr("ui.result.turns"), "value": "18 / 30"},
		{"label": tr("ui.result.survived") + mark, "value": "1 / 5"},
		{"label": tr("ui.result.defeated") + mark, "value": "3"},
		{"label": tr("ui.result.time"), "value": "12:34"},
	]

## ボタンを押して finished が行き先を返すか（両方の口を1回ずつ）。
func _press() -> void:
	_banner.play("森の追撃", "DEFEAT", false, _rows(), "", "", false, true)
	_banner._on_stamped()
	print("  焦点=もう一度挑む: %s" % _banner._retry.has_focus())
	_banner._retry.emit_signal("pressed")
	_banner.play("森の追撃", "DEFEAT", false, _rows(), "", "", false, true)
	_banner._on_stamped()
	_banner._to_select.emit_signal("pressed")
	_banner.play("森の追撃", "DEFEAT", false, _rows(), "", "", false, true)
	_banner._on_stamped()
	_banner._dismiss()  # 選ばずに閉じた＝空
	print("  finished の行き先=%s" % str(_got))
	quit()

## 紙・印・明細・ボタンの実寸（目視で断定しない）。重なりは矩形の交差で見る。
func _measure(shot: Array) -> void:
	var sheet: Panel = _banner._sheet
	var stamp: Control = _banner._stamp
	var origin := sheet.get_global_rect().position
	var body := Rect2()
	for l: Label in _labels(_banner._body):
		body = body.merge(l.get_global_rect()) if body.size != Vector2.ZERO else l.get_global_rect()
	var lb: Button = _banner._to_select
	var rb: Button = _banner._retry
	print("--- %s" % shot[1])
	print("  sheet=%s  ボタン左=%s%s  右=%s%s" % [sheet.size,
		lb.get_global_rect().position - origin, lb.size, rb.get_global_rect().position - origin, rb.size])
	print("  紙からはみ出し=%s  明細と重なる=%s  印と重なる=%s" % [
		not sheet.get_global_rect().encloses(lb.get_global_rect().merge(rb.get_global_rect())),
		body.intersects(lb.get_global_rect().merge(rb.get_global_rect())),
		stamp.get_global_rect().intersects(lb.get_global_rect().merge(rb.get_global_rect()))])
	print("  明細の下端=%.0f  ボタンの上端=%.0f（紙の上から）" % [
		body.end.y - origin.y, lb.get_global_rect().position.y - origin.y])

func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label and not (c as Label).text.is_empty():
			out.append(c)
		out.append_array(_labels(c))
	return out
