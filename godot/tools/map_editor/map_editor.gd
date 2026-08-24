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
const MODE_LABELS := { "stage": "ステージ", "select": "選択", "terrain": "地形", "player": "自軍",
	"enemy": "敵", "squad": "敵グループ", "base": "拠点", "event": "イベント", "outcome": "勝敗" }
const TOOL_LABELS := { "pen": "ペン（1マスずつ）", "fill": "ベタ塗り（地続きをまとめて）" }
const TEAM_LABELS := { "player": "自軍", "enemy": "敵", "neutral": "中立" }
const KIND_LABELS := { "fort": "砦 (fort)", "hq": "本拠地 (hq)" }
## sight の記号（ai.csv・ステージJSON 共通。詳細 → doc/gdd/ai.md データ構成）。
const SIGHT_UNUSED := "-"     ## その特性は sight を使わない
const SIGHT_UNLIMITED := "*"  ## 上限なし＝盤全体（視線コスト x の壁は遮る）
## `*`（上限なし）から数値へ切り替えたときの出発値。継承できる数が無いのでここで決め打つ。
## 数値を取る特性は ambush だけなので、その ai.csv 既定に合わせる。
const SIGHT_SPIN_DEFAULT := 3
## 「全体をずらす」で盤の外に出るものの言い方（MapEditorDoc.shift_losses のキー → 表示名）。
const SHIFT_LOSS_LABELS := { "terrain": "地形", "skins": "スキン指定", "units": "駒", "bases": "拠点",
	"height": "基準高さ" }

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
var _bgm_tracks: Array = []  # assets/bgm/ に実在するトラックID（BGM欄の選択肢。autowire と同じ規約）
var _ai_presets: Array = []  # [特性id]
var _ai_names := {}          # 特性id -> 表示名
var _ai_params := {}         # 特性id -> パラメーター辞書（ai.csv の1行。sight の既定値を引く）

# パレット選択状態
var _sel_terrain_category := "plain"  # 地形パレットの分類＝地形タイプの id（既定地形＝DEFAULT_CHAR に合わせる）
var _sel_terrain_skin := ""      # 塗る見た目スキンの skin_id（空＝その分類にスキンが無い＝塗れない）
var _ov_elevation := ""          # 高さ上書きの入力値（elevation）。空＝上書きなし。floor とペアでだけ塗れる
var _ov_floor := ""              # 高さ上書きの入力値（floor）。空＝上書きなし
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
var _event_box: VBoxContainer  ## 「イベント」モードの一覧＝増援（時限発生）
var _i18n_csv := {}      ## dialogue.csv の現在値（キー -> {ja, en}）。起動時に読み、書き込み後に更新
var _i18n_pending := {}  ## 予告の訳文の未保存入力（キー -> {ja, en}）。ステージ保存時に dialogue.csv へ書く
var _mode_buttons := {}
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _confirm: ConfirmationDialog
var _confirm_cb := Callable()
var _press_cell := MapEditorBoard.OUTSIDE  # 「自軍」「敵」モードのドラッグ移動の起点
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
	_i18n_csv = DialogueCsvStore.load_map()
	_doc = MapEditorDoc.new_stage()
	_build_ui()
	_sync_fields()
	_set_mode("stage")  # 開いて最初に触るのは名前と盤のサイズ


## Ctrl+Z ＝直前の地形操作の取り消し（入力欄にフォーカスがあるときは、そちらの取り消しが優先）。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.ctrl_pressed and event.keycode == KEY_Z:
		_undo_terrain()
		accept_event()


func _load_catalogs() -> void:
	var tt: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain/terrain_type.json"))
	for t in tt.get("terrains", []):
		_terrains.append({ "id": String(t["id"]), "char": String(t.get("char", "?")),
			"name": String(t.get("name", t["id"])), "memo": String(t.get("memo", "")) })
	var ut: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/unit_type.json"))
	for t in ut.get("types", []):
		var cat := String(t.get("category", ""))
		_unit_types.append({ "id": String(t["id"]), "category": cat,
			"capacity": int(t.get("capacity", 0)) })  # 同乗(passengers)を出すかと、その上限
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
	var bgm_dir := DirAccess.open(BgmCatalog.BGM_ROOT)
	if bgm_dir != null:
		for f in bgm_dir.get_files():
			# .ogg と .ogg.import のどちらで見えても同じトラックIDに畳む
			var file := String(f)
			if not (file.ends_with(".ogg") or file.ends_with(".ogg.import")):
				continue
			var id := file.trim_suffix(".import").trim_suffix(".ogg")
			if not _bgm_tracks.has(id):
				_bgm_tracks.append(id)
		_bgm_tracks.sort()
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
	# 実機で確認＝一時ファイルに書き出してゲーム本体を別プロセスで起動し、直接読み込ませる。
	# エディタの盤は真上からの平面表示＝盤の高さや立ち絵の重なりは実機の絵でしか確かめられない。
	_add_button(bar, "実機で確認", _on_preview).tooltip_text = \
		"編集中のステージを一時保存し、ゲーム本体を別ウィンドウで起動して読み込む。\n保存済みファイルには触らない。"
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
	_board.height_edited.connect(_on_height_edited)
	scroll.add_child(_board)
	_board.refresh()

	var panel_scroll := ScrollContainer.new()
	panel_scroll.custom_minimum_size = Vector2(360, 0)
	# 横スクロールを DISABLED にすると、ScrollContainer は中身の最小幅を自分の最小幅として
	# 親に要求する＝パネル幅がモードごとの「いちばん長い行」で決まり、切り替えるたびに動く。
	# AUTO なら幅は常に 360。中身は 360 に合わせて縮み、それでも溢れたときだけ横バーが出る
	# （＝溢れたことに気づける）。行が長くなりがちなラベルは折り返す（_add_label / _add_heading）。
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main.add_child(panel_scroll)
	var panel_margin := MarginContainer.new()
	panel_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 縦にも伸ばす＝一覧（地形リスト）をパネルの下端まで届かせるための連鎖。
	# panel_margin → panel → _mode_box → リスト のどこかで止まると、リストは最小高のまま。
	panel_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_margin.add_theme_constant_override("margin_left", 8)
	panel_margin.add_theme_constant_override("margin_right", 14)  # 縦スクロールバーと入力欄の間の余白
	panel_margin.add_theme_constant_override("margin_bottom", 12)
	panel_scroll.add_child(panel_margin)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	panel_margin.add_child(panel)

	# モード
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
	_mode_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


## 見出しと、単独行の説明ラベル（_add_info）は折り返す。折り返さないと長い行がパネルの幅を
## 決めてしまう。逆に、行や表の中の見出し（_add_label）を折り返すと列が1文字幅まで潰れるので、
## そちらは折り返さない。
func _add_heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


## 行・表の中に置く見出し（"col" "所属" など）。折り返さない＝列の幅を保つ。
func _add_label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)


## 単独の行として置く説明・情報のラベル。長くなるので折り返す。
## 後から文字を書き換えたいときのために作った Label を返す。
func _add_info(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


## パネルの OptionButton。項目名が長くても幅を押し広げない（行の幅に収めて切る）。
func _make_option() -> OptionButton:
	var ob := OptionButton.new()
	ob.clip_text = true
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return ob


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
	_press_cell = MapEditorBoard.OUTSIDE
	_board.queue_redraw()
	_rebuild_mode()


## いまのモードのパレットだけ貼り直す（選択は保つ）。
## パレット内の絞り込みを変えたときはこちら＝_set_mode を呼ぶと選択中の駒が外れてしまう。
func _rebuild_mode() -> void:
	var mode := _mode
	for c in _mode_box.get_children():
		c.queue_free()
	match mode:
		"stage":
			_build_stage_palette()
		"select":
			_add_hint(_mode_box, "マップ上で選択した地形・ユニットの情報を参照できる。")
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
		"event":
			_build_event_panel()
		"outcome":
			_build_outcome_panel()
		"base":
			_add_hint(_mode_box, "左クリック＝設置 or 選択\n右クリック＝削除\nドラッグ＝移動")
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
	var ob := _make_option()
	for i in keys.size():
		ob.add_item(String(displays[i]))
		if String(keys[i]) == current:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: on_pick.call(String(keys[i])))
	return _labeled_row(label, ob)


