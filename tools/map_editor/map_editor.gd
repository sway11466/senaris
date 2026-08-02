extends Control
## マップエディタ（開発ツール）。tools/map_editor/map_editor.tscn を Godot エディタで F6（指定シーンを実行）。
##
## stage.json の項目を編集する（戦闘前後の会話 dialogue は対象外＝読み込んだまま温存して保存）。
## 未知キーも同様に温存。スキーマの解釈は StageLoader に合わせる。
## 性能はステージから上書きできない（type が唯一の出どころ）＝駒は type/skin と位置で組む。
## 製品には含めない（tools/ は export プリセットの除外対象にする）。

const CsvUtil := preload("res://data/csv_util.gd")  # skin 一覧は正本CSVを読む（分類ごとに整列済み＝パレットの並びが素直）

const STAGES_DIR := "res://data/stages"
const STANDARD_CATEGORY := "基準"  ## 味方専用スキンの分類＝敵パレットには出さない
const MODE_LABELS := { "select": "選択", "terrain": "地形", "player": "自軍", "enemy": "敵", "base": "拠点" }
const TOOL_LABELS := { "pen": "ペン（1マスずつ）", "fill": "ベタ塗り（地続きをまとめて）" }
const TEAM_LABELS := { "player": "自軍", "enemy": "敵", "neutral": "中立" }
const KIND_LABELS := { "fort": "砦 (fort)", "hq": "本拠地 (hq)" }

var _doc: MapEditorDoc
var _path := ""  # 現在のファイル（グローバルパス。空=未保存）
var _mode := "terrain"

# カタログ（表示順は定義ファイル順）
var _terrains: Array = []    # [{ id, char, memo }]
var _unit_types: Array = []  # [{ id, category }]
var _categories: Array = []  # 分類（category）の一覧（出現順）
var _skins: Array = []           # [{ skin_id, type_id, category }]（CSV順＝分類ごとに整列済み）
var _skin_categories: Array = [] # 敵パレット用の分類一覧（基準を除く・出現順）
var _terrain_skins: Array = []       # [{ skin_id, terrain_type, name, memo }]（CSV順）
var _default_skin_by_type := {}      # terrain_type -> 既定スキンの skin_id（TerrainSkinCatalog と同じ規則）
var _ai_presets: Array = []  # [label]
var _ai_names := {}          # label -> 表示名
var _ai_params := {}         # label -> プリセット辞書（ai.csv の1行。sight の既定値を引く）

# パレット選択状態
var _sel_terrain := 0
var _sel_terrain_category := ""  # 地形パレットの分類（空=基本＝地形タイプ一覧 / それ以外=その type のスキン一覧）
var _sel_terrain_skin := ""      # 塗る見た目スキンの skin_id（分類が「基本」以外のとき有効）
var _paint_tool := "pen"         # 塗り方（pen=1マスずつ / fill=連結領域をまとめて）
var _sel_category := ""  # 自軍パレットの分類絞り込み（空=すべて）
var _sel_type_id := ""   # 配置する自軍ユニットの type_id
var _sel_skin_id := ""       # 配置する敵ユニットの skin_id
var _sel_skin_category := "" # 敵パレットの分類絞り込み（空=すべて）
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
var _margin_spin: SpinBox  ## 外周（盤の外側に描く地形の厚み）
var _mode_box: VBoxContainer
var _inspector: VBoxContainer
var _victory_box: VBoxContainer
var _mode_buttons := {}
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _confirm: ConfirmationDialog
var _confirm_cb := Callable()
var _press_cell := MapEditorBoard.OUTSIDE  # 選択モードのドラッグ移動の起点


func _ready() -> void:
	get_window().title = "Senaris マップエディタ"
	# 本体は 1280x720 を拡大表示する設定（project.godot の stretch）だが、ツールはドット等倍で使う
	# ＝ウィンドウを広げたぶんだけ編集領域が増える。プロジェクト設定は触らず、この窓だけ切る。
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().min_size = Vector2i(1200, 760)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	get_window().size = Vector2i(mini(1600, usable.x), mini(900, usable.y))  # 画面より大きくはしない
	get_window().move_to_center()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_catalogs()
	_doc = MapEditorDoc.new_stage()
	_build_ui()
	_sync_fields()
	_set_mode("terrain")
	_refresh_victory()


