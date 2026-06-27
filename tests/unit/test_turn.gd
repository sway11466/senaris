extends GutTest
## domain/battle_state.gd の手番ロジックのテスト。

func _state() -> BattleState:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))  # 自軍
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3))  # 敵軍
	return s

func test_initial_turn() -> void:
	var s := _state()
	assert_eq(s.current_team, 0, "開始は自軍手番")
	assert_eq(s.turn_number, 1)

func test_cannot_select_enemy_on_player_turn() -> void:
	var s := _state()
	assert_true(s.can_select(1), "自軍は選択可")
	assert_false(s.can_select(2), "敵軍は手番外で選択不可")

func test_move_marks_acted_and_blocks_reselect() -> void:
	var s := _state()
	var dest := Hex.neighbor(Hex.offset_to_axial(2, 2), 0)
	assert_true(s.move_unit(1, dest))
	assert_true(s.has_moved(1), "移動で行動済みになる")
	assert_false(s.can_select(1), "行動済みは再選択不可")
	assert_false(s.move_unit(1, Hex.neighbor(dest, 0)), "同ターンに再移動不可")

func test_enemy_cannot_move_on_player_turn() -> void:
	var s := _state()
	assert_false(s.move_unit(2, Hex.neighbor(Hex.offset_to_axial(5, 5), 0)), "手番外は動けない")

func test_end_turn_switches_team_and_clears_acted() -> void:
	var s := _state()
	s.move_unit(1, Hex.neighbor(Hex.offset_to_axial(2, 2), 0))
	s.end_turn()
	assert_eq(s.current_team, 1, "敵軍手番へ")
	assert_eq(s.turn_number, 1, "1巡目はまだターン1")
	assert_true(s.can_select(2), "敵軍が選択可に")
	assert_false(s.can_select(1), "自軍は手番外")
	s.end_turn()
	assert_eq(s.current_team, 0, "自軍へ戻る")
	assert_eq(s.turn_number, 2, "1巡してターン+1")
	assert_true(s.can_select(1), "行動済みがリセットされ再び動ける")
