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
const MODE_LABELS := { "select": "選択", "terrain": "地形", "player": "自軍", "enemy": "敵",
	"squad": "敵グループ", "base": "拠点", "outcome": "勝敗" }
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
var _base_box: VBoxContainer  ## 「拠点」モードの下段＝選択中の拠点の編集UI
var _unit_box: VBoxContainer  ## 「自軍」「敵」モードの下段＝選択中の駒の編集UI
var _victory_box: VBoxContainer
var _defeat_box: VBoxContainer
var _mode_buttons := {}
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _confirm: ConfirmationDialog
var _confirm_cb := Callable()
var _press_cell := MapEditorBoard.OUTSIDE  # 選択モードのドラッグ移動の起点
var _sel_base := MapEditorBoard.OUTSIDE    # 「拠点」モードで編集中の拠点のマス
var _sel_unit := MapEditorBoard.OUTSIDE    # 「自軍」「敵」モードで編集中の駒のマス


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
	_turn_spin.value_changed.connect(func(v: float) -> void:
		_doc.data["turn_limit"] = int(v)
		_refresh_defeat())  # 敗北条件の一覧に「ターン制限 N を超過」を出しているので追随させる
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
	var modes := HFlowContainer.new()  # モードが増えるとパネル幅に収まらない＝折り返す
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
	_sel_base = MapEditorBoard.OUTSIDE
	_sel_unit = MapEditorBoard.OUTSIDE
	_board.queue_redraw()
	for c in _mode_box.get_children():
		c.queue_free()
	match mode:
		"select":
			_add_hint(_mode_box, "クリック＝選択して下に表示（表示だけ・編集はしない）。ドラッグ＝駒/拠点を移動。\n"
				+ "拠点の中身（控えなど）を編集するのは「拠点」モード。")
			_inspector = VBoxContainer.new()
			_inspector.add_theme_constant_override("separation", 6)
			_mode_box.add_child(_inspector)
		"terrain":
			_build_terrain_palette()
		"player":
			_build_player_palette()
		"enemy":
			_build_enemy_palette()
		"squad":
			_build_squad_palette()
		"outcome":
			_build_outcome_panel()
		"base":
			_add_hint(_mode_box, "左クリック＝設置（拠点の上なら、その拠点を選んで下で編集）\n右クリック＝拠点を削除。\n"
				+ "下の3つは「これから置く拠点」の設定。既存の拠点は選んでから下段で編集する。")
			_mode_box.add_child(_labeled_option("所属", TEAM_LABELS.keys(), TEAM_LABELS.values(), _base_team,
				func(k: String) -> void: _base_team = k))
			_mode_box.add_child(_labeled_option("種別", KIND_LABELS.keys(), KIND_LABELS.values(), _base_kind,
				func(k: String) -> void: _base_kind = k))
			var ai_opts := _ai_options(true)
			_mode_box.add_child(_labeled_option("AI出撃", ai_opts[0], ai_opts[1], _base_ai,
				func(k: String) -> void: _base_ai = k))
			_mode_box.add_child(HSeparator.new())
			_base_box = VBoxContainer.new()
			_base_box.add_theme_constant_override("separation", 6)
			_mode_box.add_child(_base_box)
			_refresh_base_box()


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


## AIプリセットの sight 既定値（未設定・数値でない値は 0）。
func _preset_sight(ai_label: String) -> int:
	var preset: Dictionary = _ai_params.get(ai_label, {})
	var v: Variant = preset.get("sight")
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else 0


## 部隊/拠点の行動順 order 行。小さいほうから動く（拠点も1部隊として同じ列に並ぶ）。
## 詳細 → doc/gdd/ai.md（行動順）
func _add_order_row(parent: Control, target: Dictionary) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_label(row, "order")
	var spin := _make_spin(1, 99, float(maxi(int(target.get("order", _doc.max_order() + 1)), 1)))
	spin.custom_minimum_size = Vector2(70, 0)
	spin.tooltip_text = "行動順。小さいほうから動く。拠点（AI出撃）も同じ列に並ぶ。"
	spin.value_changed.connect(func(v: float) -> void: target["order"] = int(v))
	row.add_child(spin)
	if not target.has("order"):
		target["order"] = int(spin.value)  # 省略を残さない（実データは全部隊に書く）