## ラベル＋コントロールの1行（パレットの各項目を同じ形に揃える）。
func _labeled_row(label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	if label != "":
		_add_label(row, label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
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


## 地形パレット。分類＝地形タイプ（性能）、一覧＝その terrain_type を持つスキン（見た目）。
func _build_terrain_palette() -> void:
	if _paint_tool == "fill":
		_add_hint(_mode_box, "左クリック＝地続きをまとめて塗る / 右クリック＝そのマスの設定を取り込む。\n"
			+ "範囲は「いまの見た目が同じ」マス（地形＋スキン＋高さ上書きが一致）。誤爆は Ctrl+Z で戻せる。")
	else:
		_add_hint(_mode_box, "左ドラッグ＝塗る / 右クリック＝そのマスの設定を取り込む")
	_mode_box.add_child(_labeled_option("塗り方", TOOL_LABELS.keys(), TOOL_LABELS.values(), _paint_tool,
		func(k: String) -> void:
			_paint_tool = k
			_rebuild_mode()))
	var cat_keys := []
	var cat_names := []
	for t in _terrains:
		cat_keys.append(String(t["id"]))
		cat_names.append("%s（%s）" % [t["name"], t["id"]])
	_mode_box.add_child(_labeled_option("分類", cat_keys, cat_names, _sel_terrain_category,
		func(k: String) -> void:
			_sel_terrain_category = k
			_sel_terrain_skin = ""  # 分類を変えたら、その一覧の先頭を選び直す
			_rebuild_mode()))
	_mode_box.add_child(_height_override_row())
	_add_hint(_mode_box, "高さ上書き＝elevation と floor をペアで（空欄＝スキンの高さのまま）。見た目だけ・ルールに入らない。")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 160)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL  # パネルの下端まで伸ばす
	var pool := []
	for s in _terrain_skins:
		if String(s["terrain_type"]) == _sel_terrain_category:
			pool.append(s)
	if pool.is_empty():
		_add_hint(_mode_box, "この地形に登録されたスキンはありません（塗れません）。")
		_sel_terrain_skin = ""
		return
	var ids := []
	for s in pool:
		ids.append(String(s["skin_id"]))
	if not ids.has(_sel_terrain_skin):
		_sel_terrain_skin = String(ids[0])
	for i in pool.size():
		var s: Dictionary = pool[i]
		list.add_item("%s — %s" % [s["name"], s["skin_id"]])
		list.set_item_tooltip(i, String(s["memo"]))
		if String(s["skin_id"]) == _sel_terrain_skin:
			list.select(i)
	list.item_selected.connect(func(i: int) -> void: _sel_terrain_skin = String(ids[i]))
	_mode_box.add_child(list)


## 高さ上書きの入力行（elevation / floor の2欄）。値はテキストのまま持ち、塗る瞬間に検証する
## （_brush_override）。空欄＝上書きなし。片方だけ入れた状態では塗れない（ペア必須）。
func _height_override_row() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ev := LineEdit.new()
	ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ev.placeholder_text = "elevation"
	ev.text = _ov_elevation
	ev.text_changed.connect(func(t: String) -> void: _ov_elevation = t)
	box.add_child(ev)
	var fl := LineEdit.new()
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.placeholder_text = "floor"
	fl.text = _ov_floor
	fl.text_changed.connect(func(t: String) -> void: _ov_floor = t)
	box.add_child(fl)
	return _labeled_row("高さ上書き", box)


## 地形タイプの ASCII 1文字（terrain グリッド用）。未知なら既定地形。
func _char_of_type(type_id: String) -> String:
	for t in _terrains:
		if String(t["id"]) == type_id:
			return String(t["char"])
	return MapEditorDoc.DEFAULT_CHAR


## 特性の sight 既定値（ai.csv の生の値＝`-` / `*` / 数値）。未定義の特性は `-` 扱い。
func _preset_sight_value(ai_label: String) -> Variant:
	var preset: Dictionary = _ai_params.get(ai_label, {})
	return preset.get("sight", SIGHT_UNUSED)


## その特性が sight を使うか。`-`＝使わない（charge・raid）／`*` と数値＝使う。
## 詳細 → doc/gdd/ai.md データ構成
static func _sight_is_used(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
	var s := String(v).strip_edges()
	return s != SIGHT_UNUSED and s != ""


## sight が `*`（上限なし＝盤全体。ただし視線コスト x の壁は遮る）か。
static func _sight_is_unlimited(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and String(v).strip_edges() == SIGHT_UNLIMITED


## sight の表示文字列（`*` はそのまま、数値は10進）。
static func _sight_text(v: Variant) -> String:
	return SIGHT_UNLIMITED if _sight_is_unlimited(v) else str(_sight_number(v))


## sight のスピンボックス用の数値（`*` や非数値は SIGHT_SPIN_DEFAULT）。
static func _sight_number(v: Variant) -> int:
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else SIGHT_SPIN_DEFAULT


## 部隊/拠点の行動順 order 行。小さいほうから動く（拠点も1部隊として同じ列に並ぶ）。
## 詳細 → doc/gdd/ai.md（行動順）
func _add_order_row(parent: Control, target: Dictionary, label: String = "order") -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	if label != "":
		_add_label(row, label)
	var spin := _make_spin(1, 99, float(maxi(int(target.get("order", _doc.max_order() + 1)), 1)))
	spin.custom_minimum_size = Vector2(64, 0)
	spin.tooltip_text = "行動順。小さいほうから動く。拠点（AI出撃）も同じ列に並ぶ。"
	spin.value_changed.connect(func(v: float) -> void: target["order"] = int(v))
	row.add_child(spin)
	if not target.has("order"):
		target["order"] = int(spin.value)  # 省略を残さない（実データは全部隊に書く）


## 部隊/拠点の sight 上書き行。sight を使う特性のときだけ出す（`-` の特性では出さない）。
## 「sight」＝上書きするか（外すと特性の既定を継承）、「上限なし」＝`*` を書く、数値＝視線距離。
## sight 以外のパラメーターは出さない：新しいふるまいは ai.csv に特性を足して表現する
## （AIは「特性＝CSV／割り当て＝ステージ」の2層。詳細 → doc/gdd/ai.md データ構成）。
func _add_sight_row(parent: Control, target: Dictionary, ai_label: String) -> void:
	var preset_value: Variant = _preset_sight_value(ai_label)
	if not _sight_is_used(preset_value):
		if target.erase("sight"):  # 見えない上書きを残さない（sight を使わないAIに変えたら消す）
			_say("%s は sight を使わない特性のため、sight の上書きを外しました。" % ai_label)
		return
	var current: Variant = target.get("sight", preset_value)
	var tip := "索敵の広さ（視線コストの積算予算）。外すと %s の既定 %s を継承する。" \
		% [ai_label, _sight_text(preset_value)]
	var row := HBoxContainer.new()
	parent.add_child(row)
	var check := CheckBox.new()
	check.text = "sight"
	check.button_pressed = target.has("sight")
	check.tooltip_text = tip
	row.add_child(check)
	var star := CheckBox.new()
	star.text = "上限なし"
	star.button_pressed = _sight_is_unlimited(current)
	star.tooltip_text = "盤全体を見る（ai.csv の `*`）。視線コスト x の壁は遮る。"
	row.add_child(star)
	var spin := _make_spin(0, 20, float(_sight_number(current)))
	spin.custom_minimum_size = Vector2(64, 0)
	spin.tooltip_text = tip
	row.add_child(spin)
	# 3つのウィジェットが1つの値を作るので、書き込みも活殺も1箇所に寄せる（どれが動いても同じ関数）。
	var apply := func() -> void:
		if not check.button_pressed:
			target.erase("sight")
		elif star.button_pressed:
			target["sight"] = SIGHT_UNLIMITED
		else:
			target["sight"] = int(spin.value)
		star.disabled = not check.button_pressed
		spin.editable = check.button_pressed and not star.button_pressed
	apply.call()
	check.toggled.connect(func(_on: bool) -> void: apply.call())
	star.toggled.connect(func(_on: bool) -> void: apply.call())
	spin.value_changed.connect(func(_v: float) -> void: apply.call())


## 「ステージ」モード＝ステージ全体の設定（名前・ターン制限・盤のサイズ）。
## 入力欄はこのモードのときだけ存在する＝値の出どころは常に _doc（_sync_fields で貼り直す）。
func _build_stage_palette() -> void:
	_add_hint(_mode_box, "ステージ全体の設定。cols / rows / margin は「サイズを適用」で盤に反映する。")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	_mode_box.add_child(grid)
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
	_add_button(_mode_box, "サイズを適用", _on_resize).tooltip_text = \
		"cols / rows / margin を盤に反映する。縮小すると範囲外の駒・拠点・スキン指定は削除される。"
	# 盤を広げると余白は右と下に増える＝左上に描いたものを寄せ直すための操作。
	# 左右が2列単位な理由は MapEditorDoc.is_shiftable_dcol にある。
	_add_heading(_mode_box, "全体をずらす")
	_add_hint(_mode_box, "地形・見た目スキン・駒・拠点・防衛対象をまとめて平行移動する。\n"
		+ "左右は2列単位（1列だと奇数列と偶数列が入れ替わって形が崩れる）。\n"
		+ "盤の外に出る中身があるときは動かさない＝逆向きに押せば戻せる（Ctrl+Z の対象外）。")
	var shift_row := HBoxContainer.new()
	_mode_box.add_child(shift_row)
	for step: Array in [[-2, 0, "← 2列"], [2, 0, "→ 2列"], [0, -1, "↑ 1行"], [0, 1, "↓ 1行"]]:
		var delta := Vector2i(int(step[0]), int(step[1]))
		var b := _add_button(shift_row, String(step[2]), func() -> void: _on_shift(delta))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# BGM（bgm: { main }）。値はトラックID＝assets/bgm/{id}.ogg を規約で解決する。
	# 詳細 → doc/audio/bgm.md
	_add_heading(_mode_box, "BGM")
	_add_hint(_mode_box, "曲は assets/bgm/ に置いた .ogg から選ぶ。\n"
		+ "「（指定なし）」は冒険譚の既定（campaign.json）→ 全体既定へ送る。")
	for slot in BgmCatalog.SLOTS:
		_mode_box.add_child(_bgm_row(String(slot)))
	_sync_fields()  # 入力欄を作り直したので、いまの doc の値を入れ直す


## BGM スロット1つ分の行。選択肢は assets/bgm/ に実在する .ogg ＋ いま指しているID。
## 未配置のIDを指したステージを開いても選択肢から落とさない＝開いて保存しただけで指定が消えない。
func _bgm_row(slot: String) -> HBoxContainer:
	var current := String(_doc.bgm().get(slot, ""))
	var keys := [""]
	var displays := ["（指定なし）"]
	for track in _bgm_tracks:
		keys.append(String(track))
		displays.append(String(track))
	if current != "" and not keys.has(current):
		keys.append(current)
		displays.append("%s（ファイル未配置）" % current)
	var row := _labeled_option("bgm %s" % slot, keys, displays, current,
		func(k: String) -> void: _doc.set_bgm(slot, k))
	row.tooltip_text = "main＝そのステージの曲。"
	return row


## 「自軍」モード＝駒を置く道具（分類→種別）。置いた駒／クリックした駒は下段で名前を付けられる。
func _build_player_palette() -> void:
	_add_hint(_mode_box, "左クリック＝配置 or 選択\n右クリック＝削除\nドラッグ＝移動")
	# 分類（category）で絞ってから種別を選ぶ
	_mode_box.add_child(_labeled_option("分類", [""] + _categories, ["すべて"] + _categories, _sel_category,
		func(k: String) -> void:
			_sel_category = k
			_rebuild_mode()
			_apply_palette_to_selected_unit()))
	var ids := []
	for t in _unit_types:
		if _sel_category == "" or String(t["category"]) == _sel_category:
			ids.append(String(t["id"]))
	if not ids.has(_sel_type_id) and not ids.is_empty():
		_sel_type_id = String(ids[0])  # 絞り込みで外れたら先頭にフォールバック
	var ob := _make_option()
	for i in ids.size():
		ob.add_item(ids[i])
		if String(ids[i]) == _sel_type_id:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void:
		_sel_type_id = String(ids[i])
		_apply_palette_to_selected_unit())
	_mode_box.add_child(_labeled_row("タイプ", ob))
	_add_unit_box()


## パレットの値を、選んでいる駒に反映する（選んでいなければ何もしない＝次に置く駒の設定のまま）。
## 自軍＝タイプ、敵＝スキンと所属部隊。パレットは「置く道具」と「選んだ駒の編集」を兼ねる。
func _apply_palette_to_selected_unit() -> void:
	var hit := _doc.unit_at(_sel_unit.x, _sel_unit.y)
	if hit.is_empty():
		return
	var u: Dictionary = hit["unit"]
	var squad := int(hit["squad"])
	if _mode == "player" and squad < 0:
		if String(u.get("type", "")) == _sel_type_id:
			return
		u["type"] = _sel_type_id
		_say("(%d, %d) の駒を %s にしました。" % [_sel_unit.x, _sel_unit.y, _sel_type_id])
	elif _mode == "enemy" and squad >= 0:
		var changed := false
		if String(u.get("skin", "")) != _sel_skin_id:
			u["skin"] = _sel_skin_id
			u.erase("type")  # 敵はスキンで置く＝型の指定が残っていると食い違う
			changed = true
		if squad != _sel_squad and _doc.move_unit_to_squad(squad, int(hit["index"]), _sel_squad):
			changed = true
			_say("(%d, %d) の駒を部隊%d へ移しました。" % [_sel_unit.x, _sel_unit.y, _sel_squad])
		elif changed:
			_say("(%d, %d) の駒を %s にしました。" % [_sel_unit.x, _sel_unit.y, _sel_skin_id])
		if not changed:
			return
	else:
		return
	_board.refresh()


## 「自軍」「敵」モードの最後の行＝アクター名。駒を選ぶと、その駒のものが入る。
func _add_unit_box() -> void:
	_unit_box = VBoxContainer.new()
	_unit_box.add_theme_constant_override("separation", 6)
	_mode_box.add_child(_unit_box)
	_refresh_unit_box()


## 「敵」モードの配置先を選ぶ行。_sel_squad は「敵グループ」モードと共有＝
## グループ側で選んだ部隊に、そのまま駒を置ける。
func _add_squad_selector() -> void:
	var squads: Array = _doc.data["enemy"]
	if _sel_squad >= squads.size():
		_sel_squad = maxi(squads.size() - 1, 0)
	var ob := _make_option()
	for i in squads.size():
		ob.add_item("部隊%d[順%s]: %s（%s）" % [i, str(squads[i].get("order", "-")),
			String(squads[i].get("name", "無名")), String(squads[i].get("ai", "?"))])
	if not squads.is_empty():
		ob.select(_sel_squad)
	ob.item_selected.connect(func(i: int) -> void:
		_sel_squad = i
		_rebuild_mode()
		_apply_palette_to_selected_unit())
	_mode_box.add_child(_labeled_row("部隊", ob))


## 「敵グループ」モード＝部隊の一覧（1部隊＝2行）。作る・選ぶ・名前とAIと行動順を決める・消す。
## 駒の配置は持たない＝置くのは「敵」モードの仕事（同じ画面に混ぜると何を触っているか読めない）。
func _build_squad_palette() -> void:
	_add_hint(_mode_box, "部隊を作る・選ぶ・設定する。駒を置くのは「敵」モード。\n"
		+ "盤の敵の駒を左クリック＝その駒の部隊を選ぶ。")
	var squads: Array = _doc.data["enemy"]
	if _sel_squad >= squads.size():
		_sel_squad = maxi(squads.size() - 1, 0)
	if squads.is_empty():
		_add_hint(_mode_box, "部隊がありません。「部隊を追加」で作成します。")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)  # 部隊どうしの隙間（2行が1件だと分かるように）
	_mode_box.add_child(list)
	var group := ButtonGroup.new()
	for i in squads.size():
		_add_squad_item(list, group, i, squads[i])
	_add_button(_mode_box, "部隊を追加", func() -> void:
		_sel_squad = _doc.add_squad(_ai_presets[0] if not _ai_presets.is_empty() else "charge")
		_rebuild_mode())


## 部隊1件＝2〜3行。
## 1行目: 選択トグル（部隊番号と駒数）／部隊名／削除
## 2行目: 行動順／AI特性
## 3行目: sight 上書き（sight を使う特性のときだけ。2行目に足すとAI名が潰れる幅しかない）
func _add_squad_item(parent: VBoxContainer, group: ButtonGroup, index: int, sq: Dictionary) -> void:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 2)
	parent.add_child(item)

	var row1 := HBoxContainer.new()
	item.add_child(row1)
	var pick := Button.new()
	pick.text = "部隊%d・%d体" % [index, sq.get("units", []).size()]
	pick.toggle_mode = true
	pick.button_group = group
	pick.button_pressed = index == _sel_squad
	pick.tooltip_text = "この部隊を選ぶ（「敵」モードで駒を置く先になる）"
	pick.pressed.connect(func() -> void:
		_sel_squad = index
		_rebuild_mode())
	row1.add_child(pick)
	var name_edit := LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text = String(sq.get("name", ""))
	name_edit.placeholder_text = "部隊名の翻訳キー（省略可）"
	name_edit.text_changed.connect(func(t: String) -> void:
		if t == "":
			sq.erase("name")
		else:
			sq["name"] = t)
	row1.add_child(name_edit)
	_add_button(row1, "×", func() -> void:
		_ask("部隊%d を所属ユニットごと削除します。よろしいですか？" % index, func() -> void:
			_doc.remove_squad(index)
			_sel_squad = 0
			_rebuild_mode()
			_board.refresh()))

	# 部隊名の訳（ja・en）。イベント予告と同じ流儀＝ステージ保存時に dialogue.csv へ書く。
	var tr_row := HBoxContainer.new()
	item.add_child(tr_row)
	var texts := _i18n_texts(String(sq.get("name", "")))
	var tr_ja := LineEdit.new()
	tr_ja.text = String(texts.get("ja", ""))
	tr_ja.placeholder_text = "日本語"
	tr_ja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_ja.text_changed.connect(func(t: String) -> void: _stash_i18n(name_edit.text, "ja", t))
	tr_row.add_child(tr_ja)
	var tr_en := LineEdit.new()
	tr_en.text = String(texts.get("en", ""))
	tr_en.placeholder_text = "English"
	tr_en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_en.text_changed.connect(func(t: String) -> void: _stash_i18n(name_edit.text, "en", t))
	tr_row.add_child(tr_en)

	var row2 := HBoxContainer.new()
	item.add_child(row2)
	_add_order_row(row2, sq, "")  # 行動順（doc/gdd/ai.md 行動順）。ラベルは省いてツールチップで示す
	var ai_opts := _ai_options(false)
	var ai_row := _labeled_option("AI", ai_opts[0], ai_opts[1], String(sq.get("ai", "")),
		func(k: String) -> void:
			sq["ai"] = k
			_rebuild_mode())
	ai_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(ai_row)
	_add_sight_row(item, sq, String(sq.get("ai", "")))


