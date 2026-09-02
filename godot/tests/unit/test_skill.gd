extends GutTest
## ユニットスキル（単独発動・味方1体を強化）＝成立・対象の絞り込み・適用・持続を検証する。
## 仕組みは陣形スキルと共通（Formation のレシピとして持つ）。詳細 → doc/gdd/skills.md

func _state() -> BattleState:
	return BattleState.new(10, 8)

# ピクシー1体＋隣接する味方＋離れた味方＋隣接する敵。leader=pixie(id1)。
func _dust_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var pixie := Unit.new(1, 0, c, 5, 8, 10, 10, 1, "pixie")
	var near := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 40, 40, 1, "fighter")
	var far := Unit.new(3, 0, Hex.offset_to_axial(8, 6), 3, 8, 40, 40, 1, "fighter")
	var foe := Unit.new(4, 1, Hex.neighbor(c, 3), 3, 8, 30, 30)
	for u in [pixie, near, far, foe]:
		s.add_unit(u)
	return {"s": s, "pixie": pixie, "near": near, "far": far, "foe": foe}

func _dust_option(f: Dictionary) -> Dictionary:
	for o in Formation.available_for(f["s"], f["pixie"]):
		if String(o["recipe"]) == "pixie_dust":
			return o
	return {}

# --- 成立と対象の絞り込み ---

func test_offered_by_pixie_alone() -> void:
	var f := _dust_state()
	var o := _dust_option(f)
	assert_false(o.is_empty(), "ピクシー単独で成立する")
	assert_eq(int(o["leader_id"]), 1, "発動者はピクシー")
	assert_eq((o["participants"] as Array).size(), 1, "参加者は発動者だけ")
	assert_true(bool(o["needs_target"]), "掛ける相手を選ぶ")

func test_not_offered_by_other_types() -> void:
	var f := _dust_state()
	var found := false
	for o in Formation.available_for(f["s"], f["near"]):  # fighter（ピクシーの隣に居る）
		if String(o["recipe"]) == "pixie_dust":
			found = true
	assert_false(found, "ピクシー以外は撃てない")

## 発動者の照合もスキンID（→ doc/gdd/skills.md 共通ルール）。性能が pixie でも別スキンなら撃てない。
func test_not_offered_by_other_skin() -> void:
	var f := _dust_state()
	f["pixie"].skin_id = "harpy"
	assert_true(_dust_option(f).is_empty(), "pixie 性能でも別スキンなら撃てない")

func test_target_self_and_adjacent_ally_only() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var o := _dust_option(f)
	assert_true(Formation.can_target(s, o, f["pixie"].pos), "自分自身に掛けられる")
	assert_true(Formation.can_target(s, o, f["near"].pos), "隣接する味方に掛けられる")
	assert_false(Formation.can_target(s, o, f["far"].pos), "離れた味方には掛けられない")
	assert_false(Formation.can_target(s, o, f["foe"].pos), "隣接でも敵には掛けられない")
	assert_false(Formation.can_target(s, o, Hex.neighbor(f["pixie"].pos, 1)), "空きマスには掛けられない")

## 発動者は移動してから撃てる（陣形・ユニットスキルとも同じ規則 → doc/gdd/formations.md）。
func test_can_cast_after_moving() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var far: Unit = f["far"]
	var o := _dust_option(f)
	assert_eq(String(o["kind"]), "skill", "ユニットスキル扱い")
	assert_false(Formation.can_target(s, o, far.pos), "移動前は離れた味方に届かない")
	assert_true(s.move_unit(1, far.pos + Vector2i(-1, 0)), "far の隣へ飛ぶ")
	assert_true(Formation.can_target(s, o, far.pos), "移動先から隣接になれば掛けられる")
	assert_true(s.has_action_left(1), "移動しただけでは行動を使い切らない")
	assert_false(s.resolve_formation(o, far.pos).is_empty(), "移動後に発動できる")
	assert_true(s.is_done(1), "発動者は行動完了")

func test_cluster_recipe_is_a_formation() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var leader: Unit = null
	for i in 5:  # グレイス＝聖職5体の隣接クラスタ
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		if i == 0:
			leader = u
	var opts := Formation.available_for(s, leader)
	assert_gt(opts.size(), 0, "グレイスが成立している前提")
	assert_eq(String(opts[0]["kind"]), "formation", "陣形スキル扱い（表示ラベルの出し分け）")

# --- 適用 ---

func test_buffs_only_the_chosen_unit() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var far: Unit = f["far"]
	var foe: Unit = f["foe"]
	var near_before := float(Combat.attack_breakdown(s, near, foe, true)["total"])
	var far_before := float(Combat.attack_breakdown(s, far, foe, true)["total"])
	assert_false(s.resolve_formation(_dust_option(f), near.pos).is_empty(), "発動成功")
	assert_almost_eq(float(Combat.attack_breakdown(s, near, foe, true)["total"]), near_before + 10.0 * near.troops, 0.001,
		"対象の実効攻撃力に 10×残兵数 が乗る")
	assert_almost_eq(float(Combat.attack_breakdown(s, far, foe, true)["total"]), far_before, 0.001, "他の味方には乗らない")