## 部隊/拠点の sight 上書き行。索敵で起動するプリセットのときだけ出す。
## sight 以外の軸は出さない：新しいふるまいは ai.csv にラベルを足して表現する
## （AIは「プリセット＝CSV／割り当て＝ステージ」の2層。詳細 → doc/gdd/ai.md データ構成）。
func _add_sight_row(parent: Control, target: Dictionary, ai_label: String) -> void:
	if not _preset_uses_sight(ai_label):
		if target.erase("sight"):  # 見えない上書きを残さない（索敵で起きないAIに変えたら消す）
			_say("%s は索敵で起動しないため、sight の上書きを外しました。" % ai_label)
		return
	var preset_sight := _preset_sight(ai_label)
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


## 「自軍」モード＝駒を置く道具（分類→種別）。置いた駒／クリックした駒は下段で名前を付けられる。
func _build_player_palette() -> void:
	_add_hint(_mode_box, "左クリック＝配置（配置済みの自軍の駒の上なら、その種別を取り込んで選ぶ）\n右クリック＝駒を削除")
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
	_add_unit_box()


## 「自軍」「敵」モードの下段を作る（選んだ駒の中身）。
func _add_unit_box() -> void:
	_mode_box.add_child(HSeparator.new())
	_unit_box = VBoxContainer.new()
	_unit_box.add_theme_constant_override("separation", 6)
	_mode_box.add_child(_unit_box)
	_refresh_unit_box()


## 部隊を選ぶ行。「敵」＝選ぶだけ（配置先の指定）／「敵グループ」＝追加・削除も持つ。
## _sel_squad は両モードで共有＝グループ側で選んだ部隊に、そのまま駒を置ける。
func _add_squad_selector(with_buttons: bool) -> void:
	var squads: Array = _doc.data["enemy"]
	if _sel_squad >= squads.size():
		_sel_squad = maxi(squads.size() - 1, 0)
	var row := HBoxContainer.new()
	_mode_box.add_child(row)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in squads.size():
		ob.add_item("部隊%d[順%s]: %s（%s）" % [i, str(squads[i].get("order", "-")),
			String(squads[i].get("name", "無名")), String(squads[i].get("ai", "?"))])
	if not squads.is_empty():
		ob.select(_sel_squad)
	ob.item_selected.connect(func(i: int) -> void:
		_sel_squad = i
		_set_mode(_mode))
	row.add_child(ob)
	if not with_buttons:
		return
	_add_button(row, "追加", func() -> void:
		_sel_squad = _doc.add_squad(_ai_presets[0] if not _ai_presets.is_empty() else "charge")
		_set_mode("squad"))
	if not squads.is_empty():
		_add_button(row, "削除", func() -> void:
			_ask("部隊%d を所属ユニットごと削除します。よろしいですか？" % _sel_squad, func() -> void:
				_doc.remove_squad(_sel_squad)
				_sel_squad = 0
				_set_mode("squad")
				_board.refresh()))


## 「敵グループ」モード＝部隊そのものの管理（作る・選ぶ・名前とAIと行動順を決める）。
## 駒の配置は持たない＝置くのは「敵」モードの仕事（同じ画面に混ぜると何を触っているか読めない）。
func _build_squad_palette() -> void:
	_add_hint(_mode_box, "部隊を作る・選ぶ・設定する。駒を置くのは「敵」モード。\n"
		+ "盤の敵の駒を左クリック＝その駒の部隊を選ぶ。")
	_add_squad_selector(true)
	var squads: Array = _doc.data["enemy"]
	if squads.is_empty():
		_add_hint(_mode_box, "部隊がありません。「追加」で作成します。")
		return
	var sq: Dictionary = squads[_sel_squad]
	# 行動順（doc/gdd/ai.md 行動順）
	_add_order_row(_mode_box, sq)
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
			_set_mode("squad")))
	_add_sight_row(_mode_box, sq, String(sq.get("ai", "")))
	_add_label(_mode_box, "所属する駒: %d 体" % sq.get("units", []).size())


## 「敵」モード＝駒を置く道具（配置先の部隊とスキンを選ぶ）。部隊の設定は「敵グループ」モード。
func _build_enemy_palette() -> void:
	_add_hint(_mode_box, "左クリック＝選択中の部隊に配置（配置済みの敵の上なら、その部隊とスキンを取り込む）\n右クリック＝駒を削除")
	_add_squad_selector(false)
	if _doc.data["enemy"].is_empty():
		_add_hint(_mode_box, "部隊がありません。盤をクリックすると自動で作成します（設定は「敵グループ」モードで）。")
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
	_add_unit_box()


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
	_select_unit(col, row)  # 下段でこの駒に名前(actor)を付けられる
	if pickable:
		_say("部隊%d / %s の設定を取り込みました。" % [_sel_squad, skin])
	else:
		_say("部隊%d を選びました（%s は敵パレットに無い見た目のため取り込めません）。"
			% [_sel_squad, skin if skin != "" else String(u.get("type", "?"))])
	return true


