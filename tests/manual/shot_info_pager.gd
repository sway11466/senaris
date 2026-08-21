extends SceneTree
## 使い捨て：情報パネルのページャーを撮る（空きマス・拠点・ユニットの地形タブ・控えの多い拠点）。
## 実行: godot --path . -s res://tests/manual/shot_info_pager.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const STAGE := "res://data/stages/debug-mapops/base.json"
const BIG_STAGE := "res://data/stages/tutorial2-undead-rush/st4.json"  # 控え24件の拠点がある
const PLAIN_HEX := Vector2i(6, 1)
const BASE_HEX := Vector2i(4, 5)   # 中立拠点＝控え2体

var _main: Node
var _dir := ""
var _frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_main._title.close()
		_main._select.close()
		_main.load_stage(STAGE)
	if _frames == 35:
		_skip_talk()
	if _frames == 50:
		_panel().show_terrain(Hex.offset_to_axial(PLAIN_HEX.x, PLAIN_HEX.y))
	if _frames == 55:
		_save("pager_plain")
		_panel().show_terrain(Hex.offset_to_axial(BASE_HEX.x, BASE_HEX.y))
	if _frames == 60:
		_save("pager_base")
		_show_unit_on_base()
	if _frames == 65:
		_save("pager_tab_p1")
		_dump("p1 直後")
		_panel()._turn_page(1)
		_dump("送った直後")
	if _frames == 70:
		_save("pager_tab_p2")
		_main.load_stage(BIG_STAGE)
	if _frames == 85:
		_skip_talk()
	if _frames == 95:
		_panel().show_terrain(_big_base_hex())
	if _frames == 100:
		_save("pager_big_p1")
		_panel()._turn_page(1)
	if _frames == 105:
		_save("pager_big_p2")
		var p := _panel()
		p._tab = "ability"
		p.show_unit(_main._controller.state.units()[0].id)
	if _frames == 110:
		_save("pager_ability")
		_panel().clear()
	if _frames == 115:
		_save("pager_hint")
		_panel().show_terrain(_big_base_hex())
	if _frames == 120:
		_dump("ホイール前")
		_wheel(1)
	if _frames == 122:
		_dump("ホイール後（下）")
		_wheel(-1)
	if _frames == 124:
		_dump("ホイール後（上）")
		return true
	return false

func _skip_talk() -> void:
	if _main._conversation != null:
		_main._conversation._on_skip()

## 控えが最も多い拠点のマス。
func _big_base_hex() -> Vector2i:
	var state = _main._controller.state
	var best: Vector2i = Vector2i.ZERO
	var most := -1
	for b in state.bases():
		if b.garrison.size() > most:
			most = b.garrison.size()
			best = b.hex
	print("控えが最多の拠点: ", best, " 控え=", most)
	return best

## 拠点の上に自軍の駒を立たせて「地形」タブを開く＝行数が最も多くなる組み合わせ。
func _show_unit_on_base() -> void:
	var state = _main._controller.state
	var u = state.units()[0]
	u.pos = Hex.offset_to_axial(BASE_HEX.x, BASE_HEX.y)
	var p := _panel()
	p._tab = "terrain"
	p.show_unit(u.id)

## 板の上でホイールを回す（実際の入力経路を通す＝ハンドラ直呼びでは配線が検証できない）。
func _wheel(dir: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if dir > 0 else MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = UiLayout.RIGHT_BOX.position + UiLayout.RIGHT_BOX.size * 0.5
	root.push_input(ev)

func _dump(tag: String) -> void:
	var p := _panel()
	var head := ""
	if not p._items.is_empty():
		head = str(p._items[0])
	print(tag, " shown_unit=", p._shown_unit, " page=", p._page, "/", p._pages.size(),
		" items=", p._items.size(), " 先頭=", head)

func _panel() -> UnitInfoPanel:
	return _main.get_node("Front/InfoPanel")

func _save(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