## 「敵」モード＝駒を置く道具（配置先の部隊とスキンを選ぶ）。部隊の設定は「敵グループ」モード。
func _build_enemy_palette() -> void:
	_add_hint(_mode_box, "左クリック＝配置 or 選択\n右クリック＝削除\nドラッグ＝移動")
	_add_squad_selector()
	if _doc.data["enemy"].is_empty():
		_add_hint(_mode_box, "部隊がありません。盤をクリックすると自動で作成します（設定は「敵グループ」モードで）。")
	# 配置するスキン：分類で絞ってから選ぶ（基準＝味方専用スキンは出さない）
	_mode_box.add_child(_labeled_option("分類", [""] + _skin_categories, ["すべて"] + _skin_categories, _sel_skin_category,
		func(k: String) -> void:
			_sel_skin_category = k
			_rebuild_mode()
			_apply_palette_to_selected_unit()))
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
	var skin_ob := _make_option()
	for i in pool.size():
		skin_ob.add_item("%s（%s）" % [pool[i]["skin_id"], pool[i]["type_id"]])
		if String(pool[i]["skin_id"]) == _sel_skin_id:
			skin_ob.select(i)
	skin_ob.item_selected.connect(func(i: int) -> void:
		_sel_skin_id = String(pool_ids[i])
		_apply_palette_to_selected_unit())
	_mode_box.add_child(_labeled_row("スキン", skin_ob))
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
	_rebuild_mode()
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
	_rebuild_mode()
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
	_press_cell = MapEditorBoard.OUTSIDE  # 押すたびに引き直す（駒を掴めたときだけ下で入れる）
	# 外周(margin)は地形を描くだけの場所＝駒・拠点は置けず、選択の対象にもしない。
	if _mode != "terrain" and not _doc.in_board(col, row):
		_say("外周（margin）には駒・拠点を置けません。地形モードでのみ塗れます。")
		return
	match _mode:
		"terrain":
			if button == MOUSE_BUTTON_RIGHT:
				_pick_terrain(col, row)
				return
			_doc.push_terrain_undo()  # 1手＝押してから離すまで（ドラッグの一筆もまとめて戻せる）
			if _paint_tool == "fill":
				_fill(col, row)
			else:
				_paint(col, row)
		"player":
			if button == MOUSE_BUTTON_LEFT:
				if _pick_player(col, row):
					_press_cell = Vector2i(col, row)  # 掴んだ＝そのままドラッグで動かせる
					return  # 配置済みの自軍を左クリック＝その種別を取り込む（配置しない）
				if _doc.add_player(_sel_type_id, col, row):
					_board.refresh()
					_select_unit(col, row)
					_press_cell = Vector2i(col, row)
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
					_press_cell = Vector2i(col, row)  # 掴んだ＝そのままドラッグで動かせる
					return  # 配置済みの敵を左クリック＝その設定をパレットへ取り込む（配置しない）
				var created := false
				if _doc.data["enemy"].is_empty():
					_sel_squad = _doc.add_squad(_ai_presets[0] if not _ai_presets.is_empty() else "charge")
					_rebuild_mode()
					created = true
				if _doc.add_enemy(_sel_squad, _sel_skin_id, col, row):
					_board.refresh()
					_select_unit(col, row)
					_press_cell = Vector2i(col, row)
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
					_rebuild_mode()
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
				_press_cell = Vector2i(col, row)  # 掴んだ＝そのままドラッグで動かせる
			else:
				if _doc.remove_base_at(col, row):
					_board.refresh()
				if _sel_base == Vector2i(col, row):
					_deselect_base()
		"outcome":
			_say("勝敗条件は右のパネルで足す・消す（盤のクリックでは変わらない）。")
		"select":
			_board.selected = Vector2i(col, row)
			_board.queue_redraw()
			_show_inspection(col, row)


