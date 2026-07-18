extends Control
class_name ImageCheckTool
## 画像確認ツール（開発用・ゲーム本体非依存）。複数画像を並べて見比べる。
## - キャラクターモード: 陣営タブ×役割カテゴリでユニットをチェック選択し、選んだ分を横一列に
##   同じ高さ・足元下揃えで並べる。ドラッグできる水平線を置いて頭身を比較する。
## - 地形モード: 実ヘックス盤に合成地形を敷いて、境界（別地形の継ぎ目）と変種（同一地形の反復）を見る。
## 実行: godot --path . res://tools/image_check/image_check.tscn（エディタで開いて再生でも可）。

const UNITS_DIR := "res://assets/units"
const SRC_ROOT := "res://assets/units-src"
const TERRAIN_DIR := "res://assets/terrain"
const SKIN_CSV := "res://data/units/unit_skin.csv"
const TYPE_CSV := "res://data/units/unit_type.csv"
const PIC_H := 300.0        # 立ち絵の表示高さ（全ユニット共通＝頭身比較の基準）
const LABEL_H := 22.0
const BG := Color(0.20, 0.22, 0.25)
const CAT_ORDER := ["歩兵", "占領兵", "弓兵", "魔法兵", "斥候", "飛行兵", "精鋭", "輸送", "兵器"]

var _mode := "character"
var _img_kind := "map"       # 表示する画像（map / combat）
var _units := {}             # id -> {id, faction, category, name, map, combat}
var _order := []             # 表示順（faction→category→id）
var _factions := []          # 出現 faction（player 先頭）
var _side := {}              # skin_id -> ally/enemy
var _skin_type := {}         # skin_id -> type_id
var _skin_name := {}         # skin_id -> 表示名
var _type_cat := {}          # type_id -> 役割カテゴリ（兵種）
var _selected := {}          # id -> bool（チェック状態）

var _terrains := []
var _terr_pattern := "fill"  # fill(塗りつぶし)/horizontal/vertical/diagonal/island
var _ta := "plain"           # 分割の A（塗りつぶしの単一地形もこれ）
var _tb := "forest"          # 分割の B
var _tc := "mountain"        # 分割の C

var _toolbar: HBoxContainer
var _ctrlbar: HBoxContainer
var _char_box: HBoxContainer
var _sel_tabs: TabContainer
var _disp: Control
var _units_row: HBoxContainer
var _rulers: Array = []
var _board_box: SubViewportContainer
var _board_vp: SubViewport
var _board: Node = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_load_csvs()
	_scan_units()
	_scan_terrains()
	_build_chrome()
	_show_character()

# --- データ収集 ---

func _load_csvs() -> void:
	_read_csv(SKIN_CSV, func(c):
		if c.size() >= 5:
			_side[c[0]] = c[2]
			_skin_type[c[0]] = c[3]
			_skin_name[c[0]] = c[1])
	_read_csv(TYPE_CSV, func(c):
		if c.size() >= 13:
			_type_cat[c[0]] = c[12])

func _read_csv(path: String, on_row: Callable) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var n := 0
	while not f.eof_reached():
		var c := f.get_csv_line()
		n += 1
		if n <= 2 or c.size() < 1 or c[0].is_empty():  # 1=英語ヘッダ / 2=日本語ヘッダ
			continue
		on_row.call(c)