## Ctrl+Z ＝直前の地形操作の取り消し（入力欄にフォーカスがあるときは、そちらの取り消しが優先）。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.ctrl_pressed and event.keycode == KEY_Z:
		_undo_terrain()
		accept_event()


func _load_catalogs() -> void:
	var tt: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain/terrain_type.json"))
	for t in tt.get("terrains", []):
		_terrains.append({ "id": String(t["id"]), "char": String(t.get("char", "?")), "memo": String(t.get("memo", "")) })
	var ut: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/unit_type.json"))
	for t in ut.get("types", []):
		var cat := String(t.get("category", ""))
		_unit_types.append({ "id": String(t["id"]), "category": cat })
		if cat != "" and not _categories.has(cat):
			_categories.append(cat)
	if not _unit_types.is_empty():
		_sel_type_id = String(_unit_types[0]["id"])
	for r in CsvUtil.read_table("res://data/units/unit_skin.csv"):
		var cat := String(r.get("category", ""))
		_skins.append({ "skin_id": String(r["skin_id"]), "type_id": String(r["type_id"]), "category": cat })
		if cat != "" and cat != STANDARD_CATEGORY and not _skin_categories.has(cat):
			_skin_categories.append(cat)
		if _sel_skin_id == "" and cat != STANDARD_CATEGORY:
			_sel_skin_id = String(r["skin_id"])  # 敵パレットの初期値＝基準以外の先頭
	for r in CsvUtil.read_table("res://data/terrain/terrain_skin.csv"):
		var sid := String(r.get("skin_id", ""))
		var type_id := String(r.get("terrain_type", ""))
		if sid == "" or type_id == "":
			continue
		_terrain_skins.append({
			"skin_id": sid, "terrain_type": type_id,
			"name": String(r.get("name", sid)), "memo": String(r.get("memo", "")),
		})
		# 既定スキン＝skin_id == terrain_type を優先。無ければその type の最初の行（TerrainSkinCatalog と同じ）
		if not _default_skin_by_type.has(type_id) or sid == type_id:
			_default_skin_by_type[type_id] = sid
	var ai := AiCatalog.load_default()
	for label in ai:
		_ai_presets.append(String(label))
		_ai_names[label] = String(ai[label].get("name", label))
		_ai_params[String(label)] = ai[label]


# --- UI構築 ---