func test_buffs_defense_too() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var foe: Unit = f["foe"]
	var before := float(Combat.defense_breakdown(s, near, foe, true)["total"])
	assert_false(s.resolve_formation(_dust_option(f), near.pos).is_empty(), "発動成功")
	assert_almost_eq(float(Combat.defense_breakdown(s, near, foe, true)["total"]), before + 10.0 * near.troops, 0.001,
		"防御にも同じだけ乗る")

func test_caster_is_done() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	assert_false(s.resolve_formation(_dust_option(f), f["near"].pos).is_empty(), "発動成功")
	assert_true(s.is_done(1), "発動者は行動完了")
	assert_false(s.is_done(2), "掛けられた側は行動を消費しない")

func test_self_target() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var pixie: Unit = f["pixie"]
	assert_false(s.resolve_formation(_dust_option(f), pixie.pos).is_empty(), "自分に掛けられる")
	# 掛けた本人は発動で Lv も+1されるので、実効防御の前後差にはレベル補正が混ざる。
	# 見たいのは粉が自分に乗ったかどうかなので、状態補正の集計で測る。
	assert_almost_eq(float(s.status_aggregate(pixie, "defense")["add"]), 10.0 * pixie.troops, 0.001,
		"自分の防御に乗る")

# --- 残兵数への追随・重ねがけ・持続 ---

## 強さを決めるのは掛ける側（ピクシー）の残兵数。掛けられる側の兵数は関係しない。
func test_bonus_scales_with_caster_troops() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var pixie: Unit = f["pixie"]
	var near: Unit = f["near"]
	pixie.troops = 4  # 損耗したピクシーが撒く粉は薄い
	near.troops = 2   # 掛けられる側の兵数は効果に影響しない
	assert_false(s.resolve_formation(_dust_option(f), near.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 40.0, 0.001, "ピクシー4体なら +40")
	assert_almost_eq(float(s.status_aggregate(near, "defense")["add"]), 40.0, 0.001, "防御側も同じ")

## 値は発動時に確定する＝掛けた後にピクシーが削られても倒されても変わらない。
func test_bonus_fixed_at_cast() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var pixie: Unit = f["pixie"]
	var near: Unit = f["near"]
	assert_false(s.resolve_formation(_dust_option(f), near.pos).is_empty(), "満員8体で発動")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "+80")
	pixie.troops = 2  # 発動後に損耗
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "掛けた後は動かない")

func test_stacking_adds_up() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var foe: Unit = f["foe"]
	var before := float(Combat.attack_breakdown(s, near, foe, true)["total"])
	var second := Unit.new(5, 0, Hex.neighbor(near.pos, 2), 5, 8, 10, 10, 1, "pixie")  # near の隣の2体目
	s.add_unit(second)
	assert_false(s.resolve_formation(_dust_option(f), near.pos).is_empty(), "1体目が発動")
	var opts := Formation.available_for(s, second)
	assert_gt(opts.size(), 0, "2体目も撃てる")
	assert_false(s.resolve_formation(opts[0], near.pos).is_empty(), "同じ相手に重ねられる")
	assert_almost_eq(float(Combat.attack_breakdown(s, near, foe, true)["total"]), before + 160.0, 0.001, "+80 が2つで +160")

func test_expires_after_three_rounds() -> void:
	# 持続は自軍ターン3回ぶん（doc/gdd/skills.md ①）。敵ターンでは減らない。
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var foe: Unit = f["foe"]
	var before := float(Combat.attack_breakdown(s, near, foe, true)["total"])
	assert_false(s.resolve_formation(_dust_option(f), near.pos).is_empty(), "発動成功")
	for round_index in 3:
		s.end_turn()  # 敵ターンへ
		assert_almost_eq(float(Combat.attack_breakdown(s, near, foe, true)["total"]), before + 80.0, 0.001,
			"敵ターン中はまだ効く（%d周目）" % (round_index + 1))
		if round_index < 2:
			s.end_turn()  # 次の自軍ターンへ＝まだ残っている
			assert_almost_eq(float(Combat.attack_breakdown(s, near, foe, true)["total"]), before + 80.0, 0.001,
				"自軍ターン %d 回目もまだ効く" % (round_index + 2))
	s.end_turn()  # 3回ぶん使い切った次の自軍ターン＝満了
	assert_almost_eq(float(Combat.attack_breakdown(s, near, foe, true)["total"]), before, 0.001, "自軍ターン3回ぶんで切れる")

# --- ④ドレッドタッチ（単体弱体・対象は敵）---

# ゴースト1体＋隣接する敵＋離れた敵＋隣接する味方。leader=ghost(id1)。
# ゴーストは pixie 性能を借りた別スキン＝skin_id で照合される（→ doc/gdd/skills.md 共通ルール）。
func _dread_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var ghost := Unit.new(1, 0, c, 5, 8, 10, 10, 1, "pixie")
	ghost.skin_id = "ghost"
	var foe := Unit.new(2, 1, Hex.neighbor(c, 0), 6, 8, 50, 40, 1, "fighter")
	var far_foe := Unit.new(3, 1, Hex.offset_to_axial(8, 6), 6, 8, 50, 40, 1, "fighter")
	var ally := Unit.new(4, 0, Hex.neighbor(c, 3), 6, 8, 50, 40, 1, "fighter")
	for u in [ghost, foe, far_foe, ally]:
		s.add_unit(u)
	return {"s": s, "ghost": ghost, "foe": foe, "far_foe": far_foe, "ally": ally}