func _scan_units() -> void:
	var groups := _src_groups()
	var d := DirAccess.open(UNITS_DIR)
	if d == null:
		return
	var facs := {}
	for id in d.get_directories():
		var m := _resolve_image(id, "", groups)
		var c := _resolve_image(id, "_combat", groups)
		if m == "" and c == "":
			continue
		var faction := _faction_of(id, groups)
		var cat := String(_type_cat.get(_skin_type.get(id, ""), "その他"))
		_units[id] = { "id": id, "faction": faction, "category": cat,
			"name": String(_skin_name.get(id, id)), "map": m, "combat": c }
		facs[faction] = true
	_factions = facs.keys()
	_factions.sort()
	if _factions.has("player"):
		_factions.erase("player")
		_factions.push_front("player")
	# 表示順: faction（player先頭）→カテゴリ順→id
	_order = _units.keys()
	_order.sort_custom(func(a, b):
		var ua = _units[a]
		var ub = _units[b]
		var fa := _factions.find(ua["faction"])
		var fb := _factions.find(ub["faction"])
		if fa != fb:
			return fa < fb
		var ca := _cat_rank(ua["category"])
		var cb := _cat_rank(ub["category"])
		if ca != cb:
			return ca < cb
		return a < b)

func _cat_rank(cat: String) -> int:
	var i := CAT_ORDER.find(cat)
	return i if i >= 0 else CAT_ORDER.size()

func _src_groups() -> Array:
	var d := DirAccess.open(SRC_ROOT)
	return d.get_directories() if d != null else []

func _faction_of(id: String, groups: Array) -> String:
	for g in groups:
		if DirAccess.dir_exists_absolute("%s/%s/%s" % [SRC_ROOT, g, id]):
			return g
	var side := String(_side.get(id, "other"))
	return "player" if side == "ally" else side

func _resolve_image(id: String, kind: String, groups: Array) -> String:
	for g in groups:
		var p := "%s/%s/%s/%s%s_03_master.png" % [SRC_ROOT, g, id, id, kind]
		if ResourceLoader.exists(p):
			return p
	var game := "%s/%s/%s%s.png" % [UNITS_DIR, id, id, ("_map" if kind == "" else "_combat")]
	return game if ResourceLoader.exists(game) else ""

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
	if not _terrains.is_empty():  # A/B/C の初期値（無ければ在るもので埋める）
		_ta = _default_terr("plain", 0)
		_tb = _default_terr("forest", 1)
		_tc = _default_terr("mountain", 2)

func _default_terr(want: String, idx: int) -> String:
	if _terrains.has(want):
		return want
	return String(_terrains[min(idx, _terrains.size() - 1)])

# --- UI 骨組み ---

func _build_chrome() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_toolbar = HBoxContainer.new()
	root.add_child(_toolbar)
	_add_button(_toolbar, "キャラクター", func(): _show_character())
	_add_button(_toolbar, "地形", func(): _show_terrain())

	_ctrlbar = HBoxContainer.new()
	_ctrlbar.add_theme_constant_override("separation", 6)
	root.add_child(_ctrlbar)

	# キャラ: 左=選択タブ / 右=表示エリア
	_char_box = HBoxContainer.new()
	_char_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_box.add_theme_constant_override("separation", 8)
	root.add_child(_char_box)
	_sel_tabs = TabContainer.new()
	_sel_tabs.custom_minimum_size = Vector2(300, 0)
	_sel_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_box.add_child(_sel_tabs)
	_disp = Control.new()
	_disp.clip_contents = true
	_disp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_disp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_box.add_child(_disp)
	var scroll := ScrollContainer.new()  # 横スクロール（縦は出さない）。下端に固定＝足元を揃える
	scroll.anchor_left = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_top = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 0
	scroll.offset_right = 0
	scroll.offset_top = -(PIC_H + LABEL_H + 20)
	scroll.offset_bottom = 0
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_disp.add_child(scroll)
	_units_row = HBoxContainer.new()
	_units_row.add_theme_constant_override("separation", 12)
	scroll.add_child(_units_row)

	# 地形: SubViewport
	_board_box = SubViewportContainer.new()
	_board_box.stretch = true
	_board_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_board_box)
	_board_vp = SubViewport.new()
	_board_vp.handle_input_locally = false
	_board_box.add_child(_board_vp)
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
	_char_box.show()
	_build_char_ctrlbar()
	_build_sel_tabs()
	_rebuild_display()

