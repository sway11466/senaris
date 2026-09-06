extends SceneTree
## feature-67 検証用（使い捨て）: CombatReportView に合成 detail を食わせ、
## ja/en × 3タブのスクショを撮る。幅は本番と同じ464px（main.tscn の右パネル幅）。
## 実行: godot --path . -s res://tests/manual/shot_combat_report_i18n.gd（--headless 不可）

const OUT_DIR := "res://tests/manual/out"
var _frame := 0
var _view: CombatReportView
var _holder: Control
var _shots: Array = []  # [locale, tab, filename]
var _idx := -1

func _initialize() -> void:
	var win := root
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.10, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var holder := Control.new()
	holder.position = Vector2(8, 8)
	holder.size = Vector2(464, 620)
	win.add_child(holder)
	_holder = holder
	for loc in ["ja", "en"]:
		for tab in ["summary", "attack", "counter"]:
			_shots.append([loc, tab, "report_%s_%s.png" % [loc, tab]])

func _detail() -> AttackResult:
	# 数字は手組み（式の検算はテストの仕事＝ここは文言と幅だけ見る）。
	var atk_fwd := Combat.attack_breakdown_from(12, 14, 1.02, 1.0, 0.9, 12.0, 1.3, 0.0)
	var def_fwd := Combat.defense_breakdown_from(10, 9, 1.01, 0.68, 1.2, 8.0, 0.5, 1.0, 80.0)
	var atk_ret := Combat.attack_breakdown_from(10, 11, 1.01, 0.68, 1.2, 0.0, 1.0, 80.0)
	var def_ret := Combat.defense_breakdown_from(12, 8, 1.02, 1.0, 0.9, 0.0, 0.0, 1.3, 0.0)
	var fwd := Combat.hit_from_breakdowns(atk_fwd, def_fwd, 10)
	var ret := Combat.hit_from_breakdowns(atk_ret, def_ret, 12)
	var loss := fwd.loss
	var loss2 := ret.loss
	var out := AttackResult.new()
	out.attacker = _snap(1, "Holy Knight", 0, 3, 12, 12 - loss2, 12, "forest", Vector2i(0, 0),
		[{"name": "Grace", "op": "mul", "value": 1.3, "target": "both"}])
	out.defender = _snap(2, "Skeleton Warrior", 1, 2, 10, 10 - loss, 10, "plateau", Vector2i(1, 0), [
		{"name": "Pixie Dust", "op": "add", "value": 80.0, "target": "both"},
		{"name": "Serpent Fang", "op": "dot", "value": 1},
	])
	out.to_defender = fwd
	out.to_attacker = ret
	out.melee = true
	return out

func _snap(id: int, type_id: String, team: int, level: int, before: int, after: int, max_troops: int,
		terrain: String, pos: Vector2i, statuses: Array) -> UnitSnapshot:
	var s := UnitSnapshot.new()
	s.id = id
	s.type_id = type_id
	s.team = team
	s.level = level
	s.troops_before = before
	s.troops_after = after
	s.max_troops = max_troops
	s.terrain = terrain
	s.pos = pos
	s.statuses = statuses
	return s

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 4 != 0:  # 数フレームおきに1枚（描画を待つ）
		return false
	if _idx >= 0:
		var shot: Array = _shots[_idx]
		var img := root.get_texture().get_image()
		img.save_png(OUT_DIR.path_join(shot[2]))
	_idx += 1
	if _idx >= _shots.size():
		quit()
		return true
	var next: Array = _shots[_idx]
	TranslationServer.set_locale(next[0])
	if _view != null:
		_view.queue_free()
	_view = CombatReportView.new()  # タブ文言は _ready で焼き込む＝locale を変えたら作り直す
	_holder.add_child(_view)
	_view.bind({})
	_view.show_report(_detail())
	_view._show_tab(next[1])
	return false