func _on_cell_dragged(col: int, row: int, button: int) -> void:
	if _mode == "terrain" and _paint_tool == "pen" and button == MOUSE_BUTTON_LEFT:
		_paint(col, row)


## 左ドラッグ＝掴んだものを離したマスへ動かす（「自軍」「敵」＝駒／「拠点」＝拠点）。
## 掴めていないときは何もしない。
func _on_cell_released(col: int, row: int, button: int) -> void:
	var from := _press_cell
	_press_cell = MapEditorBoard.OUTSIDE
	if button != MOUSE_BUTTON_LEFT or from == MapEditorBoard.OUTSIDE:
		return
	var to := Vector2i(col, row)
	if to == from:
		return  # 掴んで同じマスで離した＝ただのクリック
	match _mode:
		"player", "enemy":
			if _doc.move_unit_at(from.x, from.y, to.x, to.y):
				_board.refresh()
				_select_unit(to.x, to.y)
				_say("駒を (%d, %d) → (%d, %d) へ動かしました。" % [from.x, from.y, to.x, to.y])
			else:
				_say("(%d, %d) へは動かせません（外周か、既に駒があります）。" % [to.x, to.y])
		"base":
			if _doc.move_base_at(from.x, from.y, to.x, to.y):
				_board.refresh()
				_select_base(to.x, to.y)
				_refresh_defeat()  # 防衛対象の座標も連れて動く＝一覧の表示を合わせる
				_say("拠点を (%d, %d) → (%d, %d) へ動かしました。" % [from.x, from.y, to.x, to.y])
			else:
				_say("(%d, %d) へは動かせません（外周か、既に拠点があります）。" % [to.x, to.y])


