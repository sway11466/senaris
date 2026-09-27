extends ChronicleCardChapter
class_name ChronicleCampaignsChapter
## クロニクルの冒険譚章。仕様 → doc/gdd/chronicle.md 冒険譚の一覧
##
## 上の段は冒険譚の一覧＝羊皮紙のカードの格子（ユニット・陣形スキルと同じ紙）。1つ選ぶと
## その冒険譚に入り、会話・イベント／戦果／設定集／物語をタブで切り替える。左の目次は変えない。
## 一覧へ戻るのはタブの左端の「←」（丸い木の板）と Esc。

enum Section { EVENTS, RESULTS, LORE, STORY }  # タブの並び順。冒険譚を開くと先頭のタブ
const SECTION_KEYS := ["ui.chronicle.events", "ui.chronicle.results", "ui.chronicle.lore", "ui.chronicle.story"]

## 絵の面の縦／横＝ステージセレクトの冒険譚カードの絵の枠（317×230・doc/gdd/stage_select.md）。
const ART_ASPECT := 230.0 / 317.0

var _selected_campaign_id := ""  # 冒険譚を選んでいるとき（空なら一覧）
var _section: int = Section.EVENTS
var _tabs: HFlowContainer  # 戻る（←）と節のタブ＝スクロールの外（冒険譚を開いているときだけ見せる）
var _story_left := 1   # 物語の節で開いている見開きの左ページ（奇数）
var _events_left := 1  # 会話／イベントの節で開いている見開きの左ページ（奇数）
# 会話／イベントの本。段と会話は冒険譚を開いたときに読み、ページの振り分けは _events_key が変わったときだけやり直す。
var _events_campaign := ""       # _events_chapters を読んだ冒険譚
var _events_chapters: Array = [] # [{ title, map, talks }]（ChronicleStory の段と会話）
var _events_blocks: Array = []   # ページへ流す塊（_event_blocks）
var _events_pages: Array = []    # ページごとの塊の番号
var _events_key := ""            # 振り分けたときの 冒険譚｜言語
var _events_gen := 0             # 測っている最中に組み直されたら捨てるための番号

func _ready() -> void:
	super()
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", ChronicleStyle.TAB_GAP)
	_tabs.add_theme_constant_override("v_separation", ChronicleStyle.TAB_GAP)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.visible = false
	add_child(_tabs)
	move_child(_tabs, 0)

## ステージセレクトのボードと同じ1段3枚。
func _card_columns() -> int:
	return 3

func _card_aspect() -> float:
	return ART_ASPECT

func _card_extra_h() -> float:
	return ChronicleStyle.CARD_SUMMARY_H

func reset() -> void:
	super()
	_selected_campaign_id = ""
	_section = Section.EVENTS
	_reset_books()

func rebuild() -> void:
	super()
	_rebuild_tabs()

## Esc。冒険譚を開いていれば一覧へ戻る。一覧にいれば画面に任せる。
func handle_back() -> bool:
	if _selected_campaign_id.is_empty():
		return false
	_back_to_list()
	return true

func _back_to_list() -> void:
	SfxPlayer.play_event("menu_back")
	_selected_campaign_id = ""
	_section = Section.EVENTS
	rebuild()

# ---------------------------------------------------------------------------
# タブ
# ---------------------------------------------------------------------------

## 左端に戻る（矢印だけの丸い木の板）、続けて節のタブ。いま開いているタブにだけ細枠を回す
## （マニュアルのタブと同じ）。タブは同じ幅＝いちばん長い名前に揃える。
func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	_tabs.visible = not _selected_campaign_id.is_empty()
	if not _tabs.visible:
		return
	_tabs.add_child(_round_back_button())
	var buttons: Array = []
	for i in SECTION_KEYS.size():
		var b := TavernTheme.wood_button(tr(String(SECTION_KEYS[i])))
		b.custom_minimum_size = Vector2(0, ChronicleStyle.TAB_HEIGHT)
		b.add_theme_font_size_override("font_size", ChronicleStyle.TAB_FONT_SIZE)
		b.pressed.connect(_on_tab.bind(i))
		_tabs.add_child(_tab_frame(b, i == _section))
		buttons.append(b)
	_equalize_widths.call_deferred(buttons)  # 文字の幅はツリーに入ってテーマが引けてから測れる

