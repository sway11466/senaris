extends CanvasLayer
class_name ChronicleScreen
## クロニクル（冒険の記録）。タイトルのメニューから開き、全画面の暗幕の上に
## 目次と中身を出す。仕様 → doc/gdd/chronicle.md
##
## 画面の様式はマニュアル・設定と同じ（全画面の暗幕、木の板のボタン、戻るは左下）。
## 中は3章＝ユニット／陣形スキル／冒険譚で、章は1つずつ別のファイルが持つ
## （ChronicleChapter とその子孫）。この画面が持つのは暗幕・見出し・左の目次・戻るボタンと、
## 画面全体を覆うものの置き場だけで、右のペインから先には触らない。
##
## 目次は1段目（章の一覧）と2段目（章のなか）を同じ場所に出す。2段目を出すかどうかは章が
## toc_keys で教えてくる＝冒険譚の戦果／物語／設定集も、章の側の持ち物。

signal closed  # 畳み終わった（暗幕が抜けたところ）

const LAYER := 78  # マニュアル(77)より前面。同時に開くことはないが番号は専用に取る

const SCRIM_COLOR := Color(0.03, 0.03, 0.04, 0.92)

const TOP := 18
const BOTTOM := 24
const TOC_GAP := 4
const TOC_BUTTON_HEIGHT := 32

enum Chapter { UNITS, FORMATIONS, CAMPAIGNS }
const CHAPTER_KEYS := ["ui.chronicle.units", "ui.chronicle.formations", "ui.chronicle.campaigns"]

var _root: Control
var _heading: Label
var _toc_box: VBoxContainer
var _overlay: Control  # 画面全体を覆うものの置き場（章が使う）
var _back: Button

var _chapter: int = Chapter.UNITS
var _chapters: Array[ChronicleChapter] = []  # Chapter の並び順

func _ready() -> void:
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	_heading = Label.new()
	_heading.text = tr("ui.chronicle.title")
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", ChronicleStyle.TITLE_FONT_SIZE)
	_heading.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
	_heading.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_heading.offset_top = TOP
	_heading.offset_bottom = TOP + ChronicleStyle.TITLE_FONT_SIZE + 8
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_heading)

	_root.add_child(_panes())

	_back = TavernTheme.back_button(tr("ui.chronicle.back"))
	TavernTheme.place_bottom_left(_back)
	_back.pressed.connect(_on_back)
	_root.add_child(_back)

	# 章が画面全体を覆うものを置く器。戻るボタンより後＝いちばん手前に重なる。
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)

	visible = false

## 開く。開くたびに最新のストアから組み直す。
func open(store: ChronicleStore, progress: CampaignProgress) -> void:
	var skins := SkinCatalog.load_standard()  # main.gd と同じインスタンスを参照しない＝開くときに組む
	var types := UnitCatalog.load_default()   # { type_id: UnitType }
	for ch in _chapters:
		ch.bind(store, progress, skins, types, _overlay)
	_chapter = Chapter.UNITS
	_show_current()
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, ChronicleStyle.FADE_SEC)

func close() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, ChronicleStyle.FADE_SEC)
	tween.tween_callback(func() -> void:
		visible = false
		closed.emit())

func refresh_labels() -> void:
	_heading.text = tr("ui.chronicle.title")
	for ch in _chapters:
		ch.refresh_labels()
	_back.text = tr(_chapters[_chapter].back_label())
	if visible:
		_show_current()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
	get_viewport().set_input_as_handled()

## 戻る／Esc。まず章に渡し、章が受け止めなければ画面を出る。
func _on_back() -> void:
	if _chapters[_chapter].handle_back():
		return
	SfxPlayer.play_event("menu_back")
	close()

# ---------------------------------------------------------------------------
# ペイン
# ---------------------------------------------------------------------------

func _panes() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ChronicleStyle.PANE_GAP)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = ChronicleStyle.EDGE
	row.offset_right = -ChronicleStyle.EDGE
	row.offset_top = TOP + ChronicleStyle.TITLE_FONT_SIZE + ChronicleStyle.HEAD_GAP
	row.offset_bottom = -BOTTOM

	# 左：目次
	var toc_scroll := ScrollContainer.new()
	toc_scroll.custom_minimum_size = Vector2(ChronicleStyle.TOC_WIDTH, 0)
	toc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_toc_box = VBoxContainer.new()
	_toc_box.add_theme_constant_override("separation", TOC_GAP)
	_toc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toc_scroll.add_child(_toc_box)
	row.add_child(toc_scroll)

	# 右：章。3つとも置いたままにして、いまの章だけ見せる（Chapter の並び順）
	_chapters.append(ChronicleUnitsChapter.new())
	_chapters.append(ChronicleFormationsChapter.new())
	_chapters.append(ChronicleCampaignsChapter.new())
	for ch in _chapters:
		ch.toc_changed.connect(_on_toc_changed)
		row.add_child(ch)
	return row

# ---------------------------------------------------------------------------
# 章の切り替え
# ---------------------------------------------------------------------------

## いまの章だけ見せ、中身と目次と戻るの文言を組み直す。
func _show_current() -> void:
	for i in _chapters.size():
		_chapters[i].visible = (i == _chapter)
	_chapters[_chapter].rebuild()
	_rebuild_toc()
	_back.text = tr(_chapters[_chapter].back_label())

func _select_chapter(idx: int) -> void:
	if idx == _chapter:
		return
	_chapters[_chapter].reset()  # 離れる章の選びは捨てる（戻ってきたら一覧から）
	_chapter = idx
	SfxPlayer.play_event("menu_select")
	_show_current()

## 章が段を移った＝目次と戻るの文言を組み直す（中身は章が自分で組み直している）。
func _on_toc_changed() -> void:
	_rebuild_toc()
	_back.text = tr(_chapters[_chapter].back_label())

# ---------------------------------------------------------------------------
# 目次
# ---------------------------------------------------------------------------

## 章が toc_keys を返せばそれを出す（2段目）。空なら章の一覧（1段目）。
func _rebuild_toc() -> void:
	for c in _toc_box.get_children():
		c.queue_free()
	var chapter := _chapters[_chapter]
	var keys: Array = chapter.toc_keys()
	var in_chapter := not keys.is_empty()
	var selected := chapter.toc_selected() if in_chapter else _chapter
	if not in_chapter:
		keys = CHAPTER_KEYS
	for i in keys.size():
		var btn := TavernTheme.wood_button(tr(String(keys[i])))
		btn.custom_minimum_size = Vector2(ChronicleStyle.TOC_WIDTH - 8, TOC_BUTTON_HEIGHT)
		var idx := i
		if in_chapter:
			btn.pressed.connect(func() -> void: chapter.select_toc(idx))
		else:
			btn.pressed.connect(func() -> void: _select_chapter(idx))
		_toc_box.add_child(btn)
		if i == selected:
			_add_frame(btn)

func _add_frame(c: Control) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = ChronicleStyle.FRAME_COLOR
	sb.border_width_left = ChronicleStyle.FRAME_WIDTH
	sb.border_width_right = ChronicleStyle.FRAME_WIDTH
	sb.border_width_top = ChronicleStyle.FRAME_WIDTH
	sb.border_width_bottom = ChronicleStyle.FRAME_WIDTH
	if c is Button:
		c.add_theme_stylebox_override("normal", sb)