## 配置済みの自軍の駒を左クリックしたときに、その種別をパレットへ取り込む。
## 取り込んだら true（＝配置はしない）。自軍の駒でなければ false＝従来どおり配置を試みる。
func _pick_player(col: int, row: int) -> bool:
	var hit := _doc.unit_at(col, row)
	if hit.is_empty() or int(hit["squad"]) >= 0:
		return false  # 空きマス、または敵の駒
	var u: Dictionary = hit["unit"]
	var tid := String(u.get("type", ""))
	if tid != "":
		var cat := _category_of_type(tid)
		if _sel_category != "" and _sel_category != cat:
			_sel_category = cat  # 絞り込みで一覧から外れる type は、分類ごと合わせる
		_sel_type_id = tid
	_set_mode("player")
	_select_unit(col, row)
	_say("(%d, %d) の %s を選びました。" % [col, row, tid if tid != "" else "駒"])
	return true


## unit_type の分類（未登録は ""＝「すべて」扱い）。
func _category_of_type(type_id: String) -> String:
	for t in _unit_types:
		if String(t["id"]) == type_id:
			return String(t["category"])
	return ""


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
				if _pick_player(col, row):
					return  # 配置済みの自軍を左クリック＝その種別を取り込む（配置しない）
				if _doc.add_player(_sel_type_id, col, row):
					_board.refresh()
					_select_unit(col, row)
				else:
					_say("そのマスには既に駒があります。")
			else:
				if _doc.remove_unit_at(col, row):
					_board.refresh()
				if _sel_unit == Vector2i(col, row):
					_deselect_unit()
		"enemy":
			if button == MOUSE_BUTTON_LEFT:
				if _pick_enemy(col, row):
					return  # 配置済みの敵を左クリック＝その設定をパレットへ取り込む（配置しない）
				var created := false
				if _doc.data["enemy"].is_empty():
					_sel_squad = _doc.add_squad(_ai_presets[0] if not _ai_presets.is_empty() else "charge")
					_set_mode("enemy")
					created = true
				if _doc.add_enemy(_sel_squad, _sel_skin_id, col, row):
					_board.refresh()
					_select_unit(col, row)
					if created:
						_say("部隊がなかったので部隊%d を自動で作りました（名前・AI は「敵グループ」モードで）。" % _sel_squad)
				else:
					_say("そのマスには既に駒があります。")
			else:
				if _doc.remove_unit_at(col, row):
					_board.refresh()
				if _sel_unit == Vector2i(col, row):
					_deselect_unit()
		"squad":
			# グループ管理に特化＝駒は置かない。盤は「その駒の部隊を選ぶ」ためだけに使う。
			if button == MOUSE_BUTTON_LEFT:
				var hit := _doc.unit_at(col, row)
				if hit.is_empty() or int(hit["squad"]) < 0:
					_say("敵の駒を左クリックすると、その駒の部隊を選べます。")
				else:
					_sel_squad = int(hit["squad"])
					_set_mode("squad")
					_say("部隊%d を選びました。" % _sel_squad)
		"base":
			if button == MOUSE_BUTTON_LEFT:
				# 空きマス＝設置、拠点の上＝それを選ぶ（どちらも下段の編集UIがその拠点を指す）
				if _doc.add_base(col, row, _base_team, _base_kind, _base_ai):
					_board.refresh()
					_say("(%d, %d) に拠点を置きました。" % [col, row])
				else:
					_say("(%d, %d) の拠点を選びました（下で控えなどを編集できます）。" % [col, row])
				_select_base(col, row)
			else:
				if _doc.remove_base_at(col, row):
					_board.refresh()
				if _sel_base == Vector2i(col, row):
					_deselect_base()
		"outcome":
			_say("勝敗条件は右のパネルで足す・消す（盤のクリックでは変わらない）。")
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


## 選択モードの駒表示。ここは読むだけ＝編集は「自軍」「敵」モードに寄せてある。
func _inspect_unit(hit: Dictionary) -> void:
	var u: Dictionary = hit["unit"]
	var squad := int(hit["squad"])
	var head := "自軍: %s" % String(u.get("type", u.get("skin", "?"))) if squad < 0 \
		else "敵（部隊%d）: %s" % [squad, String(u.get("skin", u.get("type", "?")))]
	_add_label(_inspector, head)
	var actor := String(u.get("actor", ""))
	_add_label(_inspector, "actor: %s" % (actor if actor != "" else "（名前なし）"))
	if u.has("passengers") and not u["passengers"].is_empty():
		_add_hint(_inspector, "同乗 %d 体（passengers は JSON 直接編集）" % u["passengers"].size())
	_add_hint(_inspector, "駒の編集は「自軍」「敵」モードで。")