func _build_ui() -> void:
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		outer.add_theme_constant_override("margin_" + s, 10)
	add_child(outer)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	outer.add_child(root)

	# ツールバー
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	_add_button(bar, "新規", _on_new)
	_add_button(bar, "開く", func() -> void: _open_dialog.popup_centered(Vector2i(900, 600)))
	_add_button(bar, "保存", _on_save)
	_add_button(bar, "名前を付けて保存", func() -> void: _save_dialog.popup_centered(Vector2i(900, 600)))
	_add_button(bar, "地形を元に戻す (Ctrl+Z)", _undo_terrain)
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
	_board.scroll = scroll  # 中ボタンドラッグのパン先
	_board.cell_pressed.connect(_on_cell_pressed)
	_board.cell_dragged.connect(_on_cell_dragged)
	_board.cell_released.connect(_on_cell_released)
	_board.zoom_requested.connect(func(step: int) -> void: zoom.value += step * zoom.step)
	scroll.add_child(_board)
	_board.refresh()

	var panel_scroll := ScrollContainer.new()
	panel_scroll.custom_minimum_size = Vector2(360, 0)
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(panel_scroll)
	var panel_margin := MarginContainer.new()
	panel_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_margin.add_theme_constant_override("margin_left", 8)
	panel_margin.add_theme_constant_override("margin_right", 14)  # 縦スクロールバーと入力欄の間の余白
	panel_margin.add_theme_constant_override("margin_bottom", 12)
	panel_scroll.add_child(panel_margin)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	panel_margin.add_child(panel)

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
	# 外周＝盤の外側に何マス地形を描くか。接続タイル（柵・道）が縁で「盤の外に何があるか」を
	# 推測せず読めるようにするためのもの。厚み1で6近傍を覆える。詳細 → doc/gdd/map.md
	_add_label(grid, "margin")
	_margin_spin = _make_spin(0, 3, 0)
	grid.add_child(_margin_spin)
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
	_board.selected = MapEditorBoard.OUTSIDE
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
			_build_terrain_palette()
		"player":
			_add_hint(_mode_box, "左クリック＝配置 / 右クリック＝駒を削除")
			# 分類（category）で絞ってから種別を選ぶ
			_mode_box.add_child(_labeled_option("分類", [""] + _categories, ["すべて"] + _categories, _sel_category,
				func(k: String) -> void:
					_sel_category = k
					_set_mode("player")))
			var ids := []
			for t in _unit_types:
				if _sel_category == "" or String(t["category"]) == _sel_category:
					ids.append(String(t["id"]))
			if not ids.has(_sel_type_id) and not ids.is_empty():
				_sel_type_id = String(ids[0])  # 絞り込みで外れたら先頭にフォールバック
			var ob := OptionButton.new()
			for i in ids.size():
				ob.add_item(ids[i])
				if String(ids[i]) == _sel_type_id:
					ob.select(i)
			ob.item_selected.connect(func(i: int) -> void: _sel_type_id = String(ids[i]))
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


## 地形パレット。分類「基本」＝地形タイプ一覧（性能）／それ以外＝その地形の見た目バリエーション一覧。
func _build_terrain_palette() -> void:
	_mode_box.add_child(_labeled_option("塗り方", TOOL_LABELS.keys(), TOOL_LABELS.values(), _paint_tool,
		func(k: String) -> void:
			_paint_tool = k
			_set_mode("terrain")))
	if _paint_tool == "fill":
		_add_hint(_mode_box, "左クリック＝地続きをまとめて塗る / 右クリック＝地続きを平地に戻す。\n"
			+ "範囲は「いまの見た目が同じ」マス（地形＋スキンの両方が一致）。誤爆は Ctrl+Z で戻せる。")
	else:
		_add_hint(_mode_box, "左ドラッグ＝塗る / 右ドラッグ＝平地に戻す")
	var cat_keys := [""]
	var cat_names := ["基本（地形タイプ）"]
	for t in _terrains:
		cat_keys.append(String(t["id"]))
		cat_names.append("%s（%s）" % [_type_display(String(t["id"])), t["id"]])
	_mode_box.add_child(_labeled_option("分類", cat_keys, cat_names, _sel_terrain_category,
		func(k: String) -> void:
			_sel_terrain_category = k
			_sel_terrain_skin = String(_default_skin_by_type.get(k, ""))  # 分類を変えたら既定スキンから
			_set_mode("terrain")))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 320)
	if _sel_terrain_category == "":
		for t in _terrains:
			list.add_item("%s  %s — %s" % [t["char"], t["id"], t["memo"]])
		if _sel_terrain < _terrains.size():
			list.select(_sel_terrain)
		list.item_selected.connect(func(i: int) -> void: _sel_terrain = i)
		_mode_box.add_child(list)
		return
	# 見た目バリエーション：既定スキンを選べば「差分なし＝type の既定」に戻せる
	var default_id := String(_default_skin_by_type.get(_sel_terrain_category, ""))
	var pool := []
	for s in _terrain_skins:
		if String(s["terrain_type"]) == _sel_terrain_category:
			pool.append(s)
	if pool.is_empty():
		_add_hint(_mode_box, "この地形に登録されたスキンはありません（塗ると既定の見た目になります）。")
		_sel_terrain_skin = ""
		return
	var ids := []
	for s in pool:
		ids.append(String(s["skin_id"]))
	if not ids.has(_sel_terrain_skin):
		_sel_terrain_skin = default_id if ids.has(default_id) else String(ids[0])
	for i in pool.size():
		var s: Dictionary = pool[i]
		var mark := "（既定）" if String(s["skin_id"]) == default_id else ""
		list.add_item("%s%s — %s" % [s["name"], mark, s["skin_id"]])
		list.set_item_tooltip(i, String(s["memo"]))
		if String(s["skin_id"]) == _sel_terrain_skin:
			list.select(i)
	list.item_selected.connect(func(i: int) -> void: _sel_terrain_skin = String(ids[i]))
	_mode_box.add_child(list)


