extends GutTest
## 対地/対空の使い分けと「対空なし」ルールのテスト。詳細 → doc/gdd/combat.md

func _state() -> BattleState:
	return BattleState.new(8, 8)

func _flyer(id: int, team: int, pos: Vector2i, atk := 10, dfn := 10) -> Unit:
	var u := Unit.new(id, team, pos, 3, 8, atk, dfn)
	u.move_type = "flight"  # 飛行判定は move_type で行う
	u.atk_air = atk
	return u

func test_no_antiair_cannot_target_flyer() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var ground := Unit.new(1, 0, ap, 3, 8, 50, 10)  # 対地50だが…
	ground.atk_air = 0                               # 対空0＝飛行を狙えない
	s.add_unit(ground)
	s.add_unit(_flyer(2, 1, Hex.neighbor(ap, 0)))
	assert_false(s.can_attack(1, 2), "対空0は飛行を攻撃対象にできない")
	assert_true(s.attack_targets(1).is_empty(), "攻撃対象リストに飛行は出ない")
	assert_true(s.attack(1, 2).is_empty(), "攻撃そのものが不成立")

func test_attack_uses_atk_air_against_flyer() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var shooter := Unit.new(1, 0, ap, 3, 8, 50, 10)  # 対地50
	shooter.atk_air = 20                              # 対空20（飛行にはこちらを使う）
	s.add_unit(shooter)
	s.add_unit(_flyer(2, 1, Hex.neighbor(ap, 0), 10, 10))
	var r := s.attack(1, 2)
	# 対空20 vs 防御10 → 0.8 → 6。対地50を使っていたら 8 になるはず。
	assert_eq(r["damage"], 6, "飛行相手には atk_air(20) を使う（atk_ground 50 ではない）")

func test_flyer_hits_ground_no_retaliation_when_no_antiair() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var flyer := _flyer(1, 1, ap, 50, 10)
	var ground := Unit.new(2, 0, Hex.neighbor(ap, 0), 3, 8, 50, 40)  # 硬くて生き残る
	ground.atk_air = 0                                                # 対空なし
	s.add_unit(flyer)
	s.add_unit(ground)
	s.current_team = 1  # 飛行側(team1)の手番
	var r := s.attack(1, 2)
	assert_gt(r["damage"], 0, "飛行は地上を攻撃できる（対地で）")
	assert_eq(r["retaliation"], 0, "対空0の地上は反撃できない")
	assert_eq(s.unit_by_id(2).level, 1, "反撃不成立→防御側は経験+0")
	assert_eq(s.unit_by_id(1).level, 2, "攻撃側は参加で+1")

func test_ground_with_antiair_retaliates_against_flyer() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var flyer := _flyer(1, 1, ap, 30, 10)
	var aa := Unit.new(2, 0, Hex.neighbor(ap, 0), 3, 8, 40, 20)
	aa.atk_air = 25  # 対空あり
	s.add_unit(flyer)
	s.add_unit(aa)
	s.current_team = 1
	var r := s.attack(1, 2)
	assert_gt(r["retaliation"], 0, "対空ありの地上は飛行に反撃できる")
	assert_eq(s.unit_by_id(2).level, 2, "反撃成立で防御側+1")

func test_loader_sets_aerial_and_atk_air_from_type() -> void:
	var catalog := {
		"dragon": UnitType.from_dict({
			"id": "dragon", "atk_ground": 90, "atk_air": 60,
			"defense": 70, "move": 6, "move_type": "flight", "max_troops": 8,
		}),
	}
	var data := { "cols": 6, "rows": 6, "units": [
		{ "type": "dragon", "team": 1, "col": 1, "row": 1 },
	] }
	var s := StageLoader.build(data, catalog)
	var u := s.unit_by_id(1)
	assert_true(u.is_aerial(), "move_type=flight → is_aerial()")
	assert_eq(u.atk_air, 60, "atk_air を種別から載せる")
	assert_eq(u.unit_attack, 90, "対地は atk_ground")