## 選択モードの拠点表示。ここは読むだけ＝編集は「拠点」モードに寄せてある
## （同じ設定が2箇所にあると、どちらが効くのか分からなくなるため）。
func _inspect_base(hit: Dictionary) -> void:
	var b: Dictionary = hit["base"]
	_add_label(_inspector, "拠点: %s / %s" % [
		String(TEAM_LABELS.get(String(b.get("team", "neutral")), b.get("team", "?"))),
		String(KIND_LABELS.get(String(b.get("kind", "fort")), b.get("kind", "?")))])
	var ai := String(b.get("ai", ""))
	if ai == "":
		_add_label(_inspector, "AI出撃: （なし）")
	else:
		_add_label(_inspector, "AI出撃: %s（%s）  order: %s"
			% [ai, String(_ai_names.get(ai, ai)), str(b.get("order", "-"))])
		if _preset_uses_sight(ai):
			var default_sight := _preset_sight(ai)
			_add_label(_inspector, "sight: %d%s" % [int(b.get("sight", default_sight)),
				"（上書き）" if b.has("sight") else "（%s の既定）" % ai])
	var g: Variant = b.get("garrison", [])
	if typeof(g) == TYPE_ARRAY and not (g as Array).is_empty():
		_add_label(_inspector, "控え（garrison）")
		for e in g:
			_add_label(_inspector, "  ・%s ×%d"
				% [String(e.get("skin", e.get("type", "?"))), maxi(int(e.get("count", 1)), 1)])
	else:
		_add_label(_inspector, "控え（garrison）: （なし）")
	_add_hint(_inspector, "拠点の編集は「拠点」モードで。")


# --- 「自軍」「敵」モードの編集UI（選択中の駒） ---


## 編集する駒を選ぶ（盤の選択枠も合わせる）。
func _select_unit(col: int, row: int) -> void:
	_sel_unit = Vector2i(col, row)
	_board.selected = _sel_unit
	_board.queue_redraw()
	_refresh_unit_box()


func _deselect_unit() -> void:
	_sel_unit = MapEditorBoard.OUTSIDE
	_board.selected = MapEditorBoard.OUTSIDE
	_board.queue_redraw()
	_refresh_unit_box()


## 下段を貼り直す。選んでいない（または駒が消えた）ときは案内だけ出す。
func _refresh_unit_box() -> void:
	if _unit_box == null or not is_instance_valid(_unit_box):
		return  # 「自軍」「敵」モード以外では箱が無い＝描くものがない
	for c in _unit_box.get_children():
		c.queue_free()
	var hit := _doc.unit_at(_sel_unit.x, _sel_unit.y)
	if hit.is_empty():
		_add_hint(_unit_box, "盤の駒を左クリックすると、ここで名前（actor）を付けられます。")
		return
	var u: Dictionary = hit["unit"]
	var squad := int(hit["squad"])
	_add_heading(_unit_box, "選んだ駒 (%d, %d)" % [_sel_unit.x, _sel_unit.y])
	_add_label(_unit_box, "自軍: %s" % String(u.get("type", u.get("skin", "?"))) if squad < 0 \
		else "敵（部隊%d）: %s" % [squad, String(u.get("skin", u.get("type", "?")))])
	if u.has("passengers") and typeof(u["passengers"]) == TYPE_ARRAY and not u["passengers"].is_empty():
		_add_hint(_unit_box, "同乗 %d 体（passengers は JSON 直接編集）" % u["passengers"].size())
	_add_actor_row(_unit_box, u)
	_add_button(_unit_box, "この駒を削除", func() -> void:
		_doc.remove_unit_at(_sel_unit.x, _sel_unit.y)
		_board.refresh()
		_deselect_unit())