func _build_char_ctrlbar() -> void:
	_clear(_ctrlbar)
	_add_button(_ctrlbar, "map", func(): _set_kind("map"))
	_add_button(_ctrlbar, "combat", func(): _set_kind("combat"))
	var sep := VSeparator.new()
	_ctrlbar.add_child(sep)
	_add_button(_ctrlbar, "水平線を追加", func(): _add_ruler(_disp.size.y * 0.45))
	_add_button(_ctrlbar, "線を消す", func(): _clear_rulers())
	_add_button(_ctrlbar, "選択解除", func(): _clear_selection())

func _set_kind(k: String) -> void:
	_img_kind = k
	_rebuild_display()

## 選択タブ: 陣営ごとにタブ、中身は役割カテゴリ見出し＋チェックボックス。
func _build_sel_tabs() -> void:
	_clear(_sel_tabs)
	for fac in _factions:
		var scroll := ScrollContainer.new()
		scroll.name = fac
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(vb)
		var cur_cat := ""
		for id in _order:
			var u = _units[id]
			if u["faction"] != fac:
				continue
			if u["category"] != cur_cat:
				cur_cat = u["category"]
				var head := Label.new()
				head.text = "― %s ―" % cur_cat
				head.modulate = Color(0.7, 0.85, 1.0)
				vb.add_child(head)
			var cb := CheckBox.new()
			cb.text = "%s (%s)" % [u["name"], id]
			cb.button_pressed = _selected.get(id, false)
			cb.toggled.connect(func(on): _selected[id] = on; _rebuild_display())
			vb.add_child(cb)
		_sel_tabs.add_child(scroll)
		_sel_tabs.set_tab_title(_sel_tabs.get_tab_count() - 1, fac)

func _clear_selection() -> void:
	_selected.clear()
	_build_sel_tabs()
	_rebuild_display()

## 選択されたユニットを横一列に（同高・足元下揃え）。並べ替えは _order 準拠。
func _rebuild_display() -> void:
	_clear(_units_row)
	for id in _order:
		if not _selected.get(id, false):
			continue
		_units_row.add_child(_unit_column(_units[id]))

func _unit_column(u: Dictionary) -> Control:
	var col := VBoxContainer.new()  # ラベル＋立ち絵。バンドは表示エリア下端に固定＝足元が揃う。
	var lbl := Label.new()
	lbl.text = u["id"]
	lbl.custom_minimum_size = Vector2(0, LABEL_H)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(lbl)
	col.add_child(_pic(String(u[_img_kind])))
	return col

func _pic(path: String) -> Control:
	if path == "" or not ResourceLoader.exists(path):
		var ph := Label.new()
		ph.text = "—（%s なし）" % _img_kind
		ph.custom_minimum_size = Vector2(PIC_H * 0.6, PIC_H)
		ph.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.modulate = Color(1, 1, 1, 0.35)
		return ph
	var tex := load(path) as Texture2D
	var ts := tex.get_size()
	var w: float = PIC_H * (ts.x / ts.y) if ts.y > 0 else PIC_H
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(w, PIC_H)
	tr.tooltip_text = path
	return tr

# --- 頭身比較の水平線（ドラッグで上下）---

func _add_ruler(y: float) -> void:
	var ln := Control.new()  # アンカーは付けず手動サイズ（幅=表示エリア幅）＝設定時の警告を避ける
	ln.size = Vector2(_disp.size.x, 14)
	ln.position = Vector2(0, clampf(y, 0, _disp.size.y))
	ln.mouse_filter = Control.MOUSE_FILTER_STOP
	ln.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	var bar := ColorRect.new()
	bar.color = Color(1.0, 0.35, 0.35, 0.9)
	bar.anchor_right = 1.0
	bar.offset_top = 6
	bar.offset_bottom = 8
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ln.add_child(bar)
	var knob := ColorRect.new()  # 左端のつまみ
	knob.color = Color(1.0, 0.35, 0.35, 1.0)
	knob.size = Vector2(14, 14)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ln.add_child(knob)
	ln.gui_input.connect(func(e):
		if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			ln.position.y = clampf(ln.position.y + e.relative.y, 0, _disp.size.y - 14))
	_disp.add_child(ln)
	_rulers.append(ln)

