extends GutTest
## domain/surround/surround.gd（段階式・ゲート付き）と戦闘への包囲補正のテスト。

# 中央のユニットを、指定方向の隣に敵を置いて包囲したときの係数を返す。
func _factor_with(dirs: Array) -> float:
	var s := BattleState.new(8, 8)
	var c := Hex.offset_to_axial(4, 4)  # 周囲6マスが盤内になる中央寄り
	s.add_unit(Unit.new(1, 0, c, 3))
	var id := 10
	for d in dirs:
		s.add_unit(Unit.new(id, 1, Hex.neighbor(c, d), 3))
		id += 1
	return Surround.factor(s, s.unit_by_id(1))

func test_one_enemy_no_surround() -> void:
	assert_eq(_factor_with([0]), 1.0, "隣接1体ではゲート未達で包囲不成立")

func test_two_adjacent_pair() -> void:
	assert_almost_eq(_factor_with([0, 1]), 0.76, 0.001, "隣り合う2体（占有2/ZOC2）→ 0.76")

func test_two_one_gap() -> void:
	assert_almost_eq(_factor_with([0, 2]), 0.72, 0.001, "1つ飛び2体（占有2/ZOC3）→ 0.72")

func test_two_opposite() -> void:
	assert_almost_eq(_factor_with([0, 3]), 0.68, 0.001, "対角2体（占有2/ZOC4）→ 0.68")

func test_full_occupation() -> void:
	assert_almost_eq(_factor_with([0, 1, 2, 3, 4, 5]), 0.52, 0.001, "全占有（占有6）→ 0.52（下限0.10には未達）")

func test_allies_do_not_count() -> void:
	var s := BattleState.new(8, 8)
	var c := Hex.offset_to_axial(4, 4)
	s.add_unit(Unit.new(1, 0, c, 3))
	s.add_unit(Unit.new(2, 0, Hex.neighbor(c, 0), 3))  # 味方
	s.add_unit(Unit.new(3, 0, Hex.neighbor(c, 3), 3))  # 味方
	assert_eq(Surround.factor(s, s.unit_by_id(1)), 1.0, "味方は包囲に数えない")

func test_edge_is_weaker() -> void:
	# 隅は盤外を数えないので、敵で固めても包囲が弱い（中央の対角0.50より高い）。
	var s := BattleState.new(8, 8)
	var c := Hex.offset_to_axial(0, 0)
	s.add_unit(Unit.new(1, 0, c, 3))
	var id := 10
	for d in 6:
		var h := Hex.neighbor(c, d)
		if s.in_field(h):
			s.add_unit(Unit.new(id, 1, h, 3))
			id += 1
	assert_almost_eq(Surround.factor(s, s.unit_by_id(1)), 0.84, 0.001, "隅は2マスしか覆えず 0.84（中央の対角0.68より弱い）")

# 注: 「対角2体で包囲して攻撃」は包囲と支援が同時に効く（側面ユニットは攻撃支援者でもある）。
# その複合ケースの戦闘結果は test_support.gd で検証する。