func _dread_option(f: Dictionary) -> Dictionary:
	for o in Formation.available_for(f["s"], f["ghost"]):
		if String(o["recipe"]) == "dread_touch":
			return o
	return {}

func test_dread_offered_by_ghost_alone() -> void:
	var f := _dread_state()
	var o := _dread_option(f)
	assert_false(o.is_empty(), "ゴースト単独で成立する")
	assert_eq(String(o["kind"]), "skill", "ユニットスキル扱い")
	assert_eq(String(o["buff_kind"]), "debuff", "弱体＝ピュリファイが落とす対象")

## ピクシー性能を借りているだけなので、ピクシーダストは撃てない（照合はスキンID）。
func test_ghost_cannot_cast_pixie_dust() -> void:
	var f := _dread_state()
	var found := false
	for o in Formation.available_for(f["s"], f["ghost"]):
		if String(o["recipe"]) == "pixie_dust":
			found = true
	assert_false(found, "ゴーストはピクシーダストを撃てない")

func test_dread_targets_adjacent_enemy_only() -> void:
	var f := _dread_state()
	var s: BattleState = f["s"]
	var o := _dread_option(f)
	assert_true(Formation.can_target(s, o, f["foe"].pos), "隣接する敵に掛けられる")
	assert_false(Formation.can_target(s, o, f["far_foe"].pos), "離れた敵には掛けられない")
	assert_false(Formation.can_target(s, o, f["ally"].pos), "隣接でも味方には掛けられない")
	assert_false(Formation.can_target(s, o, f["ghost"].pos), "自分自身は選べない")
	assert_false(Formation.can_target(s, o, Hex.neighbor(f["ghost"].pos, 1)), "空きマスには掛けられない")

func test_dread_lowers_attack_and_defense() -> void:
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var ghost: Unit = f["ghost"]
	var atk_before := float(Combat.attack_breakdown(s, foe, ghost, true)["total"])
	var def_before := float(Combat.defense_breakdown(s, foe, ghost, true)["total"])
	assert_false(s.resolve_formation(_dread_option(f), foe.pos).is_empty(), "発動成功")
	assert_almost_eq(float(Combat.attack_breakdown(s, foe, ghost, true)["total"]), atk_before - 80.0, 0.001,
		"満員のゴーストなら実効攻撃力が -80")
	assert_almost_eq(float(Combat.defense_breakdown(s, foe, ghost, true)["total"]), def_before - 80.0, 0.001,
		"防御にも同じだけ効く")

## 強さを決めるのは掛ける側（ゴースト）の残兵数＝削れば効きが薄くなる。
func test_dread_scales_with_caster_troops() -> void:
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	f["ghost"].troops = 3
	assert_false(s.resolve_formation(_dread_option(f), foe.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["add"]), -30.0, 0.001, "ゴースト3体なら -30")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["add"]), -30.0, 0.001, "防御側も同じ")

func test_dread_expires_after_three_rounds() -> void:
	# 持続は発動側ターン3回ぶん（doc/gdd/skills.md ④）。相手ターンでは減らない。
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var ghost: Unit = f["ghost"]
	var before := float(Combat.attack_breakdown(s, foe, ghost, true)["total"])
	assert_false(s.resolve_formation(_dread_option(f), foe.pos).is_empty(), "発動成功")
	for round_index in 3:
		s.end_turn()  # 相手ターンへ
		assert_almost_eq(float(Combat.attack_breakdown(s, foe, ghost, true)["total"]), before - 80.0, 0.001,
			"相手ターン中は効いている（%d周目）" % (round_index + 1))
		if round_index < 2:
			s.end_turn()  # 次の発動側ターンへ＝まだ残っている
			assert_almost_eq(float(Combat.attack_breakdown(s, foe, ghost, true)["total"]), before - 80.0, 0.001,
				"発動側ターン %d 回目もまだ効く" % (round_index + 2))
	s.end_turn()  # 3回ぶん使い切った次の発動側ターン＝満了
	assert_almost_eq(float(Combat.attack_breakdown(s, foe, ghost, true)["total"]), before, 0.001, "発動側ターン3回ぶんで切れる")

# --- ②ヴェノムファング（単体弱体・係数型）---

# ロックサーペント1体＋隣接する敵＋離れた敵＋隣接する味方。leader=rock_serpent(id1)。
func _venom_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var serpent := Unit.new(1, 0, c, 7, 8, 20, 20, 1, "scout")
	serpent.skin_id = "rock_serpent"
	var foe := Unit.new(2, 1, Hex.neighbor(c, 0), 6, 8, 50, 40, 1, "fighter")
	var far_foe := Unit.new(3, 1, Hex.offset_to_axial(8, 6), 6, 8, 50, 40, 1, "fighter")
	var ally := Unit.new(4, 0, Hex.neighbor(c, 3), 6, 8, 50, 40, 1, "fighter")
	for u in [serpent, foe, far_foe, ally]:
		s.add_unit(u)
	return {"s": s, "serpent": serpent, "foe": foe, "far_foe": far_foe, "ally": ally}

func _venom_option(f: Dictionary) -> Dictionary:
	for o in Formation.available_for(f["s"], f["serpent"]):
		if String(o["recipe"]) == "venom_fang":
			return o
	return {}

