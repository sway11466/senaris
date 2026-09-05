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
	panel.show_skill_report({"recipe": "trinity_nova", "caster": {}, "results": []})
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
			"statuses": [{"name": "Grace", "op": "mul", "value": 1.3, "target": "both"}],
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