## いま塗る内容 [地形の文字, skin_id, 高さ上書き]。
## 選んだスキンは必ず書く（TerrainSkinCatalog の空欄フォールバック＝型IDと同名のスキンは、
## object 系の地形には存在しない＝空で書くと描かれないマスになる）。
## 高さ上書きの入力が不正（片方だけ・数値でない）なら null＝塗れない。
## スキンが1つも無い地形（大岩・立入禁止）は選べないので null＝塗れない。
func _brush() -> Variant:
	var ov: Variant = _brush_override()
	if ov == null:
		return null
	if _sel_terrain_skin == "":
		return null
	return [_char_of_type(_sel_terrain_category), _sel_terrain_skin, ov]


## 高さ上書きの入力値 → { elevation, floor }。両方空＝{}（上書きなし）。
## 片方だけ・数値でない＝null（塗る操作を止める＝半分だけ書いた JSON を作らない）。
func _brush_override() -> Variant:
	var ev := _ov_elevation.strip_edges()
	var fl := _ov_floor.strip_edges()
	if ev == "" and fl == "":
		return {}
	if not ev.is_valid_float() or not fl.is_valid_float():
		return null
	return { "elevation": ev.to_float(), "floor": fl.to_float() }


## 地形を1マス塗る。性能（terrain の文字）と見た目（terrain_skins の差分＋高さ上書き）を同時に決める。
func _paint(col: int, row: int) -> void:
	var brush: Variant = _brush()
	if brush == null:
		_say("高さ上書きは elevation と floor を数値のペアで入れてください（空欄＝上書きなし）。")
		return
	_doc.set_terrain_char(col, row, String(brush[0]))
	_doc.set_terrain_skin(col, row, String(brush[1]), brush[2])
	_board.queue_redraw()


## 地続き（いまの見た目が同じマス）をまとめて塗る。高さ上書きも込みで塗る。
func _fill(col: int, row: int) -> void:
	var brush: Variant = _brush()
	if brush == null:
		_say("高さ上書きは elevation と floor を数値のペアで入れてください（空欄＝上書きなし）。")
		return
	var n := _doc.fill_terrain(col, row, String(brush[0]), String(brush[1]), brush[2])
	_board.queue_redraw()
	_say("%d マスを塗りました（Ctrl+Z で戻せます）。" % n)


## 右クリックしたマスの設定をパレットへ取り込む（スポイト）。分類・スキン・高さ上書きを
## そのマスと同じにする＝そのまま左クリックで同じマスを複製できる。盤は変えない＝Undo に積まない。
func _pick_terrain(col: int, row: int) -> void:
	var tid := TerrainType.char_to_id(_doc.terrain_char(col, row))
	var skin := _doc.terrain_skin(col, row)
	if skin == "":
		skin = tid  # 差分なし＝型IDと同名のスキン（TerrainSkinCatalog の解決と同じ）
	var exact := _has_terrain_skin(tid, skin)  # 盤の文字とスキンの terrain_type が食い違うマスがある
	_sel_terrain_category = tid
	_sel_terrain_skin = skin if exact else ""
	var ov := _doc.height_override(col, row)
	_ov_elevation = "" if ov.is_empty() else str(ov["elevation"])
	_ov_floor = "" if ov.is_empty() else str(ov["floor"])
	_rebuild_mode()  # 取り込んだ値でパレットを開き直す（スキンが引けなければ一覧の先頭になる）
	if exact:
		_say("(%d, %d) の設定を取り込みました（%s / %s）。" % [col, row, tid, _sel_terrain_skin])
	else:
		_say("(%d, %d) のスキン '%s' は %s の一覧にありません。分類だけ取り込み、スキンは %s になりました。"
				% [col, row, skin, tid, _sel_terrain_skin])


## その地形タイプにその skin_id が登録されているか。
func _has_terrain_skin(type_id: String, skin_id: String) -> bool:
	for s in _terrain_skins:
		if String(s["skin_id"]) == skin_id and String(s["terrain_type"]) == type_id:
			return true
	return false


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
	_add_info(_inspector, "マス (%d, %d)  地形: %s" % [col, row, tid])
	var skin := _doc.terrain_skin(col, row)
	_add_info(_inspector, "見た目: %s" % [skin if skin != "" else "%s（差分なし）" % tid])
	var ov := _doc.height_override(col, row)
	if not ov.is_empty():
		_add_info(_inspector, "高さ上書き: elevation %s / floor %s" % [str(ov["elevation"]), str(ov["floor"])])
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
	_add_info(_inspector,head)
	var actor := String(u.get("actor", ""))
	_add_info(_inspector, "actor: %s" % (actor if actor != "" else "（名前なし）"))
	if u.has("passengers") and not u["passengers"].is_empty():
		_add_hint(_inspector, "同乗 %d 体（passengers は JSON 直接編集）" % u["passengers"].size())
	_add_hint(_inspector, "駒の編集は「自軍」「敵」モードで。")


## 選択モードの拠点表示。ここは読むだけ＝編集は「拠点」モードに寄せてある
## （同じ設定が2箇所にあると、どちらが効くのか分からなくなるため）。
func _inspect_base(hit: Dictionary) -> void:
	var b: Dictionary = hit["base"]
	_add_info(_inspector, "拠点: %s / %s" % [
		String(TEAM_LABELS.get(String(b.get("team", "neutral")), b.get("team", "?"))),
		String(KIND_LABELS.get(String(b.get("kind", "fort")), b.get("kind", "?")))])
	var ai := String(b.get("ai", ""))
	if ai == "":
		_add_info(_inspector, "AI出撃: （なし）")
	else:
		_add_info(_inspector, "AI出撃: %s（%s）  order: %s"
			% [ai, String(_ai_names.get(ai, ai)), str(b.get("order", "-"))])
		var preset_sight: Variant = _preset_sight_value(ai)
		if _sight_is_used(preset_sight):
			_add_info(_inspector, "sight: %s%s" % [_sight_text(b.get("sight", preset_sight)),
				"（上書き）" if b.has("sight") else "（%s の既定）" % ai])
	var g: Variant = b.get("garrison", [])
	if typeof(g) == TYPE_ARRAY and not (g as Array).is_empty():
		_add_info(_inspector, "控え（garrison）: 計 %d 体" % MapEditorDoc.garrison_count(b))
		for e in g:
			_add_info(_inspector, "  ・%s ×%d"
				% [String(e.get("skin", e.get("type", "?"))), maxi(int(e.get("count", 1)), 1)])
	else:
		_add_info(_inspector, "控え（garrison）: （なし）")
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


