extends GutTest
## domain の攻撃解決（battle_state.attack / combat.gd）のテスト。

func _state() -> BattleState:
	return BattleState.new(8, 8)

func test_attack_is_simultaneous() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 4))      # 攻撃側 威力4
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 10, 3))  # 防御側 威力3
	var r := s.attack(1, 2)
	assert_false(r.is_empty(), "隣接敵を攻撃できる")
	assert_eq(r["damage"], 4, "防御側へのダメージ")
	assert_eq(r["retaliation"], 3, "攻撃側への反撃ダメージ")
	assert_eq(s.unit_by_id(2).hp, 6, "防御側は威力4ぶん減る")
	assert_eq(s.unit_by_id(1).hp, 7, "攻撃側も反撃で威力3ぶん減る")
	assert_true(s.is_done(1), "攻撃したら行動終了")

func test_attack_kills_and_removes() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 20))
	var tp := Hex.neighbor(ap, 0)
	s.add_unit(Unit.new(2, 1, tp, 3, 10, 4))
	var r := s.attack(1, 2)
	assert_true(r["killed"], "致死ダメージで撃破")
	assert_false(r["attacker_killed"], "攻撃側は反撃を耐える")
	assert_null(s.unit_by_id(2), "倒した敵は盤から消える")
	assert_null(s.unit_at(tp), "そのマスは空く")

func test_simultaneous_mutual_kill() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 50))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 10, 50))
	var r := s.attack(1, 2)
	assert_true(r["killed"] and r["attacker_killed"], "相討ちで両者撃破")
	assert_null(s.unit_by_id(1))
	assert_null(s.unit_by_id(2))

func test_attack_requires_adjacent_enemy() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 4))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3, 10, 4))  # 遠い
	assert_true(s.attack(1, 2).is_empty(), "非隣接は攻撃不可")
	s.add_unit(Unit.new(3, 0, Hex.neighbor(ap, 1), 3, 10, 4))  # 味方が隣接
	assert_true(s.attack(1, 3).is_empty(), "味方は攻撃不可")

func test_cannot_attack_off_turn() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 4))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 10, 4))
	assert_true(s.attack(2, 1).is_empty(), "手番外の陣営は攻撃できない")

func test_cannot_attack_twice() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 4))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 10, 4))
	s.add_unit(Unit.new(3, 1, Hex.neighbor(ap, 1), 3, 10, 4))
	assert_false(s.attack(1, 2).is_empty(), "1回目は成功")
	assert_true(s.attack(1, 3).is_empty(), "同ターン2回目は不可")

func test_attack_targets_lists_adjacent_enemies() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 10, 4))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 10, 4))
	s.add_unit(Unit.new(3, 1, Hex.neighbor(ap, 2), 3, 10, 4))
	s.add_unit(Unit.new(4, 1, Hex.offset_to_axial(6, 6), 3, 10, 4))  # 遠い
	var ids := s.attack_targets(1)
	assert_eq(ids.size(), 2, "隣接する敵2体だけが対象")
	assert_true(ids.has(2) and ids.has(3))
