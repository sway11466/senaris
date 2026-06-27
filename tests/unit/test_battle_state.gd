extends GutTest
## domain/battle_state.gd と domain/unit/unit.gd のテスト。

func _state() -> BattleState:
	return BattleState.new(6, 6)

func test_add_and_query() -> void:
	var s := _state()
	var u := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3)
	s.add_unit(u)
	assert_eq(s.unit_by_id(1), u)
	assert_eq(s.unit_at(u.pos), u, "座標からユニットを引ける")
	assert_null(s.unit_at(Hex.offset_to_axial(0, 0)), "空きマスは null")
	assert_null(s.unit_by_id(999), "未知IDは null")

func test_reachable_includes_start_excludes_occupied() -> void:
	var s := _state()
	var a := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 2)
	s.add_unit(a)
	assert_true(s.reachable(1).has(a.pos), "起点を含む")
	var blocked := Hex.neighbor(a.pos, 0)
	s.add_unit(Unit.new(2, 1, blocked, 1))
	assert_false(s.reachable(1).has(blocked), "他ユニットのマスは到達不可")

func test_move_valid() -> void:
	var s := _state()
	var start := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, start, 2))
	var dest := Hex.neighbor(start, 0)
	assert_true(s.can_move(1, dest))
	assert_true(s.move_unit(1, dest), "妥当な移動は成功")
	assert_eq(s.unit_by_id(1).pos, dest, "座標が更新される")

func test_move_rejects_occupied_and_out_of_range() -> void:
	var s := _state()
	var start := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, start, 2))
	var occupied := Hex.neighbor(start, 0)
	s.add_unit(Unit.new(2, 1, occupied, 2))
	assert_false(s.move_unit(1, occupied), "他ユニットの上には移動不可")
	assert_false(s.move_unit(1, Hex.offset_to_axial(5, 5)), "移動力を超える先は不可")
	assert_eq(s.unit_by_id(1).pos, start, "不正な移動では動かない")
