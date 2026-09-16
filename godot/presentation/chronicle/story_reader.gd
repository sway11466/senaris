extends CanvasLayer
class_name ChronicleStoryReader
## クロニクルの「物語」＝会話の通し読み。挿絵を背景に敷き、その上で会話パネルを章から章へ
## 連ねる。仕様 → doc/gdd/chronicle.md 物語
##
## 1章＝ステージ1本（章題はステージの題名）。章のなかは 開幕 → イベント → 決着 の順。
## どの会話をどの順で出すかは application/chronicle_story.gd が決める＝ここは出すだけ。
## 操作は3つ＝次へ（パネル右）・次の章へ（パネル左）・やめる（画面左下）。

signal closed  # 通し読みを畳んだ（章の一覧へ戻る）

const LAYER := 79  # クロニクル画面(78)より前面。開くのは物語を読むあいだだけ
const FADE_SEC := 0.25
const TITLE_FADE_SEC := 0.4
const TITLE_HOLD := 1.6   # 会話の無い章（記録より前にクリアした回）で章題を見せる時間
const GROUND := Color(0.03, 0.03, 0.04)  # 挿絵の無い章の地
const TITLE_FONT_SIZE := 24
const ACCENT := Color(0.90, 0.82, 0.62)
const TOP := 18

var _root: Control
var _art: TextureRect
var _title: Label
var _panel: ConversationPanel
var _back: Button

var _chapters: Array = []
var _chapter := 0
var _talks: Array = []   # いま読んでいる章の会話（本文つき）
var _talk := 0
var _skipped := false    # パネル左のボタンで飛ばした＝次の章へ
var _session := 0        # 開くたびに増やす＝待ちの途中で畳んだ回を捨てる

func _ready() -> void:
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var ground := ColorRect.new()
	ground.color = GROUND
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ground)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_art)

	# 暗幕はゲーム中の会話と同じ濃さ（ScreenLighting と同じ色）＝挿絵の上で文字を読ませる。
	var scrim := ColorRect.new()
	scrim.color = ScreenLighting.DIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", ACCENT)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = TOP
	_title.offset_bottom = TOP + TITLE_FONT_SIZE + 8
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title)

	# 会話板は盤のときと同じ箱・同じ場所に置く＝ゲーム中の開幕会話と同じ画で読ませる。
	_panel = preload("res://presentation/ui/conversation_panel.gd").new()
	_panel.size = UiLayout.RIGHT_BOX.size
	_panel.position = UiLayout.RIGHT_BOX.position
	_panel.closed.connect(_on_talk_closed)
	_panel.skipped.connect(_on_talk_skipped)
	_root.add_child(_panel)

	_back = TavernTheme.back_button(tr("ui.chronicle.story_quit"))
	TavernTheme.place_bottom_left(_back)
	_back.pressed.connect(_on_quit)
	_root.add_child(_back)

	visible = false

## 通し読みを開く。chapters＝ChronicleStory の章の列、index＝始める章、skins＝顔絵の表。
func open(chapters: Array, index: int, skins: Dictionary) -> void:
	_session += 1
	_panel.bind(skins)
	_chapters = chapters
	_chapter = clampi(index, 0, maxi(chapters.size() - 1, 0))
	_back.text = tr("ui.chronicle.story_quit")
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SEC)
	_open_chapter()

func refresh_labels() -> void:
	_back.text = tr("ui.chronicle.story_quit")
	_panel.refresh_labels()
	if visible and _chapter < _chapters.size():
		_title.text = tr(String((_chapters[_chapter] as Dictionary)["title"]))

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_quit()
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# 進行
# ---------------------------------------------------------------------------

## 章を開く。章題を出し、その章の会話を本文つきで解いて先頭から流す。
## 会話の無い章（記録より前にクリアした回）は章題だけ見せて次へ送る。
func _open_chapter() -> void:
	if _chapter >= _chapters.size():
		_finish()
		return
	var chapter: Dictionary = _chapters[_chapter]
	_set_art(String(chapter["art"]))
	_show_title(tr(String(chapter["title"])))
	_talks = ChronicleStory.chapter_talks(chapter)
	_talk = 0
	if _talks.is_empty():
		var session := _session
		await get_tree().create_timer(TITLE_HOLD).timeout
		if session != _session or not visible:
			return  # 待っているあいだに畳まれた／別の章から開き直された
		_chapter += 1
		_open_chapter()
		return
	_open_talk()

## 章のなかの1本を流す。読み切ったら次の1本、章の終わりなら次の章へ。
func _open_talk() -> void:
	if _talk >= _talks.size():
		_chapter += 1
		_open_chapter()
		return
	var talk: Dictionary = _talks[_talk]
	_panel.start(talk["lines"], _finish_label(), "ui.chronicle.story_next_chapter")

## 最後の1行を読んだ後のボタンの文言。物語の終わりだけ「読み終える」。
func _finish_label() -> String:
	var last_talk := _talk >= _talks.size() - 1
	var last_chapter := _chapter >= _chapters.size() - 1
	return "ui.chronicle.story_end" if last_talk and last_chapter else "ui.talk.next"

func _on_talk_skipped() -> void:
	_skipped = true

func _on_talk_closed() -> void:
	if not visible:
		return  # やめるボタンで畳んだ＝板を閉じただけ
	if _skipped:
		_skipped = false
		_chapter += 1
		_open_chapter()
		return
	_talk += 1
	_open_talk()

func _on_quit() -> void:
	SfxPlayer.play_event("menu_back")
	_finish()

## 畳む。読み終わり・やめるで同じ（どちらも章の一覧へ戻る）。
func _finish() -> void:
	_session += 1
	visible = false
	_chapters = []
	_talks = []
	_skipped = false
	closed.emit()

func _show_title(text: String) -> void:
	_title.text = text
	_title.modulate.a = 0.0
	create_tween().tween_property(_title, "modulate:a", 1.0, TITLE_FADE_SEC)

## 章の挿絵を敷く。置かれていない章は絵なし＝地と暗幕だけで読ませる。
func _set_art(path: String) -> void:
	_art.texture = null if path.is_empty() else load(path)