func test_venom_offered_by_rock_serpent_alone() -> void:
	var f := _venom_state()
	var o := _venom_option(f)
	assert_false(o.is_empty(), "ロックサーペント単独で成立する")
	assert_eq(String(o["kind"]), "skill", "ユニットスキル扱い")
	assert_eq(String(o["buff_kind"]), "debuff", "弱体＝ピュリファイが落とす対象")

func test_venom_not_offered_by_other_skins() -> void:
	var f := _venom_state()
	var found := false
	for o in Formation.available_for(f["s"], f["ally"]):  # fighter
		if String(o["recipe"]) == "venom_fang":
			found = true
	assert_false(found, "ロックサーペント以外は撃てない")

func test_venom_targets_adjacent_enemy_only() -> void:
	var f := _venom_state()
	var s: BattleState = f["s"]
	var o := _venom_option(f)
	assert_true(Formation.can_target(s, o, f["foe"].pos), "隣接する敵に掛けられる")
	assert_false(Formation.can_target(s, o, f["far_foe"].pos), "離れた敵には掛けられない")
	assert_false(Formation.can_target(s, o, f["ally"].pos), "隣接でも味方には掛けられない")
	assert_false(Formation.can_target(s, o, f["serpent"].pos), "自分自身は選べない")

func test_venom_lowers_attack_and_defense_by_mul() -> void:
	var f := _venom_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_venom_option(f), foe.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 0.9, 0.001,
		"1本で攻撃に ×0.9")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["mul"]), 0.9, 0.001,
		"防御にも ×0.9")

## 係数は固定（0.9）＝発動者の残兵数に依らない。ドレッドタッチ（add・残兵依存）との違い。
func test_venom_value_independent_of_caster_troops() -> void:
	var f := _venom_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	f["serpent"].troops = 3  # 損耗しても係数は変わらない
	assert_false(s.resolve_formation(_venom_option(f), foe.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 0.9, 0.001,
		"3体でも ×0.9（残兵に依らない）")

## 重ねがけは掛け合わさる＝0.9×0.9=0.81。加算（ドレッドタッチ）と違い 0 にはならない。
func test_venom_stacking_multiplies() -> void:
	var f := _venom_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var second := Unit.new(5, 0, Hex.neighbor(foe.pos, 2), 7, 8, 20, 20, 1, "scout")
	second.skin_id = "rock_serpent"
	s.add_unit(second)
	assert_false(s.resolve_formation(_venom_option(f), foe.pos).is_empty(), "1体目が発動")
	var opts := Formation.available_for(s, second)
	var o2 := {}
	for o in opts:
		if String(o["recipe"]) == "venom_fang":
			o2 = o
	assert_false(o2.is_empty(), "2体目も撃てる")
	assert_false(s.resolve_formation(o2, foe.pos).is_empty(), "同じ相手に重ねられる")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 0.81, 0.001,
		"2本で ×0.81（0.9×0.9）")

func test_venom_expires_after_three_rounds() -> void:
	var f := _venom_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_venom_option(f), foe.pos).is_empty(), "発動成功")
	for round_index in 3:
		s.end_turn()  # 相手ターンへ
		assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 0.9, 0.001,
			"相手ターン中は効いている（%d周目）" % (round_index + 1))
		if round_index < 2:
			s.end_turn()  # 次の発動側ターンへ＝まだ残っている
			assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 0.9, 0.001,
				"発動側ターン %d 回目もまだ効く" % (round_index + 2))
	s.end_turn()  # 3回ぶん使い切った次の発動側ターン＝満了
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 1.0, 0.001,
		"発動側ターン3回ぶんで切れる")

# --- ⑤スライムスプリット（分裂・駒生成）---

# スライム1体＋周囲に空きマスがある配置。leader=slime(id1)。
# スライムは敵（team=1）なので end_turn で敵ターンに進めてから使う。
func _split_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	s.end_turn()  # 敵ターン（team=1）に進める
	s.set_charge(slime.id, "slime_split", 3)  # チャージ済み（即発動できる状態）
	return {"s": s, "slime": slime}

func _split_option(f: Dictionary) -> Dictionary:
	for o in Formation.available_for(f["s"], f["slime"]):
		if String(o["recipe"]) == "slime_split":
			return o
	return {}

func test_split_offered_by_slime_alone() -> void:
	var f := _split_state()
	var o := _split_option(f)
	assert_false(o.is_empty(), "スライム単独で成立する")
	assert_eq(String(o["kind"]), "skill", "ユニットスキル扱い")
	assert_false(bool(o["needs_target"]), "対象選択は不要")

func test_split_not_offered_by_other_skins() -> void:
	var f := _split_state()
	var fighter := Unit.new(2, 1, Hex.neighbor(f["slime"].pos, 0), 6, 8, 50, 40, 1, "fighter")
	f["s"].add_unit(fighter)
	var found := false
	for o in Formation.available_for(f["s"], fighter):
		if String(o["recipe"]) == "slime_split":
			found = true
	assert_false(found, "スライム以外は撃てない")

func test_split_spawns_a_unit() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	var before_count := s.units().size()
	var result := s.resolve_formation(_split_option(f), Vector2i.ZERO)
	assert_false(result.is_empty(), "発動成功")
	assert_eq(s.units().size(), before_count + 1, "駒が1体増える")

