extends GutTest
## Combat の「明示係数版」(*_from) が、盤ベースの計算と一致することの保証。
## 開発ツール tools/combat_sim はこの *_from 経路で戦闘を再現するので、
## ここが一致していれば「画面の数字＝実戦の数字」が担保される。

func _state() -> BattleState:
	return BattleState.new(8, 8)

# --- 盤ベース と 明示係数版 が同じ内訳・同じ損害を返す ---

func test_from_matches_board_plain() -> void:
	# 平地・Lv1・包囲支援なし・貫通なしの素朴な1対1。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var a := Unit.new(1, 0, ap, 3, 8, 30, 10)
	var t := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 80)
	s.add_unit(a)
	s.add_unit(t)
	var board := Combat.hit_detail(s, a, t)

	var atk := Combat.attack_breakdown_from(8, 30, Combat.experience_at(1), Surround.factor_from_counts(0, 0), TerrainType.attack_factor("plain"), 0.0)
	var df := Combat.defense_breakdown_from(8, 80, Combat.experience_at(1), Surround.factor_from_counts(0, 0), TerrainType.defense_factor("plain"), 0.0, 0.0)
	var sim := Combat.hit_from_breakdowns(atk, df, 8)

	assert_almost_eq(float(sim["attack"]["total"]), float(board["attack"]["total"]), 0.001, "実効攻撃が一致")
	assert_almost_eq(float(sim["defense"]["total"]), float(board["defense"]["total"]), 0.001, "実効防御が一致")
	assert_almost_eq(float(sim["fraction"]), float(board["fraction"]), 0.0001, "割合が一致")
	assert_eq(sim["loss"], board["loss"], "失う兵が一致")

func test_from_matches_board_with_terrain_and_level() -> void:
	# 台地(攻防×1.15)・攻撃側Lv6(×1.40)を絡める。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.set_terrain(ap, "plateau")
	var a := Unit.new(1, 0, ap, 3, 8, 20, 15, 6)
	var t := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 7, 12, 40, 1)
	s.add_unit(a)
	s.add_unit(t)
	var board := Combat.hit_detail(s, a, t)

	var atk := Combat.attack_breakdown_from(8, 20, Combat.experience_at(6), Surround.factor_from_counts(0, 0), TerrainType.attack_factor("plateau"), 0.0)
	var df := Combat.defense_breakdown_from(7, 40, Combat.experience_at(1), Surround.factor_from_counts(0, 0), TerrainType.defense_factor("plain"), 0.0, 0.0)
	var sim := Combat.hit_from_breakdowns(atk, df, 7)

	assert_almost_eq(float(sim["attack"]["total"]), float(board["attack"]["total"]), 0.001, "台地×Lv6の実効攻撃が一致")
	assert_almost_eq(float(sim["defense"]["total"]), float(board["defense"]["total"]), 0.001, "実効防御が一致")
	assert_eq(sim["loss"], board["loss"], "失う兵が一致")

func test_surround_from_counts_matches_board() -> void:
	# 対角2体で囲んだ状況（占有2）を、盤の包囲係数と counts 版で突き合わせ。
	var s := _state()
	var c := Hex.offset_to_axial(4, 4)
	var t := Unit.new(1, 1, c, 3, 8, 10, 10)
	s.add_unit(t)
	s.add_unit(Unit.new(2, 0, Hex.neighbor(c, 0), 3))
	s.add_unit(Unit.new(3, 0, Hex.neighbor(c, 3), 3))
	# 対角2体は占有2に加え、残り4つの隣接マスを両者のZOCが覆う（occ=2, zoc=4）→ 0.68。
	var board_factor := Surround.factor(s, t)
	assert_almost_eq(Surround.factor_from_counts(2, 4), board_factor, 0.0001, "占有2・ZOC4 が盤の係数(0.68)と一致")
