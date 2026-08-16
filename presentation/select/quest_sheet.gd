extends Control
class_name QuestSheet
## 出撃確認の依頼書ダイアログ。仕様 → doc/gdd/stage_select.md（依頼書）
## ボードから紙を1枚受け取る見立て＝羊皮紙シート＋出撃する/別のステージを選ぶ。
## 標準 ConfirmationDialog の置き換え。勝利条件・推奨戦力といった事前情報は載せない
## ＝出撃確認のワンクッションに徹する（説明は盤と開始の会話が担う）。

signal confirmed

const SHEET_SIZE := Vector2(560, 400)  # parchment_sheet.png と同寸（中央タイルが1:1）

var _title: Label

func _ready() -> void:
	# set_anchors_preset はツリー内で呼ぶと現在の矩形（サイズ0）を保つようオフセットを
	# 補正してしまう。_and_offsets 版でオフセットもリセットする。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	# 幕: 背後のクリックを止める。幕クリック＝戻る（誤出撃防止のワンクッションなので閉じやすく）
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
	sheet.custom_minimum_size = SHEET_SIZE
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

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", TavernTheme.INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_title)

	# インクの罫線（題と本文の区切り）
	var rule := ColorRect.new()
	rule.color = Color(TavernTheme.INK_SOFT, 0.55)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	content.add_child(rule)

	var question := Label.new()
	question.text = "出撃しますか？"
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.add_theme_font_size_override("font_size", 18)
	question.add_theme_color_override("font_color", TavernTheme.INK)
	content.add_child(question)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	# 左＝やめる／右＝進む（doc/gdd/uiux.md ボタンの左右）。紙の下辺の両端に開いて置く。
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	content.add_child(buttons)

	var back := TavernTheme.ink_button("別のステージを選ぶ")
	back.pressed.connect(_cancel)
	buttons.add_child(back)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)

	var sortie := TavernTheme.wax_button("出撃する")
	sortie.pressed.connect(_on_sortie_pressed)
	buttons.add_child(sortie)

func open(stage_title: String) -> void:
	_title.text = stage_title
	visible = true

func close() -> void:
	visible = false

## 取り消して閉じる（戻るボタン・幕クリック・Esc の共通入口）。開くときに音が鳴るので、
## 閉じるときも鳴らないと非対称になる。出撃は確定音が鳴るので、こちらは通さない。
func _cancel() -> void:
	SfxPlayer.play_event("menu_back")
	close()

func _on_sortie_pressed() -> void:
	close()
	confirmed.emit()

func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_cancel()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