func test_split_inherits_troops() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	f["slime"].troops = 5  # 損耗した状態で分裂
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	var spawned: Unit = null
	for u in s.units():
		if u.id != f["slime"].id:
			spawned = u
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(spawned.troops, 5, "兵数は発動者の現在値を引き継ぐ")
	assert_eq(spawned.max_troops, 8, "max_troops は type の既定値")

func test_split_spawned_is_done() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	var spawned: Unit = null
	for u in s.units():
		if u.id != f["slime"].id:
			spawned = u
	assert_not_null(spawned, "新しい駒が居る")
	assert_true(s.is_done(spawned.id), "生まれたターンは行動済み")

func test_split_caster_is_done() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	assert_true(s.is_done(f["slime"].id), "発動者は行動完了")

func test_split_caster_gains_no_level() -> void:
	# 共通ルール「発動者は Lv+1」の例外＝分裂ではレベルが上がらない。詳細 → doc/gdd/skills.md ⑤
	var f := _split_state()
	var s: BattleState = f["s"]
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	assert_eq((f["slime"] as Unit).level, 1, "分裂ではレベルが上がらない")

func test_split_result_cells_hold_spawned_hex() -> void:
	# 湧いた位置は cells で返る＝盤はこれを光らせる（演出シーンは出さない）。詳細 → doc/gdd/skills.md ⑤
	var f := _split_state()
	var s: BattleState = f["s"]
	var result := s.resolve_formation(_split_option(f), Vector2i.ZERO)
	var spawned: Unit = null
	for u in s.units():
		if u.id != f["slime"].id:
			spawned = u
	assert_not_null(spawned, "新しい駒が居る")
	var cells: Array = result["cells"]
	assert_eq(cells.size(), 1, "光らせる面は湧いた1マスだけ")
	assert_true(spawned.pos in cells, "湧いた位置が cells に入る")

func test_split_spawned_inherits_skin_and_type() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	var spawned: Unit = null
	for u in s.units():
		if u.id != f["slime"].id:
			spawned = u
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(spawned.skin_id, "slime", "skin_id を引き継ぐ")
	assert_eq(spawned.type_id, "slime", "type_id を引き継ぐ")
	assert_eq(spawned.team, f["slime"].team, "陣営を引き継ぐ")

func test_split_id_does_not_collide() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	# 既存の id より大きい id を持つ駒を足す
	var other := Unit.new(100, 1, Hex.offset_to_axial(7, 7), 2, 8, 20, 20, 1, "slime")
	s.add_unit(other)
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	var spawned: Unit = null
	for u in s.units():
		if u.id != f["slime"].id and u.id != 100:
			spawned = u
	assert_not_null(spawned, "新しい駒が居る")
	assert_gt(spawned.id, 100, "既存の最大 id より大きい")

## 隣接に空きマスが無ければメニューに出ない＝発動できない。
func test_split_not_offered_when_surrounded() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	var slime: Unit = f["slime"]
	# 6方向すべてに駒を置いて埋める
	for dir in 6:
		var nb := Hex.neighbor(slime.pos, dir)
		s.add_unit(Unit.new(10 + dir, 1, nb, 2, 8, 20, 20, 1, "fighter"))
	assert_true(_split_option(f).is_empty(), "隣接が全部埋まっていると成立しない")

## 殲滅勝利の判定に分裂で増えた駒が含まれる（全滅させないと勝てない）。
func test_split_spawned_counts_for_annihilation() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	assert_eq(s.team_unit_count(1), 2, "敵の駒数が2に増えている")

# --- ③ピュリファイ（有害な補正の解除）---

# プリースト＋隣接する味方＋離れた味方＋隣接する敵。leader=priest(id1)。
func _purify_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var priest := Unit.new(1, 0, c, 2, 8, 40, 20, 1, "priest")
	var near := Unit.new(2, 0, Hex.neighbor(c, 0), 6, 8, 50, 40, 1, "fighter")
	var far := Unit.new(3, 0, Hex.offset_to_axial(8, 6), 6, 8, 50, 40, 1, "fighter")
	var foe := Unit.new(4, 1, Hex.neighbor(c, 3), 6, 8, 50, 40, 1, "fighter")
	for u in [priest, near, far, foe]:
		s.add_unit(u)
	return {"s": s, "priest": priest, "near": near, "far": far, "foe": foe}

func _purify_option(f: Dictionary) -> Dictionary:
	for o in Formation.available_for(f["s"], f["priest"]):
		if String(o["recipe"]) == "purify":
			return o
	return {}

## near に有害な弱体（ドレッドタッチ相当）と無害な強化（ピクシーダスト相当）を1つずつ掛ける。
func _afflict(s: BattleState, u: Unit) -> void:
	s.add_status_mod({"scope": "unit", "unit_id": u.id, "op": "add", "target": "both",
		"value": -80.0, "owner_team": 1, "remaining": 1, "name": "ドレッドタッチ", "kind": "debuff"})
	s.add_status_mod({"scope": "unit", "unit_id": u.id, "op": "add", "target": "both",
		"value": 80.0, "owner_team": 0, "remaining": 1, "name": "ピクシーダスト", "kind": "buff"})

func test_purify_offered_by_clergy_alone() -> void:
	var f := _purify_state()
	var o := _purify_option(f)
	assert_false(o.is_empty(), "聖職単独で成立する")
	assert_eq(String(o["kind"]), "skill", "ユニットスキル扱い")
	assert_true(bool(o["needs_target"]), "掛ける相手を選ぶ")