## 戻る＝矢印だけを載せた丸い木の板。直径は枠込みのタブの高さ＝並びの中で上下が揃う。
func _round_back_button() -> Control:
	var d := ChronicleStyle.TAB_HEIGHT + (ChronicleStyle.FRAME_WIDTH + ChronicleStyle.FRAME_PAD) * 2
	var back := TavernTheme.wood_button(tr("ui.chronicle.back_list"))
	back.add_theme_font_size_override("font_size", ChronicleStyle.TAB_FONT_SIZE)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := back.get_theme_stylebox(state).duplicate() as StyleBox
		box.content_margin_left = 0  # 板の左右の余白を詰める＝直径の正方形に収まって円になる
		box.content_margin_right = 0
		back.add_theme_stylebox_override(state, box)
	back.custom_minimum_size = Vector2(d, d)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_back_to_list)
	TavernTheme.round_corners(back, d * 0.5)
	return back

## タブの幅をいちばん広いものに揃える。
func _equalize_widths(buttons: Array) -> void:
	var w := 0.0
	for b in buttons:
		if is_instance_valid(b):
			w = maxf(w, (b as Control).get_combined_minimum_size().x)
	for b in buttons:
		if is_instance_valid(b):
			(b as Control).custom_minimum_size.x = w

## 冒険譚を開き直した・画面を開き直した＝本を最初の見開きに戻し、会話／イベントは読み直す
## （遊んだぶん記録が増えているかもしれない）。
func _reset_books() -> void:
	_story_left = 1
	_events_left = 1
	_events_campaign = ""
	_events_key = ""

## タブの板を細枠で包む。selected でなければ枠は透明（場所だけ取る）。
func _tab_frame(b: Button, selected: bool) -> Control:
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_border_width_all(ChronicleStyle.FRAME_WIDTH)
	box.border_color = ChronicleStyle.FRAME_COLOR if selected else Color(0, 0, 0, 0)
	box.set_content_margin_all(ChronicleStyle.FRAME_PAD)
	frame.add_theme_stylebox_override("panel", box)
	frame.add_child(b)
	return frame

func _on_tab(index: int) -> void:
	if index == _section:
		return
	_section = index
	SfxPlayer.play_event("menu_select")
	rebuild()

func _build() -> void:
	if _selected_campaign_id.is_empty():
		_build_list()
		return
	match _section:
		Section.RESULTS:
			_build_results()
		Section.EVENTS:
			_build_events()
		Section.STORY:
			_build_book()
		Section.LORE:
			_build_lore()

