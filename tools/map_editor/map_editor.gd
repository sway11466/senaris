extends Control
## マップエディタ（開発ツール）。tools/map_editor/map_editor.tscn を Godot エディタで F6（指定シーンを実行）。
##
## stage.json の項目を編集する（戦闘前後の会話 dialogue は対象外＝読み込んだまま温存して保存）。
## terrain_skins・未知キーも同様に温存。スキーマの解釈は StageLoader に合わせる。
## 個別上書きキー（move/troops/atk 等）は編集しない方針（ステージは type/skin の素の性能で組む）。
## 製品には含めない（tools/ は export プリセットの除外対象にする）。

const STAGES_DIR := "res://data/stages"
const MODE_LABELS := { "select": "選択", "terrain": "地形", "player": "自軍", "enemy": "敵", "base": "拠点" }
const TEAM_LABELS := { "player": "自軍", "enemy": "敵", "neutral": "中立" }
const KIND_LABELS := { "fort": "砦 (fort)", "hq": "本拠地 (hq)" }

var _doc: MapEditorDoc
var _path := ""  # 現在のファイル（グローバルパス。空=未保存）
var _mode := "terrain"

# カタログ（表示順は定義ファイル順）
var _terrains: Array = []    # [{ id, char, memo }]
var _unit_types: Array = []  # [type_id]
var _skins: Array = []       # [{ skin_id, type_id }]
var _ai_presets: Array = []  # [label]
var _ai_names := {}          # label -> 表示名

# パレット選択状態
var _sel_terrain := 0
var _sel_type := 0
var _sel_skin := 0
var _sel_squad := 0
var _base_team := "enemy"
var _base_kind := "fort"
var _base_ai := ""

# UI参照
var _board: MapEditorBoard
var _path_label: Label
var _status: Label
var _name_edit: LineEdit
var _turn_spin: SpinBox
var _cols_spin: SpinBox
var _rows_spin: SpinBox
var _mode_box: VBoxContainer
var _inspector: VBoxContainer
var _victory_box: VBoxContainer
var _mode_buttons := {}
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _confirm: ConfirmationDialog
var _confirm_cb := Callable()
var _press_cell := Vector2i(-1, -1)  # 選択モードのドラッグ移動の起点


func _ready() -> void:
	get_window().title = "Senaris マップエディタ"
	get_window().min_size = Vector2i(1200, 760)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_catalogs()
	_doc = MapEditorDoc.new_stage()
	_build_ui()
	_sync_fields()
	_set_mode("terrain")
	_refresh_victory()


func _load_catalogs() -> void:
	var tt: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain/terrain_type.json"))
	for t in tt.get("terrains", []):
		_terrains.append({ "id": String(t["id"]), "char": String(t.get("char", "?")), "memo": String(t.get("memo", "")) })
	var ut: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/unit_type.json"))
	for t in ut.get("types", []):
		_unit_types.append(String(t["id"]))
	var us: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/unit_skin.json"))
	for type_id in us.get("skins", {}):
		for side in ["ally", "enemy"]:
			for s in us["skins"][type_id].get(side, []):
				_skins.append({ "skin_id": String(s.get("skin_id", "")), "type_id": String(type_id) })
	var ai := AiCatalog.load_default()
	for label in ai:
		_ai_presets.append(String(label))
		_ai_names[label] = String(ai[label].get("name", label))


