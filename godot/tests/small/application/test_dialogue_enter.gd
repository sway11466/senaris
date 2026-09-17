extends GutTest
## 会話の途中の登場（intro の enter 行）。行の相手（部隊 name／駒 unit_id）を盤の駒に解決する
## resolve_enter と、生データの整合を並べる enter_problems。仕様 → doc/gdd/map.md 会話の途中の登場

func _catalog() -> Dictionary:
	var fighter := UnitType.new()
	fighter.id = "fighter"
	fighter.move = 6
	fighter.move_type = "foot"
	return { "fighter": fighter }

# 6x4 の平地。味方1部隊（名前あり）・敵2部隊（1つは名前なし）。
func _data(intro: Array) -> Dictionary:
	return {
		"cols": 6, "rows": 4,
		"terrain": ["......", "......", "......", "......"],
		"player": [ { "name": "p.party", "units": [
			{ "type": "fighter", "col": 0, "row": 0, "unit_id": "hero" },
			{ "type": "fighter", "col": 1, "row": 0 } ] } ],
		"enemy": [
			{ "order": 1, "name": "e.squad", "ai": "charge", "units": [
				{ "type": "fighter", "col": 5, "row": 3 },
				{ "type": "fighter", "col": 4, "row": 3 } ] },
			{ "order": 2, "ai": "charge", "units": [
				{ "type": "fighter", "col": 5, "row": 0, "unit_id": "boss" } ] } ],
		"dialogue": { "intro": intro, "outro": [] },
	}

func _state(intro: Array = []) -> BattleState:
	return StageLoader.build(_data(intro), _catalog())

func _handle_of(state: BattleState, unit_id: String) -> int:
	for u in state.units():
		if u.unit_id == unit_id:
			return u.handle
	return -1

# --- resolve_enter ---

func test_squad_resolves_to_all_its_units() -> void:
	var s := _state()
	var infos := StageLoader.resolve_enter(s, { "enter": [ { "squad": "e.squad", "entry": "fade" } ] })
	assert_eq(infos.size(), 1, "相手1つ＝info 1つ")
	var info: Dictionary = infos[0]
	assert_eq((info["units"] as Array).size(), 2, "部隊の駒が全部入る")
	for h in info["units"]:
		assert_eq(String(s.squad_of(int(h)).get("name", "")), "e.squad", "全部その部隊の駒")
	assert_eq(String(info["entry"]), "fade")
	assert_eq(info["from"], Vector2i.MAX, "fade は入口を持たない")

func test_unit_resolves_by_unit_id_with_from() -> void:
	var s := _state()
	var infos := StageLoader.resolve_enter(s,
		{ "enter": [ { "unit": "boss", "entry": "march", "from": { "col": 5, "row": 1 } } ] })
	assert_eq(infos.size(), 1)
	var info: Dictionary = infos[0]
	assert_eq(info["units"], [_handle_of(s, "boss")], "unit_id の駒1体")
	assert_eq(String(info["entry"]), "march")
	assert_eq(info["from"], Hex.offset_to_axial(5, 1), "入口は offset → axial に直す")

func test_targets_on_one_line_stay_separate() -> void:
	# 同じ行に並べた相手は、それぞれの登場の仕方を持ったまま別の info になる（盤が同時に出す）。
	var s := _state()
	var infos := StageLoader.resolve_enter(s, { "enter": [
		{ "squad": "e.squad", "entry": "fade" },
		{ "unit": "hero", "entry": "scatter", "from": { "col": 0, "row": 1 } } ] })
	assert_eq(infos.size(), 2)
	assert_eq(String(infos[0]["entry"]), "fade")
	assert_eq(String(infos[1]["entry"]), "scatter")

func test_missing_target_is_dropped() -> void:
	# 名簿に居ない actor の駒は盤に出ていない＝相手が無いのは正しい状態。行ごと止めない。
	var s := _state()
	var infos := StageLoader.resolve_enter(s, { "enter": [
		{ "squad": "nope", "entry": "fade" },
		{ "unit": "boss", "entry": "fade" } ] })
	assert_eq(infos.size(), 1, "居ない相手だけ落ちる")

func test_line_without_enter_resolves_to_nothing() -> void:
	var s := _state()
	assert_eq(StageLoader.resolve_enter(s, { "speaker": "x", "text": "y" }), [])
	assert_eq(StageLoader.resolve_enter(s, { "enter": "e.squad" }), [], "配列でない値は読まない")

func test_has_enter_lines() -> void:
	assert_false(StageLoader.has_enter_lines({ "intro": [ { "text": "a" } ] }))
	assert_true(StageLoader.has_enter_lines({ "intro": [ { "text": "a" }, { "enter": [] } ] }))

# --- enter_problems ---

func _problems(intro: Array) -> Array:
	return StageLoader.enter_problems(_data(intro))

func test_well_formed_lines_have_no_problems() -> void:
	assert_eq(_problems([
		{ "text": "bang", "sfx": "x" },
		{ "enter": [
			{ "squad": "e.squad", "entry": "fade" },
			{ "unit": "boss", "entry": "march", "from": { "col": 5, "row": 1 } } ] },
		{ "enter": [ { "squad": "p.party", "entry": "scatter", "from": { "col": 0, "row": 1 } } ] },
	]), [])

func test_enter_outside_intro_is_a_problem() -> void:
	var data := _data([])
	data["dialogue"]["outro"] = [ { "enter": [ { "unit": "boss", "entry": "fade" } ] } ]
	assert_eq(StageLoader.enter_problems(data).size(), 1, "outro の enter 行は不整合")

func test_unknown_squad_and_unit_are_problems() -> void:
	assert_eq(_problems([ { "enter": [ { "squad": "nope", "entry": "fade" } ] } ]).size(), 1)
	assert_eq(_problems([ { "enter": [ { "unit": "nope", "entry": "fade" } ] } ]).size(), 1)

func test_target_needs_exactly_one_of_squad_or_unit() -> void:
	assert_eq(_problems([ { "enter": [ { "squad": "e.squad", "unit": "boss", "entry": "fade" } ] } ]).size(), 1)
	assert_eq(_problems([ { "enter": [ { "entry": "fade" } ] } ]).size(), 1)

func test_same_unit_named_twice_is_a_problem() -> void:
	# 部隊で指した駒を、あとの行で unit_id でも指す＝同じ駒を2度出そうとしている。
	assert_eq(_problems([
		{ "enter": [ { "squad": "p.party", "entry": "fade" } ] },
		{ "enter": [ { "unit": "hero", "entry": "fade" } ] },
	]).size(), 1)

func test_entry_and_from_follow_the_reinforcement_rules() -> void:
	assert_eq(_problems([ { "enter": [ { "unit": "boss" } ] } ]).size(), 1, "entry は必須")
	assert_eq(_problems([ { "enter": [ { "unit": "boss", "entry": "fade", "from": { "col": 5, "row": 1 } } ] } ]).size(), 1,
		"fade は from を持たない")
	assert_eq(_problems([ { "enter": [ { "unit": "boss", "entry": "march" } ] } ]).size(), 1, "march は from が要る")

func test_duplicate_squad_name_cannot_be_named() -> void:
	var data := _data([ { "enter": [ { "squad": "e.squad", "entry": "fade" } ] } ])
	data["enemy"][1]["name"] = "e.squad"
	assert_eq(StageLoader.enter_problems(data).size(), 1, "同じ name の部隊が2つ＝指せない")

func test_stage_without_dialogue_has_no_problems() -> void:
	assert_eq(StageLoader.enter_problems({ "player": [], "enemy": [] }), [])
