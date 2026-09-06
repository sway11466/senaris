extends SceneTree
## bug-5 の検証（使い捨て）。盤の上で言語を切り替えたとき、情報板に出ているものが
## 新しい言語で描き直されるかを、板が持つ行データ（_items）で実測する。

var _main: Node
var _f := 0
var _log: PackedStringArray = []

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_f += 1
	if _f == 10:
		_main._select.close()
		_main.load_stage("res://data/stages/debug-ai/charge.json")
	elif _f == 60:
		_run()
		return true
	return false

func _dump(panel: Node, tag: String) -> void:
	var parts: PackedStringArray = []
	for it in panel._items:
		if String(it.get("t", "")) == "row":
			parts.append("%s=%s" % [it.get("label", ""), it.get("value", "")])
		else:
			var s := String(it.get("text", ""))
			if not s.is_empty():
				parts.append(s)
	_log.append("[%s] %s" % [tag, " | ".join(parts)])

func _case(panel: Node, tag: String, show: Callable) -> void:
	TranslationServer.set_locale("ja")
	show.call()
	_dump(panel, tag + " ja")
	TranslationServer.set_locale("en")
	_main._refresh_labels()
	_dump(panel, tag + " en(切替後)")

func _run() -> void:
	var panel := _main.get_node("Front/InfoPanel")
	var uid := int(panel._state.units()[0].id)
	_case(panel, "案内文", func(): panel.clear())
	_case(panel, "駒", func(): panel.show_unit(uid))
	_case(panel, "地形", func(): panel.show_terrain(Vector2i(3, 3)))
	TranslationServer.set_locale("ja")
	panel.set_event({"label": "dbg.event.goblins", "turns": 3})
	_log.append("[残りターン ja] %s" % panel._event_row.text)
	TranslationServer.set_locale("en")
	_main._refresh_labels()
	_log.append("[残りターン en(切替後)] %s" % panel._event_row.text)
	# 戦闘結果＝サマリーの表と、攻撃タブの内訳の本文
	panel.show_combat(_detail())
	TranslationServer.set_locale("ja")
	panel._report._show_tab("attack")
	_log.append("[戦闘結果 ja] %s" % panel._report._detail_label.text.replace("
", " / "))
	TranslationServer.set_locale("en")
	_main._refresh_labels()
	_log.append("[戦闘結果 en(切替後)] %s" % panel._report._detail_label.text.replace("
", " / "))
	# スキル結果＝サマリーの見出しと本文
	TranslationServer.set_locale("ja")
	var empty_skill := SkillResult.new()
	empty_skill.recipe = "trinity_nova"
	panel.show_skill_report(empty_skill)
	_log.append("[スキル結果 ja] %s" % _skill_text(panel))
	TranslationServer.set_locale("en")
	_main._refresh_labels()
	_log.append("[スキル結果 en(切替後)] %s" % _skill_text(panel))
	var f := FileAccess.open("res://tests/manual/out/info_i18n_refresh.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()

func _skill_text(panel: Node) -> String:
	var parts: PackedStringArray = [panel._skill_report._head.text]
	for c in panel._skill_report._body.get_children():
		if c is Label:
			parts.append(c.text)
	return " | ".join(parts)

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
