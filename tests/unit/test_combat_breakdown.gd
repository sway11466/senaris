extends GutTest
## 戦闘の内訳(breakdown)が「式の単一の真実」であること、そして
## 表示用 detail が実際に適用された損害と完全一致することを保証するテスト。
## 詳細 → doc/gdd/combat.md（戦闘結果ビューの導出）

func _state() -> BattleState:
	return BattleState.new(8, 8)

# --- 単一の真実: 実効値・損害は breakdown から導く ---

func test_effective_values_delegate_to_breakdown() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var a := Unit.new(1, 0, ap, 3, 8, 20, 15)
	var t := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 7, 12, 10)
	s.add_unit(a)
	s.add_unit(t)
	assert_eq(Combat.effective_attack(s, a, t), Combat.attack_breakdown(s, a, t)["total"], "effective_attack＝breakdown.total")
	assert_eq(Combat.effective_defense(s, t, a), Combat.defense_breakdown(s, t, a)["total"], "effective_defense＝breakdown.total")
	assert_eq(Combat.casualties(s, a, t), Combat.hit_detail(s, a, t)["loss"], "casualties＝hit_detail.loss")

func test_attack_breakdown_factors() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.set_terrain(ap, "plateau")  # 攻×1.15
	var a := Unit.new(1, 0, ap, 3, 8, 50, 40)
	var t := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 4)
	s.add_unit(a)
	s.add_unit(t)
	var b := Combat.attack_breakdown(s, a, t)
	assert_eq(b["kind"], "attack")
	assert_eq(b["troops"], 8)
	assert_eq(b["stat"], 50, "地上相手は対地")
	assert_false(b["vs_aerial"])
	assert_almost_eq(float(b["experience"]), 1.0, 0.001)
	assert_almost_eq(float(b["terrain"]), 1.15, 0.001)
	assert_almost_eq(float(b["total"]), 8.0 * 50.0 * 1.15, 0.01, "兵8×対地50×地形1.15＝460")

func test_attack_breakdown_uses_atk_air_vs_flyer() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var a := Unit.new(1, 0, ap, 3, 8, 50, 40)
	a.atk_air = 20
	var fly := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10)
	fly.move_type = "flight"
	s.add_unit(a)
	s.add_unit(fly)
	var b := Combat.attack_breakdown(s, a, fly)
	assert_true(b["vs_aerial"], "相手が飛行")
	assert_eq(b["stat"], 20, "飛行相手は対空(atk_air)を使う")

func test_defense_breakdown_reflects_surround() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(4, 4)
	var t := Unit.new(1, 1, c, 3, 8, 10, 10)              # 標的(team1)
	s.add_unit(t)
	s.add_unit(Unit.new(2, 0, Hex.neighbor(c, 0), 3))    # 囲み1
	s.add_unit(Unit.new(3, 0, Hex.neighbor(c, 3), 3))    # 囲み2（対角）→ 包囲0.68
	var b := Combat.defense_breakdown(s, t, s.unit_by_id(2))
	assert_almost_eq(float(b["surround"]), 0.68, 0.001, "対角2体で包囲0.68が防御に乗る")
	assert_lt(float(b["total"]), 80.0, "包囲で実効防御が素の80未満")

func test_hit_detail_fraction_and_loss() -> void:
	# 互角(攻80/防80) → 割合0.5 → 兵8×0.5=4。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var a := Unit.new(1, 0, ap, 3, 8, 10, 10)
	var t := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10)
	s.add_unit(a)
	s.add_unit(t)
	var h := Combat.hit_detail(s, a, t)
	assert_almost_eq(float(h["fraction"]), 0.5, 0.001, "互角は割合0.5")
	assert_eq(h["loss"], 4, "兵8×0.5=4")

# --- 表示と実処理の一致（最重要のガード） ---

func test_attack_detail_matches_applied_damage() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.set_terrain(ap, "plateau")  # 攻撃側を台地に＝非自明な係数を絡める
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 50, 40, 1, "fighter"))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 50, 40, 1, "fighter"))
	var r := s.attack(1, 2)
	var d: Dictionary = r["detail"]
	# 盤の兵数の増減＝detail の loss＝戻り値の damage/retaliation（式が1か所だから必ず一致）
	assert_eq(d["defender"]["troops_before"] - d["defender"]["troops_after"], r["damage"], "防御側の兵減＝damage")
	assert_eq(d["attacker"]["troops_before"] - d["attacker"]["troops_after"], r["retaliation"], "攻撃側の兵減＝retaliation")
	assert_eq(d["to_defender"]["loss"], r["damage"], "to_defender.loss＝damage")
	assert_eq(d["to_attacker"]["loss"], r["retaliation"], "to_attacker.loss＝retaliation")
	# スナップショットは戦闘前の値（撃破後も表示できるよう固める）
	assert_eq(d["attacker"]["level"], 1, "戦闘前レベルを保持（加算前）")
	assert_eq(d["attacker"]["max"], 8)
	assert_eq(d["attacker"]["terrain"], "plateau", "足元の地形を保持")

func test_ranged_detail_has_no_retaliation() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var a := Unit.new(1, 0, ap, 3, 8, 30, 10)
	a.attack_range = 2
	s.add_unit(a)
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(4, 2), 3, 8, 10, 10))  # 距離2
	var r := s.attack(1, 2)
	var d: Dictionary = r["detail"]
	assert_null(d["to_attacker"], "間接は反撃なし→ to_attacker は null")
	assert_not_null(d["to_defender"], "前進ぶんは常にある")
	assert_eq(d["attacker"]["troops_before"] - d["attacker"]["troops_after"], 0, "攻撃側は無傷")
