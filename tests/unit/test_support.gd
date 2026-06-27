extends GutTest
## domain/combat/combat.gd の支援効果（加算・原典方式）のテスト。
## 支援(攻) ＝ 防御対象に隣接する自軍の (兵数 × ユニット攻撃力 × 0.5) 合計
## 支援(防) ＝ 攻撃者に隣接する自軍の (兵数 × ユニット防御力 × 0.5) 合計、支援前防御の2倍上限

func test_attack_support_from_ally_next_to_defender() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var dp := Hex.neighbor(ap, 0)            # 防御側（攻撃側の隣）
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 10, 10))  # 攻撃側
	s.add_unit(Unit.new(2, 1, dp, 3, 8, 10, 10))  # 防御側
	s.add_unit(Unit.new(3, 0, Hex.neighbor(dp, 2), 3, 6, 8, 10))  # 味方: 兵6 攻8 → 支援 6×8×0.5=24
	# 攻撃側の包囲は不成立（隣接敵は防御側1体のみ）→ base 80、支援 +24
	var ea := Combat.effective_attack(s, s.unit_by_id(1), s.unit_by_id(2))
	assert_almost_eq(ea, 104.0, 0.001, "隣接味方の攻撃支援 +24")

func test_defense_support_from_ally_next_to_attacker() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var dp := Hex.neighbor(ap, 0)
	s.add_unit(Unit.new(1, 1, ap, 3, 8, 10, 10))  # 攻撃側 team1
	s.add_unit(Unit.new(2, 0, dp, 3, 8, 10, 10))  # 防御側 team0
	s.add_unit(Unit.new(3, 0, Hex.neighbor(ap, 2), 3, 4, 0, 10))  # 味方: 兵4 防10 → 支援 4×10×0.5=20
	# 防御側の包囲は不成立（隣接敵は攻撃側1体）→ base 80、支援 +20
	var ed := Combat.effective_defense(s, s.unit_by_id(2), s.unit_by_id(1))
	assert_almost_eq(ed, 100.0, 0.001, "攻撃者に隣接する味方の防御支援 +20")

func test_defense_support_capped_at_double() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var dp := Hex.neighbor(ap, 0)
	s.add_unit(Unit.new(1, 1, ap, 3, 8, 10, 10))
	s.add_unit(Unit.new(2, 0, dp, 3, 8, 10, 10))                  # base 防 80
	s.add_unit(Unit.new(3, 0, Hex.neighbor(ap, 2), 3, 8, 0, 100))  # 巨大支援 8×100×0.5=400
	var ed := Combat.effective_defense(s, s.unit_by_id(2), s.unit_by_id(1))
	assert_almost_eq(ed, 160.0, 0.001, "支援後でも支援前の2倍(80→160)が上限")

func test_flanker_boosts_attack_and_cuts_retaliation() -> void:
	# 包囲と支援の複合: 側面ユニットZは Yを包囲しつつ Xの攻撃を支援し Xの防御も支援する。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var c := Hex.offset_to_axial(4, 4)
	s.add_unit(Unit.new(1, 0, c, 3, 8, 10, 10))                  # 防御 Y
	s.add_unit(Unit.new(2, 1, Hex.neighbor(c, 0), 3, 8, 10, 10))  # 攻撃 X
	s.add_unit(Unit.new(3, 1, Hex.neighbor(c, 3), 3, 8, 10, 10))  # 側面 Z（対角）
	var r := s.attack(2, 1)
	assert_eq(r["damage"], 7, "Y包囲(防0.5)＋Zの攻撃支援(+40)で 7 削る")
	assert_eq(r["retaliation"], 1, "Yは弱り、Xは防御支援(+40)で 1 しか受けない")
