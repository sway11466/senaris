extends GutTest
## domain/battle_state.gd の勝敗判定のテスト（自軍＝team 0 視点）。

func test_ongoing_when_both_teams_present() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3))
	assert_false(s.is_over(), "両軍が残っていれば未決着")
	assert_eq(s.outcome(), BattleState.ONGOING)

func test_player_wins_when_enemy_wiped() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 100, 10))               # 圧倒的攻撃
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 2, 1, 1))
	s.attack(1, 2)
	assert_true(s.is_over(), "敵全滅で決着")
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "自軍の勝利")

func test_player_loses_when_wiped() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 1, 1, 1))                  # 弱小・反撃で全滅
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 100, 10))
	s.attack(1, 2)
	assert_true(s.is_over())
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "自軍全滅は敗北")

func test_mutual_destruction_is_loss() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 2, 100, 1))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 2, 100, 1))
	s.attack(1, 2)  # 相討ちで両軍全滅
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "相討ち全滅も自軍全滅なので敗北")