func test_purify_not_offered_by_others() -> void:
	var f := _purify_state()
	var found := false
	for o in Formation.available_for(f["s"], f["near"]):  # fighter
		if String(o["recipe"]) == "purify":
			found = true
	assert_false(found, "聖職以外は撃てない")

func test_purify_targets_self_and_adjacent_ally_only() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var o := _purify_option(f)
	# 弱体が掛かっていなければ味方でも対象にならない（落とすものが無い）
	assert_false(Formation.can_target(s, o, f["priest"].pos), "弱体の無い自分には掛けられない")
	assert_false(Formation.can_target(s, o, f["near"].pos), "弱体の無い味方には掛けられない")
	for u in [f["priest"], f["near"], f["far"], f["foe"]]:
		_afflict(s, u)
	assert_true(Formation.can_target(s, o, f["priest"].pos), "弱体の掛かった自分自身に掛けられる")
	assert_true(Formation.can_target(s, o, f["near"].pos), "弱体の掛かった隣接する味方に掛けられる")
	assert_false(Formation.can_target(s, o, f["far"].pos), "離れた味方には掛けられない")
	assert_false(Formation.can_target(s, o, f["foe"].pos), "敵には掛けられない（弱体があっても）")
	assert_false(Formation.can_target(s, o, Hex.neighbor(f["priest"].pos, 1)), "空きマスには掛けられない")

## 撃てる先＝弱体の掛かった味方だけ。誰にも掛かっていなければ空＝メニューは項目を無効化する。
func test_purify_targetable_cells_only_debuffed_allies() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var o := _purify_option(f)
	assert_true(Formation.targetable_cells(s, o).is_empty(), "弱体が誰にも無ければ撃てる先は無い")
	_afflict(s, f["near"])
	var cells := Formation.targetable_cells(s, o)
	assert_eq(cells.size(), 1, "弱体の掛かった味方1体だけ")
	assert_true(f["near"].pos in cells, "それは near")

## 味方から掛かった強化しか無い駒は対象にならない（落とすのは弱体だけ）。
func test_purify_ignores_buff_only_ally() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	s.add_status_mod({"scope": "unit", "unit_id": near.id, "op": "add", "target": "both",
		"value": 80.0, "owner_team": 0, "remaining": 1, "kind": "buff"})
	assert_false(Formation.can_target(s, _purify_option(f), near.pos), "強化だけの味方には掛けられない")

## 移動先を仮定した判定でも弱体の有無を見る（自分に掛かった弱体は移動先でも付いてくる）。
func test_purify_can_target_self_from_move_destination() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var priest: Unit = f["priest"]
	var o := _purify_option(f)
	var dest: Vector2i = Hex.neighbor(priest.pos, 1)
	assert_false(Formation.can_target(s, o, dest, dest), "弱体が無ければ移動先の自分にも掛けられない")
	_afflict(s, priest)
	assert_true(Formation.can_target(s, o, dest, dest), "弱体があれば移動先の自分に掛けられる")

# --- ユニットスキルの一覧（情報パネルの能力タブが読む）---

func test_unit_skills_of_lists_solo_recipes_by_skin() -> void:
	var f := _purify_state()
	assert_eq(Formation.unit_skills_of(f["priest"]), ["purify"] as Array[String], "プリーストはピュリファイ")
	assert_true(Formation.unit_skills_of(f["near"]).is_empty(), "ファイターは持たない")
	var pixie := Unit.new(9, 0, Hex.offset_to_axial(1, 1), 8, 8, 10, 10, 5, "pixie")
	assert_eq(Formation.unit_skills_of(pixie), ["pixie_dust"] as Array[String], "ピクシーはピクシーダスト")
	assert_true(Formation.unit_skills_of(null).is_empty(), "null は空")

func test_purify_drops_debuffs_and_keeps_buffs() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	_afflict(s, near)
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 0.0, 0.001, "掛ける前は -80 と +80 で相殺")
	assert_false(s.resolve_formation(_purify_option(f), near.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "弱体だけ落ちて強化は残る")
	assert_almost_eq(float(s.status_aggregate(near, "defense")["add"]), 80.0, 0.001, "防御側も同じ")

## 掛けられた数がいくつでも1回の発動で全部落ちる（ヴェノムファングが3本刺さっていても1回で済む）。
func test_purify_drops_every_debuff_at_once() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	for i in 3:
		s.add_status_mod({"scope": "unit", "unit_id": near.id, "op": "add", "target": "both",
			"value": -50.0, "owner_team": 1, "remaining": 1, "kind": "debuff"})
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), -150.0, 0.001, "3本で -150")
	assert_false(s.resolve_formation(_purify_option(f), near.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 0.0, 0.001, "1回で全部落ちる")

## 落とすのは対象1体ぶんだけ＝他の味方に掛かった弱体や、陣営全体の補正は動かさない。
func test_purify_touches_only_the_target() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var far: Unit = f["far"]
	_afflict(s, near)
	_afflict(s, far)
	s.add_status_mod({"scope": "team", "team": 0, "op": "mul", "target": "both",
		"value": 0.7, "owner_team": 1, "remaining": 1, "kind": "debuff"})
	assert_false(s.resolve_formation(_purify_option(f), near.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "対象の弱体は落ちる")
	assert_almost_eq(float(s.status_aggregate(far, "attack")["add"]), 0.0, 0.001, "離れた味方の弱体は残る")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["mul"]), 0.7, 0.001, "陣営全体の補正は1人のピュリファイでは落ちない")

