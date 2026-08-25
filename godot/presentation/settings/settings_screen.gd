extends CanvasLayer
class_name SettingsScreen
## 設定画面。タイトルのメニューから開き、全画面の暗幕の上に項目を出す。
## 画面の設計 → doc/gdd/settings.md
##
## 酒場の設え（依頼ボード・羊皮紙・看板・焼き印）は持たない＝設定はゲームの中の行為ではない。
## 持ち込むのは「押せる物は木の板」の様式だけで、板の外の文字と枠は無機質なグレーにする。
##
## 値の適用と保存はここでは行わない。選ばれたことを signal で伝え、
## TranslationServer と SettingsStore を触るのは main（設定を持つのは1箇所）。

signal closed                          # 畳み終わった（暗幕が抜けたところ）＝呼び出し元へ戻す
signal locale_chosen(locale: String)   # 言語を選んだ

const LAYER := 76  # タイトル(70)・セーブスロット(75)より前面＝タイトルに重ねて出す

## 暗幕。タイトルが敷く横グラデーションの暗幕とは別物で、絵を均一に沈める1枚。
const SCRIM_COLOR := Color(0.03, 0.03, 0.04, 0.92)
const FADE_SEC := 0.25

const UI_GRAY := Color(0.82, 0.82, 0.82)             # 板の外の文字
const FRAME_COLOR := Color(0.82, 0.82, 0.82, 0.75)   # 選択中の板に回す細枠（campaign_select.gd の DOT_COLOR と同値）
const FRAME_WIDTH := 2
const FRAME_PAD := 6

const TITLE_FONT_SIZE := 30
const LABEL_FONT_SIZE := 20
const BUTTON_FONT_SIZE := 20
const LABEL_WIDTH := 140      # 項目名の欄。項目が増えても選択子の左端が揃う
const OPTION_SIZE := Vector2(150, 48)
const TITLE_GAP := 40
const ROW_GAP := 24
const OPTION_GAP := 16

## 言語の選択肢。名前は各言語の自称で書き、翻訳キーにしない
## ＝英語表示のときに Japanese と出ると、日本語で遊びたい人が自分の言語を見つけられない。
const LANGUAGES := [["ja", "日本語"], ["en", "English"]]

var _root: Control
var _heading: Label
var _language_label: Label
var _back: Button
var _frames := {}    # locale -> PanelContainer（選択中だけ縁が出る）
var _locale := ""    # いま選ばれている言語

func _ready() -> void:
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 後ろ（タイトル）へ触らせない
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", ROW_GAP)
	center.add_child(column)

	_heading = Label.new()
	_heading.text = tr("ui.settings.title")
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_heading.add_theme_color_override("font_color", UI_GRAY)
	column.add_child(_heading)
	column.add_child(_gap(TITLE_GAP))

	column.add_child(_language_row())

	# 戻るは画面の左下＝セレクト・貼り紙と同じ場所と大きさ（TavernTheme が1箇所で決める）。
	# 項目の列には混ぜない＝戻る先はどの画面でも同じ隅にある。
	_back = TavernTheme.back_button(tr("ui.settings.back"))
	TavernTheme.place_bottom_left(_back)
	_back.pressed.connect(_on_back)
	_root.add_child(_back)

	visible = false

## 設定を開く。locale＝いま使っている言語（選択中の印を付ける）。
func open(locale: String) -> void:
	_locale = locale
	_mark_selected()
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SEC)

## 畳む。暗幕が薄れてタイトルの絵とメニューが戻る。closed は抜け切ってから出す
## ＝呼び出し元が絵を戻すのが、暗幕がまだ濃いうちに見えない。
func close() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	tween.tween_callback(func() -> void:
		visible = false
		closed.emit())

## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## 選択肢の名前は各言語の自称＝訳さないので触らない。
func refresh_labels() -> void:
	_heading.text = tr("ui.settings.title")
	_language_label.text = tr("ui.settings.language")
	_back.text = tr("ui.settings.back")

## 言語の行＝項目名＋横並びの2択。
func _language_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", OPTION_GAP)
	_language_label = Label.new()
	_language_label.text = tr("ui.settings.language")
	_language_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	_language_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_language_label.add_theme_color_override("font_color", UI_GRAY)
	row.add_child(_language_label)
	for lang in LANGUAGES:
		var b := TavernTheme.wood_button(String(lang[1]))
		b.custom_minimum_size = OPTION_SIZE
		b.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
		b.pressed.connect(_on_language.bind(String(lang[0])))
		var frame := PanelContainer.new()  # 選択中の印＝板の縁に回す灰色の細枠
		frame.add_theme_stylebox_override("panel", _frame_box(false))
		frame.add_child(b)
		row.add_child(frame)
		_frames[String(lang[0])] = frame
	return row

## 選択中の板にだけ縁を出す。沈んだ板（dim_wood_button）は「押せるが選べない」を表す形なので使わない。
func _mark_selected() -> void:
	for locale in _frames:
		var frame: PanelContainer = _frames[locale]
		frame.add_theme_stylebox_override("panel", _frame_box(locale == _locale))

func _frame_box(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_border_width_all(FRAME_WIDTH)
	box.border_color = FRAME_COLOR if selected else Color(0, 0, 0, 0)
	box.set_content_margin_all(FRAME_PAD)
	return box

func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _on_language(locale: String) -> void:
	SfxPlayer.play_event("menu_command")
	if locale == _locale:
		return
	_locale = locale
	_mark_selected()
	locale_chosen.emit(locale)

func _on_back() -> void:
	SfxPlayer.play_event("menu_back")
	close()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back()
