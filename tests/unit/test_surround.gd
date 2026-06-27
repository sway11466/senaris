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
	assert_almost_eq(_factor_with([0, 1]), 0.60, 0.001, "隣り合う2体（占有2/ZOC2）→ 0.60")

func test_two_one_gap() -> void:
	assert_almost_eq(_factor_with([0, 2]), 0.55, 0.001, "1つ飛び2体（占有2/ZOC3）→ 0.55")

func test_two_opposite() -> void:
	assert_almost_eq(_factor_with([0, 3]), 0.50, 0.001, "対角2体（占有2/ZOC4）→ 0.50")

func test_full_occupation_hits_floor() -> void:
	assert_almost_eq(_factor_with([0, 1, 2, 3, 4, 5]), 0.10, 0.001, "全占有 → 下限0.10")

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
	assert_almost_eq(Surround.factor(s, s.unit_by_id(1)), 0.70, 0.001, "隅は2マスしか覆えず 0.70")

func test_surround_affects_combat() -> void:
	# 対角2体で包囲された防御側は ×0.5 → 被ダメ増・反撃減。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var c := Hex.offset_to_axial(4, 4)
	s.add_unit(Unit.new(1, 0, c, 3, 8, 10, 10))                  # 防御側（包囲される）
	s.add_unit(Unit.new(2, 1, Hex.neighbor(c, 0), 3, 8, 10, 10))  # 攻撃側
	s.add_unit(Unit.new(3, 1, Hex.neighbor(c, 3), 3, 8, 10, 10))  # 包囲の頭数（対角）
	assert_almost_eq(Surround.factor(s, s.unit_by_id(1)), 0.50, 0.001)
	var r := s.attack(2, 1)
	assert_eq(r["damage"], 6, "包囲(×0.5)で被ダメ増 4→6")
	assert_eq(r["retaliation"], 2, "包囲側の反撃減 4→2（攻撃側は隣接1体で包囲不成立）")
