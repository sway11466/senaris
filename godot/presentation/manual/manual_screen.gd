extends CanvasLayer
class_name ManualScreen
## ゲーム内マニュアル。タイトルのメニューから開き、全画面の暗幕の上に目次と本文を出す。
## 画面の設計 → doc/gdd/manual.md ／ 章立て → ManualToc ／ 本文 → data/i18n/manual.csv
##
## 見せ方は設定画面（settings_screen.gd）と同じ様式。マニュアルは作中の誰の行為でもなく
## アプリケーションの操作なので、酒場の設え（羊皮紙・依頼ボード）は持たない。
## 持ち込むのは「押せる物は木の板」と「戻るは画面の左下」の2つだけ。
##
## 左が目次、右が本文。節が2つ以上ある章（いまは敵AIだけ）は、選ぶとその章の下に節が開く
## ＝章の一覧は消えないので、いま何を開いているかが見えたままになる。段を上がる操作を
## 持たないので、左下の戻ると Esc はどちらも画面を閉じる＝隅のボタンはどの画面でも
## 「この画面を出る」の一つだけになる。
##
## 節の中でさらに切り替わるもの（敵AIの特性ごとの行動）は、本文ペインの上にタブで並べる。
## タブと節の見出しはスクロールの外に置く＝長い本文を繰っている間も、どの特性を読んでいるか
## が見えている。タブは幅で折り返す（HFlowContainer）。
##
## 本文はスクロールで流す。ページ割りにしないのは、同じ内容でも言語で行数が変わり、
## 日本語で決めた割りが英語で溢れるため（doc/gdd/manual.md）。

signal closed  # 畳み終わった（暗幕が抜けたところ）＝呼び出し元へ戻す

const LAYER := 77  # 設定(76)より前面。ただし両方が同時に開くことはない

## 暗幕。設定画面と同じ＝絵を均一に沈める1枚。
const SCRIM_COLOR := Color(0.03, 0.03, 0.04, 0.92)
const FADE_SEC := 0.25

const UI_GRAY := Color(0.82, 0.82, 0.82)             # 本文
const ACCENT := Color(0.90, 0.82, 0.62)              # 見出し・用語（木の板の字と同じ色）
const FRAME_COLOR := Color(0.82, 0.82, 0.82, 0.75)   # 選択中の板に回す細枠（設定画面と同値）
const FRAME_WIDTH := 2
const FRAME_PAD := 3

const TITLE_FONT_SIZE := 24
const SECTION_FONT_SIZE := 24
const HEAD_FONT_SIZE := 20
const BODY_FONT_SIZE := 16
const TOC_FONT_SIZE := 16

const EDGE := 48          # 画面の左右の余白
const TOP := 18           # 見出しの上
const HEAD_GAP := 14      # 見出しと中身の間
## 画面下の余白。戻るボタン（左下）と横に重なるのは目次の列だけなので、本文はもっと下まで
## 使える＝目次だけ戻るボタンのぶん空け、本文は画面下の余白まで伸ばす。
const BOTTOM := 24        # 本文の下＝画面下の余白（戻るボタンの余白と同じ）
const TOC_BOTTOM := 96    # 目次の下＝戻るボタンの高さぶん
const TOC_WIDTH := 268
const PANE_GAP := 32

## 目次の行は、いちばん長い形（敵AIを開いた状態＝章8＋節4）が縦に収まる寸法にしてある。
## 収まらないと目次までスクロールすることになり、スクロールは本文だけという約束が崩れる
## （doc/gdd/manual.md）。節を増やすときは shot_manual.gd で入れ物との比を測り直す。
const TOC_BUTTON_HEIGHT := 32
const TOC_GAP := 4
const BLOCK_GAP := 12     # 段落と段落の間
const HEAD_TOP_GAP := 14  # 小見出しの上に足す余白
const RULE_NUM_WIDTH := 26
const RULE_INDENT := 14
const TOC_SPINE_WIDTH := 30     # 節を束ねる縦長の板（章名を縦に書く）の幅
const TAB_GAP := 6              # タブとタブの間
const TAB_HEIGHT := 30
const TAB_FONT_SIZE := 15
## タブのアイコン。情報パネル（unit_info_panel.gd）と同じ場所・同じ規約＝`{特性id}.png` が
## 在れば出し、無ければ文字だけで並ぶ。タブを持つ節がいまは敵AIの特性だけなのでここを見る。
const TAB_ICON_DIR := "res://assets/ui/ai/"
const TAB_ICON_SIZE := 20
const TAB_ICON_GAP := 6
const HEAD_BOTTOM_GAP := 10     # 見出し・タブと本文の間

