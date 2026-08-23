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
		for tab in ["summary", "attacker", "defender"]:
			_shots.append([loc, tab, "report_%s_%s.png" % [loc, tab]])

func _detail() -> Dictionary:
	# 数字は手組み（式の検算はテストの仕事＝ここは文言と幅だけ見る）。
	var atk_fwd := Combat.attack_breakdown_from(12, 14, 1.02, 1.0, 0.9, 12.0, 1.3, 0.0)
	var def_fwd := Combat.defense_breakdown_from(10, 9, 1.01, 0.68, 1.2, 8.0, 0.5, 1.0, 80.0)
	var atk_ret := Combat.attack_breakdown_from(10, 11, 1.01, 0.68, 1.2, 0.0, 1.0, 80.0)
	var def_ret := Combat.defense_breakdown_from(12, 8, 1.02, 1.0, 0.9, 0.0, 0.0, 1.3, 0.0)
	var ap := pow(float(atk_fwd["total"]), 2.0)
	var dp := pow(float(def_fwd["total"]), 2.0)
	var frac := ap / (ap + dp)
	var loss := clampi(int(round(10.0 * frac)), 0, 10)
	var ap2 := pow(float(atk_ret["total"]), 2.0)
	var dp2 := pow(float(def_ret["total"]), 2.0)
	var frac2 := ap2 / (ap2 + dp2)
	var loss2 := clampi(int(round(12.0 * frac2)), 0, 12)
	return {
		"attacker": {
			"id": 1, "type_id": "Holy Knight", "skin_id": "", "team": 0, "level": 3,
			"troops_before": 12, "troops_after": 12 - loss2, "max": 12, "terrain": "forest", "pos": Vector2i(0, 0),
			"statuses": [{"name": "Holy Aria", "op": "mul", "value": 1.3, "target": "both"}],
		},
		"defender": {
			"id": 2, "type_id": "Skeleton Warrior", "skin_id": "", "team": 1, "level": 2,
			"troops_before": 10, "troops_after": 10 - loss, "max": 10, "terrain": "plateau", "pos": Vector2i(1, 0),
			"statuses": [
				{"name": "Pixie Dust", "op": "add", "value": 80.0, "target": "both"},
				{"name": "Serpent Fang", "op": "dot", "value": 1},
			],
		},
		"to_defender": {"attack": atk_fwd, "defense": def_fwd, "fraction": frac, "loss": loss},
		"to_attacker": {"attack": atk_ret, "defense": def_ret, "fraction": frac2, "loss": loss2},
		"melee": true,
	}

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
