extends CanvasLayer
class_name SettingsScreen
## 設定画面。タイトルのメニューと盤のシステムメニューから開き、全画面の暗幕の上に項目を出す。
## 画面の設計 → doc/gdd/settings.md
##
## 酒場の設え（依頼ボード・羊皮紙・看板・焼き印）は持たない＝設定はゲームの中の行為ではない。
## 持ち込むのは「押せる物は木の板」の様式だけで、板の外の文字と枠は無機質なグレーにする。
## 音量のつまみと数値の欄は Godot 標準の部品をそのまま使う（システムの操作なので世界観を織り込まない）。
##
## 値の適用と保存はここでは行わない。選ばれたことを signal で伝え、
## TranslationServer・AudioServer・DisplayServer と SettingsStore を触るのは main（設定を持つのは1箇所）。

signal closed                          # 畳み終わった（暗幕が抜けたところ）＝呼び出し元へ戻す
signal locale_chosen(locale: String)   # 言語を選んだ
signal volume_changed(bus: String, value: int)  # 音量が動いた（つまみを引きずっている最中も）＝音に反映する用
signal volume_settled(bus: String, value: int)  # 音量が決まった（つまみを離した・欄を確定した）＝保存する用
signal window_mode_chosen(mode: String)  # 画面モードを選んだ（SettingsStore.WINDOW_MODES の値）

const LAYER := 76  # タイトル(70)・セーブスロット(75)より前面＝タイトルにも盤にも重ねて出す

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
const LABEL_WIDTH := 160      # 項目名の欄。項目が増えても選択子の左端が揃う（英語の Master Volume が収まる幅）
const OPTION_SIZE := Vector2(150, 48)
const TITLE_GAP := 40
const ROW_GAP := 24
const OPTION_GAP := 16
## 音量の行（つまみ＋間＋数値の欄）の幅は2択の行（板2枚＋枠の余白＋間＝340）と同じにして右端を揃える。
const SPIN_BOX_WIDTH := 80
const SLIDER_WIDTH := 340 - OPTION_GAP - SPIN_BOX_WIDTH  # 244

## 言語の選択肢。名前は各言語の自称で書き、翻訳キーにしない
## ＝英語表示のときに Japanese と出ると、日本語で遊びたい人が自分の言語を見つけられない。
const LANGUAGES := [["ja", "日本語"], ["en", "English"]]
## 音量の行。系統の id（SettingsStore.VOLUME_BUSES）と項目名の翻訳キー。
const VOLUME_ROWS := [["master", "ui.settings.volume_master"], ["music", "ui.settings.volume_music"], ["sfx", "ui.settings.volume_sfx"]]
## 画面モードの選択肢。id（SettingsStore.WINDOW_MODES）と板の文字の翻訳キー。
const WINDOW_MODES := [["windowed", "ui.settings.windowed"], ["fullscreen", "ui.settings.fullscreen"]]

var _root: Control
var _heading: Label
var _back: Button
var _labels := {}          # 翻訳キー -> Label（項目名。言語が変わったら貼り直す）
var _choice_frames := {}   # 行id -> { 選択肢id -> PanelContainer }（選択中だけ縁が出る）
var _choice_buttons := {}  # 行id -> { 選択肢id -> Button }（翻訳する板の文字を貼り直す用）
var _sliders := {}         # 系統 -> HSlider
var _spins := {}           # 系統 -> SpinBox
var _dragging := {}        # 系統 -> つまみを引きずっている最中か
var _locale := ""          # いま選ばれている言語
var _window_mode := ""     # いま選ばれている画面モード

func _ready() -> void:
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 後ろ（タイトル・盤）へ触らせない
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

	column.add_child(_choice_row("locale", "ui.settings.language", LANGUAGES, false, _on_language))
	for row in VOLUME_ROWS:
		column.add_child(_volume_row(String(row[0]), String(row[1])))
	column.add_child(_choice_row("window_mode", "ui.settings.window_mode", WINDOW_MODES, true, _on_window_mode))

	# 戻るは画面の左下＝セレクト・貼り紙と同じ場所と大きさ（TavernTheme が1箇所で決める）。
	# 項目の列には混ぜない＝戻る先はどの画面でも同じ隅にある。
	_back = TavernTheme.back_button(tr("ui.settings.back"))
	TavernTheme.place_bottom_left(_back)
	_back.pressed.connect(_on_back)
	_root.add_child(_back)

	visible = false

## 設定を開く。locale＝いま使っている言語、volumes＝系統 -> 0〜100、window_mode＝いまの画面モード
## （それぞれ選択中の印・つまみの位置に反映する）。
func open(locale: String, volumes: Dictionary, window_mode: String) -> void:
	_locale = locale
	_window_mode = window_mode
	_mark_choice("locale", _locale)
	_mark_choice("window_mode", _window_mode)
	for bus in _sliders:
		var value := int(volumes[bus])
		(_sliders[bus] as HSlider).set_value_no_signal(value)
		(_spins[bus] as SpinBox).set_value_no_signal(value)
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SEC)

## 畳む。暗幕が薄れて呼び出し元（タイトルの絵とメニュー・盤）が戻る。closed は抜け切ってから出す
## ＝呼び出し元が絵を戻すのが、暗幕がまだ濃いうちに見えない。
func close() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	tween.tween_callback(func() -> void:
		visible = false
		closed.emit())

## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## 言語の選択肢の名前は各言語の自称＝訳さないので触らない。
func refresh_labels() -> void:
	_heading.text = tr("ui.settings.title")
	for key in _labels:
		(_labels[key] as Label).text = tr(String(key))
	for mode in WINDOW_MODES:
		(_choice_buttons["window_mode"][String(mode[0])] as Button).text = tr(String(mode[1]))
	_back.text = tr("ui.settings.back")