func _build_placeholder(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	label.add_theme_color_override("font_color", ChronicleStyle.DIM_GRAY)
	_content_box.add_child(label)

# ---------------------------------------------------------------------------
# 一覧
# ---------------------------------------------------------------------------

## 冒険譚の一覧＝ボードごとに見出し（ボード名）とカードの格子。ボードの並びと名前は
## ステージセレクトと同じ（CampaignSelect.BOARDS）。押すとその冒険譚に入る（遊んでいない冒険譚も押せる）。
func _build_list() -> void:
	if _progress == null:
		return
	var by_board := {}
	for c in _progress.campaigns(false):  # デバッグ冒険譚を除く
		var b := String(c.get("board", ""))
		if not by_board.has(b):
			by_board[b] = []
		by_board[b].append(c)
	var card_size := _card_size()
	for entry in CampaignSelect.BOARDS:
		var camps: Array = by_board.get(entry["board"], [])
		if not camps.is_empty():
			_add_board(String(entry["name"]), camps, card_size)

## ボード1枚ぶん（見出し・カードの格子・ボード間の余白）を上段に置く。
func _add_board(board_name: String, camps: Array, card_size: Vector2) -> void:
	var head := Label.new()
	head.text = board_name  # ボード名は訳さない（CampaignSelect.BOARDS と同じ扱い）
	head.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	head.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
	_content_box.add_child(head)

	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", ChronicleStyle.CARD_GAP)
	grid.add_theme_constant_override("v_separation", ChronicleStyle.CARD_GAP)
	for c in camps:
		var cid: String = c["id"]
		var played := _is_played(c)
		var card := _paper_card(hash(cid), played, card_size, null,
			func() -> void: _open_campaign(cid), tr(String(c.get("title", cid))), true)
		var summary := Label.new()
		summary.text = _summary_text(c) if played else ""
		summary.custom_minimum_size = Vector2(0, ChronicleStyle.CARD_SUMMARY_H)
		summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary.add_theme_font_size_override("font_size", ChronicleStyle.COUNT_FONT_SIZE)
		summary.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
		(card.get_meta("card_col") as Control).add_child(summary)
		var path := _art_path(c) if played else ""  # 遊んでいなければ絵は読まない（黒い四角だけ）
		_defer_face(card, [path], func() -> Control: return _campaign_art(path, played), false)
		grid.add_child(card)
	_content_box.add_child(grid)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ChronicleStyle.CATEGORY_GAP)
	_content_box.add_child(spacer)

## 一度でも遊んだか＝どこかのステージを開始した記録がある（クリア前でも開始時に残る）。
func _is_played(c: Dictionary) -> bool:
	for s in c["stages"]:
		if not _progress.story(String(c["id"]), String(s["id"])).is_empty():
			return true
	return _progress.cleared_count(String(c["id"])) > 0

## カードの名前の下の1行（クリア数／全部。全クリア後はランクと合計時間も）。
func _summary_text(c: Dictionary) -> String:
	var cid: String = c["id"]
	var stages: Array = c["stages"]
	var parts: Array = [tr("ui.chronicle.cleared_progress") % [_progress.cleared_count(cid), stages.size()]]
	if _progress.is_all_cleared(cid):
		var rank := _campaign_rank(cid, stages)
		if not rank.is_empty():
			parts.append(tr("ui.chronicle.campaign_rank") % rank)
		var t := _campaign_total_time(cid, stages)
		if t > 0:
			parts.append(tr("ui.chronicle.total_time") % _format_duration(t))
	return "  ".join(parts)

## カードの絵＝ステージセレクトの冒険譚カードと同じ（card があればそれ、無ければ cover）。
## 連番の変種は先頭の1枚に固定＝組み直すたびに絵が変わらない。無ければ空文字。
func _art_path(c: Dictionary) -> String:
	var card_paths: Array = c.get("card_paths", [])
	var shown: Array = card_paths if not card_paths.is_empty() else c.get("cover_paths", [])
	return "" if shown.is_empty() else String(shown[0])

## 絵の面。枠いっぱいに切り取って敷く（セレクトの貼り紙と同じ）。遊んでいない冒険譚は
## 真っ黒な四角＝絵を塗らずに四角を置く（手配書のように背景の透けた絵を塗ると形が残るため）。
## 遊んだ冒険譚で絵が無ければ空。
func _campaign_art(path: String, played: bool) -> Control:
	var tex: Texture2D = null if path.is_empty() else load(path) as Texture2D
	if tex == null:
		var blank := ColorRect.new()
		blank.color = ChronicleStyle.SILHOUETTE if not played else Color(0, 0, 0, 0)
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		TavernTheme.round_corners(blank, float(TavernTheme.ART_CORNER_RADIUS))
		return blank
	var art := TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TavernTheme.round_corners(art, float(TavernTheme.ART_CORNER_RADIUS))
	return art