## アクター名の行を貼り直す（選んだ駒が変わった／消えたとき）。
func _refresh_unit_box() -> void:
	if _unit_box == null or not is_instance_valid(_unit_box):
		return  # 「自軍」「敵」モード以外では箱が無い＝描くものがない
	for c in _unit_box.get_children():
		c.queue_free()
	var hit := _doc.unit_at(_sel_unit.x, _sel_unit.y)
	var u: Dictionary = hit["unit"] if not hit.is_empty() else {}
	_add_actor_row(_unit_box, u)
	if _mode == "player":
		_add_supply_row(_unit_box, u)
	if not u.is_empty():
		_add_passenger_rows(_unit_box, u, _mode == "enemy", func() -> void:
			_board.refresh()
			_refresh_unit_box())


## 同乗（passengers）の一覧＋追加。輸送（capacity ≥ 1）の駒にだけ出す。
## 中身は拠点の控えと同じ形＝1行1体、× で外す。載せた駒は盤上に出ない（殲滅の数に入らない）。
## 詳細 → doc/gdd/movement.md（輸送）
## by_skin＝駒を skin で選ぶ（敵）か type で選ぶ（自軍）か。on_change＝1行足し引きしたあとの貼り直し。
## 盤の駒（選択パネル）とイベントの駒（増援）で貼り直し先が違うので、呼び出し側から渡す。
func _add_passenger_rows(parent: VBoxContainer, u: Dictionary, by_skin: bool, on_change: Callable) -> void:
	var capacity := _capacity_of(u)
	if capacity <= 0:
		return
	# 空のまま passengers キーを生やさない（読み込んで保存しただけで差分が出てしまう）
	var raw: Variant = u.get("passengers", [])
	var list: Array = raw if typeof(raw) == TYPE_ARRAY else []
	_add_info(parent, "同乗（passengers） %d/%d" % [list.size(), capacity])
	var keys := _unit_pick_keys(by_skin)
	var displays := _unit_pick_displays(by_skin)
	for i in list.size():
		var entry: Dictionary = list[i]
		var row := _labeled_option("", keys, displays, String(entry.get("skin", entry.get("type", ""))),
			func(k: String) -> void:
				entry.erase("skin")
				entry.erase("type")
				entry["skin" if by_skin else "type"] = k
				_board.refresh())
		parent.add_child(row)
		_add_button(row, "×", func() -> void:
			if i >= list.size():
				return  # 貼り直し待ちの古い行（queue_free は次のフレーム）
			list.remove_at(i)
			if list.is_empty():
				u.erase("passengers")  # 空の passengers キーは書き出さない
			on_change.call())
	_add_button(parent, "同乗を追加", func() -> void:
		if list.size() >= capacity:
			_say("この輸送は %d 体までです。" % capacity)
			return
		list.append({ ("skin" if by_skin else "type"): String(keys[0]) })
		u["passengers"] = list
		on_change.call())


## 駒を選ぶドロップダウンのキー列。敵は skin（基準＝味方専用スキンは出さない）、自軍は type。
func _unit_pick_keys(by_skin: bool) -> Array:
	var keys := []
	if by_skin:
		for s in _skins:
			if String(s["category"]) != STANDARD_CATEGORY:
				keys.append(String(s["skin_id"]))
	else:
		for t in _unit_types:
			keys.append(String(t["id"]))
	return keys


## _unit_pick_keys と同じ並びの表示名。
func _unit_pick_displays(by_skin: bool) -> Array:
	var out := []
	if by_skin:
		for s in _skins:
			if String(s["category"]) != STANDARD_CATEGORY:
				out.append("%s（%s）" % [s["skin_id"], s["type_id"]])
	else:
		for t in _unit_types:
			out.append(String(t["id"]))
	return out


## 駒の積載数（type から引く。敵は skin → type を逆引き）。輸送でなければ 0。
func _capacity_of(u: Dictionary) -> int:
	var type_id := String(u.get("type", ""))
	if type_id == "":
		for s in _skins:
			if String(s["skin_id"]) == String(u.get("skin", "")):
				type_id = String(s["type_id"])
				break
	for t in _unit_types:
		if String(t["id"]) == type_id:
			return int(t["capacity"])
	return 0


## 名指し(actor)の入力行。空＝名前なし。味方・敵のどちらにも付けられる。
## u が空＝駒を選んでいない＝入力できない（名前は駒に付くもので、パレットの設定ではない）。
## 確定は Enter かフォーカスを外したとき＝1文字打つたびに勝敗条件を追い直さない。
func _add_actor_row(parent: VBoxContainer, u: Dictionary) -> void:
	var edit := LineEdit.new()
	edit.text = String(u.get("actor", ""))
	edit.editable = not u.is_empty()
	edit.placeholder_text = "（名前なし）" if not u.is_empty() else "（駒を選ぶと入力できる）"
	edit.tooltip_text = "駒を名指す値。会話の分岐・継承(carryover)・勝敗条件がこの名前を見る。\n" \
		+ "名前のない雑兵には付けない（doc/gdd/map.md 名前つきの駒）。"
	var row := _labeled_row("アクター名", edit)
	parent.add_child(row)
	if u.is_empty():
		return
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


## 戦力供給(supply)の行。自軍の駒にだけ出す（名簿は自軍のもの）。
## 省略＝名簿から引く＝居なければ盤に出ない。join＝この盤で配給する＝クリアで名簿に載る。
## refill＝名簿から引いて兵数だけ満員に戻す。revive＝離脱者（兵力ゼロ）も満員で呼び戻す。
## 詳細 → doc/gdd/map.md 配置
func _add_supply_row(parent: VBoxContainer, u: Dictionary) -> void:
	var keys := ["", "join", "refill", "revive"]
	var displays := ["名簿から（そのまま）", "この盤で初登場（配給）", "名簿から＋兵を満タン", "離脱者も呼び戻す"]
	var ob := _make_option()
	for d in displays:
		ob.add_item(d)
	ob.select(maxi(keys.find(String(u.get("supply", ""))), 0))
	ob.disabled = u.is_empty()
	ob.tooltip_text = "名簿から（そのまま）＝前の盤の損耗・成長のまま出す。まだ仲間になっていなければ盤に出ない。\n" \
		+ "この盤で初登場＝名簿を見ずに配給する。クリアで名簿に載る。\n" \
		+ "兵を満タン＝成長はそのままで兵数だけ戻す（幕間の休息）。離脱者は戻らない。\n" \
		+ "離脱者も呼び戻す＝兵力ゼロで抜けた仲間も満タンで戻す。\n" \
		+ "アクター名の無い駒はいつも配給なので、この設定は要らない。"
	parent.add_child(_labeled_row("継承", ob))
	if ob.disabled:
		return
	ob.item_selected.connect(func(i: int) -> void:
		var key := String(keys[i])
		var actor := String(u.get("actor", ""))
		if key != "" and actor == "":  # 名前の無い駒はもともと配給＝指定を書いても意味が無い
			_say("アクター名の無い駒はいつも配給されます。先に名前を付けてください。")
			ob.select(0)
			return
		if key == "":
			u.erase("supply")
			_say("\"%s\" を名簿から引くようにしました（未加入なら盤に出ません）。" % actor)
		else:
			u["supply"] = key
			_say("\"%s\" の出し方を「%s」にしました。" % [actor, displays[i]]))


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
	# 控え（garrison）。見出しに総数を出す＝行が増えても「この拠点に何体眠っているか」が一目で読める
	if typeof(b.get("garrison")) != TYPE_ARRAY:
		b["garrison"] = []
	var g: Array = b["garrison"]
	var total := _add_info(parent, "")
	var show_total := func() -> void:
		total.text = "控え（garrison）: 計 %d 体" % MapEditorDoc.garrison_count(b)
	show_total.call()
	for i in g.size():
		var entry: Dictionary = g[i]
		var row := HBoxContainer.new()
		parent.add_child(row)
		var ob := _make_option()
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
			show_total.call()  # 下段は貼り直さない（入力中の行が消える）＝見出しだけ書き換える
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