# --- UI構築 ---


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# ツールバー
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	_add_button(bar, "新規", _on_new)
	_add_button(bar, "開く", func() -> void: _open_dialog.popup_centered(Vector2i(900, 600)))
	_add_button(bar, "保存", _on_save)
	_add_button(bar, "名前を付けて保存", func() -> void: _save_dialog.popup_centered(Vector2i(900, 600)))
	_path_label = Label.new()
	_path_label.text = "（未保存の新規ステージ）"
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.clip_text = true
	_path_label.modulate = Color(1, 1, 1, 0.6)
	bar.add_child(_path_label)
	var zoom_label := Label.new()
	zoom_label.text = "ズーム"
	bar.add_child(zoom_label)
	var zoom := HSlider.new()
	zoom.min_value = 14
	zoom.max_value = 44
	zoom.step = 2
	zoom.value = 26
	zoom.custom_minimum_size = Vector2(140, 0)
	zoom.value_changed.connect(func(v: float) -> void: _board.hex_size = v)
	bar.add_child(zoom)

	# 中央：盤（左・スクロール） + パネル（右）
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 8)
	root.add_child(main)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	_board = MapEditorBoard.new()
	_board.doc = _doc
	_board.cell_pressed.connect(_on_cell_pressed)
	_board.cell_dragged.connect(_on_cell_dragged)
	_board.cell_released.connect(_on_cell_released)
	scroll.add_child(_board)
	_board.refresh()

	var panel_scroll := ScrollContainer.new()
	panel_scroll.custom_minimum_size = Vector2(340, 0)
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(panel_scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	panel_scroll.add_child(panel)

	# ステージ情報
	_add_heading(panel, "ステージ情報")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	panel.add_child(grid)
	_add_label(grid, "name")
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String) -> void: _doc.data["name"] = t)
	grid.add_child(_name_edit)
	_add_label(grid, "turn_limit")
	_turn_spin = _make_spin(1, 999, 30)
	_turn_spin.value_changed.connect(func(v: float) -> void: _doc.data["turn_limit"] = int(v))
	grid.add_child(_turn_spin)
	_add_label(grid, "cols")
	_cols_spin = _make_spin(4, 99, 12)
	grid.add_child(_cols_spin)
	_add_label(grid, "rows")
	_rows_spin = _make_spin(4, 99, 8)
	grid.add_child(_rows_spin)
	_add_button(panel, "サイズを適用（縮小で範囲外の駒は削除）", _on_resize)

	# モード
	panel.add_child(HSeparator.new())
	_add_heading(panel, "モード")
	var modes := HBoxContainer.new()
	panel.add_child(modes)
	var group := ButtonGroup.new()
	for m in MODE_LABELS:
		var b := Button.new()
		b.text = MODE_LABELS[m]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_set_mode.bind(m))
		modes.add_child(b)
		_mode_buttons[m] = b
	_mode_box = VBoxContainer.new()
	_mode_box.add_theme_constant_override("separation", 6)
	panel.add_child(_mode_box)

	# 勝利条件
	panel.add_child(HSeparator.new())
	_add_heading(panel, "勝利条件（敵全滅は常に有効）")
	_victory_box = VBoxContainer.new()
	panel.add_child(_victory_box)

	# ステータス行
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	root.add_child(_status)

	# ダイアログ類
	_open_dialog = _make_file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	_open_dialog.file_selected.connect(_on_open_file)
	_save_dialog = _make_file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	_save_dialog.file_selected.connect(_write)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func() -> void:
		if _confirm_cb.is_valid():
			_confirm_cb.call())
	add_child(_confirm)


func _make_file_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = mode
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.json ; JSON ステージ"])
	d.current_dir = ProjectSettings.globalize_path(STAGES_DIR)
	add_child(d)
	return d


func _add_heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)


func _add_label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)