func _open_campaign(campaign_id: String) -> void:
	_selected_campaign_id = campaign_id
	_section = Section.EVENTS
	_reset_books()
	SfxPlayer.play_event("menu_select")
	rebuild()

# ---------------------------------------------------------------------------
# 戦果（RESULTS）
# ---------------------------------------------------------------------------

## 選択中の冒険譚のステージごとの戦果を出す。
func _build_results() -> void:
	if _progress == null:
		return
	var c := _progress.campaign(_selected_campaign_id)
	if c.is_empty():
		return
	# 冒険譚の見出し
	var head := Label.new()
	head.text = tr(String(c.get("title", _selected_campaign_id)))
	head.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	head.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
	_content_box.add_child(head)

	# 冒険譚サマリー（全クリアならランクと合計時間）
	var stages: Array = c["stages"]
	if _progress.is_all_cleared(_selected_campaign_id):
		var summary_parts: Array = []
		var rank := _campaign_rank(_selected_campaign_id, stages)
		if not rank.is_empty():
			summary_parts.append(tr("ui.chronicle.campaign_rank") % rank)
		var t := _campaign_total_time(_selected_campaign_id, stages)
		if t > 0:
			summary_parts.append(tr("ui.chronicle.total_time") % _format_duration(t))
		if not summary_parts.is_empty():
			var summary := Label.new()
			summary.text = "  ".join(summary_parts)
			summary.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
			summary.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
			_content_box.add_child(summary)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ChronicleStyle.CATEGORY_GAP)
	_content_box.add_child(spacer)

	# ステージごとの行
	for s in stages:
		var sid: String = s["id"]
		var cleared := _progress.stage_state(_selected_campaign_id, sid) == CampaignProgress.CLEARED
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, ChronicleStyle.ITEM_HEIGHT)
		row.add_theme_constant_override("separation", 16)

		var title_label := Label.new()
		if cleared:
			title_label.text = tr(String(s.get("title", sid)))
		else:
			title_label.text = tr("ui.chronicle.unknown")
		title_label.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
		title_label.add_theme_color_override("font_color",
			ChronicleStyle.UI_GRAY if cleared else ChronicleStyle.DIM_GRAY)
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title_label)

		if cleared:
			var rank := _progress.best_rank(_selected_campaign_id, sid)
			if not rank.is_empty():
				var rank_label := Label.new()
				rank_label.text = rank
				rank_label.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
				rank_label.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
				rank_label.custom_minimum_size = Vector2(30, 0)
				row.add_child(rank_label)
			var time := _progress.best_time(_selected_campaign_id, sid)
			if time > 0:
				var time_label := Label.new()
				time_label.text = _format_duration(time)
				time_label.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
				time_label.add_theme_color_override("font_color", ChronicleStyle.DIM_GRAY)
				row.add_child(time_label)

		_content_box.add_child(row)

# ---------------------------------------------------------------------------
# 会話／イベント（EVENTS）
# ---------------------------------------------------------------------------

## 会話を本で読む。全ステージぶんの行を画面の外で一度組んで高さを測り、ページへ振り分ける。
## 振り分けは覚えておき、めくるたびには測り直さない（冒険譚か言語が変わったときだけ）。
## 並ぶのは経験した会話だけ＝見ていない出来事の存在を匂わせない（doc/gdd/chronicle.md 会話／イベント）。
func _build_events() -> void:
	if _progress == null:
		return
	if _events_campaign != _selected_campaign_id:
		_load_events()
	if _events_chapters.is_empty():
		_build_placeholder(tr("ui.chronicle.story_empty"))
		return
	var blocks := _event_blocks()
	var key := "%s|%s" % [_selected_campaign_id, TranslationServer.get_locale()]
	if key == _events_key:
		_add_book(_events_spread(), _events_pages.size())
		return
	_events_gen += 1
	var gen := _events_gen
	var heights := await _measure_blocks(blocks)
	if gen != _events_gen or not is_inside_tree():
		return  # 測っている間に組み直された
	_events_blocks = blocks
	_events_pages = _paginate(blocks, heights)
	_events_key = key
	_events_left = clampi(_events_left, 1, maxi(1, _events_pages.size()))
	if _events_left % 2 == 0:
		_events_left -= 1
	rebuild()