## 地形タイプの表示名（既定スキンの name。未登録の type は id をそのまま）。
func _type_display(type_id: String) -> String:
	for s in _terrain_skins:
		if String(s["skin_id"]) == String(_default_skin_by_type.get(type_id, "")):
			return String(s["name"])
	return type_id


## 地形タイプの ASCII 1文字（terrain グリッド用）。未知なら既定地形。
func _char_of_type(type_id: String) -> String:
	for t in _terrains:
		if String(t["id"]) == type_id:
			return String(t["char"])
	return MapEditorDoc.DEFAULT_CHAR


## AIプリセットが索敵で起動するか（engage に sight トークン）。いまの ai.csv では guard だけ。
func _preset_uses_sight(ai_label: String) -> bool:
	var preset: Dictionary = _ai_params.get(ai_label, {})
	return "sight" in String(preset.get("engage", "")).split("|")


## 部隊/拠点の sight 上書き行。索敵で起動するプリセットのときだけ出す。
## sight 以外の軸は出さない：新しいふるまいは ai.csv にラベルを足して表現する
## （AIは「プリセット＝CSV／割り当て＝ステージ」の2層。詳細 → doc/gdd/ai.md データ構成）。
func _add_sight_row(parent: Control, target: Dictionary, ai_label: String) -> void:
	if not _preset_uses_sight(ai_label):
		if target.erase("sight"):  # 見えない上書きを残さない（索敵で起きないAIに変えたら消す）
			_say("%s は索敵で起動しないため、sight の上書きを外しました。" % ai_label)
		return
	var preset: Dictionary = _ai_params.get(ai_label, {})
	var preset_sight := int(preset.get("sight", 0)) if typeof(preset.get("sight")) != TYPE_STRING else 0
	var row := HBoxContainer.new()
	parent.add_child(row)
	var check := CheckBox.new()
	check.text = "sight"
	check.button_pressed = target.has("sight")
	check.tooltip_text = "索敵の広さ（視線コストの積算予算）。外すとプリセット既定を継承する。"
	row.add_child(check)
	var spin := _make_spin(0, 20, float(int(target.get("sight", preset_sight))))
	spin.custom_minimum_size = Vector2(70, 0)
	spin.editable = check.button_pressed
	row.add_child(spin)
	_add_label(row, "（既定 %d）" % preset_sight)
	check.toggled.connect(func(on: bool) -> void:
		spin.editable = on
		if on:
			target["sight"] = int(spin.value)
		else:
			target.erase("sight"))
	spin.value_changed.connect(func(v: float) -> void:
		if check.button_pressed:
			target["sight"] = int(v))


