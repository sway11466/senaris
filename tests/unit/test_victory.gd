extends GutTest
## domain/battle_state.gd の勝敗判定のテスト。

func test_ongoing_when_both_teams_present() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3))
	assert_false(s.is_over(), "両軍が残っていれば未決着")
	assert_eq(s.winner(), -1)

func test_player_wins_when_enemy_wiped() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 50))            # 一撃で倒す威力
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 10, 1))
	s.attack(1, 2)
	assert_true(s.is_over(), "敵全滅で決着")
	assert_eq(s.winner(), 0, "自軍の勝利")

func test_mutual_destruction_has_no_winner() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 50))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 10, 50))
	s.attack(1, 2)  # 相討ちで両軍全滅
	assert_eq(s.winner(), -1, "両軍全滅は勝者なし")
