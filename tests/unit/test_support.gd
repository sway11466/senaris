extends GutTest
## domain/combat/combat.gd の支援効果（加算・原典方式・率0.25）のテスト。
## 支援(攻) ＝ 防御対象に隣接する自軍の (兵数 × ユニット攻撃力 × 0.25) 合計
## 支援(防) ＝ 攻撃者に隣接する自軍の (兵数 × ユニット防御力 × 0.25) 合計、支援前防御の2倍上限

func test_attack_support_from_ally_next_to_defender() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var dp := Hex.neighbor(ap, 0)            # 防御側（攻撃側の隣）
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))  # 攻撃側
	s.add_unit(Unit.new(2, 1, dp, 3, 8, 10, 10))  # 防御側
	s.add_unit(Unit.new(3, 0, Hex.neighbor(dp, 2), 3, 6, 8, 10))  # 味方: 兵6 攻8 → 支援 6×8×0.25=12
	# 攻撃側の包囲は不成立（隣接敵は防御側1体のみ）→ base 80、支援 +12
	var ea := Combat.effective_attack(s, s.unit_by_id(1), s.unit_by_id(2))
	assert_almost_eq(ea, 92.0, 0.001, "隣接味方の攻撃支援 +12")

func test_defense_support_from_ally_next_to_attacker() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var dp := Hex.neighbor(ap, 0)
	s.add_unit(Unit.new(1, 1, ap, 3, 8, 10, 10))  # 攻撃側 team1
	s.add_unit(Unit.new(2, 0, dp, 3, 8, 10, 10))  # 防御側 team0
	s.add_unit(Unit.new(3, 0, Hex.neighbor(ap, 2), 3, 4, 0, 10))  # 味方: 兵4 防10 → 支援 4×10×0.25=10
	# 防御側の包囲は不成立（隣接敵は攻撃側1体）→ base 80、支援 +10
	var df := Combat.defense_breakdown(s, s.unit_by_id(2), s.unit_by_id(1))
	assert_almost_eq(float(df["total"]), 90.0, 0.001, "攻撃者に隣接する味方の防御支援 +10")
	assert_false(bool(df["capped"]), "支援+10は2倍上限(160)に届かない＝capped=false")

func test_defense_support_capped_at_double() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var dp := Hex.neighbor(ap, 0)
	s.add_unit(Unit.new(1, 1, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 0, dp, 3, 8, 10, 10))                  # base 防 80
	s.add_unit(Unit.new(3, 0, Hex.neighbor(ap, 2), 3, 8, 0, 100))  # 巨大支援 8×100×0.25=200
	var df := Combat.defense_breakdown(s, s.unit_by_id(2), s.unit_by_id(1))
	assert_almost_eq(float(df["total"]), 160.0, 0.001, "支援後でも支援前の2倍(80→160)が上限")
	assert_true(bool(df["capped"]), "上限が効いたことを内訳が示す＝capped=true")

func test_flanker_boosts_attack_and_cuts_retaliation() -> void:
	# 包囲と支援の複合: 側面ユニットZは Yを包囲しつつ Xの攻撃を支援し Xの防御も支援する。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var c := Hex.offset_to_axial(4, 4)
	s.add_unit(Unit.new(1, 0, c, 3, 8, 10, 10))                  # 防御 Y
	s.add_unit(Unit.new(2, 1, Hex.neighbor(c, 0), 3, 8, 10, 10))  # 攻撃 X
	s.add_unit(Unit.new(3, 1, Hex.neighbor(c, 3), 3, 8, 10, 10))  # 側面 Z（対角）
	var r := s.attack(2, 1)
	assert_eq(r["damage"], 6, "Y包囲(対角=防0.68)＋Zの攻撃支援(+20)で 6 削る")
	assert_eq(r["retaliation"], 2, "Yは弱るが、Xも反撃を 2 受ける（タダではない）")