var _root: Control
var _heading: Label
var _toc_box: VBoxContainer
var _body_head: VBoxContainer
var _body_box: VBoxContainer
var _body_scroll: ScrollContainer
var _back: Button

var _chapter := 0   ## いま開いている章（CHAPTERS の添字）
var _section := 0   ## いま開いている節（その章の sections の添字）
var _tab := 0       ## いま開いているタブ（節がタブを持つときだけ使う）
var _tab_icons := {}  ## タブid -> Texture2D / null（無い印）。組み直すたびに load しない

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

	_heading = Label.new()
	_heading.text = tr("ui.manual.title")
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_heading.add_theme_color_override("font_color", ACCENT)
	_heading.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_heading.offset_top = TOP
	_heading.offset_bottom = TOP + TITLE_FONT_SIZE + 8
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_heading)

	_root.add_child(_panes())

	# 戻るは画面の左下＝設定・セレクトと同じ場所と大きさ（TavernTheme が1箇所で決める）。
	_back = TavernTheme.back_button(tr("ui.manual.back"))
	TavernTheme.place_bottom_left(_back)
	_back.pressed.connect(_on_back)
	_root.add_child(_back)

	visible = false

## マニュアルを開く。開くたび先頭の章から見せる（読みかけの位置は覚えない）。
func open() -> void:
	_chapter = 0
	_section = 0
	_tab = 0
	_rebuild()
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SEC)

## 畳む。closed は暗幕が抜け切ってから出す＝呼び出し元が絵を戻すのが暗幕の下で見えない。
func close() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	tween.tween_callback(func() -> void:
		visible = false
		closed.emit())

## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## 目次も本文も翻訳キーから組み立てているので、まるごと作り直す。
func refresh_labels() -> void:
	_heading.text = tr("ui.manual.title")
	_back.text = tr("ui.manual.back")
	_rebuild()

## 左の目次と右の本文。見出しの下から戻るボタンの上までを使う。
func _panes() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PANE_GAP)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = EDGE
	row.offset_right = -EDGE
	row.offset_top = TOP + TITLE_FONT_SIZE + HEAD_GAP
	row.offset_bottom = -BOTTOM

	var toc_scroll := ScrollContainer.new()  # 章が増えても溢れないための保険。常用はしない
	toc_scroll.custom_minimum_size = Vector2(TOC_WIDTH, 0)
	toc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_toc_box = VBoxContainer.new()
	_toc_box.add_theme_constant_override("separation", TOC_GAP)
	_toc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toc_scroll.add_child(_toc_box)
	var toc_col := MarginContainer.new()  # 目次だけ戻るボタンのぶん下を空ける
	toc_col.add_theme_constant_override("margin_bottom", TOC_BOTTOM - BOTTOM)
	toc_col.add_child(toc_scroll)
	row.add_child(toc_col)

	var body_col := VBoxContainer.new()
	body_col.add_theme_constant_override("separation", HEAD_BOTTOM_GAP)
	body_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_head = VBoxContainer.new()  # 節の見出しとタブ＝スクロールしない
	_body_head.add_theme_constant_override("separation", HEAD_BOTTOM_GAP)
	_body_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_col.add_child(_body_head)

	_body_scroll = ScrollContainer.new()
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 横スクロールを止めると子の幅がコンテナに合う＝本文の折り返しが効く。
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_box = VBoxContainer.new()
	_body_box.add_theme_constant_override("separation", BLOCK_GAP)
	_body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(_body_box)
	body_col.add_child(_body_scroll)
	row.add_child(body_col)
	return row

## 目次と本文を組み直す。
func _rebuild() -> void:
	_build_toc()
	_build_body()

func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)  # 先に外す＝作り直した行と1フレーム重なって見えない
		child.queue_free()

