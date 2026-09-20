extends SceneTree
## 使い捨て：情報板の能力タブ（駒の絵）と地形タブ（地形の見本）の見た目を日英で確かめる。
## 起動: godot --path . -s res://tests/manual/check_info_figure.gd
## 出力: res://tests/manual/out/info_figure_log.txt ＋ info_figure_{stage}_{unit}_{tab}_{locale}.png

const STAGES := [
	["tutorial1-goblin-raid", "goblin-raid-st1", "res://data/stages/tutorial1-goblin-raid/goblin-raid-st1.json"],
	["tutorial2-undead-rush", "undead-rush-st2", "res://data/stages/tutorial2-undead-rush/undead-rush-st2.json"],
	["tutorial3-dragon-hunt", "dragon-hunt-st6", "res://data/stages/tutorial3-dragon-hunt/dragon-hunt-st6.json"],
]

var _main: Node = null
var _frame := 0
var _i := 0
var _phase := 0   # 0=ステージを読む 1=会話を飛ばす 2=撮る
var _at := 15
var _log := ""
var _steps: Array[Callable] = []
var _step_i := 0

func _initialize() -> void:
	var packed: PackedScene = load("res://presentation/main/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < _at:
		return false
	if _i >= STAGES.size():
		var f := FileAccess.open("res://tests/manual/out/info_figure_log.txt", FileAccess.WRITE)
		f.store_string(_log)
		f.close()
		return true
	match _phase:
		0:
			if _main._title != null:
				_main._title.visible = false
			_main._select.visible = false
			var e: Array = STAGES[_i]
			_main._on_stage_chosen(String(e[0]), String(e[1]), String(e[2]))
			_phase = 1
			_at = _frame + 25
		1:
			if _main._conversation != null and _main._conversation.visible:
				_main._conversation._on_skip()
				_at = _frame + 15
				return false
			_plan_steps(String(STAGES[_i][1]))
			_phase = 2
			_at = _frame + 5
		2:
			if _step_i >= _steps.size():
				_i += 1
				_phase = 0
				_at = _frame + 15
				return false
			_steps[_step_i].call()
			_step_i += 1
			_at = _frame + 6
	return false

## 撮る駒：味方の先頭1体と、オブジェクト地形（拠点など）か拠点の上に立つ駒を1体。
func _plan_steps(stage: String) -> void:
	_steps = []
	_step_i = 0
	var st: BattleState = _main._controller.state
	var picks: Array = []
	var first_ally: Unit = null
	var on_object: Unit = null
	for u: Unit in st.units():
		if first_ally == null and u.team == 0:
			first_ally = u
		var terr: String = st.terrain_at(u.pos)
		if on_object == null and (TerrainType.layer(terr) == "object" or st.base_at(u.pos) != null):
			on_object = u
	if first_ally != null:
		picks.append(first_ally)
	if on_object != null and on_object != first_ally:
		picks.append(on_object)
	var panel: UnitInfoPanel = _main.get_node("Front/InfoPanel")
	for loc in ["ja", "en"]:
		_steps.append(func() -> void:
			SettingsApplier.apply_locale(loc)
			_main._refresh_labels())
		for u: Unit in picks:
			for tab in ["ability", "terrain"]:
				_steps.append(func() -> void:
					panel._on_tab_pressed(tab)
					panel.show_unit(u.handle)
					_log += "%s %s h=%d type=%s pos=%s terr=%s tab=%s face_unit=%s face_terr=%s size=%s\n" % [
						stage, loc, u.handle, u.type_id, u.pos, st.terrain_at(u.pos), tab,
						panel._unit_face.visible, panel._terrain_face.visible, panel._unit_face.size])
				_steps.append(func() -> void:
					_shot("%s_%d_%s_%s" % [stage, u.handle, tab, loc]))
	_steps.append(func() -> void:
		SettingsApplier.apply_locale("ja")
		_main._refresh_labels())

func _shot(tag: String) -> void:
	root.get_texture().get_image().save_png("res://tests/manual/out/info_figure_%s.png" % tag)