func _build_enemy_palette() -> void:
	_add_hint(_mode_box, "左クリック＝選択中の部隊に配置（配置済みの敵の上なら、その部隊とスキンを取り込む）\n右クリック＝駒を削除")
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
	# AIプリセット（索敵で起きるプリセットのときだけ sight を上書きできる）
	var ai_opts := _ai_options(false)
	_mode_box.add_child(_labeled_option("AI", ai_opts[0], ai_opts[1], String(sq.get("ai", "")),
		func(k: String) -> void:
			sq["ai"] = k
			_set_mode("enemy")))
	_add_sight_row(_mode_box, sq, String(sq.get("ai", "")))
	# 配置するスキン：分類で絞ってから選ぶ（基準＝味方専用スキンは出さない）
	_mode_box.add_child(_labeled_option("分類", [""] + _skin_categories, ["すべて"] + _skin_categories, _sel_skin_category,
		func(k: String) -> void:
			_sel_skin_category = k
			_set_mode("enemy")))
	var pool := []
	for s in _skins:
		if String(s["category"]) == STANDARD_CATEGORY:
			continue
		if _sel_skin_category != "" and String(s["category"]) != _sel_skin_category:
			continue
		pool.append(s)
	var pool_ids := []
	for s in pool:
		pool_ids.append(String(s["skin_id"]))
	if not pool_ids.has(_sel_skin_id) and not pool_ids.is_empty():
		_sel_skin_id = String(pool_ids[0])  # 絞り込みで外れたら先頭にフォールバック
	var skin_ob := OptionButton.new()
	for i in pool.size():
		skin_ob.add_item("%s（%s）" % [pool[i]["skin_id"], pool[i]["type_id"]])
		if String(pool[i]["skin_id"]) == _sel_skin_id:
			skin_ob.select(i)
	skin_ob.item_selected.connect(func(i: int) -> void: _sel_skin_id = String(pool_ids[i]))
	_mode_box.add_child(skin_ob)


## 配置済みの敵の駒を左クリックしたときに、その設定（部隊・スキン）をパレットへ取り込む。
## 取り込んだら true（＝配置はしない）。敵の駒でなければ false＝従来どおり配置を試みる。
func _pick_enemy(col: int, row: int) -> bool:
	var hit := _doc.unit_at(col, row)
	if hit.is_empty() or int(hit["squad"]) < 0:
		return false
	var u: Dictionary = hit["unit"]
	var skin := String(u.get("skin", ""))
	_sel_squad = int(hit["squad"])  # 部隊名・AI・sight はこの選択に追従して表示される
	var pickable := _is_enemy_skin(skin)
	if pickable:
		var cat := _skin_category(skin)
		if _sel_skin_category != "" and _sel_skin_category != cat:
			_sel_skin_category = cat  # 絞り込みで一覧から外れる skin は、分類ごと合わせる
		_sel_skin_id = skin
	_set_mode("enemy")
	if pickable:
		_say("部隊%d / %s の設定を取り込みました。" % [_sel_squad, skin])
	else:
		_say("部隊%d を選びました（%s は敵パレットに無い見た目のため取り込めません）。"
			% [_sel_squad, skin if skin != "" else String(u.get("type", "?"))])
	return true


## 敵パレットに出る見た目か（未登録／基準＝味方専用は出ない）。
func _is_enemy_skin(skin_id: String) -> bool:
	for s in _skins:
		if String(s["skin_id"]) == skin_id:
			return String(s["category"]) != STANDARD_CATEGORY
	return false


## skin_id の分類（未登録は ""＝「すべて」扱い）。
func _skin_category(skin_id: String) -> String:
	for s in _skins:
		if String(s["skin_id"]) == skin_id:
			return String(s["category"])
	return ""


# --- 盤の操作 ---


func _on_cell_pressed(col: int, row: int, button: int) -> void:
	# 外周(margin)は地形を描くだけの場所＝駒・拠点は置けず、選択の対象にもしない。
	if _mode != "terrain" and not _doc.in_board(col, row):
		_say("外周（margin）には駒・拠点を置けません。地形モードでのみ塗れます。")
		return
	match _mode:
		"terrain":
			_doc.push_terrain_undo()  # 1手＝押してから離すまで（ドラッグの一筆もまとめて戻せる）
			if _paint_tool == "fill":
				_fill(col, row, button)
			else:
				_paint(col, row, button)
		"player":
			if button == MOUSE_BUTTON_LEFT:
				if _doc.add_player(_sel_type_id, col, row):
					_board.refresh()
				else:
					_say("そのマスには既に駒があります。")
			else:
				if _doc.remove_unit_at(col, row):
					_board.refresh()
		"enemy":
			if button == MOUSE_BUTTON_LEFT:
				if _pick_enemy(col, row):
					return  # 配置済みの敵を左クリック＝その設定をパレットへ取り込む（配置しない）
				if _doc.data["enemy"].is_empty():
					_sel_squad = _doc.add_squad(_ai_presets[0] if not _ai_presets.is_empty() else "charge")
					_set_mode("enemy")
				if _doc.add_enemy(_sel_squad, _sel_skin_id, col, row):
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
	if _mode == "terrain" and _paint_tool == "pen":
		_paint(col, row, button)


