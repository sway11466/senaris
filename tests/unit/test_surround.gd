extends GutTest
## domain/surround/surround.gd と、戦闘への包囲補正(×0.5)のテスト。

func test_not_surrounded_with_one_enemy() -> void:
	var s := BattleState.new(8, 8)
	var c := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(1, 0, c, 3))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(c, 0), 3))
	assert_false(Surround.is_surrounded(s, s.unit_by_id(1)), "1体隣接では包囲でない")

func test_surrounded_by_two_opposite() -> void:
	# 反対側2体の占有＋ZOCで6方向を覆える（最小2体で成立）。
	var s := BattleState.new(8, 8)
	var c := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(1, 0, c, 3))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(c, 0), 3))
	s.add_unit(Unit.new(3, 1, Hex.neighbor(c, 3), 3))  # dir0 の反対
	assert_true(Surround.is_surrounded(s, s.unit_by_id(1)), "対角2体で包囲成立")

func test_allies_do_not_surround() -> void:
	var s := BattleState.new(8, 8)
	var c := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(1, 0, c, 3))
	s.add_unit(Unit.new(2, 0, Hex.neighbor(c, 0), 3))  # 味方
	s.add_unit(Unit.new(3, 0, Hex.neighbor(c, 3), 3))  # 味方
	assert_false(Surround.is_surrounded(s, s.unit_by_id(1)), "味方は包囲に数えない")

func test_edge_unit_not_surrounded() -> void:
	# 盤端は周囲に盤外があるので包囲不成立。
	var s := BattleState.new(8, 8)
	var c := Hex.offset_to_axial(0, 0)  # 隅
	s.add_unit(Unit.new(1, 0, c, 3))
	var id := 100
	for dir in 6:
		var h := Hex.neighbor(c, dir)
		if s.in_field(h):
			s.add_unit(Unit.new(id, 1, h, 3))
			id += 1
	assert_false(Surround.is_surrounded(s, s.unit_by_id(1)), "盤端は包囲されない")

func test_surround_halves_combat() -> void:
	# 包囲された防御側は攻防とも半減 → 被ダメ増・反撃減。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var c := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(1, 0, c, 3, 8, 10, 10))                  # 防御側（包囲される）
	s.add_unit(Unit.new(2, 1, Hex.neighbor(c, 0), 3, 8, 10, 10))  # 攻撃側
	s.add_unit(Unit.new(3, 1, Hex.neighbor(c, 3), 3, 8, 10, 10))  # 包囲の頭数
	assert_true(Surround.is_surrounded(s, s.unit_by_id(1)))
	var r := s.attack(2, 1)
	assert_eq(r["damage"], 6, "包囲された防御側は被ダメ増（互角なら4→6）")
	assert_eq(r["retaliation"], 2, "包囲された側の反撃は減る（4→2）")