## 目次。節が1つの章は行1つ、節を2つ以上持つ章は節を全部並べ、その左に章名を縦に書いた板を
## 立てて束ねる。開閉で伸び縮みさせないのは、全部出しても縦に収まるため＝畳んだり開いたり
## する操作を覚えなくてよい。束ねた章は章そのものの行を持たない＝押せる行が節だけになり、
## 印もいつも1つで済む。
func _build_toc() -> void:
	_clear(_toc_box)
	for i in ManualToc.CHAPTERS.size():
		var chapter: Dictionary = ManualToc.CHAPTERS[i]
		var id := String(chapter["id"])
		var sections: Array = chapter["sections"]
		if sections.size() < 2:
			_toc_box.add_child(_toc_row(tr(ManualToc.chapter_title_key(id)), i == _chapter, _on_chapter.bind(i)))
			continue
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", TOC_GAP)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_child(_toc_spine(tr(ManualToc.chapter_title_key(id))))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", TOC_GAP)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for j in sections.size():
			var key := ManualToc.section_title_key(id, String(sections[j]["id"]))
			col.add_child(_toc_row(tr(key), i == _chapter and j == _section, _on_section.bind(i, j)))
		group.add_child(col)
		_toc_box.add_child(group)

## 節を束ねる縦長の板。章名を時計回りに90度倒して縦書きにする（上から下へ読む＝本の背と同じ向き）。
## 文字を1字ずつ縦に積まないのは、英語（Enemy AI）が読めなくなるため。
## 板の中で字を回すので、板の寸法が決まってから位置と大きさを入れ直す（resized）。
func _toc_spine(text: String) -> Control:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", TavernTheme.plaque_stylebox())
	panel.custom_minimum_size = Vector2(TOC_SPINE_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 押す物ではない＝節の行だけが押せる

	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", TOC_FONT_SIZE)
	l.add_theme_color_override("font_color", ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.rotation = PI / 2.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(l)
	panel.resized.connect(func() -> void:
		# 90度倒したので、字の入れ物は縦横を入れ替えた大きさ。右上を原点に置くと上から下へ流れる。
		l.size = Vector2(panel.size.y, panel.size.x)
		l.position = Vector2(panel.size.x, 0.0))
	return panel

## 目次の1行＝木の板。いま開いている行にだけ灰色の細枠を回す（設定画面の選択中と同じ印）。
func _toc_row(text: String, selected: bool, action: Callable) -> Control:
	var b := TavernTheme.wood_button(text)
	b.custom_minimum_size = Vector2(0, TOC_BUTTON_HEIGHT)
	b.add_theme_font_size_override("font_size", TOC_FONT_SIZE)
	b.pressed.connect(action)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _frame_box(selected))
	frame.add_child(b)
	return frame

func _frame_box(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_border_width_all(FRAME_WIDTH)
	box.border_color = FRAME_COLOR if selected else Color(0, 0, 0, 0)
	box.set_content_margin_all(FRAME_PAD)
	return box

## 本文＝節の見出しと、ブロックを上から並べたもの。節がタブを持つなら見出しの下にタブを敷き、
## 選んでいるタブの中身を本文に出す。見出しとタブはスクロールの外（_body_head）に置く。
func _build_body() -> void:
	_clear(_body_head)
	_clear(_body_box)
	var chapter: Dictionary = ManualToc.CHAPTERS[_chapter]
	var chapter_id := String(chapter["id"])
	var section: Dictionary = chapter["sections"][_section]
	var section_id := String(section["id"])

	_body_head.add_child(_label(tr(ManualToc.section_title_key(chapter_id, section_id)), SECTION_FONT_SIZE, ACCENT))

	var holder := section
	if ManualToc.has_tabs(section):
		_body_head.add_child(_tab_row(chapter_id, section["tabs"]))
		holder = section["tabs"][_tab]
		section_id = String(holder["id"])

	for block in holder["blocks"]:
		match String(block["t"]):
			"p":
				_body_box.add_child(_label(tr(ManualToc.key(chapter_id, section_id, String(block["e"]))), BODY_FONT_SIZE, UI_GRAY))
			"h":
				_body_box.add_child(_gap(HEAD_TOP_GAP))
				_body_box.add_child(_label(tr(ManualToc.key(chapter_id, section_id, String(block["e"]))), HEAD_FONT_SIZE, ACCENT))
			"dl":
				for e in block["e"]:
					_body_box.add_child(_definition(chapter_id, section_id, String(e)))
			"rules":
				for i in range(1, int(block["n"]) + 1):
					_body_box.add_child(_rule_row(chapter_id, section_id, i))
	# 組み直した直後は寸法が確定していないので、先頭へ戻すのは次のフレームに任せる。
	_body_scroll.set_deferred("scroll_vertical", 0)

## 用語1件＝見出しの語と、その下に説明。
func _definition(chapter_id: String, section_id: String, element: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_label(tr(ManualToc.key(chapter_id, section_id, "%s.term" % element)), BODY_FONT_SIZE, ACCENT))
	var desc := _label(tr(ManualToc.key(chapter_id, section_id, "%s.desc" % element)), BODY_FONT_SIZE, UI_GRAY)
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", RULE_INDENT)
	indent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	indent.add_child(desc)
	box.add_child(indent)
	return box

## 行動ルールの1行＝番号・条件・行動。3列の表にせず、番号の右に条件と行動を積む
## ＝日本語も英語も1行が長く、幅の決まった3列に収めると桁が潰れるため。
func _rule_row(chapter_id: String, section_id: String, index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var num := _label(str(index), BODY_FONT_SIZE, ACCENT)
	num.custom_minimum_size = Vector2(RULE_NUM_WIDTH, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	num.size_flags_horizontal = Control.SIZE_FILL  # 番号は伸ばさない＝伸びると条件文を右へ押す
	row.add_child(num)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(_label(tr(ManualToc.key(chapter_id, section_id, "rule%d.cond" % index)), BODY_FONT_SIZE, UI_GRAY))
	var act := _label("→ %s" % tr(ManualToc.key(chapter_id, section_id, "rule%d.act" % index)), BODY_FONT_SIZE, ACCENT)
	text.add_child(act)
	row.add_child(text)
	return row

## タブの並び。幅に入らなければ折り返す。いま開いているタブにだけ細枠を回す
## ＝選択の印を目次の行と同じにして、印を2種類作らない。
func _tab_row(chapter_id: String, tabs: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", TAB_GAP)
	flow.add_theme_constant_override("v_separation", TAB_GAP)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in tabs.size():
		var id := String(tabs[i]["id"])
		var b := TavernTheme.wood_button(tr(ManualToc.section_title_key(chapter_id, id)))
		b.custom_minimum_size = Vector2(0, TAB_HEIGHT)
		b.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
		var tex := _tab_icon(id)
		if tex != null:
			b.icon = tex
			b.add_theme_constant_override("icon_max_width", TAB_ICON_SIZE)
			b.add_theme_constant_override("h_separation", TAB_ICON_GAP)
		b.pressed.connect(_on_tab.bind(i))
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", _frame_box(i == _tab))
		frame.add_child(b)
		flow.add_child(frame)
	return flow

## タブのアイコン（無ければ null）。有無は一度引いたら控えておく。
func _tab_icon(id: String) -> Texture2D:
	if _tab_icons.has(id):
		return _tab_icons[id]
	var path := TAB_ICON_DIR + id + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tab_icons[id] = tex
	return tex

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## 章を選んだ。節が2つ以上ある章なら、その章の下に節が開く（先頭の節を出す）。
func _on_chapter(index: int) -> void:
	SfxPlayer.play_event("menu_command")
	_chapter = index
	_section = 0
	_tab = 0
	_rebuild()

## 節を選んだ。どの章の節も常に出ているので、章もここで移る。
func _on_section(chapter_index: int, index: int) -> void:
	SfxPlayer.play_event("menu_command")
	_chapter = chapter_index
	_section = index
	_tab = 0
	_rebuild()

## タブを選んだ。目次は動かないので本文だけ組み直す。
func _on_tab(index: int) -> void:
	SfxPlayer.play_event("menu_command")
	_tab = index
	_build_body()

func _on_back() -> void:
	SfxPlayer.play_event("menu_back")
	close()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back()
