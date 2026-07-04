extends GutTest
## 防御貫通(pierce)の適用と、再調整後ロスターの「対空の担い手」を検証する。
## pierce＝攻撃側が相手の実効防御を pierce ぶん減らす（魔法兵0.5＝防御半減／物理0＝据え置き）。
## 詳細 → doc/gdd/combat.md, doc/gdd/units.md

func _state() -> BattleState:
	return BattleState.new(8, 8)

# --- 防御貫通(pierce) ---

func test_pierce_halves_effective_defense() -> void:
	# 攻撃側 pierce=0.5 → 防御側(高防御40)の実効防御が半減して total に反映。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var mage := Unit.new(1, 0, ap, 3, 8, 40, 30)
	mage.pierce = 0.5
	var zombie := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 40)  # 高防御40
	s.add_unit(mage)
	s.add_unit(zombie)
	var df := Combat.defense_breakdown(s, zombie, mage)  # 防御側=zombie / 攻撃側=mage
	assert_almost_eq(float(df["pierce"]), 0.5, 0.001, "貫通後係数0.5（内訳dict）")
	assert_almost_eq(float(df["total"]), 8.0 * 40.0 * 0.5, 0.01, "実効防御が半減（兵8×防40×0.5＝160）")

func test_pierce_increases_damage_vs_high_defense() -> void:
	# 同条件で pierce=0.5 の攻撃は pierce=0 より高防御相手への損害が大きい。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var atk := Unit.new(1, 0, ap, 3, 8, 40, 30)
	var zombie := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 40)
	s.add_unit(atk)
	s.add_unit(zombie)
	var loss_phys := int(Combat.hit_detail(s, atk, zombie)["loss"])  # pierce=0
	atk.pierce = 0.5
	var loss_mage := int(Combat.hit_detail(s, atk, zombie)["loss"])
	assert_gt(loss_mage, loss_phys, "貫通ありの方が高防御相手に損害が大きい（%d>%d）" % [loss_mage, loss_phys])

func test_no_pierce_is_regression() -> void:
	# pierce=0（物理）は実効防御を変えない＝従来どおり。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var atk := Unit.new(1, 0, ap, 3, 8, 50, 40)  # pierce は既定0.0
	var foe := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 40)
	s.add_unit(atk)
	s.add_unit(foe)
	var df := Combat.defense_breakdown(s, foe, atk)
	assert_almost_eq(float(df["pierce"]), 1.0, 0.001, "貫通なし＝係数1.0")
	assert_almost_eq(float(df["total"]), 8.0 * 40.0, 0.01, "pierce0は実効防御そのまま（320）")

func test_pierce_reflected_in_attack_detail() -> void:
	# 実際の攻撃でも、防御内訳(detail)に貫通係数が出て損害に効く（表示と実処理の一致）。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var mage := Unit.new(1, 0, ap, 3, 8, 40, 30, 1, "wizard")
	mage.pierce = 0.5
	var zombie := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 40)
	s.add_unit(mage)
	s.add_unit(zombie)
	var r := s.attack(1, 2)
	var d: Dictionary = r["detail"]
	assert_almost_eq(float(d["to_defender"]["defense"]["pierce"]), 0.5, 0.001, "detail の防御内訳に貫通係数0.5が出る")

# --- 再調整後ロスター: 対空の担い手（弓兵・飛行・魔法兵に集約） ---

## catalog の type_id から Unit を1体組む（_make_unit と同じ流儀で box フィールドを載せる）。
func _from_type(cat: Dictionary, type_id: String, id: int, team: int, pos: Vector2i) -> Unit:
	var t: UnitType = cat[type_id]
	var u := Unit.new(id, team, pos, t.move, t.max_troops, t.atk_ground, t.defense, 1, type_id)
	u.atk_air = t.atk_air
	u.move_type = t.move_type
	u.attack_range = t.attack_range
	u.pierce = t.pierce
	u.can_capture = t.can_capture
	return u

func test_capture_units_cannot_target_flyer() -> void:
	# 占領兵（パラディン含む）は atk_air=0 → 飛行を攻撃対象にできない。
	var cat := UnitCatalog.load_default()
	for tid in ["cleric", "priest", "bishop", "paladin"]:
		var s := _state()
		var ap := Hex.offset_to_axial(2, 2)
		s.add_unit(_from_type(cat, tid, 1, 0, ap))
		s.add_unit(_from_type(cat, "dragon", 2, 1, Hex.neighbor(ap, 0)))  # dragon=飛行
		assert_false(s.can_attack(1, 2), "%s は対空0で飛行を狙えない" % tid)

func test_mages_and_archers_can_target_flyer() -> void:
	# 魔法兵・弓兵は対空ありで飛行を攻撃できる。
	var cat := UnitCatalog.load_default()
	for tid in ["wizard", "witch", "archer", "hunter", "elf"]:
		var s := _state()
		var ap := Hex.offset_to_axial(2, 2)
		s.add_unit(_from_type(cat, tid, 1, 0, ap))
		s.add_unit(_from_type(cat, "dragon", 2, 1, Hex.neighbor(ap, 0)))
		assert_true(s.can_attack(1, 2), "%s は対空ありで飛行を狙える" % tid)