## 項目名の欄（左端。幅を揃えて選択子の左端を揃える）。
func _label(key: String) -> Label:
	var label := Label.new()
	label.text = tr(key)
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", UI_GRAY)
	_labels[key] = label
	return label

## 行の器＝項目名＋選択子を横に並べ、画面の中央に寄せる。
func _row(label_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", OPTION_GAP)
	row.add_child(_label(label_key))
	return row

## 行を閉じる＝項目名と同じ幅の余白を右端にも置く。選択子の中心が画面の中心＝見出しの真下に来る。
## これが無いと、行の中央寄せが項目名を含めた幅で効いて、選択子だけが右へずれる。
func _finish_row(row: HBoxContainer) -> HBoxContainer:
	var mirror := Control.new()
	mirror.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mirror)
	return row

## 2択の行＝項目名＋横並びの木の板。options＝[[id, 文字]]。translated＝文字を翻訳キーとして引くか
## （言語の行は各言語の自称なので引かない）。on_pick＝板を押したときに id を渡す先。
func _choice_row(row_id: String, label_key: String, options: Array, translated: bool, on_pick: Callable) -> Control:
	var row := _row(label_key)
	var frames := {}
	var buttons := {}
	for option in options:
		var id := String(option[0])
		var text := tr(String(option[1])) if translated else String(option[1])
		var b := TavernTheme.wood_button(text)
		b.custom_minimum_size = OPTION_SIZE
		b.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
		b.pressed.connect(on_pick.bind(id))
		var frame := PanelContainer.new()  # 選択中の印＝板の縁に回す灰色の細枠
		frame.add_theme_stylebox_override("panel", _frame_box(false))
		frame.add_child(b)
		row.add_child(frame)
		frames[id] = frame
		buttons[id] = b
	_choice_frames[row_id] = frames
	_choice_buttons[row_id] = buttons
	return _finish_row(row)

## 音量の行＝項目名＋つまみ（0〜100）＋数値の欄。同じ値を2つの部品で持ち、片方を動かすともう片方が追う。
## 細かく合わせたいときは欄に直に打つ（doc/gdd/settings.md 音量）。
func _volume_row(bus: String, label_key: String) -> Control:
	var row := _row(label_key)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = SettingsStore.VOLUME_MAX
	slider.step = 1
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_slider_value.bind(bus))
	slider.drag_started.connect(_on_slider_drag_started.bind(bus))
	slider.drag_ended.connect(_on_slider_drag_ended.bind(bus))
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = SettingsStore.VOLUME_MAX
	spin.step = 1
	spin.rounded = true
	spin.custom_minimum_size = Vector2(SPIN_BOX_WIDTH, 0)
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.get_line_edit().add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	spin.value_changed.connect(_on_spin_value.bind(bus))
	row.add_child(spin)
	_sliders[bus] = slider
	_spins[bus] = spin
	_dragging[bus] = false
	return _finish_row(row)

## 選択中の板にだけ縁を出す。沈んだ板（dim_wood_button）は「押せるが選べない」を表す形なので使わない。
func _mark_choice(row_id: String, selected: String) -> void:
	var frames: Dictionary = _choice_frames[row_id]
	for id in frames:
		(frames[id] as PanelContainer).add_theme_stylebox_override("panel", _frame_box(id == selected))

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
	_mark_choice("locale", _locale)
	locale_chosen.emit(locale)

func _on_window_mode(mode: String) -> void:
	SfxPlayer.play_event("menu_command")
	if mode == _window_mode:
		return
	_window_mode = mode
	_mark_choice("window_mode", _window_mode)
	window_mode_chosen.emit(mode)

## つまみが動いた。引きずっている最中は音に反映するだけで、決まった値は離したときに出す
## （SettingsStore は書くたびに世代退避するので、1ピクセルごとに書かせない）。
## キーボードの左右で1段ずつ動かしたときは引きずりが無い＝その場で決まった値にする。
func _on_slider_value(value: float, bus: String) -> void:
	(_spins[bus] as SpinBox).set_value_no_signal(value)
	volume_changed.emit(bus, int(value))
	if not _dragging[bus]:
		_settle_volume(bus, int(value))

func _on_slider_drag_started(bus: String) -> void:
	_dragging[bus] = true

func _on_slider_drag_ended(value_changed: bool, bus: String) -> void:
	_dragging[bus] = false
	if value_changed:
		_settle_volume(bus, int((_sliders[bus] as HSlider).value))

## 数値の欄が確定した（Enter・欄を離れた・矢印）＝その値で決まり。つまみも追わせる。
func _on_spin_value(value: float, bus: String) -> void:
	(_sliders[bus] as HSlider).set_value_no_signal(value)
	volume_changed.emit(bus, int(value))
	_settle_volume(bus, int(value))

## 決まった音量を伝える。効果音と全体の音量は、決まったところで決定音を1つ鳴らして
## 「その大きさで鳴る」ことを聞かせる（BGM は流れている曲がそのまま追うので要らない）。
func _settle_volume(bus: String, value: int) -> void:
	volume_settled.emit(bus, value)
	if bus == "sfx" or bus == "master":
		SfxPlayer.play_event("menu_command")

func _on_back() -> void:
	SfxPlayer.play_event("menu_back")
	close()

## 開いている間のキー入力はここで止める。Esc は戻る。それ以外も後ろへ通さない
## ＝盤の上に開いたとき、Enter がターン終了に届かないようにする（doc/gdd/uiux.md）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
	get_viewport().set_input_as_handled()