# --- イベント（時限発生＝増援）。盤に描くものではないのでリスト編集で持つ。詳細 → doc/gdd/map.md イベント ---

func _build_event_panel() -> void:
	_add_hint(_mode_box, "指定ターンに、盤に居ない駒を足す（増援）。\n"
		+ "ターンは両陣営1巡で1。その陣営の手番が始まる時点で出る。\n"
		+ "座標は駒ごとに指定する。埋まっている／入れない地形なら最寄りの空きへずれる。")
	_event_box = VBoxContainer.new()
	_event_box.add_theme_constant_override("separation", 8)
	_mode_box.add_child(_event_box)
	_refresh_events()


func _refresh_events() -> void:
	if _event_box == null or not is_instance_valid(_event_box):
		return  # 「イベント」モード以外では箱が無い＝描くものがない
	for c in _event_box.get_children():
		c.queue_free()
	var list := _doc.event_list()
	for i in list.size():
		if typeof(list[i]) == TYPE_DICTIONARY:
			_add_event_rows(i, list[i])
	_add_button(_event_box, "＋ 増援を足す", func() -> void:
		_doc.add_event(_doc.event_list().size() + 1, "player")
		_refresh_events())


## 増援1件（見出し＋ターン・陣営・AI・予告文・駒の一覧）。
func _add_event_rows(index: int, ev: Dictionary) -> void:
	var team := String(ev.get("team", "player"))
	var units: Array = _doc.event_units(index)
	_add_outcome_head(_event_box, "%dターン目 ／ %s ／ %d体" % [int(ev.get("turn", 1)),
		TEAM_LABELS.get(team, team), units.size()], func() -> void:
			_doc.remove_event(index)
			_refresh_events())
	var box := _indent(_event_box)
	var type_id := String(ev.get("type", "reinforce"))
	if type_id != "reinforce":
		_add_warn(box, "エディタが知らないイベント種別 '%s'（JSONを直接見る）" % type_id)
		return
	var turn := _make_spin(1, 999, int(ev.get("turn", 1)))
	turn.value_changed.connect(func(v: float) -> void:
		ev["turn"] = int(v)
		_refresh_events())
	box.add_child(_labeled_row("ターン", turn))
	box.add_child(_labeled_option("陣営", ["player", "enemy"], ["自軍", "敵"], team,
		func(k: String) -> void:
			ev["team"] = k
			if k == "player":
				ev.erase("ai")  # 自軍の増援は部隊を持たない
			for u in units:  # 選び方が type ↔ skin で変わるので、指定を持ち越さない
				u.erase("type")
				u.erase("skin")
			_refresh_events()))
	if team == "enemy":
		var ai_opts := _ai_options(false)
		box.add_child(_labeled_option("AI", ai_opts[0], ai_opts[1], String(ev.get("ai", "")),
			func(k: String) -> void: ev["ai"] = k))
	var label := LineEdit.new()
	label.text = String(ev.get("label", ""))
	label.placeholder_text = "翻訳キー（空＝予告を出さない）"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_changed.connect(func(t: String) -> void:
		if t.strip_edges().is_empty():
			ev.erase("label")  # 空の label キーは書き出さない
		else:
			ev["label"] = t)
	box.add_child(_labeled_row("予告", label))
	# 訳文（ja・en）。開いたとき＝未保存の入力→dialogue.csv の順で埋める。書き込みはステージ保存時。
	var texts := _i18n_texts(String(ev.get("label", "")))
	var tr_ja := LineEdit.new()
	tr_ja.text = String(texts.get("ja", ""))
	tr_ja.placeholder_text = "日本語"
	tr_ja.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_ja.text_changed.connect(func(t: String) -> void: _stash_i18n(label.text, "ja", t))
	box.add_child(_labeled_row("訳 ja", tr_ja))
	var tr_en := LineEdit.new()
	tr_en.text = String(texts.get("en", ""))
	tr_en.placeholder_text = "English"
	tr_en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_en.text_changed.connect(func(t: String) -> void: _stash_i18n(label.text, "en", t))
	box.add_child(_labeled_row("訳 en", tr_en))
	_add_note(box, "予告は右パネル下の板に出る。訳文の {n} に残りターン数が入る。\n"
		+ "訳はステージ保存時に dialogue.csv へ書き込む（ja・en が揃うまで書かない・要 再インポート）。")
	_add_event_unit_rows(box, index, ev, units)


