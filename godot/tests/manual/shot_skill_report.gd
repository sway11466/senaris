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

func _snap(id: int, type_id: String, team: int, level: int, troops: int, max_troops: int) -> Dictionary:
	return {
		"id": id, "type_id": type_id, "skin_id": "", "team": team, "level": level,
		"troops_before": troops, "troops_after": troops, "max": max_troops,
		"terrain": "plain", "pos": Vector2i(0, 0), "statuses": [],
	}

func _hit(v_troops: int, v_def: int) -> Dictionary:
	# 数字は手組み（式の検算はテストの仕事＝ここは文言と幅だけ見る）。
	var atk := Combat.attack_breakdown_from(6, 40, 1.02, 1.0, 0.9, 0.0, 1.3, 0.0)
	var df := Combat.defense_breakdown_from(v_troops, v_def, 1.01, 0.68, 1.2, 0.0, 0.5, 1.0, 0.0)
	return Combat.hit_from_breakdowns(atk, df, v_troops)

func _nova() -> Dictionary:
	var caster := _snap(1, "Wizard", 0, 2, 6, 8)
	var h1 := _hit(8, 20)
	var v1 := _snap(9, "Goblin Grunt", 1, 1, 8, 8)
	v1["troops_after"] = 8 - int(h1["loss"])
	var h2 := _hit(3, 8)
	var v2 := _snap(10, "Goblin Archer", 1, 1, 3, 8)
	v2["troops_after"] = maxi(3 - int(h2["loss"]), 0)
	return {
		"recipe": "trinity_nova",
		"results": [
			{"target_id": 9, "hex": Vector2i(4, 3), "loss": int(h1["loss"]), "killed": false, "detail": h1, "victim": v1},
			{"target_id": 10, "hex": Vector2i(5, 3), "loss": 3, "killed": true, "detail": h2, "victim": v2},
		],
		"center": Vector2i(4, 3), "cells": [], "leader_id": 1,
		"caster": caster,
	}

func _grace() -> Dictionary:
	return {
		"recipe": "grace", "results": [], "center": Vector2i(0, 0), "cells": [], "leader_id": 1,
		"caster": _snap(1, "Cleric", 0, 3, 5, 8),
		"status": {"scope": "team", "team": 0, "op": "mul", "target": "both", "value": 1.3,
			"remaining": 1, "name": "グレイス", "kind": "buff"},
	}

func _pixie() -> Dictionary:
	var target := _snap(5, "Holy Knight", 0, 3, 7, 8)
	return {
		"recipe": "pixie_dust", "results": [], "center": Vector2i(0, 0), "cells": [], "leader_id": 2,
		"caster": _snap(2, "Pixie", 0, 1, 8, 8),
		"status": {"scope": "unit", "unit_id": 5, "op": "add", "target": "both", "value": 80.0,
			"remaining": 3, "name": "ピクシーダスト", "kind": "buff"},
		"skill": {"recipe": "pixie_dust", "caster": _snap(2, "Pixie", 0, 1, 8, 8), "target": target},
	}

func _empty() -> Dictionary:
	return {
		"recipe": "trinity_nova", "results": [], "center": Vector2i(4, 3), "cells": [], "leader_id": 1,
		"caster": _snap(1, "Wizard", 0, 2, 6, 8),
	}

func _result_of(key: String) -> Dictionary:
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
