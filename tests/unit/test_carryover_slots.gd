extends GutTest
## carryover_slots の配置規則（actor 名指し＋残りを名簿順で詰める・兵力ゼロは出撃しない）。
## 仕様 → doc/gdd/map.md（配置）

func _catalog() -> Dictionary:
	return {
		"elf": UnitType.from_dict({ "id": "elf", "atk_ground": 6, "defense": 5, "move": 5, "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 8 }),
		"recruit": UnitType.from_dict({ "id": "recruit", "atk_ground": 5, "defense": 5, "move": 3, "max_troops": 8 }),
	}

func _member(type_id: String, actor: String, troops: int = 8) -> Dictionary:
	return { "type": type_id, "skin": type_id, "level": 1, "troops": troops, "max_troops": 8, "actor": actor }

func _at(s: BattleState, col: int, row: int) -> Unit:
	return s.unit_at(Hex.offset_to_axial(col, row))

func test_named_slot_places_that_actor() -> void:
	var carried: Array = [_member("knight", "t3.van"), _member("elf", "t3.elf")]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "carryover_slots": [
		{ "col": 1, "row": 1, "actor": "t3.elf" },
		{ "col": 2, "row": 1 },
	] }, _catalog(), {}, carried)
	assert_eq(_at(s, 1, 1).actor, "t3.elf", "名指しのスロットにその仲間が入る")
	assert_eq(_at(s, 2, 1).actor, "t3.van", "残りは名簿順で詰まる")

func test_missing_actor_leaves_the_slot_empty() -> void:
	# 未加入の仲間を名指ししたスロットは空のまま＝他の駒に回さない（作者の配置を守る）。
	var carried: Array = [_member("knight", "t3.van")]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "carryover_slots": [
		{ "col": 1, "row": 1, "actor": "t3.elf" },
		{ "col": 2, "row": 1 },
	] }, _catalog(), {}, carried)
	assert_null(_at(s, 1, 1), "未加入の名指しスロットは空")
	assert_eq(_at(s, 2, 1).actor, "t3.van", "指名なしのスロットに詰まる")
	assert_eq(s.units().size(), 1)

func test_zero_troops_member_is_not_deployed() -> void:
	# 兵力ゼロの離脱者は名簿に在籍するが盤には出ない。
	var carried: Array = [_member("knight", "t3.van", 0), _member("elf", "t3.elf", 5)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "carryover_slots": [
		{ "col": 1, "row": 1 },
		{ "col": 2, "row": 1 },
	] }, _catalog(), {}, carried)
	assert_eq(s.units().size(), 1, "出撃するのは兵力の残る1体だけ")
	assert_eq(_at(s, 1, 1).actor, "t3.elf")
	assert_eq(_at(s, 1, 1).troops, 5, "損耗を持ち越す")

func test_zero_troops_named_slot_stays_empty() -> void:
	var carried: Array = [_member("elf", "t3.elf", 0)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "carryover_slots": [
		{ "col": 1, "row": 1, "actor": "t3.elf" },
	] }, _catalog(), {}, carried)
	assert_eq(s.units().size(), 0, "離脱者は名指しでも出撃しない")

func test_anonymous_members_fill_in_order() -> void:
	var carried: Array = [
		{ "type": "recruit", "skin": "recruit", "level": 1, "troops": 7, "max_troops": 8 },
		{ "type": "knight", "skin": "knight", "level": 2, "troops": 8, "max_troops": 8 },
	]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "carryover_slots": [
		{ "col": 1, "row": 1 }, { "col": 2, "row": 1 },
	] }, _catalog(), {}, carried)
	assert_eq(_at(s, 1, 1).type_id, "recruit", "名簿順で詰まる")
	assert_eq(_at(s, 2, 1).type_id, "knight")

func test_carried_units_belong_to_player() -> void:
	var carried: Array = [_member("elf", "t3.elf")]
	var s := StageLoader.build({ "cols": 8, "rows": 6, 
		"carryover_slots": [{ "col": 1, "row": 1 }] }, _catalog(), {}, carried)
	var u := _at(s, 1, 1)
	assert_eq(u.team, 0)
	assert_eq(u.recruited_team, 0, "名簿に載っている＝帰属は自軍で確定")
