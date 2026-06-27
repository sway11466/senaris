extends GutTest
## domain の攻撃解決（battle_state.attack / combat.gd）のテスト。決定的・兵数モデル。

func _state() -> BattleState:
	return BattleState.new(8, 8)

func test_even_fight_simultaneous() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))
	var r := s.attack(1, 2)
	assert_eq(r["damage"], 4, "互角(8/10/10)同士は4減らす（A=D→割合0.5）")
	assert_eq(r["retaliation"], 4, "同時攻撃なので反撃も4")
	assert_eq(s.unit_by_id(2).troops, 4)
	assert_eq(s.unit_by_id(1).troops, 4)

func test_attack_advantage_hits_harder() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 20, 10))               # 攻撃2倍
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))
	var r := s.attack(1, 2)
	assert_eq(r["damage"], 6, "攻撃2倍(p=2)で割合0.8→6減らす")
	assert_eq(r["retaliation"], 4, "防御は同じなので反撃は互角時と同じ4（攻防は独立）")

func test_overwhelming_kills_without_loss() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 100, 10))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 2, 1, 1))
	var r := s.attack(1, 2)
	assert_true(r["killed"], "圧倒的攻撃で撃破")
	assert_false(r["attacker_killed"], "弱い反撃では落ちない")
	assert_eq(s.unit_by_id(1).troops, 8, "微小な反撃は兵数を減らさない")
	assert_null(s.unit_by_id(2), "倒した敵は盤から消える")

func test_simultaneous_mutual_kill() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 2, 100, 1))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 2, 100, 1))
	var r := s.attack(1, 2)
	assert_true(r["killed"] and r["attacker_killed"], "相討ちで両者撃破")
	assert_null(s.unit_by_id(1))
	assert_null(s.unit_by_id(2))

func test_attack_marks_done() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))
	s.attack(1, 2)
	assert_true(s.has_attacked(1), "攻撃済みになる")
	assert_true(s.is_done(1), "攻撃したら行動終了")

func test_attack_requires_adjacent_enemy() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3, 8, 10, 10))  # 遠い
	assert_true(s.attack(1, 2).is_empty(), "非隣接は攻撃不可")
	s.add_unit(Unit.new(3, 0, Hex.neighbor(ap, 1), 3, 8, 10, 10))  # 味方が隣接
	assert_true(s.attack(1, 3).is_empty(), "味方は攻撃不可")

func test_cannot_attack_off_turn() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))
	assert_true(s.attack(2, 1).is_empty(), "手番外の陣営は攻撃できない")

func test_cannot_attack_twice() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))
	s.add_unit(Unit.new(3, 1, Hex.neighbor(ap, 1), 3, 8, 10, 10))
	assert_false(s.attack(1, 2).is_empty(), "1回目は成功")
	assert_true(s.attack(1, 3).is_empty(), "同ターン2回目は不可")

func test_attack_targets_lists_adjacent_enemies() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))
	s.add_unit(Unit.new(3, 1, Hex.neighbor(ap, 2), 3, 8, 10, 10))
	s.add_unit(Unit.new(4, 1, Hex.offset_to_axial(6, 6), 3, 8, 10, 10))  # 遠い
	var ids := s.attack_targets(1)
	assert_eq(ids.size(), 2, "隣接する敵2体だけが対象")
	assert_true(ids.has(2) and ids.has(3))

func test_combat_is_deterministic() -> void:
	# 同じ初期条件なら何度やっても同じ結果（乱数なし）。
	var first := -999
	for i in 3:
		var s := _state()
		var ap := Hex.offset_to_axial(2, 2)
		s.add_unit(Unit.new(1, 0, ap, 3, 8, 13, 11))
		s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 6, 9, 12))
		var r := s.attack(1, 2)
		if first == -999:
			first = r["damage"]
		assert_eq(r["damage"], first, "毎回同じ結果（乱数なし）")
