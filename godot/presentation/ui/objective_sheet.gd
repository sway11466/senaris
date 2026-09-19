extends CanvasLayer
class_name ObjectiveSheet
## 勝利／敗北条件の紙（システムメニューの「勝利／敗北条件を確認」）。仕様 → doc/gdd/uiux.md
## 依頼書（presentation/select/quest_sheet.gd）と同じ羊皮紙＝出撃前に受け取った紙を盤で読み直す見立て。
## 中身は組まない＝行は main から受け取る（組むのは application/objective_text.gd）。

const LAYER := 80  # クロニクルの物語(79)より前面。同時に開くことはないが番号は専用に取る
const SHEET_W := 560.0   # 紙の最小の幅。高さは条件の行数で伸びる
const TITLE_FONT := 26
const HEAD_FONT := 20
const BODY_FONT := 17
const NOTE_FONT := 14    # 見出しに添える「いずれか1つで決まる」
const DOT := 7.0         # 行の頭の印（インクの点）。記号を文字で置かない＝環境でフォントが変わる
const DOT_GAP := 10.0

signal closed

var _title: Label
var _win_box: VBoxContainer
var _lose_box: VBoxContainer
var _win_head: Label
var _lose_head: Label
var _win_note: Label
var _lose_note: Label
var _close: Button

func _ready() -> void:
	layer = LAYER
	visible = false

	# 幕: 背後のクリックを止める。幕クリックで閉じる（読むだけの紙＝閉じやすくする）
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(SHEET_W, 0.0)
	sheet.add_theme_stylebox_override("panel", TavernTheme.sheet_stylebox())
	center.add_child(sheet)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, 32)
	pad.add_theme_constant_override("margin_top", 36)
	sheet.add_child(pad)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	pad.add_child(content)

	_title = _label(tr("ui.objective.title"), TITLE_FONT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_title)

	var rule := ColorRect.new()  # インクの罫線（題と本文の区切り）。依頼書と同じ作り
	rule.color = Color(TavernTheme.INK_SOFT, 0.55)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	content.add_child(rule)

	_win_head = _label(tr("ui.objective.win_head"), HEAD_FONT)
	content.add_child(_win_head)
	_win_note = _label(tr("ui.objective.any"), NOTE_FONT)
	_win_note.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	content.add_child(_win_note)
	_win_box = _lines_box()
	content.add_child(_win_box)

	_lose_head = _label(tr("ui.objective.lose_head"), HEAD_FONT)
	content.add_child(_lose_head)
	_lose_note = _label(tr("ui.objective.any"), NOTE_FONT)
	_lose_note.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	content.add_child(_lose_note)
	_lose_box = _lines_box()
	content.add_child(_lose_box)

	# 読むだけの紙なので進む先は無い＝やめる側（左）に閉じるだけを置く（doc/gdd/uiux.md ボタンの左右）。
	var buttons := HBoxContainer.new()
	content.add_child(buttons)
	_close = TavernTheme.ink_button(tr("ui.hud.close"))
	_close.pressed.connect(close)
	buttons.add_child(_close)

## 条件の行を並べる箱（見出しの下に1段下げて積む）。
func _lines_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	return box

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TavernTheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## 紙を出す。lines＝ObjectiveText.build の戻り（{ "victory": [...], "defeat": [...] }）。
func open(lines: Dictionary) -> void:
	_title.text = tr("ui.objective.title")
	_win_head.text = tr("ui.objective.win_head")
	_lose_head.text = tr("ui.objective.lose_head")
	_close.text = tr("ui.hud.close")  # 開くたびに貼り直す＝言語を変えたあとも紙の文字が揃う
	var win: PackedStringArray = lines.get("victory", PackedStringArray())
	var lose: PackedStringArray = lines.get("defeat", PackedStringArray())
	_fill(_win_box, win)
	_fill(_lose_box, lose)
	# 「いずれか1つで決まる」は2つ以上あるときだけ＝1つしかない紙に択の説明を足さない。
	_win_note.text = tr("ui.objective.any")
	_lose_note.text = tr("ui.objective.any")
	_win_note.visible = win.size() > 1
	_lose_note.visible = lose.size() > 1
	visible = true

## 閉じる（「閉じる」・幕クリック・Esc の共通入口）。同じ手触りの紙（依頼書・セーブ枠・設定）と
## 同じ音で畳む＝どれを閉じたかで音が変わらない。
func close() -> void:
	if not visible:
		return
	SfxPlayer.play_event("menu_back")
	visible = false
	closed.emit()

## 条件の行を貼り直す。行の頭にはインクの点を置く＝どこからが1件かが読める。
func _fill(box: VBoxContainer, lines: PackedStringArray) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(DOT_GAP))
		var dot := ColorRect.new()
		dot.color = TavernTheme.INK_SOFT
		dot.custom_minimum_size = Vector2(DOT, DOT)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var text := _label(line, BODY_FONT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		box.add_child(row)

## 幕を押した＝閉じる。押下を吸って盤へ通さない。
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

## 開いている間のキー入力はここで止める。Esc は閉じる。それ以外も後ろへ通さない
## ＝盤の上に開いたとき、Enter がターン終了に届かない（設定画面と同じ扱い）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	get_viewport().set_input_as_handled()