## 名指し(actor)の入力行。空＝名前なし。味方・敵のどちらにも付けられる。
## 確定は Enter かフォーカスを外したとき＝1文字打つたびに勝敗条件を追い直さない。
func _add_actor_row(parent: VBoxContainer, u: Dictionary) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_label(row, "actor")
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = String(u.get("actor", ""))
	edit.placeholder_text = "（名前なし）"
	edit.tooltip_text = "駒を名指す値。会話の分岐・継承(carryover)・勝敗条件がこの名前を見る。\n" \
		+ "名前のない雑兵には付けない（doc/gdd/map.md 名前つきの駒）。"
	row.add_child(edit)
	var apply := func(text: String) -> void:
		var new_name := text.strip_edges()
		var old := String(u.get("actor", ""))
		if new_name == old:
			return
		if new_name != "" and _doc.used_actors().has(new_name):
			_say("actor \"%s\" は既に他の駒が使っています。別の名前にしてください。" % new_name)
			edit.text = old
			return
		_doc.set_actor(u, new_name)  # 元の名前を指していた勝敗条件も一緒に付け替わる
		edit.text = new_name
		if new_name == "":
			_say("actor を外しました（この駒を指していた勝敗条件も外れます）。")
		elif old == "":
			_say("actor \"%s\" を付けました。" % new_name)
		else:
			_say("actor を \"%s\" → \"%s\" に変えました（勝敗条件も追随）。" % [old, new_name])
	edit.text_submitted.connect(func(text: String) -> void: apply.call(text))
	edit.focus_exited.connect(func() -> void: apply.call(edit.text))
	_add_button(row, "自動", func() -> void:
		# 下段は貼り直さない：入力欄が消えると focus_exited が古い文字列で走り、付けた名前を上書きしてしまう
		apply.call(_doc.free_actor(String(u.get("skin", u.get("type", ""))))))


# --- 「拠点」モードの編集UI（選択中の1つ） ---


## 編集する拠点を選ぶ（盤の選択枠も合わせる）。
func _select_base(col: int, row: int) -> void:
	_sel_base = Vector2i(col, row)
	_board.selected = _sel_base
	_board.queue_redraw()
	_refresh_base_box()


func _deselect_base() -> void:
	_sel_base = MapEditorBoard.OUTSIDE
	_board.selected = MapEditorBoard.OUTSIDE
	_board.queue_redraw()
	_refresh_base_box()


## 下段を貼り直す。選んでいない（または拠点が消えた）ときは案内だけ出す。
func _refresh_base_box() -> void:
	if _base_box == null or not is_instance_valid(_base_box):
		return  # 「拠点」モード以外では箱が無い＝描くものがない
	for c in _base_box.get_children():
		c.queue_free()
	var hit := _doc.base_at(_sel_base.x, _sel_base.y)
	if hit.is_empty():
		_add_hint(_base_box, "盤の拠点を左クリックすると、ここで控え（garrison）などを編集できます。")
		return
	_add_heading(_base_box, "選んだ拠点 (%d, %d)" % [_sel_base.x, _sel_base.y])
	_build_base_editor(_base_box, hit["base"])


func _build_base_editor(parent: VBoxContainer, b: Dictionary) -> void:
	parent.add_child(_labeled_option("所属", TEAM_LABELS.keys(), TEAM_LABELS.values(),
		String(b.get("team", "neutral")),
		func(k: String) -> void:
			b["team"] = k
			_board.refresh()))
	parent.add_child(_labeled_option("種別", KIND_LABELS.keys(), KIND_LABELS.values(),
		String(b.get("kind", "fort")),
		func(k: String) -> void:
			b["kind"] = k
			_board.refresh()))
	var ai_opts := _ai_options(true)
	parent.add_child(_labeled_option("AI出撃", ai_opts[0], ai_opts[1], String(b.get("ai", "")),
		func(k: String) -> void:
			if k == "":
				b.erase("ai")
				b.erase("order")  # AI出撃しない拠点は行動順の列に並ばない
			else:
				b["ai"] = k
			_refresh_base_box()))  # order / sight 行の出し入れ
	if b.has("ai"):
		_add_order_row(parent, b)  # 拠点も1部隊＝盤上の部隊と同じ列に並ぶ（doc/gdd/ai.md 行動順）
	_add_sight_row(parent, b, String(b.get("ai", "")))
	# 控え（garrison）
	_add_label(parent, "控え（garrison）")
	if typeof(b.get("garrison")) != TYPE_ARRAY:
		b["garrison"] = []
	var g: Array = b["garrison"]
	for i in g.size():
		var entry: Dictionary = g[i]
		var row := HBoxContainer.new()
		parent.add_child(row)
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
			_refresh_base_box())
	_add_button(parent, "控えを追加", func() -> void:
		g.append({ "skin": _skins[0]["skin_id"], "count": 1 })
		_board.refresh()
		_refresh_base_box())
	_add_button(parent, "この拠点を削除", func() -> void:
		_doc.remove_base_at(int(b["col"]), int(b["row"]))
		_board.refresh()
		_deselect_base())


# --- 勝敗条件（「勝敗」モード） ---
# 1条件＝「見出し1行＋インデントした中身」。見出しは折り返さない（切れた分はツールチップ）＝
# 一覧として縦に読める。常時ルール（データに書かなくても効くもの）は灰色・×なしで並べる
# ＝「見えるが触れない」で常時だと分かる。
# 1条件の中は AND（すべて失う/倒す）、条件どうしは OR。「いずれかで成立」させたい対象は、
# 同じ条件に足さず別の条件として足す（doc/gdd/map.md 勝敗条件）。


