extends Control
class_name ImageCheckTool
## 画像確認ツール（開発用・ゲーム本体非依存）。複数画像を並べて見比べる。
## - キャラクターモード: 行=ユニット／列=[map|combat]。横で服装(map↔combat)、縦で頭身を比較。
## - 地形モード: 実ヘックス盤で地形の境界・変種を見る（Phase 2）。
## 実行: godot --path . res://tools/image_check/image_check.tscn（エディタで開いて再生でも可）。
## 仕様相談の経緯はコミット履歴参照。

const UNITS_DIR := "res://assets/units"
const SRC_ROOT := "res://assets/units-src"
const CSV_PATH := "res://data/units/unit_skin.csv"
const ROW_H := 150.0        # 各絵の表示高さ（全ユニット共通＝頭身比較の基準）
const LABEL_W := 130.0      # 行頭のユニット名の幅
const BG := Color(0.20, 0.22, 0.25)

var _mode := "character"
var _filter := "all"
var _units: Array = []       # [{id, faction, map, combat}]（map/combat はパス or ""）
var _side := {}              # skin_id -> "ally"/"enemy"（CSV フォールバック用）
var _filters: Array = []     # 出現した faction 一覧（ボタン生成用）

var _toolbar: HBoxContainer
var _filterbar: HBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_load_side()
	_scan_units()
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

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

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
	_build_filterbar()
	_rebuild_character()

func _build_filterbar() -> void:
	_clear(_filterbar)
	if _mode != "character":
		return
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

# --- 地形モード（Phase 2 で実装） ---

func _show_terrain() -> void:
	_mode = "terrain"
	_clear(_filterbar)
	_clear(_body)
	var l := Label.new()
	l.text = "地形モードは Phase 2 で実装予定"
	_body.add_child(l)