func test_purify_consumes_the_casters_action() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	_afflict(s, near)
	assert_false(s.resolve_formation(_purify_option(f), near.pos).is_empty(), "発動成功")
	assert_true(s.is_done(1), "発動者は行動完了")
	assert_false(s.is_done(2), "掛けられた側は行動を消費しない")
	assert_eq(f["priest"].level, 2, "発動者に Lv+1（撃破は起きないので前半だけ）")

# --- チャージ（再使用間隔）---

## チャージ量 0 のスライムはスライムスプリットを撃てない。
func test_charge_blocks_uncharged_skill() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	s.end_turn()  # 敵ターン
	# チャージ未設定（0）＝撃てない
	var found := false
	for o in Formation.available_for(s, slime):
		if String(o["recipe"]) == "slime_split":
			found = true
	assert_false(found, "チャージ量 0 では成立しない")

## チャージ量が必要量に達すると発動できる。
func test_charge_allows_when_full() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	s.end_turn()  # 敵ターン
	s.set_charge(slime.id, "slime_split", 3)
	var found := false
	for o in Formation.available_for(s, slime):
		if String(o["recipe"]) == "slime_split":
			found = true
	assert_true(found, "チャージ量が必要量に達すれば成立する")

## チャージ量が必要量未満だと撃てない（1足りない）。
func test_charge_blocks_when_short() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	s.end_turn()
	s.set_charge(slime.id, "slime_split", 2)  # 3 が必要だが 2 しか溜まっていない
	var found := false
	for o in Formation.available_for(s, slime):
		if String(o["recipe"]) == "slime_split":
			found = true
	assert_false(found, "チャージ量が足りなければ成立しない")

## 毎ターン開始時にチャージ量が +1 される。
func test_charge_increments_each_turn() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	assert_eq(s.get_charge(slime.id, "slime_split"), 0, "初期値は 0")
	# team=0 のターンを終了 → team=1 のターン開始（敵ターン）＝敵駒のチャージが +1
	s.end_turn()
	assert_eq(s.get_charge(slime.id, "slime_split"), 1, "1ターン目で +1")
	s.end_turn()  # team=1 → team=0（プレイヤーターン）＝敵は増えない
	assert_eq(s.get_charge(slime.id, "slime_split"), 1, "相手ターンでは増えない")
	s.end_turn()  # team=0 → team=1（敵ターン）
	assert_eq(s.get_charge(slime.id, "slime_split"), 2, "2ターン目で +1")

## 発動するとチャージ量が 0 に戻る。
func test_charge_resets_on_use() -> void:
	var f := _split_state()  # チャージ3で即発動可
	var s: BattleState = f["s"]
	assert_eq(s.get_charge(f["slime"].id, "slime_split"), 3, "発動前は 3")
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	assert_eq(s.get_charge(f["slime"].id, "slime_split"), 0, "発動後は 0 に戻る")

## 分裂で生まれた駒のチャージ量は 0（溜まるまで撃てない）。
func test_charge_spawned_starts_at_zero() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.resolve_formation(_split_option(f), Vector2i.ZERO)
	var spawned: Unit = null
	for u in s.units():
		if u.id != f["slime"].id:
			spawned = u
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(s.get_charge(spawned.id, "slime_split"), 0, "生まれた駒のチャージ量は 0")

## 3ターン溜めれば盤に出た直後の駒でも発動できる（初期 0 → 3ターンで 3）。
func test_charge_accumulates_to_threshold() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	# 3ターンぶんのサイクルを回す（player→enemy→player→enemy→player→enemy）
	for i in 3:
		s.end_turn()  # → enemy turn: charge +1
		s.end_turn()  # → player turn: charge stays
	assert_eq(s.get_charge(slime.id, "slime_split"), 3, "3ターンで必要量に達する")
	var found := false
	for o in Formation.available_for(s, slime):
		if String(o["recipe"]) == "slime_split":
			found = true
	assert_true(found, "必要量に達したので発動できる")

## チャージ量は中断セーブに乗る（to_save_diff → apply_save_diff で往復）。
func test_charge_survives_serialization() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	s.set_charge(slime.id, "slime_split", 2)
	var restored := _state()  # 同じ器（盤サイズ）を組み直して差分を被せる＝実際の再開と同じ形
	restored.apply_save_diff(s.to_save_diff())
	assert_eq(restored.get_charge(slime.id, "slime_split"), 2, "復元後もチャージ量が保たれる")

# --- ⑥ポイズンスティング（継続ダメージ）。詳細 → doc/gdd/skills.md ---

# スコーピオン1体（敵team=1）＋隣接する味方2体＋離れた味方＋隣接する仲間の蠍。
# 発動側を敵にするのは、対象側（プレイヤー）のターン開始で減ることを確かめるため。
func _sting_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var scorpion := Unit.new(1, 1, c, 5, 8, 50, 70, 1, "knight")
	scorpion.skin_id = "scorpion"
	var foe := Unit.new(2, 0, Hex.neighbor(c, 0), 6, 8, 50, 40, 1, "fighter")
	var far_foe := Unit.new(3, 0, Hex.offset_to_axial(8, 6), 6, 8, 50, 40, 1, "fighter")
	var ally := Unit.new(4, 1, Hex.neighbor(c, 3), 6, 8, 50, 40, 1, "fighter")
	for u in [scorpion, foe, far_foe, ally]:
		s.add_unit(u)
	s.end_turn()  # 敵ターン（team=1）へ
	return {"s": s, "scorpion": scorpion, "foe": foe, "far_foe": far_foe, "ally": ally}

