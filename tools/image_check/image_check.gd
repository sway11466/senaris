extends Control
class_name ImageCheckTool
## 画像確認ツール（開発用・ゲーム本体非依存）。複数画像を並べて見比べる。
## - キャラクターモード: 行=ユニット／列=[map|combat]。横で服装(map↔combat)、縦で頭身を比較。
## - 地形モード: 実ヘックス盤に合成地形を敷いて、境界（別地形の継ぎ目）と変種（同一地形の反復）を見る。
## 実行: godot --path . res://tools/image_check/image_check.tscn（エディタで開いて再生でも可）。

const UNITS_DIR := "res://assets/units"
const SRC_ROOT := "res://assets/units-src"
const TERRAIN_DIR := "res://assets/terrain"
const CSV_PATH := "res://data/units/unit_skin.csv"
const ROW_H := 150.0        # 各絵の表示高さ（全ユニット共通＝頭身比較の基準）
const LABEL_W := 130.0      # 行頭のユニット名の幅
const BG := Color(0.20, 0.22, 0.25)

var _mode := "character"
var _filter := "all"
var _units: Array = []       # [{id, faction, map, combat}]（map/combat はパス or ""）
var _side := {}              # skin_id -> "ally"/"enemy"（CSV フォールバック用）
var _filters: Array = []     # 出現した faction 一覧（ボタン生成用）

var _terrains: Array = []    # 基本 terrain_id 一覧
var _terr_sub := "variation" # "variation"（変種）/"boundary"（境界）
var _terr_one := "plain"
var _terr_a := "plain"
var _terr_b := "forest"

var _toolbar: HBoxContainer
var _filterbar: HBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _board_box: SubViewportContainer
var _board_vp: SubViewport
var _board: Node = null  # 現在の HexBoard3D（SubViewport のサイズ確定時に再フィットする）

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_load_side()
	_scan_units()
	_scan_terrains()
	_build_chrome()
	_show_character()

# --- データ収集 ---

func _load_side() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return
	var first := true
	while not f.eof_reached():
		var cols := f.get_csv_line()
		if cols.size() < 3:
			continue
		if first:  # 1行目=英語ヘッダ
			first = false
			continue
		if cols[0] == "スキンID" or cols[0].is_empty():  # 2行目=日本語ヘッダ等
			continue
		_side[cols[0]] = cols[2]

## assets/units/* を走査し、各ユニットの map/combat 画像（tight な -src master 優先）と faction を決める。
func _scan_units() -> void:
	var groups := _src_groups()
	var d := DirAccess.open(UNITS_DIR)
	if d == null:
		return
	var seen := {}
	for id in d.get_directories():
		var faction := _faction_of(id, groups)
		var m := _resolve_image(id, "", groups)         # {id}_03_master → {id}_map.png
		var c := _resolve_image(id, "_combat", groups)  # {id}_combat_03_master → {id}_combat.png
		if m == "" and c == "":
			continue
		_units.append({ "id": id, "faction": faction, "map": m, "combat": c })
		seen[faction] = true
	_units.sort_custom(func(a, b):  # 味方(player)を先頭、その後は faction 名→id 順
		var ra := 0 if a["faction"] == "player" else 1
		var rb := 0 if b["faction"] == "player" else 1
		if ra != rb:
			return ra < rb
		if a["faction"] != b["faction"]:
			return a["faction"] < b["faction"]
		return a["id"] < b["id"])
	_filters = seen.keys()
	_filters.sort()
	if _filters.has("player"):  # 味方フィルタを先頭に
		_filters.erase("player")
		_filters.push_front("player")

func _src_groups() -> Array:
	var d := DirAccess.open(SRC_ROOT)
	return d.get_directories() if d != null else []

func _faction_of(id: String, groups: Array) -> String:
	for g in groups:
		if DirAccess.dir_exists_absolute("%s/%s/%s" % [SRC_ROOT, g, id]):
			return g
	# -src が無ければ CSV の陣営でフォールバック（ally→player 扱い）
	var side := String(_side.get(id, "other"))
	return "player" if side == "ally" else side

## tight な -src master（{id}{kind}_03_master.png）を優先、無ければゲーム用 png。kind="" or "_combat"。
func _resolve_image(id: String, kind: String, groups: Array) -> String:
	for g in groups:
		var p := "%s/%s/%s/%s%s_03_master.png" % [SRC_ROOT, g, id, id, kind]
		if ResourceLoader.exists(p):
			return p
	var game := "%s/%s/%s%s.png" % [UNITS_DIR, id, id, ("_map" if kind == "" else "_combat")]
	return game if ResourceLoader.exists(game) else ""

## assets/terrain/ から基本 terrain_id を集める（末尾 _<数字> の変種は畳む）。
func _scan_terrains() -> void:
	var d := DirAccess.open(TERRAIN_DIR)
	if d == null:
		return
	var seen := {}
	for f in d.get_files():
		if not f.ends_with(".png"):
			continue
		var base := f.trim_suffix(".png")
		var parts := base.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			base = parts[0]
		seen[base] = true
	_terrains = seen.keys()
	_terrains.sort()
	if _terrains.has("plain"):
		_terr_one = "plain"
		_terr_a = "plain"
	if _terrains.has("forest"):
		_terr_b = "forest"

# --- UI 骨組み ---

