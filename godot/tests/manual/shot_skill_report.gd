extends SceneTree
## feature-88 検証用（使い捨て）: SkillReportView に合成 result を食わせ、
## ja/en × ページ（サマリー・対象1・対象2／バフ・空撃ち）のスクショを撮る。
## 幅は本番と同じ464px（main.tscn の右パネル幅）。
## 実行: godot --path . -s res://tests/manual/shot_skill_report.gd（--headless 不可）

const OUT_DIR := "res://tests/manual/out"
var _frame := 0
var _view: SkillReportView
var _holder: Control
var _shots: Array = []  # [locale, result名, ページ番号, filename]
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
		_shots.append([loc, "nova", 0, "skill_%s_nova_summary.png" % loc])
		_shots.append([loc, "nova", 1, "skill_%s_nova_target1.png" % loc])
		_shots.append([loc, "nova", 2, "skill_%s_nova_target2.png" % loc])
		_shots.append([loc, "grace", 0, "skill_%s_grace.png" % loc])
		_shots.append([loc, "pixie", 0, "skill_%s_pixie.png" % loc])
		_shots.append([loc, "empty", 0, "skill_%s_empty.png" % loc])

func _snap(id: int, type_id: String, team: int, level: int, troops: int, max_troops: int) -> UnitSnapshot:
	var s := UnitSnapshot.new()
	s.id = id
	s.type_id = type_id
	s.team = team
	s.level = level
	s.troops_before = troops
	s.troops_after = troops
	s.max_troops = max_troops
	s.terrain = "plain"
	return s

func _hit(v_troops: int, v_def: int) -> HitDetail:
	# 数字は手組み（式の検算はテストの仕事＝ここは文言と幅だけ見る）。
	var atk := Combat.attack_breakdown_from(6, 40, 1.02, 1.0, 0.9, 0.0, 1.3, 0.0)
	var df := Combat.defense_breakdown_from(v_troops, v_def, 1.01, 0.68, 1.2, 0.0, 0.5, 1.0, 0.0)
	return Combat.hit_from_breakdowns(atk, df, v_troops)

func _skill_hit(target_id: int, hex: Vector2i, h: HitDetail, victim: UnitSnapshot, killed: bool) -> SkillHit:
	var sh := SkillHit.new()
	sh.target_id = target_id
	sh.hex = hex
	sh.loss = h.loss
	sh.killed = killed
	sh.detail = h
	sh.victim = victim
	return sh

func _base(recipe: String, caster: UnitSnapshot, center: Vector2i, leader_id: int) -> SkillResult:
	var r := SkillResult.new()
	r.recipe = recipe
	r.caster = caster
	r.center = center
	r.leader_id = leader_id
	return r

func _nova() -> SkillResult:
	var r := _base("trinity_nova", _snap(1, "Wizard", 0, 2, 6, 8), Vector2i(4, 3), 1)
	var h1 := _hit(8, 20)
	var v1 := _snap(9, "Goblin Grunt", 1, 1, 8, 8)
	v1.troops_after = 8 - h1.loss
	var h2 := _hit(3, 8)
	var v2 := _snap(10, "Goblin Archer", 1, 1, 3, 8)
	v2.troops_after = maxi(3 - h2.loss, 0)
	r.hits = [_skill_hit(9, Vector2i(4, 3), h1, v1, false), _skill_hit(10, Vector2i(5, 3), h2, v2, true)]
	return r

func _grace() -> SkillResult:
	var r := _base("grace", _snap(1, "Cleric", 0, 3, 5, 8), Vector2i(0, 0), 1)
	r.status = {"scope": "team", "team": 0, "op": "mul", "target": "both", "value": 1.3,
		"remaining": 1, "name": "グレイス", "kind": "buff"}
	return r

func _pixie() -> SkillResult:
	var r := _base("pixie_dust", _snap(2, "Pixie", 0, 1, 8, 8), Vector2i(0, 0), 2)
	r.status = {"scope": "unit", "unit_id": 5, "op": "add", "target": "both", "value": 80.0,
		"remaining": 3, "name": "ピクシーダスト", "kind": "buff"}
	var c := SkillCast.new()
	c.recipe = "pixie_dust"
	c.caster = _snap(2, "Pixie", 0, 1, 8, 8)
	c.target = _snap(5, "Holy Knight", 0, 3, 7, 8)
	r.cast = c
	return r

func _empty() -> SkillResult:
	return _base("trinity_nova", _snap(1, "Wizard", 0, 2, 6, 8), Vector2i(4, 3), 1)

func _result_of(key: String) -> SkillResult:
	match key:
		"nova": return _nova()
		"grace": return _grace()
		"pixie": return _pixie()
	return _empty()

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 4 != 0:  # 数フレームおきに1枚（描画を待つ）
		return false
	if _idx >= 0:
		var shot: Array = _shots[_idx]
		var img := root.get_texture().get_image()
		img.save_png(OUT_DIR.path_join(shot[3]))
	_idx += 1
	if _idx >= _shots.size():
		quit()
		return true
	var next: Array = _shots[_idx]
	TranslationServer.set_locale(next[0])
	if _view != null:
		_view.queue_free()
	_view = SkillReportView.new()
	_holder.add_child(_view)
	_view.bind({})
	_view.show_result(_result_of(next[1]))
	for i in int(next[2]):
		_view.turn_page(1)
	return false
