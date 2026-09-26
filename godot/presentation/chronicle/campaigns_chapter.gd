extends ChronicleCardChapter
class_name ChronicleCampaignsChapter
## クロニクルの冒険譚章。仕様 → doc/gdd/chronicle.md 冒険譚の一覧
##
## 上の段は冒険譚の一覧＝羊皮紙のカードの格子（ユニット・陣形スキルと同じ紙）。1つ選ぶと
## その冒険譚に入り、戦果／物語／設定集をタブで切り替える。左の目次は変えない。戻るで一覧へ上がる。
## 物語の通し読みは別の層に出る（ChronicleStoryReader）＝この章が持って開く。

enum Section { RESULTS, STORY, LORE }
const SECTION_KEYS := ["ui.chronicle.results", "ui.chronicle.story", "ui.chronicle.lore"]

## 絵の面の縦／横＝ステージセレクトの冒険譚カードの絵の枠（317×230・doc/gdd/stage_select.md）。
const ART_ASPECT := 230.0 / 317.0

var _selected_campaign_id := ""  # 冒険譚を選んでいるとき（空なら一覧）
var _section: int = Section.RESULTS
var _tabs: HFlowContainer  # 戦果／物語／設定集のタブ＝スクロールの外（冒険譚を開いているときだけ見せる）
var _reader: ChronicleStoryReader = null  # 物語の通し読み（この画面の上に開く）

func _ready() -> void:
	super()
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", ChronicleStyle.TAB_GAP)
	_tabs.add_theme_constant_override("v_separation", ChronicleStyle.TAB_GAP)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.visible = false
	add_child(_tabs)
	move_child(_tabs, 0)
	# 通し読みは自分より前面の層に自分で出る＝読むあいだは目次ごと覆う。
	_reader = ChronicleStoryReader.new()
	_reader.name = "StoryReader"
	add_child(_reader)

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
	_section = Section.RESULTS

func refresh_labels() -> void:
	super()
	_reader.refresh_labels()

func rebuild() -> void:
	super()
	_rebuild_tabs()

func back_label() -> String:
	return "ui.chronicle.back" if _selected_campaign_id.is_empty() else "ui.chronicle.back_campaigns"

## 冒険譚を開いていれば一覧へ戻る。一覧にいれば画面に任せる。
func handle_back() -> bool:
	if _selected_campaign_id.is_empty():
		return false
	SfxPlayer.play_event("menu_back")
	_selected_campaign_id = ""
	_section = Section.RESULTS
	rebuild()
	back_label_changed.emit()
	return true

# ---------------------------------------------------------------------------
# タブ
# ---------------------------------------------------------------------------

## 戦果／物語／設定集。いま開いているタブにだけ細枠を回す（マニュアルのタブと同じ）。
func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	_tabs.visible = not _selected_campaign_id.is_empty()
	if not _tabs.visible:
		return
	for i in SECTION_KEYS.size():
		var b := TavernTheme.wood_button(tr(String(SECTION_KEYS[i])))
		b.custom_minimum_size = Vector2(0, ChronicleStyle.TAB_HEIGHT)
		b.add_theme_font_size_override("font_size", ChronicleStyle.TAB_FONT_SIZE)
		b.pressed.connect(_on_tab.bind(i))
		var frame := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.set_border_width_all(ChronicleStyle.FRAME_WIDTH)
		box.border_color = ChronicleStyle.FRAME_COLOR if i == _section else Color(0, 0, 0, 0)
		box.set_content_margin_all(ChronicleStyle.FRAME_PAD)
		frame.add_theme_stylebox_override("panel", box)
		frame.add_child(b)
		_tabs.add_child(frame)

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
		Section.STORY:
			_build_story()
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
	_section = Section.RESULTS
	SfxPlayer.play_event("menu_select")
	rebuild()
	back_label_changed.emit()

# ---------------------------------------------------------------------------
# 戦果（2段目・RESULTS）
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
# 物語（2段目・STORY）
# ---------------------------------------------------------------------------

## 章題を並べる。押すとその章から通し読みが始まる（先頭は「はじめから」）。
## 並ぶのは経験した章だけ＝見ていない出来事の存在を匂わせない（doc/gdd/chronicle.md 物語）。
func _build_story() -> void:
	if _progress == null:
		return
	var campaign := _progress.campaign(_selected_campaign_id)
	if campaign.is_empty():
		return
	var chronicle := ChronicleLoader.load_for(_selected_campaign_id)
	var chapters := ChronicleStory.load(_selected_campaign_id, chronicle["story"], campaign, _progress)
	if chapters.is_empty():
		_build_placeholder(tr("ui.chronicle.story_empty"))
		return

	var head := Label.new()
	head.text = tr("ui.chronicle.story")
	head.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	head.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
	_content_box.add_child(head)

	_content_box.add_child(_story_button(tr("ui.chronicle.story_from_start"), chapters, 0))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ChronicleStyle.CATEGORY_GAP)
	_content_box.add_child(spacer)
	for i in chapters.size():
		var chapter: Dictionary = chapters[i]
		_content_box.add_child(_story_button(tr(String(chapter["title"])), chapters, i))

## 章題1行のボタン（冒険譚の一覧と同じ手つき）。
func _story_button(text: String, chapters: Array, index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, ChronicleStyle.ITEM_HEIGHT)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "  " + text
	btn.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
	btn.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.pressed.connect(func() -> void: _open_story(chapters, index))
	return btn

## 通し読みを開く。読んでいるあいだ、この画面は板の裏に置いたまま。
func _open_story(chapters: Array, index: int) -> void:
	SfxPlayer.play_event("menu_select")
	_reader.open(chapters, index, _skins)

# ---------------------------------------------------------------------------
# 設定集（2段目・LORE）
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