## 段（1ステージ）の列と、段ごとの会話を読む。冒険譚を開き直したときだけ。
func _load_events() -> void:
	_events_campaign = _selected_campaign_id
	_events_key = ""
	_events_chapters = []
	var campaign := _progress.campaign(_selected_campaign_id)
	if campaign.is_empty():
		return
	var chronicle := ChronicleLoader.load_for(_selected_campaign_id)
	for chapter in ChronicleStory.load(_selected_campaign_id, chronicle["story"], campaign, _progress, _store):
		_events_chapters.append({
			"title": String(chapter["title"]),
			"map": String(chapter["map"]),
			"talks": ChronicleStory.chapter_talks(chapter),
		})

## ページへ流す塊の列。塊は ステージの頭（題名＋盤の絵・新しいページから）／会話の見出し（戦闘前・中・後）／
## 行／会話の間。取得／喪失の両方を経験した組は、2つの会話を続けて並べる（見出しに取得・喪失を添える）。
func _event_blocks() -> Array:
	var blocks: Array = []
	for chapter in _events_chapters:
		blocks.append({ "kind": "stage", "title": chapter["title"], "map": chapter["map"] })
		var shown: Array = []  # 並べ終えたイベント（組の相手が同じ回に記録されていても二度出さない）
		for talk in chapter["talks"]:
			var options: Array = talk["options"]
			if options.is_empty():
				_append_talk(blocks, String(talk["phase"]), talk["lines"])
				continue
			if shown.has(String(talk["event"])):
				continue
			for opt in options:
				var side := "lost" if String(opt["captured_by"]) == "enemy" else "secured"
				_append_talk(blocks, "event_" + side, opt["lines"])
				shown.append(String(opt["event"]))
	return blocks

## 会話1本ぶんの塊（会話の間・見出し・行）を足す。ステージの最初の会話には間を置かない。
func _append_talk(blocks: Array, phase: String, lines: Array) -> void:
	if String(blocks.back()["kind"]) != "stage":
		blocks.append({ "kind": "gap" })
	blocks.append({ "kind": "phase", "phase": phase })
	for raw in lines:
		if typeof(raw) == TYPE_DICTIONARY:
			blocks.append({ "kind": "line", "line": raw })