func _build_chrome() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 8)
	root.add_child(_toolbar)
	_add_button(_toolbar, "キャラクター", func(): _show_character())
	_add_button(_toolbar, "地形", func(): _show_terrain())

	_filterbar = HBoxContainer.new()
	_filterbar.add_theme_constant_override("separation", 6)
	root.add_child(_filterbar)

	# キャラ用スクロール
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	# 地形用 SubViewport（実3D盤・入力は取らず表示専用）
	_board_box = SubViewportContainer.new()
	_board_box.stretch = true
	_board_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_board_box)
	_board_vp = SubViewport.new()
	_board_vp.handle_input_locally = false  # 表示専用（盤入力を拾わない）
	_board_vp.transparent_bg = false
	_board_box.add_child(_board_vp)
	# SubViewport のサイズが確定/変化したら盤を再フィット（表示直後は未確定でフレーミングを外すため）。
	_board_vp.size_changed.connect(func():
		if _board != null and is_instance_valid(_board):
			_board.fit_to_view())
	_board_box.hide()

func _add_button(bar: HBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	bar.add_child(b)
	return b

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

# --- キャラクターモード ---

func _show_character() -> void:
	_mode = "character"
	_board_box.hide()
	_scroll.show()
	_build_char_filterbar()
	_rebuild_character()

func _build_char_filterbar() -> void:
	_clear(_filterbar)
	_add_button(_filterbar, "すべて", func(): _set_filter("all"))
	for fac in _filters:
		var f: String = fac
		_add_button(_filterbar, f, func(): _set_filter(f))

func _set_filter(f: String) -> void:
	_filter = f
	_rebuild_character()

func _rebuild_character() -> void:
	_clear(_body)
	_body.add_child(_row_labels(["ユニット", "map", "combat"]))
	for u in _units:
		if _filter != "all" and u["faction"] != _filter:
			continue
		_body.add_child(_unit_row(u))

func _row_labels(texts: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = texts[0]
	lbl.custom_minimum_size = Vector2(LABEL_W, 0)
	h.add_child(lbl)
	for i in range(1, texts.size()):
		var l := Label.new()
		l.text = texts[i]
		l.custom_minimum_size = Vector2(ROW_H, 0)
		h.add_child(l)
	return h

func _unit_row(u: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size = Vector2(0, ROW_H)
	var name_lbl := Label.new()
	name_lbl.text = "%s\n(%s)" % [u["id"], u["faction"]]
	name_lbl.custom_minimum_size = Vector2(LABEL_W, 0)
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name_lbl)
	h.add_child(_pic(u["map"]))
	h.add_child(_pic(u["combat"]))
	return h

## 画像1枚を高さ ROW_H・アスペクト維持・下揃え（足元ベースライン）で作る。無ければ欠落プレースホルダ。
func _pic(path: String) -> Control:
	if path == "" or not ResourceLoader.exists(path):
		var ph := Label.new()
		ph.text = "—"
		ph.custom_minimum_size = Vector2(ROW_H, ROW_H)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		ph.modulate = Color(1, 1, 1, 0.35)
		return ph
	var tex := load(path) as Texture2D
	var ts := tex.get_size()
	var w: float = ROW_H * (ts.x / ts.y) if ts.y > 0 else ROW_H
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(w, ROW_H)
	tr.size_flags_vertical = Control.SIZE_SHRINK_END  # 下揃え＝足元を揃える
	tr.tooltip_text = path
	return tr

# --- 地形モード（実ヘックス盤） ---

func _show_terrain() -> void:
	_mode = "terrain"
	_scroll.hide()
	_board_box.show()
	_build_terrain_filterbar()
	_rebuild_terrain()

func _build_terrain_filterbar() -> void:
	_clear(_filterbar)
	_add_button(_filterbar, "変種", func(): _set_terr_sub("variation"))
	_add_button(_filterbar, "境界", func(): _set_terr_sub("boundary"))
	if _terr_sub == "variation":
		_filterbar.add_child(_terrain_picker("地形", _terr_one, func(t): _terr_one = t; _rebuild_terrain()))
	else:
		_filterbar.add_child(_terrain_picker("A", _terr_a, func(t): _terr_a = t; _rebuild_terrain()))
		_filterbar.add_child(_terrain_picker("B", _terr_b, func(t): _terr_b = t; _rebuild_terrain()))

func _set_terr_sub(s: String) -> void:
	_terr_sub = s
	_build_terrain_filterbar()
	_rebuild_terrain()

func _terrain_picker(label: String, current: String, on_pick: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label + ":"
	h.add_child(l)
	var opt := OptionButton.new()
	for i in _terrains.size():
		opt.add_item(String(_terrains[i]), i)
		if _terrains[i] == current:
			opt.select(i)
	opt.item_selected.connect(func(idx): on_pick.call(String(_terrains[idx])))
	h.add_child(opt)
	return h

## 合成 BattleState を組んで実3D盤に敷き、SubViewport に描く。呼ぶたびに盤を作り直す。
func _rebuild_terrain() -> void:
	_clear(_board_vp)
	var cols := 9
	var rows := 7
	var state := BattleState.new(cols, rows)
	for col in cols:
		for row in rows:
			state.set_terrain(Hex.offset_to_axial(col, row), _terrain_for(col, cols))
	var ctrl := MatchController.new()
	ctrl.name = "MC"
	ctrl.setup(state)
	ctrl.ai_team = 1
	_board_vp.add_child(ctrl)
	var board: HexBoard3D = preload("res://presentation/board/hex_board_3d.gd").new()
	_board_vp.add_child(board)
	board.bind(state, ctrl, {}, {})  # ユニット無し・地形は既定skin（変種は盤が hex 位置で自動分配）
	_board = board  # size_changed 時の再フィット対象

## 各 hex の terrain_id。変種＝全面1地形／境界＝左半分A・右半分B（縦の継ぎ目）。
func _terrain_for(col: int, cols: int) -> String:
	if _terr_sub == "variation":
		return _terr_one
	return _terr_a if col < cols / 2 else _terr_b