func _sting_option(f: Dictionary) -> Dictionary:
	for o in Formation.available_for(f["s"], f["scorpion"]):
		if String(o["recipe"]) == "poison_sting":
			return o
	return {}

func test_sting_offered_by_scorpion_alone() -> void:
	var f := _sting_state()
	var o := _sting_option(f)
	assert_false(o.is_empty(), "スコーピオン単独で成立する")
	assert_eq(String(o["kind"]), "skill", "ユニットスキル扱い")
	assert_eq(String(o["buff_kind"]), "debuff", "弱体＝ピュリファイが落とす対象")

func test_sting_not_offered_by_other_skins() -> void:
	var f := _sting_state()
	var found := false
	for o in Formation.available_for(f["s"], f["ally"]):  # fighter
		if String(o["recipe"]) == "poison_sting":
			found = true
	assert_false(found, "スコーピオン以外は撃てない")

func test_sting_targets_adjacent_enemy_only() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var o := _sting_option(f)
	assert_true(Formation.can_target(s, o, f["foe"].pos), "隣接する敵に掛けられる")
	assert_false(Formation.can_target(s, o, f["far_foe"].pos), "離れた敵には掛けられない")
	assert_false(Formation.can_target(s, o, f["ally"].pos), "隣接でも味方には掛けられない")
	assert_false(Formation.can_target(s, o, f["scorpion"].pos), "自分自身は選べない")

## 掛けた瞬間には減らない＝最初に減るのは次の対象ターン開始。
func test_sting_does_not_reduce_on_cast() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "発動成功")
	assert_eq(foe.troops, 8, "発動した瞬間は兵数が動かない")

func test_sting_reduces_one_troop_at_target_turn_start() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "発動成功")
	s.end_turn()  # 対象側（プレイヤー）のターン開始
	assert_eq(foe.troops, 7, "対象側のターン開始で1減る")

## 攻防の補正チェーンには乗らない（ヴェノムファングとの違い）。
func test_sting_does_not_touch_attack_or_defense() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 1.0, 0.001, "攻撃に係数は乗らない")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["add"]), 0.0, 0.001, "攻撃に加算もない")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["mul"]), 1.0, 0.001, "防御に係数は乗らない")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["add"]), 0.0, 0.001, "防御に加算もない")

## 3ターンぶん＝合計3減って止まる。
func test_sting_ticks_three_times_then_expires() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "発動成功")
	for round_index in 3:
		s.end_turn()  # 対象側のターン開始＝毒が入る
		assert_eq(foe.troops, 8 - (round_index + 1), "%d回目で %d 減っている" % [round_index + 1, round_index + 1])
		s.end_turn()  # 発動側のターン開始＝持続を1消費
	s.end_turn()  # 4回目の対象ターン＝もう掛かっていない
	assert_eq(foe.troops, 5, "3回で止まる（合計3減）")

## 重ねがけは加算＝2本刺されば毎ターン2減る。
func test_sting_stacking_adds_up() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var second := Unit.new(5, 1, Hex.neighbor(foe.pos, 2), 5, 8, 50, 70, 1, "knight")
	second.skin_id = "scorpion"
	s.add_unit(second)
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "1体目が発動")
	var o2 := {}
	for o in Formation.available_for(s, second):
		if String(o["recipe"]) == "poison_sting":
			o2 = o
	assert_false(o2.is_empty(), "2体目も撃てる")
	assert_false(s.resolve_formation(o2, foe.pos).is_empty(), "同じ相手に重ねられる")
	s.end_turn()
	assert_eq(foe.troops, 6, "2本で毎ターン2減る")

## 毒では全滅しない＝残兵1で止まる。倒すのは戦闘の役目（doc/gdd/skills.md）。
func test_sting_never_kills() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	foe.troops = 1
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "発動成功")
	s.end_turn()
	assert_eq(foe.troops, 1, "残兵1は減らない")
	assert_not_null(s.unit_by_id(foe.id), "盤から消えない")

## ピュリファイで落とせる（他の弱体と同じ器に乗っている）。
func test_sting_is_cleansable() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "発動成功")
	assert_eq(s.debuff_count(foe), 1, "弱体1本として数える")
	assert_eq(s.clear_debuffs(foe), 1, "ピュリファイが落とす")
	s.end_turn()
	assert_eq(foe.troops, 8, "落としたので減らない")

## 中断セーブに乗る（他の状態補正と同じ器なので往復できる）。
func test_sting_survives_serialization() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_false(s.resolve_formation(_sting_option(f), foe.pos).is_empty(), "発動成功")
	var restored := _state()  # 同じ器（盤サイズ）を組み直して差分を被せる＝実際の再開と同じ形
	restored.apply_save_diff(s.to_save_diff())
	restored.end_turn()
	assert_eq(restored.unit_by_id(foe.id).troops, 7, "復元後もターン開始で減る")