func _clear_rulers() -> void:
	for ln in _rulers:
		if is_instance_valid(ln):
			ln.queue_free()
	_rulers.clear()

# --- 地形モード（実ヘックス盤）---

func _show_terrain() -> void:
	_mode = "terrain"
	_char_box.hide()
	_board_box.show()
	_build_terrain_ctrlbar()
	_rebuild_terrain()

func _build_terrain_ctrlbar() -> void:
	_clear(_ctrlbar)
	_add_button(_ctrlbar, "塗りつぶし", func(): _set_pattern("fill"))
	_add_button(_ctrlbar, "水平分割", func(): _set_pattern("horizontal"))
	_add_button(_ctrlbar, "垂直分割", func(): _set_pattern("vertical"))
	_add_button(_ctrlbar, "斜め分割", func(): _set_pattern("diagonal"))
	_add_button(_ctrlbar, "アイランド", func(): _set_pattern("island"))
	_ctrlbar.add_child(VSeparator.new())
	if _terr_pattern == "fill":
		_ctrlbar.add_child(_terrain_picker("地形", _ta, func(t): _ta = t; _rebuild_terrain()))
	else:  # 分割系は3地形（A=1つ目/B/C の順に敷く）
		_ctrlbar.add_child(_terrain_picker("A", _ta, func(t): _ta = t; _rebuild_terrain()))
		_ctrlbar.add_child(_terrain_picker("B", _tb, func(t): _tb = t; _rebuild_terrain()))
		_ctrlbar.add_child(_terrain_picker("C", _tc, func(t): _tc = t; _rebuild_terrain()))

func _set_pattern(p: String) -> void:
	_terr_pattern = p
	_build_terrain_ctrlbar()
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

func _rebuild_terrain() -> void:
	_clear(_board_vp)
	var cols := 9
	var rows := 7
	var state := BattleState.new(cols, rows)
	for col in cols:
		for row in rows:
			state.set_terrain(Hex.offset_to_axial(col, row), _terrain_for(col, row, cols, rows))
	var ctrl := MatchController.new()
	ctrl.name = "MC"
	ctrl.setup(state)
	ctrl.ai_team = 1
	_board_vp.add_child(ctrl)
	var board: HexBoard3D = preload("res://presentation/board/hex_board_3d.gd").new()
	_board_vp.add_child(board)
	board.bind(state, ctrl, {}, {})
	_board = board

## 各 hex の terrain_id をパターンで決める。分割系は A/B/C を3帯に敷く。
func _terrain_for(col: int, row: int, cols: int, rows: int) -> String:
	match _terr_pattern:
		"vertical":
			return _band3(col, cols)          # 縦3列
		"horizontal":
			return _band3(row, rows)          # 横3帯
		"diagonal":
			return _band3(col + row, cols + rows - 1)  # 斜め3帯
		"island":                             # 同心円: 中心=C, 中間=B, 外=A
			var dx := absf(col - (cols - 1) / 2.0) / (cols / 2.0)
			var dy := absf(row - (rows - 1) / 2.0) / (rows / 2.0)
			var r := maxf(dx, dy)
			return _tc if r < 0.34 else (_tb if r < 0.67 else _ta)
		_:
			return _ta                        # fill（塗りつぶし）

func _band3(v: int, span: int) -> String:
	var b := clampi(int(float(v) * 3.0 / float(max(span, 1))), 0, 2)
	return [_ta, _tb, _tc][b]

# --- テスト補助（ハーネスから選択を指定する）---
func preselect(ids: Array) -> void:
	for id in ids:
		_selected[id] = true
	_build_sel_tabs()
	_rebuild_display()
