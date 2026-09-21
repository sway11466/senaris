extends Control
## セーブエディタ（開発ツール）。tools/save_editor/save_editor.tscn を Godot エディタで F6、または
## godot --path godot res://tools/save_editor/save_editor.tscn
##
## 開くのは実機の user:// のファイルだけ（SavePaths＝エディタからデバッグ起動したときと同じ置き場）。
## ファイル選択は持たない。書き込みはストア（ProgressStore / RosterStore / ChronicleStore）を通す
## ＝版と形式の責任はストアに残し、ここは値だけを持つ。純ロジックは save_editor_model.gd。
## 仕様 → doc/backlog.md feature-130。製品には含めない（tools/ は export の除外対象）。

var _progress: ProgressStore
var _roster: RosterStore
var _chronicle: ChronicleStore
var _campaigns: Array = []  # CampaignCatalog.load_all() のデバッグ以外
var _catalog: Dictionary
var _skins: Dictionary

var _campaign_list: ItemList
var _stage_list: ItemList
var _stage_head: Label
var _roster_box: VBoxContainer
var _roster_rows: Array = []  # [{ candidate, check: CheckBox, level: SpinBox, troops: SpinBox }]
var _clear_btn: Button
var _remove_btn: Button
var _status: Label


func _ready() -> void:
	get_window().title = "Senaris セーブエディタ"
	get_window().min_size = Vector2i(1100, 720)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress = ProgressStore.new()
	_roster = RosterStore.new()
	_chronicle = ChronicleStore.new()
	_catalog = UnitCatalog.load_default()
	_skins = SkinCatalog.load_standard()
	for c in CampaignCatalog.load_all():
		if not bool(c.get("debug", false)):
			_campaigns.append(c)
	_build_ui()
	_fill_campaigns()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "セーブエディタ"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var sub := Label.new()
	sub.text = "置き場: %s（%s / %s / %s）。書き込みは各ストアを通す＝実機と同じ形で保存され、直前の中身は世代に退避される。" \
			% [ProjectSettings.globalize_path(SavePaths.dir), ProgressStore.FILE, RosterStore.FILE, ChronicleStore.FILE]
	sub.modulate = Color(1, 1, 1, 0.55)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_campaign_list = ItemList.new()
	_campaign_list.custom_minimum_size = Vector2(260, 0)
	_campaign_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_list.item_selected.connect(_on_campaign_selected)
	body.add_child(_section("冒険譚", _campaign_list))

	_stage_list = ItemList.new()
	_stage_list.custom_minimum_size = Vector2(380, 0)
	_stage_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_list.item_selected.connect(_on_stage_selected)
	body.add_child(_section("ステージ（✓＝クリア済み・ランク・所要時間）", _stage_list))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)

	_stage_head = Label.new()
	_stage_head.text = "ステージを選んでください"
	_stage_head.add_theme_font_size_override("font_size", 18)
	right.add_child(_stage_head)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	right.add_child(btns)
	_clear_btn = Button.new()
	_clear_btn.text = "クリア済みにする（名簿も書く）"
	_clear_btn.disabled = true
	_clear_btn.pressed.connect(_on_mark_cleared)
	btns.add_child(_clear_btn)
	_remove_btn = Button.new()
	_remove_btn.text = "クリア済みデータを消す"
	_remove_btn.disabled = true
	_remove_btn.pressed.connect(_on_remove)
	btns.add_child(_remove_btn)

	var roster_head := Label.new()
	roster_head.text = "名簿＝このステージをクリアした時点の控え。チェック無し＝加入しなかった／兵数0＝離脱（在籍は続く）。既定は全員 Lv1・満員"
	roster_head.modulate = Color(1, 1, 1, 0.55)
	roster_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(roster_head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_roster_box = VBoxContainer.new()
	_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_box)

	var chron := HBoxContainer.new()
	chron.add_theme_constant_override("separation", 12)
	root.add_child(chron)
	var all_on := Button.new()
	all_on.text = "クロニクルを全部ONにする"
	all_on.pressed.connect(_on_all_on)
	chron.add_child(all_on)
	var note := Label.new()
	note.text = "全スキン・全陣形スキル・物語の記録（マニフェストの全ステージ）。物語の通し読みはクリア済みのステージまで出る＝クリア済みは左の欄で"
	note.modulate = Color(1, 1, 1, 0.55)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chron.add_child(note)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _section(head_text: String, body: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := Label.new()
	head.text = head_text
	box.add_child(head)
	box.add_child(body)
	return box


# ---------------------------------------------------------------------------
# 冒険譚・ステージの一覧

func _fill_campaigns() -> void:
	_campaign_list.clear()
	for c in _campaigns:
		_campaign_list.add_item("%s（%s）" % [tr(String(c["title"])), c["id"]])
	if _campaigns.is_empty():
		_say("冒険譚がありません")
		return
	_campaign_list.select(0)
	_on_campaign_selected(0)


func _campaign() -> Dictionary:
	var sel := _campaign_list.get_selected_items()
	return _campaigns[sel[0]] if not sel.is_empty() else {}


func _stage() -> Dictionary:
	var c := _campaign()
	var sel := _stage_list.get_selected_items()
	if c.is_empty() or sel.is_empty():
		return {}
	return c["stages"][sel[0]]


func _on_campaign_selected(_index: int) -> void:
	_fill_stages()
	_refresh_stage()


func _fill_stages() -> void:
	var selected := _stage_list.get_selected_items()
	_stage_list.clear()
	var c := _campaign()
	if c.is_empty():
		return
	var cid := String(c["id"])
	var stages: Array = c["stages"]
	for i in stages.size():
		var sid := String(stages[i]["id"])
		var mark := "✓" if _progress.is_cleared(cid, sid) else "－"
		var extra := ""
		var rank := _progress.best_rank(cid, sid)
		if not rank.is_empty():
			extra += " " + rank
		var t := _progress.best_time(cid, sid)
		if t > 0:
			extra += " %d:%02d" % [t / 60, t % 60]
		_stage_list.add_item("%s %d. %s%s" % [mark, i + 1, tr(String(stages[i]["title"])), extra])
	if not selected.is_empty() and selected[0] < stages.size():
		_stage_list.select(selected[0])


func _on_stage_selected(_index: int) -> void:
	_refresh_stage()


## 右の欄＝選んだステージの状態と名簿の候補を組み直す。
func _refresh_stage() -> void:
	for child in _roster_box.get_children():
		child.queue_free()
	_roster_rows.clear()
	var c := _campaign()
	var s := _stage()
	if s.is_empty():
		_stage_head.text = "ステージを選んでください"
		_clear_btn.disabled = true
		_remove_btn.disabled = true
		return
	var cid := String(c["id"])
	var sid := String(s["id"])
	var cleared := _progress.is_cleared(cid, sid)
	_stage_head.text = "%s ／ %s（%s）" % [tr(String(s["title"])), sid, "クリア済み" if cleared else "未クリア"]
	_clear_btn.disabled = false
	_remove_btn.disabled = not cleared

	var cands := SaveEditorModel.candidates_for(c, sid, _catalog, _skins)
	if cands.is_empty():
		var none := Label.new()
		none.text = "この冒険譚は名簿を使わない（actor 付きの駒が無い）"
		none.modulate = Color(1, 1, 1, 0.55)
		_roster_box.add_child(none)
		return
	var existing := _roster.load_roster(cid, sid)
	var by_actor := {}
	for u in existing:
		by_actor[String((u as Dictionary).get("actor", ""))] = u
	var head := Label.new()
	head.text = "控えあり（%d 体）＝今の値を出す" % existing.size() if not existing.is_empty() else "控えなし＝既定値を出す"
	head.modulate = Color(1, 1, 1, 0.55)
	_roster_box.add_child(head)
	for cand in cands:
		_add_roster_row(cand, by_actor.get(cand["actor"], {}), existing.is_empty())


func _add_roster_row(cand: Dictionary, known: Dictionary, fresh: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_roster_box.add_child(row)
	var max_troops := int(cand["max_troops"])

	var check := CheckBox.new()
	check.text = "%s（%s）" % [cand["actor"], cand["type"]]
	check.custom_minimum_size = Vector2(280, 0)
	check.button_pressed = fresh or not known.is_empty()
	row.add_child(check)

	var lv_label := Label.new()
	lv_label.text = "Lv"
	row.add_child(lv_label)
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = 99
	level.value = int(known.get("level", 1))
	row.add_child(level)

	var tr_label := Label.new()
	tr_label.text = "兵"
	row.add_child(tr_label)
	var troops := SpinBox.new()
	troops.min_value = 0
	troops.max_value = max_troops
	troops.value = int(known.get("troops", max_troops))
	row.add_child(troops)
	var max_label := Label.new()
	max_label.text = "/ %d" % max_troops
	max_label.modulate = Color(1, 1, 1, 0.55)
	row.add_child(max_label)

	_roster_rows.append({ "candidate": cand, "check": check, "level": level, "troops": troops })


# ---------------------------------------------------------------------------
# 操作

func _on_mark_cleared() -> void:
	var c := _campaign()
	var s := _stage()
	if s.is_empty():
		return
	var cid := String(c["id"])
	var sid := String(s["id"])
	_progress.mark_cleared(cid, sid)
	if _roster_rows.is_empty():
		_say("%s をクリア済みにしました" % sid)
	else:
		var units: Array = []
		for r in _roster_rows:
			if (r["check"] as CheckBox).button_pressed:
				units.append(SaveEditorModel.roster_entry(r["candidate"],
						int((r["level"] as SpinBox).value), int((r["troops"] as SpinBox).value)))
		_roster.save_roster(cid, sid, units)
		_say("%s をクリア済みにし、名簿の控え（%d 体）を書きました" % [sid, units.size()])
	_fill_stages()
	_refresh_stage()


func _on_remove() -> void:
	var c := _campaign()
	var s := _stage()
	if s.is_empty():
		return
	var cid := String(c["id"])
	var sid := String(s["id"])
	_progress.remove_stage(cid, sid)
	_roster.clear_roster(cid, sid)
	_say("%s のクリア済みデータ（クリア済み・ランク・所要時間・経験した会話・名簿の控え）を消しました" % sid)
	_fill_stages()
	_refresh_stage()


func _on_all_on() -> void:
	var n := SaveEditorModel.all_on(_progress, _chronicle, _campaigns, ChronicleLoader.load_all(), _catalog, _skins)
	_chronicle.save()
	_say("クロニクルを全部ONにしました（スキン +%d・陣形スキル +%d・物語の記録 %d ステージ）" \
			% [n["skins"], n["skills"], n["stages"]])


func _say(text: String) -> void:
	_status.text = text
	print("save_editor: " + text)
