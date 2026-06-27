extends GutTest
## domain/ai/nearest_attacker_brain.gd の思考テスト（純ロジック・ツリー不要）。

var _brain: NearestAttackerBrain

func before_each() -> void:
	_brain = NearestAttackerBrain.new()

# 指定 team の手番として、行動が尽きるまで AI を実際に適用する（安全のため上限付き）。
func _run_turn(state: BattleState, team: int) -> void:
	state.current_team = team
	var guard := 0
	while guard < 100:
		guard += 1
		var a := _brain.next_action(state, team)
		if a == null:
			return
		if a.kind == AiAction.Kind.MOVE:
			assert_true(state.move_unit(a.unit_id, a.to), "AIの移動は妥当であるべき")
		else:
			assert_false(state.attack(a.unit_id, a.target_id).is_empty(), "AIの攻撃は妥当であるべき")
	fail_test("AIの手番が終了しなかった（無限ループの疑い）")

func test_attacks_adjacent_enemy() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var ep := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(10, 1, ep, 3))                  # AIユニット
	s.add_unit(Unit.new(1, 0, Hex.neighbor(ep, 0), 3))  # 隣接する自軍
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "隣接敵がいれば攻撃を選ぶ")
	assert_eq(a.target_id, 1)

func test_moves_closer_when_far() -> void:
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var ai_pos := Hex.offset_to_axial(0, 1)
	var enemy_pos := Hex.offset_to_axial(10, 1)
	s.add_unit(Unit.new(10, 1, ai_pos, 3))
	s.add_unit(Unit.new(1, 0, enemy_pos, 3))
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.MOVE, "遠ければ近づく")
	assert_lt(Hex.distance(a.to, enemy_pos), Hex.distance(ai_pos, enemy_pos), "距離が縮む")

func test_focuses_weakest_adjacent() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var ep := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(10, 1, ep, 3))
	s.add_unit(Unit.new(1, 0, Hex.neighbor(ep, 0), 3, 8))   # 兵数8
	s.add_unit(Unit.new(2, 0, Hex.neighbor(ep, 2), 3, 3))   # 兵数3（弱い）
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, 2, "最も兵数の少ない敵を狙う")

func test_no_action_without_enemies() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	s.add_unit(Unit.new(10, 1, Hex.offset_to_axial(3, 3), 3))
	assert_null(_brain.next_action(s, 1), "敵がいなければ何もしない")

func test_full_turn_engages_and_damages() -> void:
	# 数ヘックス離れた敵へ寄って殴る一連の流れ。AIは強くて落ちない設定。
	var s := BattleState.new(12, 3)
	s.add_unit(Unit.new(10, 1, Hex.offset_to_axial(0, 1), 4, 8, 20, 20))  # AI 移動力4・強い
	var enemy_pos := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(1, 0, enemy_pos, 3, 8, 1, 10))                    # 反撃は微弱
	_run_turn(s, 1)
	var ai := s.unit_by_id(10)
	assert_not_null(ai, "AIユニットは生存（敵の反撃が微弱なので）")
	assert_eq(Hex.distance(ai.pos, enemy_pos), 1, "敵に隣接するまで前進する")
	assert_lt(s.unit_by_id(1).troops, 8, "前進後に攻撃して兵数を削る")