## 増援の駒（1行1体＝駒の種類・座標・× ／ 輸送なら同乗もぶら下げる）。
func _add_event_unit_rows(parent: VBoxContainer, index: int, ev: Dictionary, units: Array) -> void:
	var by_skin := String(ev.get("team", "player")) == "enemy"
	var keys := _unit_pick_keys(by_skin)
	var displays := _unit_pick_displays(by_skin)
	if keys.is_empty():
		return
	var cols := int(_doc.data.get("cols", 12))
	var rows := int(_doc.data.get("rows", 8))
	_add_info(parent, "駒（units） %d体" % units.size())
	for i in units.size():
		var u: Dictionary = units[i]
		var row := _labeled_option("", keys, displays, String(u.get("skin", u.get("type", ""))),
			func(k: String) -> void:
				u.erase("skin")
				u.erase("type")
				u["skin" if by_skin else "type"] = k
				_refresh_events())
		parent.add_child(row)
		_add_button(row, "×", func() -> void:
			if i >= units.size():
				return  # 貼り直し待ちの古い行（queue_free は次のフレーム）
			units.remove_at(i)
			_refresh_events())
		# 座標は別行。同じ行に足すと駒のドロップダウンが潰れて種類が読めなくなる。
		var pos := HBoxContainer.new()
		parent.add_child(pos)
		var col_spin := _make_spin(0, cols - 1, int(u.get("col", 0)))
		col_spin.value_changed.connect(func(v: float) -> void: u["col"] = int(v))
		pos.add_child(_labeled_row("col", col_spin))
		var row_spin := _make_spin(0, rows - 1, int(u.get("row", 0)))
		row_spin.value_changed.connect(func(v: float) -> void: u["row"] = int(v))
		pos.add_child(_labeled_row("row", row_spin))
		_add_passenger_rows(_indent(parent), u, by_skin, _refresh_events)
	_add_button(parent, "駒を追加", func() -> void:
		units.append({ ("skin" if by_skin else "type"): String(keys[0]), "col": 0, "row": 0 })
		ev["units"] = units
		_refresh_events())


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
	_add_button(box, "対象を追加", func() -> void:
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
	_add_button(box, "対象を追加", func() -> void:
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


## 拠点を指す対象の行。盤にある拠点から選ぶ＝拠点でないマスは選びようがない
## （座標を2つ手で入れる形だと、片方を変えた途中の座標で弾かれて移せなくなる）。
## 指す先の拠点が消えているときだけ、その座標を選択肢の末尾に残す＝黙って別の拠点にすり替えない。
func _add_base_target_row(parent: Control, t: Dictionary, on_remove: Callable) -> void:
	var keys := []
	var displays := []
	for b in _doc.data.get("bases", []):
		var col := int(b.get("col", 0))
		var r := int(b.get("row", 0))
		keys.append(_base_target_key(col, r))
		displays.append("(%d, %d) %s / %s" % [col, r,
			String(TEAM_LABELS.get(String(b.get("team", "neutral")), b.get("team", "?"))),
			String(KIND_LABELS.get(String(b.get("kind", "fort")), b.get("kind", "?")))])
	var cur_col := int(t.get("col", -1))
	var cur_row := int(t.get("row", -1))
	var cur_key := _base_target_key(cur_col, cur_row)
	if not keys.has(cur_key):
		keys.append(cur_key)
		displays.append("(%d, %d) 拠点なし" % [cur_col, cur_row])
	var row := _labeled_option("拠点", keys, displays, cur_key, func(key: String) -> void:
		var picked := key.split(",")
		t["col"] = int(picked[0])
		t["row"] = int(picked[1])
		_say("防衛対象を (%s, %s) にしました。" % [picked[0], picked[1]])
		_refresh_defeat())  # 選び直しで「拠点なし」の項目と警告が消える
	if on_remove.is_valid():
		_add_button(row, "×", on_remove)
	parent.add_child(row)


func _base_target_key(col: int, row: int) -> String:
	return "%d,%d" % [col, row]


## 「条件を追加」の行（種類を選んで ＋）。
func _add_kind_adder(parent: Control, kinds: Dictionary, on_add: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_label(row, "条件を追加")
	var ob := _make_option()
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
	_path_label.text = _path if _path != "" else "（未保存の新規ステージ）"
	_path_label.tooltip_text = _path_label.text
	if _name_edit == null or not is_instance_valid(_name_edit):
		return  # 「ステージ」モード以外では入力欄が無い（作り直すときに読み直す）
	_name_edit.text = String(_doc.data.get("name", ""))
	_turn_spin.set_value_no_signal(maxf(int(_doc.data.get("turn_limit", 30)), 1))
	_cols_spin.set_value_no_signal(_doc.cols())
	_rows_spin.set_value_no_signal(_doc.rows())
	_margin_spin.set_value_no_signal(_doc.margin())


func _on_resize() -> void:
	_doc.set_margin(int(_margin_spin.value))  # 外周を先に決める（resize が同じグリッドを整えるため）
	var dropped := _doc.resize(int(_cols_spin.value), int(_rows_spin.value))
	_deselect_base()  # 縮小で選んでいた拠点・駒が消えることがある（下段は案内に戻す）
	_deselect_unit()
	_board.refresh()
	_say("サイズを %d×%d（外周 %d）にしました。" % [_doc.cols(), _doc.rows(), _doc.margin()]
		+ ("範囲外の駒/拠点/スキン指定を %d 件削除しました。" % dropped if dropped > 0 else ""))


## 盤の中身をまとめてずらす。外へ出る中身があるときは何もせず、何が邪魔かを伝える。
func _on_shift(delta: Vector2i) -> void:
	var lost := _doc.shift_losses(delta.x, delta.y)
	if not lost.is_empty():
		var parts := []
		for key in SHIFT_LOSS_LABELS:
			if lost.has(key):
				parts.append("%s %d 件" % [SHIFT_LOSS_LABELS[key], int(lost[key])])
		_say("ずらせません。盤の外に出る %s があります。先に盤を広げてください。" % "／".join(parts))
		return
	_doc.shift(delta.x, delta.y)
	_deselect_base()  # 選んでいた拠点・駒は別のマスへ動いた（下段は案内に戻す）
	_deselect_unit()
	_board.refresh()
	_say("全体を%sずらしました。" % _shift_label(delta))


## ずらした向きの言い方（案内文用）。左右か上下のどちらか一方だけが 0 でない前提。
func _shift_label(delta: Vector2i) -> String:
	if delta.x != 0:
		return "右へ %d 列" % delta.x if delta.x > 0 else "左へ %d 列" % -delta.x
	return "下へ %d 行" % delta.y if delta.y > 0 else "上へ %d 行" % -delta.y


## 盤の番号帯の高さ入力欄で確定（→ MapEditorBoard.height_edited）。見た目だけの値なので
## 地形の取り消し（Ctrl+Z）の対象にはしない＝もう一度クリックして打ち直す。
func _on_height_edited(axis: String, index: int, value: float) -> void:
	if axis == "col":
		_doc.set_col_height(index, value)
	else:
		_doc.set_row_height(index, value)
	_board.refresh()
	_say("%s %d の基準高さを %s にしました（見た目だけ・ルールに入らない）。"
		% ["列" if axis == "col" else "行", index, MapEditorBoard._fmt_height(value)])


## 「実機で確認」＝編集中の内容を一時ファイルへ書き、ゲーム本体を別プロセスで起動して読ませる。
## 保存済みファイルには触らない。起動の中身は preview_launch.gd（shot スクリプトと同じ流儀）。
func _on_preview() -> void:
	var tmp := "user://map_editor_preview.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_say("一時ファイルを書けませんでした: " + tmp)
		return
	f.store_string(_doc.to_text())
	f.close()
	var pid := OS.create_process(OS.get_executable_path(), [
		"--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tools/map_editor/preview_launch.gd",
		"--", ProjectSettings.globalize_path(tmp)])
	if pid == -1:
		_say("実機の起動に失敗しました。")
	else:
		_say("実機を別ウィンドウで起動しました（いまの編集内容のコピーを読ませています）。")


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
	var i18n_msg := _save_i18n()
	_sync_fields()
	_say("保存しました: " + path + i18n_msg)


## 予告・部隊名の訳文の現在値（未保存の入力を優先し、無ければ dialogue.csv。どちらも無ければ空）。
func _i18n_texts(key: String) -> Dictionary:
	if key != "" and _i18n_pending.has(key):
		return _i18n_pending[key]
	if key != "" and _i18n_csv.has(key):
		return _i18n_csv[key]
	return {}


## 訳文の入力を保存待ちに積む。書き込みはステージ保存時（_save_event_i18n）。
func _stash_i18n(key: String, lang: String, text: String) -> void:
	key = key.strip_edges()
	if key == "":
		return
	if not _i18n_pending.has(key):
		var cur := _i18n_texts(key)
		_i18n_pending[key] = { "ja": String(cur.get("ja", "")), "en": String(cur.get("en", "")) }
	_i18n_pending[key][lang] = text


## イベント予告・部隊名の訳文を dialogue.csv へ書く。結果をステータス用のメッセージ断片で返す。
## ja・en の両方が入っているときだけ書く（片方だけの中途半端な行を CSV に作らない）。
## 書くのは「いまステージが使っているキー」だけ＝消したイベント・部隊の入力痕は書かない。
func _save_i18n() -> String:
	var used: Array = []  # [ [呼び名, キー], … ]（警告文でどの欄かを示す）
	for raw in _doc.event_list():
		if typeof(raw) == TYPE_DICTIONARY:
			used.append(["予告", String((raw as Dictionary).get("label", ""))])
	for raw in _doc.data.get("enemy", []):
		if typeof(raw) == TYPE_DICTIONARY:
			used.append(["部隊名", String((raw as Dictionary).get("name", ""))])
	var wrote := 0
	var warn: Array[String] = []
	for pair in used:
		var what := String(pair[0])
		var key := String(pair[1]).strip_edges()
		if key == "":
			continue
		var p: Dictionary = _i18n_pending.get(key, {})
		if p.is_empty():
			if not _i18n_csv.has(key):
				warn.append("%s '%s' の訳文が未登録" % [what, key])
			continue
		var ja := String(p.get("ja", ""))
		var en := String(p.get("en", ""))
		if ja.strip_edges() == "" or en.strip_edges() == "":
			warn.append("%s '%s' は ja・en が揃うまで書き込まない" % [what, key])
			continue
		if DialogueCsvStore.upsert_file(key, ja, en):
			_i18n_csv[key] = { "ja": ja, "en": en }
			_i18n_pending.erase(key)
			wrote += 1
		else:
			warn.append("dialogue.csv を書けなかった")
	var msg := ""
	if wrote > 0:
		msg += " ／ dialogue.csv を更新（%d件）＝再インポートが必要" % wrote
	if not warn.is_empty():
		msg += " ／ " + "・".join(warn)
	return msg