func _add_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _make_spin(minv: float, maxv: float, value: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = value
	sb.custom_minimum_size = Vector2(110, 0)
	return sb


func _say(msg: String) -> void:
	_status.text = msg


func _ask(text: String, cb: Callable) -> void:
	_confirm_cb = cb
	_confirm.dialog_text = text
	_confirm.popup_centered()


# --- モード切替とパレット ---


func _set_mode(mode: String) -> void:
	_mode = mode
	_mode_buttons[mode].button_pressed = true
	_board.selected = Vector2i(-1, -1)
	_board.queue_redraw()
	for c in _mode_box.get_children():
		c.queue_free()
	match mode:
		"select":
			_add_hint(_mode_box, "クリック＝選択して下に表示。ドラッグ＝駒/拠点を移動。")
			_inspector = VBoxContainer.new()
			_inspector.add_theme_constant_override("separation", 6)
			_mode_box.add_child(_inspector)
		"terrain":
			_add_hint(_mode_box, "左ドラッグ＝塗る / 右ドラッグ＝平地に戻す")
			var list := ItemList.new()
			list.custom_minimum_size = Vector2(0, 320)
			for t in _terrains:
				list.add_item("%s  %s — %s" % [t["char"], t["id"], t["memo"]])
			list.select(_sel_terrain)
			list.item_selected.connect(func(i: int) -> void: _sel_terrain = i)
			_mode_box.add_child(list)
		"player":
			_add_hint(_mode_box, "左クリック＝配置 / 右クリック＝駒を削除")
			var ob := OptionButton.new()
			for id in _unit_types:
				ob.add_item(id)
			ob.select(_sel_type)
			ob.item_selected.connect(func(i: int) -> void: _sel_type = i)
			_mode_box.add_child(ob)
		"enemy":
			_build_enemy_palette()
		"base":
			_add_hint(_mode_box, "左クリック＝設置 / 右クリック＝拠点を削除。\n控え（garrison）は「選択」モードで拠点を選んで編集。")
			_mode_box.add_child(_labeled_option("所属", TEAM_LABELS.keys(), TEAM_LABELS.values(), _base_team,
				func(k: String) -> void: _base_team = k))
			_mode_box.add_child(_labeled_option("種別", KIND_LABELS.keys(), KIND_LABELS.values(), _base_kind,
				func(k: String) -> void: _base_kind = k))
			var ai_opts := _ai_options(true)
			_mode_box.add_child(_labeled_option("AI出撃", ai_opts[0], ai_opts[1], _base_ai,
				func(k: String) -> void: _base_ai = k))


func _add_hint(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 0.6)
	parent.add_child(l)


## ラベル＋OptionButton の行。keys[i] を displays[i] で表示し、選択で on_pick(keys[i]) を呼ぶ。
func _labeled_option(label: String, keys: Array, displays: Array, current: String, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	_add_label(row, label)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in keys.size():
		ob.add_item(String(displays[i]))
		if String(keys[i]) == current:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: on_pick.call(String(keys[i])))
	row.add_child(ob)
	return row


## AIプリセットの選択肢（with_none=true で先頭に「なし」＝空文字）。[keys, displays] を返す。
func _ai_options(with_none: bool) -> Array:
	var keys := []
	var displays := []
	if with_none:
		keys.append("")
		displays.append("（なし）")
	for k in _ai_presets:
		keys.append(k)
		displays.append("%s（%s）" % [k, _ai_names[k]])
	return [keys, displays]


func _build_enemy_palette() -> void:
	_add_hint(_mode_box, "左クリック＝選択中の部隊に配置 / 右クリック＝駒を削除")
	var squads: Array = _doc.data["enemy"]
	if _sel_squad >= squads.size():
		_sel_squad = maxi(squads.size() - 1, 0)
	# 部隊の選択と追加/削除
	var row := HBoxContainer.new()
	_mode_box.add_child(row)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in squads.size():
		ob.add_item("部隊%d: %s（%s）" % [i, String(squads[i].get("name", "無名")), String(squads[i].get("ai", "?"))])
	if not squads.is_empty():
		ob.select(_sel_squad)
	ob.item_selected.connect(func(i: int) -> void:
		_sel_squad = i
		_set_mode("enemy"))
	row.add_child(ob)
	_add_button(row, "追加", func() -> void:
		_sel_squad = _doc.add_squad(_ai_presets[0] if not _ai_presets.is_empty() else "charge")
		_set_mode("enemy"))
	if not squads.is_empty():
		_add_button(row, "削除", func() -> void:
			_ask("部隊%d を所属ユニットごと削除します。よろしいですか？" % _sel_squad, func() -> void:
				_doc.remove_squad(_sel_squad)
				_sel_squad = 0
				_set_mode("enemy")
				_board.refresh()))
	if squads.is_empty():
		_add_hint(_mode_box, "部隊がありません。「追加」するか、盤をクリックすると自動で作成します。")
		return
	var sq: Dictionary = squads[_sel_squad]
	# 部隊名
	var name_row := HBoxContainer.new()
	_mode_box.add_child(name_row)
	_add_label(name_row, "部隊名")
	var name_edit := LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text = String(sq.get("name", ""))
	name_edit.placeholder_text = "（省略可）"
	name_edit.text_changed.connect(func(t: String) -> void:
		if t == "":
			sq.erase("name")
		else:
			sq["name"] = t)
	name_row.add_child(name_edit)
	# AIプリセット
	var ai_opts := _ai_options(false)
	_mode_box.add_child(_labeled_option("AI", ai_opts[0], ai_opts[1], String(sq.get("ai", "")),
		func(k: String) -> void: sq["ai"] = k))
	# 配置するスキン
	var skin_ob := OptionButton.new()
	for i in _skins.size():
		skin_ob.add_item("%s（%s）" % [_skins[i]["skin_id"], _skins[i]["type_id"]])
	skin_ob.select(_sel_skin)
	skin_ob.item_selected.connect(func(i: int) -> void: _sel_skin = i)
	_mode_box.add_child(skin_ob)


# --- 盤の操作 ---


func _on_cell_pressed(col: int, row: int, button: int) -> void:
	match _mode:
		"terrain":
			_paint(col, row, button)
		"player":
			if button == MOUSE_BUTTON_LEFT:
				if _doc.add_player(_unit_types[_sel_type], col, row):
					_board.refresh()
				else:
					_say("そのマスには既に駒があります。")
			else:
				if _doc.remove_unit_at(col, row):
					_board.refresh()
		"enemy":
			if button == MOUSE_BUTTON_LEFT:
				if _doc.data["enemy"].is_empty():
					_sel_squad = _doc.add_squad(_ai_presets[0] if not _ai_presets.is_empty() else "charge")
					_set_mode("enemy")
				if _doc.add_enemy(_sel_squad, _skins[_sel_skin]["skin_id"], col, row):
					_board.refresh()
				else:
					_say("そのマスには既に駒があります。")
			else:
				if _doc.remove_unit_at(col, row):
					_board.refresh()
		"base":
			if button == MOUSE_BUTTON_LEFT:
				if _doc.add_base(col, row, _base_team, _base_kind, _base_ai):
					_board.refresh()
				else:
					_say("そのマスには既に拠点があります。")
			else:
				if _doc.remove_base_at(col, row):
					_board.refresh()
		"select":
			_press_cell = Vector2i(col, row)
			_board.selected = _press_cell
			_board.queue_redraw()
			_show_inspection(col, row)


func _on_cell_dragged(col: int, row: int, button: int) -> void:
	if _mode == "terrain":
		_paint(col, row, button)


func _on_cell_released(col: int, row: int, _button: int) -> void:
	if _mode != "select" or _press_cell.x < 0:
		return
	var to := Vector2i(col, row)
	if to != _press_cell:
		if _doc.move(_press_cell.x, _press_cell.y, to.x, to.y):
			_board.selected = to
			_board.refresh()
			_show_inspection(to.x, to.y)
		else:
			_say("そこへは移動できません（範囲外か、同じ種類が既にあります）。")
	_press_cell = Vector2i(-1, -1)


func _paint(col: int, row: int, button: int) -> void:
	var ch := MapEditorDoc.DEFAULT_CHAR if button == MOUSE_BUTTON_RIGHT else String(_terrains[_sel_terrain]["char"])
	_doc.set_terrain_char(col, row, ch)
	_board.queue_redraw()


# --- 選択モードのインスペクタ ---


func _show_inspection(col: int, row: int) -> void:
	if _inspector == null or not is_instance_valid(_inspector):
		return
	for c in _inspector.get_children():
		c.queue_free()
	var tid := TerrainType.char_to_id(_doc.terrain_char(col, row))
	_add_label(_inspector, "マス (%d, %d)  地形: %s" % [col, row, tid])
	var uh := _doc.unit_at(col, row)
	if not uh.is_empty():
		_inspect_unit(uh)
	var bh := _doc.base_at(col, row)
	if not bh.is_empty():
		_inspect_base(bh)
	if uh.is_empty() and bh.is_empty():
		_add_hint(_inspector, "（駒・拠点なし）")


func _inspect_unit(hit: Dictionary) -> void:
	var u: Dictionary = hit["unit"]
	var squad := int(hit["squad"])
	var ids := _doc.computed_ids()
	var id := int(ids.get("p:%d" % hit["index"] if squad < 0 else "e:%d:%d" % [squad, hit["index"]], 0))
	var head := "自軍: %s" % String(u.get("type", u.get("skin", "?"))) if squad < 0 \
		else "敵（部隊%d）: %s" % [squad, String(u.get("skin", u.get("type", "?")))]
	_add_label(_inspector, head)
	_add_label(_inspector, "id: %d%s" % [id, "（明示）" if u.has("id") else "（自動採番）"])
	if u.has("passengers") and not u["passengers"].is_empty():
		_add_hint(_inspector, "同乗 %d 体（passengers は JSON 直接編集）" % u["passengers"].size())
	if squad >= 0:
		_add_button(_inspector, "ボス指定（撃破で勝利条件に追加）", func() -> void:
			var bid := _doc.set_boss(squad, int(hit["index"]))
			_say("id %d を勝利条件（defeat_unit）に追加しました。" % bid)
			_board.refresh()
			_refresh_victory()
			_show_inspection(int(u["col"]), int(u["row"])))
	_add_button(_inspector, "この駒を削除", func() -> void:
		_doc.remove_unit_at(int(u.get("col", 0)), int(u.get("row", 0)))
		_board.refresh()
		_show_inspection(int(u.get("col", 0)), int(u.get("row", 0))))


func _inspect_base(hit: Dictionary) -> void:
	var b: Dictionary = hit["base"]
	_add_label(_inspector, "拠点")
	_inspector.add_child(_labeled_option("所属", TEAM_LABELS.keys(), TEAM_LABELS.values(),
		String(b.get("team", "neutral")),
		func(k: String) -> void:
			b["team"] = k
			_board.refresh()))
	_inspector.add_child(_labeled_option("種別", KIND_LABELS.keys(), KIND_LABELS.values(),
		String(b.get("kind", "fort")),
		func(k: String) -> void:
			b["kind"] = k
			_board.refresh()))
	var ai_opts := _ai_options(true)
	_inspector.add_child(_labeled_option("AI出撃", ai_opts[0], ai_opts[1], String(b.get("ai", "")),
		func(k: String) -> void:
			if k == "":
				b.erase("ai")
			else:
				b["ai"] = k))
	# 控え（garrison）
	_add_label(_inspector, "控え（garrison）")
	if typeof(b.get("garrison")) != TYPE_ARRAY:
		b["garrison"] = []
	var g: Array = b["garrison"]
	for i in g.size():
		var entry: Dictionary = g[i]
		var row := HBoxContainer.new()
		_inspector.add_child(row)
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var current := String(entry.get("skin", entry.get("type", "")))
		for j in _skins.size():
			ob.add_item("%s（%s）" % [_skins[j]["skin_id"], _skins[j]["type_id"]])
			if _skins[j]["skin_id"] == current:
				ob.select(j)
		ob.item_selected.connect(func(j: int) -> void:
			entry["skin"] = _skins[j]["skin_id"]
			entry.erase("type")
			_board.refresh())
		row.add_child(ob)
		var count := _make_spin(1, 20, maxi(int(entry.get("count", 1)), 1))
		count.custom_minimum_size = Vector2(70, 0)
		count.value_changed.connect(func(v: float) -> void:
			entry["count"] = int(v)
			_board.refresh())
		row.add_child(count)
		_add_button(row, "×", func() -> void:
			g.remove_at(i)
			_board.refresh()
			_show_inspection(int(b["col"]), int(b["row"])))
	_add_button(_inspector, "控えを追加", func() -> void:
		g.append({ "skin": _skins[0]["skin_id"], "count": 1 })
		_board.refresh()
		_show_inspection(int(b["col"]), int(b["row"])))
	_add_button(_inspector, "この拠点を削除", func() -> void:
		_doc.remove_base_at(int(b["col"]), int(b["row"]))
		_board.refresh()
		_show_inspection(int(b["col"]), int(b["row"])))


# --- 勝利条件 ---


func _refresh_victory() -> void:
	for c in _victory_box.get_children():
		c.queue_free()
	var list := _doc.victory_list()
	if list.is_empty():
		_add_hint(_victory_box, "（追加条件なし）")
		return
	for i in list.size():
		var c: Dictionary = list[i]
		var row := HBoxContainer.new()
		_victory_box.add_child(row)
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s: unit_id=%d" % [String(c.get("type", "?")), int(c.get("unit_id", 0))] \
			if c.has("unit_id") else String(c.get("type", "?"))
		row.add_child(l)
		_add_button(row, "×", func() -> void:
			_doc.remove_victory(i)
			_refresh_victory())


# --- ファイル操作 ---


func _on_new() -> void:
	_ask("未保存の変更は失われます。新規ステージを作成しますか？", func() -> void:
		_doc = MapEditorDoc.new_stage()
		_path = ""
		_after_load())


func _on_open_file(path: String) -> void:
	var doc := MapEditorDoc.from_text(FileAccess.get_file_as_string(path))
	if doc == null:
		_say("読み込めませんでした（JSONが不正）: " + path)
		return
	_doc = doc
	_path = path
	_after_load()
	_say("読み込みました: " + path)


## doc 差し替え後の共通処理（フィールド同期・盤/パレット/勝利条件の再構築）。
func _after_load() -> void:
	_sel_squad = 0
	_board.doc = _doc
	_sync_fields()
	_board.refresh()
	_set_mode(_mode)
	_refresh_victory()


func _sync_fields() -> void:
	_name_edit.text = String(_doc.data.get("name", ""))
	_turn_spin.set_value_no_signal(maxf(int(_doc.data.get("turn_limit", 30)), 1))
	_cols_spin.set_value_no_signal(_doc.cols())
	_rows_spin.set_value_no_signal(_doc.rows())
	_path_label.text = _path if _path != "" else "（未保存の新規ステージ）"
	_path_label.tooltip_text = _path_label.text


func _on_resize() -> void:
	var dropped := _doc.resize(int(_cols_spin.value), int(_rows_spin.value))
	_board.selected = Vector2i(-1, -1)
	_board.refresh()
	_say("サイズを %d×%d にしました。" % [_doc.cols(), _doc.rows()]
		+ ("範囲外の駒/拠点を %d 件削除しました。" % dropped if dropped > 0 else ""))


func _on_save() -> void:
	if _path == "":
		_save_dialog.popup_centered(Vector2i(900, 600))
	else:
		_write(_path)


func _write(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_say("保存に失敗しました: " + path)
		return
	f.store_string(_doc.to_text())
	f.close()
	_path = path
	_sync_fields()
	_say("保存しました: " + path)