## 塊の高さを測る。本文の幅の器に並べて画面の外（透明）でレイアウトさせる。
## 折り返す Label は幅が付いてから高さが決まるので、2フレーム待つ。
func _measure_blocks(blocks: Array) -> Array:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(ChronicleBook.TEXT_WIDTH, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", 0)
	box.modulate = Color(1, 1, 1, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nodes: Array = []
	for b in blocks:
		var n := _block_node(b)
		nodes.append(n)
		box.add_child(n)
	_content_box.add_child(box)
	await get_tree().process_frame
	await get_tree().process_frame
	var heights: Array = []
	for n in nodes:
		heights.append((n as Control).get_combined_minimum_size().y if is_instance_valid(n) else 0.0)
	if is_instance_valid(box):
		box.queue_free()
	return heights

## ページに振り分ける。返り値＝ページごとの塊の番号の列。
## ステージの頭は新しいページから。見出しは次の行と離さない。会話の間はページの頭では捨てる。
func _paginate(blocks: Array, heights: Array) -> Array:
	var pages: Array = []
	var page: Array = []
	var used := 0.0
	var gap := float(ChronicleStyle.EVENTS_LINE_GAP)
	for i in blocks.size():
		var kind := String(blocks[i]["kind"])
		var h: float = heights[i]
		if kind == "phase" and i + 1 < blocks.size():
			h += gap + float(heights[i + 1])  # 見出しだけがページの下に残らないよう、最初の行と合わせて測る
		var need := h if page.is_empty() else used + gap + h
		if not page.is_empty() and (kind == "stage" or need > ChronicleBook.TEXT_HEIGHT):
			pages.append(page)
			page = []
			used = 0.0
		if page.is_empty() and kind == "gap":
			continue
		used = float(heights[i]) if page.is_empty() else used + gap + float(heights[i])
		page.append(i)
	if not page.is_empty():
		pages.append(page)
	return pages

## いま開いている見開き。
func _events_spread() -> Control:
	return ChronicleBook.spread(_events_page(_events_left, true), _events_page(_events_left + 1, false))

func _events_page(page: int, gutter_right: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ChronicleStyle.EVENTS_LINE_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page <= _events_pages.size():
		for i in _events_pages[page - 1]:
			col.add_child(_block_node(_events_blocks[i]))
	return ChronicleBook.sheet_page(hash(_selected_campaign_id) + page, gutter_right, col)

## 塊1つぶんの Control（測るときとページに置くときで同じものを組む＝高さが一致する）。
func _block_node(b: Dictionary) -> Control:
	match String(b["kind"]):
		"stage":
			return _stage_head(String(b["title"]), String(b["map"]))
		"phase":
			return _phase_head(String(b["phase"]))
		"gap":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, ChronicleStyle.EVENTS_TALK_GAP)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return spacer
		_:
			return _line_row(b["line"])

## ステージの頭＝題名と盤の絵（物語の挿絵と同じ置き方）。
func _stage_head(title: String, map_path: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ChronicleStyle.EVENTS_LINE_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := Label.new()
	head.text = tr(title)
	head.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	head.add_theme_color_override("font_color", TavernTheme.INK)
	col.add_child(head)
	var tex: Texture2D = null if map_path.is_empty() else load(map_path) as Texture2D
	if tex != null:
		col.add_child(ChronicleBook.image_rect(tex))
	return col

## 会話の見出し＝戦闘前（開幕）・戦闘中（イベント。取得／喪失の組は event_secured・event_lost）・
## 戦闘後（決着）。中央ぞろえの薄いインク。
func _phase_head(phase: String) -> Control:
	var label := _plain_line(tr("ui.chronicle.phase_" + phase))
	label.add_theme_font_size_override("font_size", ChronicleStyle.COUNT_FONT_SIZE)
	return label

## 会話の1行。話者のいる行＝顔・名前・台詞。場面の切り替え（scene）とト書き（話者なし）は文字だけ。
func _line_row(line: Dictionary) -> Control:
	if line.has("scene"):
		return _plain_line(tr(String(line["scene"])))
	if String(line.get("speaker", "")).is_empty():
		return _plain_line(tr(String(line.get("text", ""))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_face(String(line.get("skin", ""))))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.text = tr(String(line.get("speaker", "")))
	name_label.add_theme_font_size_override("font_size", ChronicleStyle.COUNT_FONT_SIZE)
	name_label.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	col.add_child(name_label)
	var text := Label.new()
	text.text = tr(String(line.get("text", "")))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
	text.add_theme_color_override("font_color", TavernTheme.INK)
	col.add_child(text)
	row.add_child(col)
	return row

func _plain_line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", ChronicleStyle.COUNT_FONT_SIZE)
	label.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	return label

## 顔の小さな絵＝会話パネルと同じ絵（portrait 優先、無ければ盤の絵）を実体だけ切り出して枠に収める。
## 絵が無ければ同じ大きさの空き＝行の頭が揃う。
func _face(skin_id: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(ChronicleStyle.EVENTS_FACE_SIZE, ChronicleStyle.EVENTS_FACE_SIZE)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := SkinCatalog.skin_by_id(_skins, skin_id)
	if skin == null:
		return box
	for slot in ["portrait", "map"]:
		var path := skin.image(slot)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var art := _art_rect(_cropped(tex, path), false)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(art)
		break
	return box

# ---------------------------------------------------------------------------
# 設定集（LORE）
# ---------------------------------------------------------------------------

## 選択中の冒険譚の設定集を出す。解放された節を順に出し、未解放があれば末尾に1行。
## 設定集データは data/chronicle/<冒険譚 id>.json（ChronicleLoader）から取得する＝ゲーム進行データとは分離。
func _build_lore() -> void:
	if _progress == null:
		return
	var chronicle := ChronicleLoader.load_for(_selected_campaign_id)
	var lore: Array = chronicle["lore"]
	if lore.is_empty():
		_build_placeholder(tr("ui.chronicle.lore"))
		return

	var has_locked := false
	for section in lore:
		if not _is_lore_section_unlocked(_selected_campaign_id, section):
			has_locked = true
			break
		_build_lore_section(_selected_campaign_id, String(section["id"]))

	if has_locked:
		var locked_label := Label.new()
		locked_label.text = tr("ui.chronicle.lore_locked")
		locked_label.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
		locked_label.add_theme_color_override("font_color", ChronicleStyle.DIM_GRAY)
		locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content_box.add_child(locked_label)

## 設定集の節が解放済みかを判定。unlock 条件をすべて満たしていれば解放（AND評価）。
## CampaignProgress.stage_state() の公開 API だけで判定する＝進行データへの依存を最小に。
func _is_lore_section_unlocked(campaign_id: String, section: Dictionary) -> bool:
	for cond in section["unlock"]:
		if typeof(cond) != TYPE_DICTIONARY:
			continue
		match String(cond.get("type", "")):
			"cleared":
				if _progress.stage_state(campaign_id, String(cond.get("stage", ""))) != CampaignProgress.CLEARED:
					return false
			_:
				return false  # 未知の条件は未充足側に倒す
	return true

## 設定集の1節を出す。見出し＋段落（連番のキーが在るぶんだけ）。
func _build_lore_section(campaign_id: String, section_id: String) -> void:
	# 節見出し
	var title_key := "lore.%s.%s.title" % [campaign_id, section_id]
	var title_text := tr(title_key)
	if title_text != title_key:
		var head := Label.new()
		head.text = title_text
		head.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
		head.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
		_content_box.add_child(head)
	# 段落：lore.<冒険譚>.<節>.1, .2, .3 …
	var p := 1
	while true:
		var key := "lore.%s.%s.%d" % [campaign_id, section_id, p]
		var text := tr(key)
		if text == key:
			break
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
		label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
		_content_box.add_child(label)
		p += 1
	# 節間の余白
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ChronicleStyle.CATEGORY_GAP)
	_content_box.add_child(spacer)

# ---------------------------------------------------------------------------
# 物語（STORY）と本のめくり
# ---------------------------------------------------------------------------

## 物語の見開き。全ステージをクリアするまでは紙を出さず1行だけ。
func _build_book() -> void:
	if _progress == null:
		return
	if not _progress.is_all_cleared(_selected_campaign_id):
		var locked := Label.new()  # 読める物が在ることだけを伝える（設定集の「続きは冒険のあとで」と同じ）
		locked.text = tr("ui.chronicle.story_locked")
		locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		locked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		locked.custom_minimum_size = Vector2(0, ChronicleBook.SHEET_SIZE.y)  # 紙が出る場所の真ん中に置く
		locked.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
		locked.add_theme_color_override("font_color", ChronicleStyle.DIM_GRAY)
		_content_box.add_child(locked)
		return
	var total := ChronicleBook.page_count(_selected_campaign_id)
	if total == 0:
		return
	_add_book(ChronicleBook.build_spread(_selected_campaign_id, _story_left), total)

## 本＝見開きと、その下のめくりの板とページ番号。いまの節の開いている見開き（_left()）で組む。
func _add_book(spread: Control, total: int) -> void:
	var left := _left()
	var book := VBoxContainer.new()
	book.add_theme_constant_override("separation", ChronicleBook.NAV_GAP)
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book.add_child(spread)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", ChronicleBook.NAV_GAP)
	var prev := _page_button("ui.chronicle.page_prev", -2, left > 1)
	var next := _page_button("ui.chronicle.page_next", 2, left + 1 < total)
	var number := Label.new()
	if left + 1 <= total:
		number.text = tr("ui.chronicle.page_number") % [left, left + 1, total]
	else:  # 最後の見開きの右が白紙
		number.text = tr("ui.chronicle.page_number_single") % [left, total]
	number.add_theme_font_size_override("font_size", ChronicleStyle.TAB_FONT_SIZE)
	number.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
	nav.add_child(prev)
	nav.add_child(number)
	nav.add_child(next)
	book.add_child(nav)
	_content_box.add_child(book)

func _page_button(key: String, step: int, enabled: bool) -> Button:
	var b := TavernTheme.wood_button(tr(key))
	b.custom_minimum_size = Vector2(ChronicleStyle.TAB_HEIGHT * 2, ChronicleStyle.TAB_HEIGHT)
	b.add_theme_font_size_override("font_size", ChronicleStyle.TAB_FONT_SIZE)
	b.disabled = not enabled
	if not enabled:
		TavernTheme.dim_wood_button(b)
	b.pressed.connect(_turn_page.bind(step))
	return b

## いまの節で開いている見開きの左ページ（奇数）。節ごとに別に覚える。
func _left() -> int:
	return _events_left if _section == Section.EVENTS else _story_left

## いまの節のページ数。会話／イベントは振り分けが済んでいなければ 0。
func _page_total() -> int:
	if _section == Section.EVENTS:
		return _events_pages.size()
	return ChronicleBook.page_count(_selected_campaign_id)

## 見開きを step ページぶんめくる（±2）。端を越えるなら何もしない。
func _turn_page(step: int) -> void:
	var left := _left() + step
	if left < 1 or left > _page_total():
		return
	if _section == Section.EVENTS:
		_events_left = left
	else:
		_story_left = left
	SfxPlayer.play_event("menu_select")  # めくる音の素材が来るまで選択音で代える
	rebuild()

## ← → キーでもめくる。ボタンのフォーカス移動より先に取る（本の節を開いているときだけ）。
func _input(event: InputEvent) -> void:
	if _selected_campaign_id.is_empty() or not is_visible_in_tree():
		return
	if _section != Section.STORY and _section != Section.EVENTS:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_LEFT:
		_turn_page(-2)
	elif key.keycode == KEY_RIGHT:
		_turn_page(2)
	else:
		return
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# 冒険譚まるごとの集計
# ---------------------------------------------------------------------------

## 冒険譚ランク＝全ステージのベストランクのうち最も低いもの。未ランクがあれば空。
func _campaign_rank(campaign_id: String, stages: Array) -> String:
	var worst := "S"
	for s in stages:
		var r := _progress.best_rank(campaign_id, s["id"])
		if r.is_empty():
			return ""
		if RankEvaluator.is_better(worst, r):
			worst = r
	return worst

## クリア時間の合計＝各ステージのベストの和。未記録があれば 0。
func _campaign_total_time(campaign_id: String, stages: Array) -> int:
	var total := 0
	for s in stages:
		var t := _progress.best_time(campaign_id, s["id"])
		if t == 0:
			return 0
		total += t
	return total

## 秒を表示用テキストにする（stage_tally.gd と同じ形式）。
func _format_duration(seconds: int) -> String:
	var total := maxi(seconds, 0)
	var days := total / 86400
	var hours := (total % 86400) / 3600
	var minutes := (total % 3600) / 60
	if days > 0:
		return tr("ui.result.time_days") % [days, hours, minutes]
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total % 60]
	return "%d:%02d" % [minutes, total % 60]