## 追加できる条件の種類。key＝JSONの type、値＝[表示名, 説明]。
const VICTORY_KINDS := {
	"defeat_unit": ["ボス撃破", "名指し(actor)の駒を倒す"],
	"capture_hq": ["本拠地占領", "敵の本拠地(hq)をすべて自軍が保持する"],
}
const DEFEAT_KINDS := {
	"lose_base": ["拠点の喪失", "名指しした拠点をすべて敵に取られる（1つでも保持していれば不成立）"],
	"lose_unit": ["護衛対象の喪失", "名指し(actor)の駒をすべて失う"],
}


func _build_outcome_panel() -> void:
	_add_hint(_mode_box, "1つの条件に対象を並べる＝すべて失って（倒して）成立。\n"
		+ "「いずれかで成立」にしたいときは、同じ条件に足さず条件を分ける。")
	_add_heading(_mode_box, "勝利条件（いずれか1つで勝ち）")
	_victory_box = VBoxContainer.new()
	_mode_box.add_child(_victory_box)
	_add_heading(_mode_box, "敗北条件（いずれか1つで負け・勝利より優先）")
	_defeat_box = VBoxContainer.new()
	_mode_box.add_child(_defeat_box)
	_refresh_victory()
	_refresh_defeat()


## 条件1件の見出し行。折り返さず、はみ出した分はツールチップで読む。
## on_remove が無効なら右端は ［常時］＝消せない行だと見て分かる。
func _add_outcome_head(parent: Control, text: String, on_remove: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.tooltip_text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if on_remove.is_valid():
		_add_button(row, "×", on_remove)
	else:
		var mark := Label.new()
		mark.text = "［常時］"
		mark.modulate = Color(1, 1, 1, 0.5)
		row.add_child(mark)


## 見出しの下にぶら下げる箱（左に字下げ）。
func _indent(parent: Control) -> VBoxContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	parent.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	m.add_child(box)
	return box


## 説明の1行（灰色。ここは折り返してよい＝見出しの1行制限を補う場所）。
func _add_note(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 0.55)
	parent.add_child(l)


## 指す先が無い対象の警告（保存前に気づけるように）。
func _add_warn(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1.0, 0.72, 0.5)
	parent.add_child(l)


## 常時ルールの1件（見出し＋任意の説明）。
func _add_always_on(parent: Control, text: String, note: String = "") -> void:
	_add_outcome_head(parent, text, Callable())
	if note != "":
		_add_note(_indent(parent), note)


func _refresh_victory() -> void:
	if _victory_box == null or not is_instance_valid(_victory_box):
		return  # 「勝敗」モード以外では箱が無い＝描くものがない
	for c in _victory_box.get_children():
		c.queue_free()
	_add_always_on(_victory_box, "敵の殲滅", "盤上0 かつ 復帰手段なし")
	var list := _doc.victory_list()
	for i in list.size():
		var c: Dictionary = list[i]
		var type_id := String(c.get("type", ""))
		var kind: Array = VICTORY_KINDS.get(type_id, [type_id, "エディタが知らない条件（JSONを直接見る）"])
		_add_outcome_head(_victory_box, String(kind[0]), func() -> void:
			_doc.remove_victory(i)
			_refresh_victory())
		var box := _indent(_victory_box)
		_add_note(box, String(kind[1]))
		if type_id == "defeat_unit":
			_add_actor_target_row(box, String(c.get("actor", "")),
				func(name: String) -> void: c["actor"] = name, Callable())
	_add_kind_adder(_victory_box, VICTORY_KINDS, _add_victory_kind)


func _refresh_defeat() -> void:
	if _defeat_box == null or not is_instance_valid(_defeat_box):
		return
	for c in _defeat_box.get_children():
		c.queue_free()
	_add_always_on(_defeat_box, "自軍の殲滅", "盤上0 かつ 復帰手段なし")
	if _has_own_hq():
		_add_always_on(_defeat_box, "自軍本拠地（hq）の喪失")
	_add_always_on(_defeat_box, "時間切れ", "ターン制限 %d を超過" % int(_doc.data.get("turn_limit", 30)))
	var list := _doc.defeat_list()
	for i in list.size():
		var c: Dictionary = list[i]
		var type_id := String(c.get("type", ""))
		var kind: Array = DEFEAT_KINDS.get(type_id, [type_id, "エディタが知らない条件（JSONを直接見る）"])
		_add_outcome_head(_defeat_box, String(kind[0]), func() -> void:
			_doc.remove_defeat(i)
			_refresh_defeat())
		var box := _indent(_defeat_box)
		_add_note(box, String(kind[1]))
		match type_id:
			"lose_base":
				_build_lose_base_targets(box, c)
			"lose_unit":
				_build_lose_unit_targets(box, c)
	_add_kind_adder(_defeat_box, DEFEAT_KINDS, _add_defeat_kind)


## lose_base の対象（拠点の座標）一覧＋追加。対象が空になった条件は残さない。
func _build_lose_base_targets(box: VBoxContainer, c: Dictionary) -> void:
	if typeof(c.get("bases")) != TYPE_ARRAY:
		c["bases"] = []
	var targets: Array = c["bases"]
	if targets.is_empty():
		_add_warn(box, "対象がありません（このままだと成立しません）")
	for j in targets.size():
		var t: Dictionary = targets[j]
		_add_base_target_row(box, t, func() -> void:
			targets.remove_at(j)
			_drop_empty_defeat(c)
			_refresh_defeat())
		if _doc.base_at(int(t.get("col", -1)), int(t.get("row", -1))).is_empty():
			_add_warn(box, "  ↑ このマスに拠点がありません")
	_add_button(box, "対象を追加（すべて失って成立）", func() -> void:
		var free := _free_base_target()
		if free == MapEditorBoard.OUTSIDE:
			_say("足せる拠点がありません（盤に拠点が無いか、すべて既に対象です）。")
			return
		targets.append({ "col": free.x, "row": free.y })
		_refresh_defeat())


## lose_unit の対象（actor）一覧＋追加。対象が空になった条件は残さない。
func _build_lose_unit_targets(box: VBoxContainer, c: Dictionary) -> void:
	if typeof(c.get("actors")) != TYPE_ARRAY:
		c["actors"] = []
	var actors: Array = c["actors"]
	if actors.is_empty():
		_add_warn(box, "対象がありません（このままだと成立しません）")
	for j in actors.size():
		_add_actor_target_row(box, String(actors[j]),
			func(name: String) -> void: actors[j] = name,
			func() -> void:
				actors.remove_at(j)
				_drop_empty_defeat(c)
				_refresh_defeat())
		if not _doc.used_actors().has(String(actors[j])):
			_add_warn(box, "  ↑ この名前の駒がありません")
	_add_button(box, "対象を追加（すべて失って成立）", func() -> void:
		var free := _free_actor_target()
		if free == "":
			_say(_no_actor_message())
			return
		actors.append(free)
		_refresh_defeat())


## 対象が空になった敗北条件を取り除く（成立しない条件を黙って残さない）。
func _drop_empty_defeat(c: Dictionary) -> void:
	var targets := MapEditorDoc.lose_base_targets(c) if MapEditorDoc.is_lose_base(c) \
		else MapEditorDoc.lose_unit_actors(c)
	if not targets.is_empty():
		return
	var list := _doc.defeat_list()
	for i in list.size():
		if list[i] == c:
			_doc.remove_defeat(i)
			return


## 勝敗条件が指す actor の入力行。実在しない名前は弾いて元に戻す（保存前に「駒なし」を作らない）。
func _add_actor_target_row(parent: Control, current: String, apply: Callable,
		on_remove: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_label(row, "actor")
	var edit := LineEdit.new()
	edit.text = current
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = "駒の actor 名"
	row.add_child(edit)
	var state := { "v": current }  # 貼り直さずに現在値を持つ（貼り直すと入力中のフォーカスが飛ぶ）
	var commit := func(text: String) -> void:
		var name := text.strip_edges()
		if name == String(state["v"]):
			return
		if not _doc.used_actors().has(name):
			_say("actor \"%s\" の駒がありません。「自軍」「敵」モードで名前を付けてから指定してください。" % name)
			edit.text = String(state["v"])
			return
		state["v"] = name
		apply.call(name)
		_say("対象を \"%s\" にしました。" % name)
	edit.text_submitted.connect(func(text: String) -> void: commit.call(text))
	edit.focus_exited.connect(func() -> void: commit.call(edit.text))
	if on_remove.is_valid():
		_add_button(row, "×", on_remove)


## 拠点を指す座標の入力行。拠点の無いマスは弾いて元に戻す。
func _add_base_target_row(parent: Control, t: Dictionary, on_remove: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var cur_col := int(t.get("col", 0))
	var cur_row := int(t.get("row", 0))
	var state := { "col": cur_col, "row": cur_row }
	_add_label(row, "col")
	var col_spin := _make_spin(0, maxi(_doc.cols() - 1, 0), cur_col)
	col_spin.custom_minimum_size = Vector2(66, 0)
	row.add_child(col_spin)
	_add_label(row, "row")
	var row_spin := _make_spin(0, maxi(_doc.rows() - 1, 0), cur_row)
	row_spin.custom_minimum_size = Vector2(66, 0)
	row.add_child(row_spin)
	var commit := func(_v: float) -> void:
		var col := int(col_spin.value)
		var r := int(row_spin.value)
		if col == int(state["col"]) and r == int(state["row"]):
			return
		if _doc.base_at(col, r).is_empty():
			_say("(%d, %d) に拠点がありません。防衛対象にできるのは拠点だけです。" % [col, r])
			col_spin.set_value_no_signal(state["col"])
			row_spin.set_value_no_signal(state["row"])
			return
		state["col"] = col
		state["row"] = r
		t["col"] = col
		t["row"] = r
		_say("防衛対象を (%d, %d) にしました。" % [col, r])
	col_spin.value_changed.connect(commit)
	row_spin.value_changed.connect(commit)
	if on_remove.is_valid():
		_add_button(row, "×", on_remove)


## 「条件を追加」の行（種類を選んで ＋）。
func _add_kind_adder(parent: Control, kinds: Dictionary, on_add: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_label(row, "条件を追加")
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var keys := kinds.keys()
	for k in keys:
		ob.add_item(String(kinds[k][0]))
	row.add_child(ob)
	_add_button(row, "＋", func() -> void: on_add.call(String(keys[maxi(ob.selected, 0)])))


func _add_victory_kind(type_id: String) -> void:
	match type_id:
		"defeat_unit":
			var actor := _free_actor_target()
			if actor == "":
				_say(_no_actor_message())
				return
			_doc.add_victory({ "type": "defeat_unit", "actor": actor })
		"capture_hq":
			for c in _doc.victory_list():
				if String(c.get("type", "")) == "capture_hq":
					_say("「本拠地占領」は既に条件にあります。")
					return
			_doc.add_victory({ "type": "capture_hq" })
	_refresh_victory()


func _add_defeat_kind(type_id: String) -> void:
	match type_id:
		"lose_base":
			var free := _free_base_target()
			if free == MapEditorBoard.OUTSIDE:
				_say("足せる拠点がありません（盤に拠点が無いか、すべて既に対象です）。")
				return
			_doc.add_defeat_lose_base(free.x, free.y)  # 単独の条件＝他の条件とOR
		"lose_unit":
			var actor := _free_actor_target()
			if actor == "":
				_say(_no_actor_message())
				return
			_doc.add_defeat({ "type": "lose_unit", "actors": [actor] })
	_refresh_defeat()


## まだどの条件も指していない拠点のマス（無ければ OUTSIDE）。新しい対象の初期値に使う。
func _free_base_target() -> Vector2i:
	for b in _doc.data.get("bases", []):
		var col := int(b.get("col", 0))
		var row := int(b.get("row", 0))
		if not _doc.has_defeat_lose_base(col, row):
			return Vector2i(col, row)
	return MapEditorBoard.OUTSIDE


## まだどの条件も指していない actor（無ければ ""）。新しい対象の初期値に使う。
func _free_actor_target() -> String:
	var taken := {}
	for c in _doc.victory_list():
		if String(c.get("type", "")) == "defeat_unit":
			taken[String(c.get("actor", ""))] = true
	for c in _doc.defeat_list():
		for a in MapEditorDoc.lose_unit_actors(c):
			taken[String(a)] = true
	for a in _doc.used_actors():
		if not taken.has(String(a)):
			return String(a)
	return ""


func _no_actor_message() -> String:
	if _doc.used_actors().is_empty():
		return "名前(actor)の付いた駒がありません。「自軍」「敵」モードで先に名前を付けてください。"
	return "名前(actor)の付いた駒は、すべて既にどれかの条件が指しています。"


## 自軍 native の本拠地が盤にあるか（＝「本拠地の喪失で敗北」が効くステージか）。
## 拠点の native は初期所属＝ステージJSONの team そのまま（StageLoader）。
func _has_own_hq() -> bool:
	for b in _doc.data.get("bases", []):
		if String(b.get("kind", "fort")) == "hq" and String(b.get("team", "neutral")) == "player":
			return true
	return false


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
	_set_mode(_mode)  # パレット再構築ついでに勝敗条件の一覧も貼り直される


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
	_deselect_base()  # 縮小で選んでいた拠点・駒が消えることがある（下段は案内に戻す）
	_deselect_unit()
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