func _on_cell_released(col: int, row: int, _button: int) -> void:
	if _mode != "select" or _press_cell == MapEditorBoard.OUTSIDE:
		return
	var to := Vector2i(col, row)
	if to != _press_cell:
		if _doc.move(_press_cell.x, _press_cell.y, to.x, to.y):
			_board.selected = to
			_board.refresh()
			_show_inspection(to.x, to.y)
		else:
			_say("そこへは移動できません（範囲外か、同じ種類が既にあります）。")
	_press_cell = MapEditorBoard.OUTSIDE


## いま塗る内容 [地形の文字, skin_id]。右クリックは既定地形＋差分なしに戻す。
## 既定スキンは差分に書かない＝未指定セルは type の既定へフォールバックする既存の解釈のまま。
func _brush(button: int) -> Array:
	if button == MOUSE_BUTTON_RIGHT:
		return [MapEditorDoc.DEFAULT_CHAR, ""]
	if _sel_terrain_category == "":
		return [String(_terrains[_sel_terrain]["char"]), ""]
	var default_id := String(_default_skin_by_type.get(_sel_terrain_category, ""))
	return [_char_of_type(_sel_terrain_category),
		"" if _sel_terrain_skin == default_id else _sel_terrain_skin]


## 地形を1マス塗る。性能（terrain の文字）と見た目（terrain_skins の差分）を同時に決める。
func _paint(col: int, row: int, button: int) -> void:
	var brush := _brush(button)
	_doc.set_terrain_char(col, row, String(brush[0]))
	_doc.set_terrain_skin(col, row, String(brush[1]))
	_board.queue_redraw()


## 地続き（いまの見た目が同じマス）をまとめて塗る。
func _fill(col: int, row: int, button: int) -> void:
	var brush := _brush(button)
	var n := _doc.fill_terrain(col, row, String(brush[0]), String(brush[1]))
	_board.queue_redraw()
	_say("%d マスを塗りました（Ctrl+Z で戻せます）。" % n)


func _undo_terrain() -> void:
	if _doc.undo_terrain():
		_board.refresh()
		_say("直前の地形操作を取り消しました。")
	else:
		_say("取り消せる地形操作がありません（戻せるのは直前の1操作だけ）。")


# --- 選択モードのインスペクタ ---


func _show_inspection(col: int, row: int) -> void:
	if _inspector == null or not is_instance_valid(_inspector):
		return
	for c in _inspector.get_children():
		c.queue_free()
	var tid := TerrainType.char_to_id(_doc.terrain_char(col, row))
	_add_label(_inspector, "マス (%d, %d)  地形: %s" % [col, row, tid])
	var skin := _doc.terrain_skin(col, row)
	_add_label(_inspector, "見た目: %s" % [skin if skin != "" else "%s（既定）" % _default_skin_by_type.get(tid, tid)])
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
				b["ai"] = k
			_show_inspection(int(b["col"]), int(b["row"]))))  # sight 行の出し入れ
	_add_sight_row(_inspector, b, String(b.get("ai", "")))
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
	_margin_spin.set_value_no_signal(_doc.margin())
	_path_label.text = _path if _path != "" else "（未保存の新規ステージ）"
	_path_label.tooltip_text = _path_label.text


func _on_resize() -> void:
	_doc.set_margin(int(_margin_spin.value))  # 外周を先に決める（resize が同じグリッドを整えるため）
	var dropped := _doc.resize(int(_cols_spin.value), int(_rows_spin.value))
	_board.selected = MapEditorBoard.OUTSIDE
	_board.refresh()
	_say("サイズを %d×%d（外周 %d）にしました。" % [_doc.cols(), _doc.rows(), _doc.margin()]
		+ ("範囲外の駒/拠点/スキン指定を %d 件削除しました。" % dropped if dropped > 0 else ""))


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
