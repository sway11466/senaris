extends GutTest
## ユニットスキル（単独発動・味方1体を強化）＝成立・対象の絞り込み・適用・持続を検証する。
## 仕組みは陣形スキルと共通（Formation のスキルとして持つ）。詳細 → doc/gdd/skills.md

func _state() -> BattleState:
	return BattleState.new(10, 8)

# ピクシー1体＋隣接する味方＋離れた味方＋隣接する敵。caster=pixie(id1)。
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

func _dust_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["pixie"]):
		if o.skill == "pixie_dust":
			return o
	return null

# --- 成立と対象の絞り込み ---

func test_offered_by_pixie_alone() -> void:
	var f := _dust_state()
	var o := _dust_option(f)
	assert_not_null(o, "ピクシー単独で成立する")
	assert_eq(o.caster_id, 1, "発動者はピクシー")
	assert_eq(o.participants.size(), 1, "参加者は発動者だけ")
	assert_true(o.needs_target(), "掛ける相手を選ぶ")

func test_not_offered_by_other_types() -> void:
	var f := _dust_state()
	var found := false
	for o in Formation.available_for(f["s"], f["near"]):  # fighter（ピクシーの隣に居る）
		if o.skill == "pixie_dust":
			found = true
	assert_false(found, "ピクシー以外は撃てない")

## 発動者の照合もスキンID（→ doc/gdd/skills.md 共通ルール）。性能が pixie でも別スキンなら撃てない。
func test_not_offered_by_other_skin() -> void:
	var f := _dust_state()
	f["pixie"].skin_id = "harpy"
	assert_null(_dust_option(f), "pixie 性能でも別スキンなら撃てない")

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
	assert_true(o.is_unit_skill(), "ユニットスキル扱い")
	assert_false(Formation.can_target(s, o, far.pos), "移動前は離れた味方に届かない")
	assert_true(s.move_unit(1, far.pos + Vector2i(-1, 0)), "far の隣へ飛ぶ")
	assert_true(Formation.can_target(s, o, far.pos), "移動先から隣接になれば掛けられる")
	assert_true(s.has_action_left(1), "移動しただけでは行動を使い切らない")
	assert_not_null(FormationResolver.resolve(s, o, far.pos), "移動後に発動できる")
	assert_true(s.is_done(1), "発動者は行動完了")

func test_cluster_skill_is_a_formation() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var caster: Unit = null
	for i in 5:  # グレイス＝聖職5体の隣接クラスタ
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		if i == 0:
			caster = u
	var opts := Formation.available_for(s, caster)
	assert_gt(opts.size(), 0, "グレイスが成立している前提")
	assert_false(opts[0].is_unit_skill(), "陣形スキル扱い（表示ラベルの出し分け）")

# --- 適用 ---

func test_buffs_only_the_chosen_unit() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var far: Unit = f["far"]
	var foe: Unit = f["foe"]
	var near_before := Combat.attack_breakdown(s, near, foe).total
	var far_before := Combat.attack_breakdown(s, far, foe).total
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), near.pos), "発動成功")
	assert_almost_eq(Combat.attack_breakdown(s, near, foe).total, near_before + 10.0 * near.troops, 0.001,
		"対象の実効攻撃力に 10×残兵数 が乗る")
	assert_almost_eq(Combat.attack_breakdown(s, far, foe).total, far_before, 0.001, "他の味方には乗らない")

func test_buffs_defense_too() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var foe: Unit = f["foe"]
	var before := Combat.defense_breakdown(s, near, foe).total
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), near.pos), "発動成功")
	assert_almost_eq(Combat.defense_breakdown(s, near, foe).total, before + 10.0 * near.troops, 0.001,
		"防御にも同じだけ乗る")

func test_caster_is_done() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), f["near"].pos), "発動成功")
	assert_true(s.is_done(1), "発動者は行動完了")
	assert_false(s.is_done(2), "掛けられた側は行動を消費しない")

func test_self_target() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var pixie: Unit = f["pixie"]
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), pixie.pos), "自分に掛けられる")
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
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), near.pos), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 40.0, 0.001, "ピクシー4体なら +40")
	assert_almost_eq(float(s.status_aggregate(near, "defense")["add"]), 40.0, 0.001, "防御側も同じ")

## 値は発動時に確定する＝掛けた後にピクシーが削られても倒されても変わらない。
func test_bonus_fixed_at_cast() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var pixie: Unit = f["pixie"]
	var near: Unit = f["near"]
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), near.pos), "満員8体で発動")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "+80")
	pixie.troops = 2  # 発動後に損耗
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "掛けた後は動かない")

func test_stacking_adds_up() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var foe: Unit = f["foe"]
	var before := Combat.attack_breakdown(s, near, foe).total
	var second := Unit.new(5, 0, Hex.neighbor(near.pos, 2), 5, 8, 10, 10, 1, "pixie")  # near の隣の2体目
	s.add_unit(second)
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), near.pos), "1体目が発動")
	var opts := Formation.available_for(s, second)
	assert_gt(opts.size(), 0, "2体目も撃てる")
	assert_not_null(FormationResolver.resolve(s, opts[0], near.pos), "同じ相手に重ねられる")
	assert_almost_eq(Combat.attack_breakdown(s, near, foe).total, before + 160.0, 0.001, "+80 が2つで +160")

func test_expires_after_three_rounds() -> void:
	# 持続は自軍ターン3回ぶん（doc/gdd/skills.md ピクシーダスト）。敵ターンでは減らない。
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var foe: Unit = f["foe"]
	var before := Combat.attack_breakdown(s, near, foe).total
	assert_not_null(FormationResolver.resolve(s, _dust_option(f), near.pos), "発動成功")
	for round_index in 3:
		s.end_turn()  # 敵ターンへ
		assert_almost_eq(Combat.attack_breakdown(s, near, foe).total, before + 80.0, 0.001,
			"敵ターン中はまだ効く（%d周目）" % (round_index + 1))
		if round_index < 2:
			s.end_turn()  # 次の自軍ターンへ＝まだ残っている
			assert_almost_eq(Combat.attack_breakdown(s, near, foe).total, before + 80.0, 0.001,
				"自軍ターン %d 回目もまだ効く" % (round_index + 2))
	s.end_turn()  # 3回ぶん使い切った次の自軍ターン＝満了
	assert_almost_eq(Combat.attack_breakdown(s, near, foe).total, before, 0.001, "自軍ターン3回ぶんで切れる")

# --- ドレッドタッチ（単体弱体・対象は敵）---

# ゴースト1体＋隣接する敵＋離れた敵＋隣接する味方。caster=ghost(id1)。
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

func _dread_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["ghost"]):
		if o.skill == "dread_touch":
			return o
	return null

func test_dread_offered_by_ghost_alone() -> void:
	var f := _dread_state()
	var o := _dread_option(f)
	assert_not_null(o, "ゴースト単独で成立する")
	assert_true(o.is_unit_skill(), "ユニットスキル扱い")
	assert_eq(o.buff_kind, "debuff", "弱体＝ピュリファイが落とす対象")

## ピクシー性能を借りているだけなので、ピクシーダストは撃てない（照合はスキンID）。
func test_ghost_cannot_cast_pixie_dust() -> void:
	var f := _dread_state()
	var found := false
	for o in Formation.available_for(f["s"], f["ghost"]):
		if o.skill == "pixie_dust":
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
	var atk_before := Combat.attack_breakdown(s, foe, ghost).total
	var def_before := Combat.defense_breakdown(s, foe, ghost).total
	assert_not_null(FormationResolver.resolve(s, _dread_option(f), foe.pos), "発動成功")
	assert_almost_eq(Combat.attack_breakdown(s, foe, ghost).total, atk_before - 80.0, 0.001,
		"満員のゴーストなら実効攻撃力が -80")
	assert_almost_eq(Combat.defense_breakdown(s, foe, ghost).total, def_before - 80.0, 0.001,
		"防御にも同じだけ効く")

## 強さを決めるのは掛ける側（ゴースト）の残兵数＝削れば効きが薄くなる。
func test_dread_scales_with_caster_troops() -> void:
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	f["ghost"].troops = 3
	assert_not_null(FormationResolver.resolve(s, _dread_option(f), foe.pos), "発動成功")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["add"]), -30.0, 0.001, "ゴースト3体なら -30")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["add"]), -30.0, 0.001, "防御側も同じ")

func test_dread_expires_after_three_rounds() -> void:
	# 持続は発動側ターン3回ぶん（doc/gdd/skills.md ドレッドタッチ）。相手ターンでは減らない。
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var ghost: Unit = f["ghost"]
	var before := Combat.attack_breakdown(s, foe, ghost).total
	assert_not_null(FormationResolver.resolve(s, _dread_option(f), foe.pos), "発動成功")
	for round_index in 3:
		s.end_turn()  # 相手ターンへ
		assert_almost_eq(Combat.attack_breakdown(s, foe, ghost).total, before - 80.0, 0.001,
			"相手ターン中は効いている（%d周目）" % (round_index + 1))
		if round_index < 2:
			s.end_turn()  # 次の発動側ターンへ＝まだ残っている
			assert_almost_eq(Combat.attack_breakdown(s, foe, ghost).total, before - 80.0, 0.001,
				"発動側ターン %d 回目もまだ効く" % (round_index + 2))
	s.end_turn()  # 3回ぶん使い切った次の発動側ターン＝満了
	assert_almost_eq(Combat.attack_breakdown(s, foe, ghost).total, before, 0.001, "発動側ターン3回ぶんで切れる")

## 重ねがけは足し合わさる＝-80 が2つで -160（ピクシーダストの符号反転）。詳細 → doc/gdd/skills.md 共通ルール
func test_dread_stacking_adds_up() -> void:
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var second := Unit.new(5, 0, Hex.neighbor(foe.pos, 2), 5, 8, 10, 10, 1, "pixie")  # foe の隣の2体目
	second.skin_id = "ghost"
	s.add_unit(second)
	assert_not_null(FormationResolver.resolve(s, _dread_option(f), foe.pos), "1体目が発動")
	var o2: FormationOption = null
	for o in Formation.available_for(s, second):
		if o.skill == "dread_touch":
			o2 = o
	assert_not_null(o2, "2体目も撃てる")
	assert_not_null(FormationResolver.resolve(s, o2, foe.pos), "同じ相手に重ねられる")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["add"]), -160.0, 0.001, "攻撃に -160")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["add"]), -160.0, 0.001, "防御にも -160")

## 減算で実効攻撃力が 0 以下になった駒は削れない（攻撃0＝損害0）。詳細 → doc/gdd/skills.md ドレッドタッチ
func test_dread_attack_floor_deals_no_loss() -> void:
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var ghost: Unit = f["ghost"]
	foe.troops = 1  # 素の実効攻撃力 1×50＝50 に -80
	assert_gt(Combat.casualties(s, foe, ghost), 0, "前提: 掛ける前は削れる")
	assert_not_null(FormationResolver.resolve(s, _dread_option(f), foe.pos), "発動成功")
	assert_eq(Combat.casualties(s, foe, ghost), 0, "攻撃が0を割れば損害0")

# --- ヴェノムファング（単体弱体・係数型）---

# ロックサーペント1体＋隣接する敵＋離れた敵＋隣接する味方。caster=rock_serpent(id1)。
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

func _venom_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["serpent"]):
		if o.skill == "venom_fang":
			return o
	return null

func test_venom_offered_by_rock_serpent_alone() -> void:
	var f := _venom_state()
	var o := _venom_option(f)
	assert_not_null(o, "ロックサーペント単独で成立する")
	assert_true(o.is_unit_skill(), "ユニットスキル扱い")
	assert_eq(o.buff_kind, "debuff", "弱体＝ピュリファイが落とす対象")

func test_venom_not_offered_by_other_skins() -> void:
	var f := _venom_state()
	var found := false
	for o in Formation.available_for(f["s"], f["ally"]):  # fighter
		if o.skill == "venom_fang":
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
	assert_not_null(FormationResolver.resolve(s, _venom_option(f), foe.pos), "発動成功")
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
	assert_not_null(FormationResolver.resolve(s, _venom_option(f), foe.pos), "発動成功")
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
	assert_not_null(FormationResolver.resolve(s, _venom_option(f), foe.pos), "1体目が発動")
	var opts := Formation.available_for(s, second)
	var o2: FormationOption = null
	for o in opts:
		if o.skill == "venom_fang":
			o2 = o
	assert_not_null(o2, "2体目も撃てる")
	assert_not_null(FormationResolver.resolve(s, o2, foe.pos), "同じ相手に重ねられる")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 0.81, 0.001,
		"2本で ×0.81（0.9×0.9）")

func test_venom_expires_after_three_rounds() -> void:
	var f := _venom_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_not_null(FormationResolver.resolve(s, _venom_option(f), foe.pos), "発動成功")
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

# --- スライムスプリット（分裂・駒生成）。パッシブ＝ターン開始に自動で発動。詳細 → doc/gdd/skills.md ---

# スライム1体（敵 team=1）＋周囲に空きマス。いまはプレイヤーのターン。
# チャージは charge に置く＝次の end_turn（敵ターン開始）で +1 されてから発動を判定する。
func _split_state(charge := 2) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var slime := Unit.new(1, 1, c, 2, 8, 20, 20, 1, "slime")
	slime.skin_id = "slime"
	slime.move_type = "foot"
	s.add_unit(slime)
	s.set_charge(slime.handle, "slime_split", charge)
	return {"s": s, "slime": slime}

# 分裂で生まれた駒（発動者と id 100 以外で最初に見つかったもの）。
func _spawned(s: BattleState, caster: Unit) -> Unit:
	for u in s.units():
		if u.handle != caster.handle and u.handle != 100:
			return u
	return null

func test_split_is_passive() -> void:
	assert_true(Formation.is_passive("slime_split"), "スライムスプリットはパッシブ")
	assert_false(Formation.is_passive("pixie_dust"), "ピクシーダストはアクティブ")

func test_split_not_offered_as_an_action() -> void:
	# パッシブは手番で撃たない＝チャージが溜まっていてもメニュー・敵AIの候補に出ない。
	var f := _split_state(3)
	var s: BattleState = f["s"]
	s.current_team = 1
	var found := false
	for o in Formation.available_for(s, f["slime"]):
		if o.skill == "slime_split":
			found = true
	assert_false(found, "行動の候補に出ない")

func test_split_fires_at_turn_start() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	var before_count := s.units().size()
	s.end_turn()  # 敵ターン開始＝チャージ 3 → 分裂
	assert_eq(s.units().size(), before_count + 1, "駒が1体増える")
	assert_eq(s.last_passive_results.size(), 1, "発動の記録が1件")
	var r: Dictionary = s.last_passive_results[0]
	var spawned := _spawned(s, f["slime"])
	assert_eq(String(r["skill"]), "slime_split")
	assert_eq(int(r["caster"]), 1)
	assert_eq(int(r["unit"]), spawned.handle)
	assert_eq(r["from"], (f["slime"] as Unit).pos, "演出の起点は発動者のマス")
	assert_eq(r["to"], spawned.pos, "演出の行き先は分裂先")
	assert_true(bool(r["fx"]), "演出あり")

func test_split_fires_while_dormant() -> void:
	# 敵AIの行動開始条件に縛られない＝眠っている駒も分裂し、分裂しても起きない。
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	assert_eq(s.units().size(), 2, "行動開始前でも分裂する")
	assert_false(s.is_engaged(1), "分裂しても行動開始にならない")

func test_split_waits_for_charge() -> void:
	var f := _split_state(1)
	var s: BattleState = f["s"]
	s.end_turn()  # チャージ 2＝まだ足りない
	assert_eq(s.units().size(), 1, "溜まるまで分裂しない")
	assert_true(s.last_passive_results.is_empty(), "発動の記録も無い")

func test_split_not_on_opponent_turn_start() -> void:
	var f := _split_state(3)
	var s: BattleState = f["s"]
	s.end_turn()  # 敵ターン開始で分裂（チャージ 4 でも発動する）
	s.end_turn()  # プレイヤーのターン開始
	assert_eq(s.units().size(), 2, "相手のターン開始では分裂しない")

func test_split_needs_room() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	var i := 10
	for nb in Hex.neighbors((f["slime"] as Unit).pos):
		if s.in_field(nb):
			s.add_unit(Unit.new(i, 1, nb, 2, 8, 20, 20, 1, "fighter"))
			i += 1
	var before_count := s.units().size()
	s.end_turn()
	assert_eq(s.units().size(), before_count, "隣に空きマスが無ければ分裂しない")
	assert_eq(s.get_charge(1, "slime_split"), 3, "撃てなかったチャージは残る")

func test_split_inherits_troops() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	f["slime"].troops = 5  # 損耗した状態で分裂
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(spawned.troops, 5, "兵数は発動者の現在値を引き継ぐ")
	assert_eq(spawned.max_troops, 8, "max_troops は type の既定値")

func test_split_spawned_is_done() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_true(s.is_done(spawned.handle), "生まれたターンは行動済み")

func test_split_caster_keeps_its_action() -> void:
	# 手番を使わない＝分裂した駒もそのターンに動ける。
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	assert_false(s.is_done(1), "発動者は行動を残す")

func test_split_caster_gains_no_level() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	assert_eq((f["slime"] as Unit).level, 1, "分裂ではレベルが上がらない")

func test_split_spawned_inherits_skin_and_type() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(spawned.skin_id, "slime", "skin_id を引き継ぐ")
	assert_eq(spawned.type_id, "slime", "type_id を引き継ぐ")
	assert_eq(spawned.team, f["slime"].team, "陣営を引き継ぐ")

func test_split_spawned_joins_caster_squad() -> void:
	# 待ち伏せのスライムから生まれた駒も待ち伏せ＝発動者と同じ部隊に入る。
	var f := _split_state()
	var s: BattleState = f["s"]
	s.squads = [{ "order": 1, "name": "本隊", "ai": "ambush" }]
	s.assign_squad(1, 0)
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(s.squad_index_of(spawned.handle), 0, "発動者と同じ部隊")
	assert_eq(String(s.squad_of(spawned.handle).get("ai", "")), "ambush", "同じ AI に従う")

func test_split_spawned_without_squad_stays_unassigned() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(s.squad_index_of(spawned.handle), -1, "発動者が部隊に属さなければ生まれた駒も属さない")

func test_split_not_by_other_skins() -> void:
	var s := _state()
	var fighter := Unit.new(2, 1, Hex.offset_to_axial(3, 3), 6, 8, 50, 40, 1, "fighter")
	s.add_unit(fighter)
	s.set_charge(fighter.handle, "slime_split", 2)
	s.end_turn()
	assert_eq(s.units().size(), 1, "スライム以外は分裂しない")

func test_split_id_does_not_collide() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	var other := Unit.new(100, 1, Hex.offset_to_axial(7, 7), 2, 8, 20, 20, 1, "slime")
	s.add_unit(other)
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_gt(spawned.handle, 100, "既存の最大 id より大きい")

func test_split_id_skips_defeated() -> void:
	# 撃破済みの駒の番号は使い回さない＝その駒の記録（起動済み・部隊）を引き継がない。
	var f := _split_state()
	var s: BattleState = f["s"]
	s.squads = [{ "order": 1, "name": "本隊", "ai": "ambush" }, { "order": 2, "name": "別隊", "ai": "charge" }]
	s.assign_squad(1, 0)
	var fallen := Unit.new(100, 1, Hex.offset_to_axial(7, 7), 2, 8, 20, 20, 1, "slime")
	s.add_unit(fallen)
	s.assign_squad(100, 1)
	s.mark_engaged(100)  # 被弾で起動してから倒された
	s.remove_unit(100)
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_gt(spawned.handle, 100, "撃破済みの番号より大きい")
	assert_false(s.is_engaged(spawned.handle), "生まれた駒は起動済みを引き継がない")
	assert_eq(s.squad_index_of(spawned.handle), 0, "発動者の部隊に入る")

func test_split_id_skips_pending_event_units() -> void:
	# まだ出ていない増援の駒の番号とも重ならない。
	var f := _split_state()
	var s: BattleState = f["s"]
	var item := EventUnit.new()
	item.unit = Unit.new(200, 1, Hex.offset_to_axial(7, 7), 2, 8, 20, 20, 1, "slime")
	var e := StageEvent.new()
	e.id = "later"
	e.turn = 99
	e.team = 1
	e.units.append(item)
	s.add_event(e)
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_gt(spawned.handle, 200, "増援の駒の番号より大きい")

# --- ピュリファイ（有害な補正の解除）---

# プリースト＋隣接する味方＋離れた味方＋隣接する敵。caster=priest(id1)。
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

func _purify_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["priest"]):
		if o.skill == "purify":
			return o
	return null

## near に有害な弱体（ドレッドタッチ相当）と無害な強化（ピクシーダスト相当）を1つずつ掛ける。
func _afflict(s: BattleState, u: Unit) -> void:
	s.add_status_mod({"scope": "unit", "handle": u.handle, "op": "add", "target": "both",
		"value": -80.0, "owner_team": 1, "remaining": 1, "name": "ドレッドタッチ", "kind": "debuff"})
	s.add_status_mod({"scope": "unit", "handle": u.handle, "op": "add", "target": "both",
		"value": 80.0, "owner_team": 0, "remaining": 1, "name": "ピクシーダスト", "kind": "buff"})

func test_purify_offered_by_clergy_alone() -> void:
	var f := _purify_state()
	var o := _purify_option(f)
	assert_not_null(o, "聖職単独で成立する")
	assert_true(o.is_unit_skill(), "ユニットスキル扱い")
	assert_true(o.needs_target(), "掛ける相手を選ぶ")

func test_purify_not_offered_by_others() -> void:
	var f := _purify_state()
	var found := false
	for o in Formation.available_for(f["s"], f["near"]):  # fighter
		if o.skill == "purify":
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
	s.add_status_mod({"scope": "unit", "handle": near.handle, "op": "add", "target": "both",
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

func test_unit_skills_of_lists_solo_skills_by_skin() -> void:
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
	assert_not_null(FormationResolver.resolve(s, _purify_option(f), near.pos), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "弱体だけ落ちて強化は残る")
	assert_almost_eq(float(s.status_aggregate(near, "defense")["add"]), 80.0, 0.001, "防御側も同じ")

## 掛けられた数がいくつでも1回の発動で全部落ちる（ヴェノムファングが3本刺さっていても1回で済む）。
func test_purify_drops_every_debuff_at_once() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	for i in 3:
		s.add_status_mod({"scope": "unit", "handle": near.handle, "op": "add", "target": "both",
			"value": -50.0, "owner_team": 1, "remaining": 1, "kind": "debuff"})
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), -150.0, 0.001, "3本で -150")
	assert_not_null(FormationResolver.resolve(s, _purify_option(f), near.pos), "発動成功")
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
	assert_not_null(FormationResolver.resolve(s, _purify_option(f), near.pos), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "対象の弱体は落ちる")
	assert_almost_eq(float(s.status_aggregate(far, "attack")["add"]), 0.0, 0.001, "離れた味方の弱体は残る")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["mul"]), 0.7, 0.001, "陣営全体の補正は1人のピュリファイでは落ちない")

func test_purify_consumes_the_casters_action() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	_afflict(s, near)
	assert_not_null(FormationResolver.resolve(s, _purify_option(f), near.pos), "発動成功")
	assert_true(s.is_done(1), "発動者は行動完了")
	assert_false(s.is_done(2), "掛けられた側は行動を消費しない")
	assert_eq(f["priest"].level, 2, "発動者に Lv+1（撃破は起きないので前半だけ）")

# --- チャージ（再使用間隔）---

## 毎ターン開始時にチャージ量が +1 される。
func test_charge_increments_each_turn() -> void:
	var f := _split_state(0)
	var s: BattleState = f["s"]
	var slime: Unit = f["slime"]
	assert_eq(s.get_charge(slime.handle, "slime_split"), 0, "初期値は 0")
	s.end_turn()  # team=1 のターン開始（敵ターン）＝敵駒のチャージが +1
	assert_eq(s.get_charge(slime.handle, "slime_split"), 1, "1ターン目で +1")
	s.end_turn()  # プレイヤーターン＝敵は増えない
	assert_eq(s.get_charge(slime.handle, "slime_split"), 1, "相手ターンでは増えない")
	s.end_turn()
	assert_eq(s.get_charge(slime.handle, "slime_split"), 2, "2ターン目で +1")

## 発動するとチャージ量が 0 に戻る。
func test_charge_resets_on_use() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	assert_eq(s.get_charge(1, "slime_split"), 0, "発動後は 0 に戻る")

## 分裂で生まれた駒のチャージ量は 0（溜まるまで撃てない）。
func test_charge_spawned_starts_at_zero() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	s.end_turn()
	var spawned := _spawned(s, f["slime"])
	assert_not_null(spawned, "新しい駒が居る")
	assert_eq(s.get_charge(spawned.handle, "slime_split"), 0, "生まれた駒のチャージ量は 0")

## 盤に出た直後の駒は、3回目の自陣営ターン開始で初めて分裂する。
func test_charge_accumulates_to_threshold() -> void:
	var f := _split_state(0)
	var s: BattleState = f["s"]
	for i in 2:
		s.end_turn()  # 敵ターン開始：チャージ +1
		s.end_turn()  # プレイヤーのターン
	assert_eq(s.units().size(), 1, "2ターンではまだ分裂しない")
	s.end_turn()
	assert_eq(s.units().size(), 2, "3ターン目の頭で分裂する")

## チャージ量は中断セーブに乗る（to_save_diff → apply_save_diff で往復）。
func test_charge_survives_serialization() -> void:
	var f := _split_state()
	var s: BattleState = f["s"]
	var restored := _state()  # 同じ器（盤サイズ）を組み直して差分を被せる＝実際の再開と同じ形
	restored.apply_save_diff(s.to_save_diff())
	assert_eq(restored.get_charge(1, "slime_split"), 2, "復元後もチャージ量が保たれる")

## レシピはすべて activation を明示する（active／passive／on_done＝行動完了スキル）。パッシブだけが passive_fx を持つ。
func test_every_recipe_declares_activation() -> void:
	for rid in Formation.SKILLS:
		var r: Dictionary = Formation.SKILLS[rid]
		assert_true(String(r.get("activation", "")) in ["active", "passive", "on_done"], "%s の activation" % rid)
		if String(r["activation"]) == "passive":
			assert_true(r.get("passive_fx") is bool, "%s の passive_fx" % rid)
		else:
			assert_false(r.has("passive_fx"), "%s はアクティブ＝passive_fx を持たない" % rid)

# --- ポイズンスティング（継続ダメージ）。詳細 → doc/gdd/skills.md ---

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

func _sting_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["scorpion"]):
		if o.skill == "poison_sting":
			return o
	return null

func test_sting_offered_by_scorpion_alone() -> void:
	var f := _sting_state()
	var o := _sting_option(f)
	assert_not_null(o, "スコーピオン単独で成立する")
	assert_true(o.is_unit_skill(), "ユニットスキル扱い")
	assert_eq(o.buff_kind, "debuff", "弱体＝ピュリファイが落とす対象")

func test_sting_not_offered_by_other_skins() -> void:
	var f := _sting_state()
	var found := false
	for o in Formation.available_for(f["s"], f["ally"]):  # fighter
		if o.skill == "poison_sting":
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
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "発動成功")
	assert_eq(foe.troops, 8, "発動した瞬間は兵数が動かない")

func test_sting_reduces_one_troop_at_target_turn_start() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "発動成功")
	s.end_turn()  # 対象側（プレイヤー）のターン開始
	assert_eq(foe.troops, 7, "対象側のターン開始で1減る")

## 攻防の補正チェーンには乗らない（ヴェノムファングとの違い）。
## 減らした駒はターン開始の記録に載る（盤が減る瞬間を見せる）。減る前の兵数と出す絵を持つ。
func test_sting_tick_is_recorded() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	FormationResolver.resolve(s, _sting_option(f), foe.pos)
	s.end_turn()  # プレイヤーのターン開始＝減る
	assert_eq(s.last_dot_results.size(), 1, "減った駒が1件")
	var r: Dictionary = s.last_dot_results[0]
	assert_eq(int(r["unit"]), foe.handle)
	assert_eq(int(r["troops_before"]), 8, "減る前の兵数")
	assert_eq(int(r["shield_before"]), 0)
	assert_eq(String(r["effect"]), "poison", "盤に出す絵はレシピの tick_effect")
	s.end_turn()  # 敵ターン開始＝プレイヤーの駒は減らない
	assert_true(s.last_dot_results.is_empty(), "減らないターンは空")

## 下限に張り付いて1も減らなかった駒は記録に載せない。
func test_sting_tick_at_floor_is_not_recorded() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	FormationResolver.resolve(s, _sting_option(f), foe.pos)
	foe.troops = 1
	s.end_turn()
	assert_eq(foe.troops, 1, "毒では全滅しない")
	assert_true(s.last_dot_results.is_empty(), "減らなければ記録しない")

func test_sting_does_not_touch_attack_or_defense() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "発動成功")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 1.0, 0.001, "攻撃に係数は乗らない")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["add"]), 0.0, 0.001, "攻撃に加算もない")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["mul"]), 1.0, 0.001, "防御に係数は乗らない")
	assert_almost_eq(float(s.status_aggregate(foe, "defense")["add"]), 0.0, 0.001, "防御に加算もない")

## 3ターンぶん＝合計3減って止まる。
func test_sting_ticks_three_times_then_expires() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "発動成功")
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
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "1体目が発動")
	var o2: FormationOption = null
	for o in Formation.available_for(s, second):
		if o.skill == "poison_sting":
			o2 = o
	assert_not_null(o2, "2体目も撃てる")
	assert_not_null(FormationResolver.resolve(s, o2, foe.pos), "同じ相手に重ねられる")
	s.end_turn()
	assert_eq(foe.troops, 6, "2本で毎ターン2減る")

## 毒では全滅しない＝残兵1で止まる。倒すのは戦闘の役目（doc/gdd/skills.md）。
func test_sting_never_kills() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	foe.troops = 1
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "発動成功")
	s.end_turn()
	assert_eq(foe.troops, 1, "残兵1は減らない")
	assert_not_null(s.unit_by_handle(foe.handle), "盤から消えない")

## ピュリファイで落とせる（他の弱体と同じ器に乗っている）。
func test_sting_is_cleansable() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "発動成功")
	assert_eq(s.debuff_count(foe), 1, "弱体1本として数える")
	assert_eq(s.clear_debuffs(foe), 1, "ピュリファイが落とす")
	s.end_turn()
	assert_eq(foe.troops, 8, "落としたので減らない")

## 中断セーブに乗る（他の状態補正と同じ器なので往復できる）。
func test_sting_survives_serialization() -> void:
	var f := _sting_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	assert_not_null(FormationResolver.resolve(s, _sting_option(f), foe.pos), "発動成功")
	var restored := _state()  # 同じ器（盤サイズ）を組み直して差分を被せる＝実際の再開と同じ形
	restored.apply_save_diff(s.to_save_diff())
	restored.end_turn()
	assert_eq(restored.unit_by_handle(foe.handle).troops, 7, "復元後もターン開始で減る")

# --- 発動者のレベル（共通ルール）---

## アクティブなユニットスキルは着弾が無くても発動者が Lv+1（戦ったら+1 の前半だけ）。
## 効果の型（加算の強化・加算の弱体・係数の弱体・継続ダメージ）によらず同じ。詳細 → doc/gdd/skills.md 共通ルール
func test_unit_skill_caster_gains_one_level() -> void:
	var dust := _dust_state()
	var dread := _dread_state()
	var venom := _venom_state()
	var sting := _sting_state()
	var cases := [
		[dust, dust["pixie"], _dust_option(dust), dust["near"]],
		[dread, dread["ghost"], _dread_option(dread), dread["foe"]],
		[venom, venom["serpent"], _venom_option(venom), venom["foe"]],
		[sting, sting["scorpion"], _sting_option(sting), sting["foe"]],
	]
	for c in cases:
		var s: BattleState = c[0]["s"]
		var caster: Unit = c[1]
		var o: FormationOption = c[2]
		var target: Unit = c[3]
		assert_not_null(FormationResolver.resolve(s, o, target.pos), "%s 発動成功" % o.skill)
		assert_eq(caster.level, 2, "%s: 発動者は Lv+1" % o.skill)
		assert_eq(target.level, 1, "%s: 掛けられた側のレベルは動かない" % o.skill)

# --- ドラゴンブレス（扇状の面攻撃・チャージ3）。詳細 → doc/gdd/skills.md ドラゴンブレス ---

# レッドドラゴン1体（敵 team=1・攻撃70）。いまは敵のターンで、チャージは charge。
func _breath_state(charge := 3) -> Dictionary:
	var s := _state()
	s.current_team = 1
	var dragon := Unit.new(1, 1, Hex.offset_to_axial(4, 1), 11, 8, 70, 50, 1, "dragon")
	dragon.skin_id = "red_dragon"
	s.add_unit(dragon)
	s.set_charge(dragon.handle, "dragon_breath", charge)
	return {"s": s, "dragon": dragon}

func _breath_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["dragon"]):
		if o.skill == "dragon_breath":
			return o
	return null

func test_breath_cone_is_eight_cells_in_the_facing() -> void:
	var o := Vector2i(0, 0)
	var d := Hex.direction(5)
	var cells := Formation.cone_cells(o, o + d)
	assert_eq(cells.size(), 8, "扇は8ヘクス")
	var by_dist := {1: 0, 2: 0, 3: 0}
	for h in cells:
		by_dist[Hex.distance(o, h)] += 1
	assert_eq(by_dist, {1: 1, 2: 3, 3: 4}, "1列目1・2列目3・3列目4")
	assert_false(o + d * 3 in cells, "正面の3マス先は含まない")
	assert_false(o in cells, "発動者のヘクスは含まない")
	var expected: Array[Vector2i] = [o + d, o + d * 2, o + d + Hex.direction(4), o + d + Hex.direction(0),
			o + d * 2 + Hex.direction(4), o + d * 2 + Hex.direction(0),
			o + d + Hex.direction(4) * 2, o + d + Hex.direction(0) * 2]
	for h in expected:
		assert_true(h in cells, "扇に %s が入る" % h)
	assert_eq(Formation.cone_cells(o, o + d * 2).size(), 0, "隣でない着弾先は向きにならない")

func test_breath_waits_for_charge() -> void:
	assert_null(_breath_option(_breath_state(2)), "チャージ2では撃てない")
	assert_not_null(_breath_option(_breath_state(3)), "チャージ3で撃てる")

func test_breath_not_by_other_skins() -> void:
	var f := _breath_state()
	(f["dragon"] as Unit).skin_id = "wyrm"
	assert_null(_breath_option(f), "レッドドラゴン以外は吐けない")

func test_breath_targets_are_the_six_neighbors() -> void:
	var f := _breath_state()
	var dragon: Unit = f["dragon"]
	var cells := Formation.targetable_cells(f["s"], _breath_option(f))
	assert_eq(cells.size(), 6, "向きは隣の6ヘクス")
	for h in cells:
		assert_eq(Hex.distance(dragon.pos, h), 1, "隣だけ（自分のヘクスは選べない）")

func test_breath_uses_attack_40_and_pierce_half() -> void:
	# 竜 兵8・攻撃は上書きで40 → 実効攻撃 320。ファイター 兵8・防40 → 貫通0.5で実効防御 160。
	# 削る割合 320²/(320²+160²)=0.8 → 8×0.8=6.4 → 6。竜の攻撃70のままなら 7 になる。
	var f := _breath_state()
	var s: BattleState = f["s"]
	var dragon: Unit = f["dragon"]
	var front := dragon.pos + Hex.direction(5)
	var fighter := Unit.new(9, 0, front + Hex.direction(5), 3, 8, 50, 40)
	s.add_unit(fighter)
	var res := FormationResolver.resolve(s, _breath_option(f), front)
	assert_not_null(res, "発動成功")
	assert_eq(res.hits.size(), 1, "扇の中の1体に当たる")
	assert_eq(res.hits[0].loss, 6, "攻撃40・貫通0.5で6減る")
	assert_eq(res.cells.size(), 8, "光らせる面は扇の8ヘクス")

func test_breath_burns_allies_but_not_itself() -> void:
	var f := _breath_state()
	var s: BattleState = f["s"]
	var dragon: Unit = f["dragon"]
	var front := dragon.pos + Hex.direction(5)
	var ally := Unit.new(5, 1, front, 3, 8, 20, 20)  # 竜の仲間が扇の1列目に居る
	s.add_unit(ally)
	var res := FormationResolver.resolve(s, _breath_option(f), front)
	var ids: Array = []
	for h in res.hits:
		ids.append(h.target_id)
	assert_true(ally.handle in ids, "仲間も焼ける")
	assert_false(dragon.handle in ids, "発動者は焼けない")

func test_breath_resets_charge_and_ends_action() -> void:
	var f := _breath_state()
	var s: BattleState = f["s"]
	var dragon: Unit = f["dragon"]
	FormationResolver.resolve(s, _breath_option(f), dragon.pos + Hex.direction(5))
	assert_eq(s.get_charge(dragon.handle, "dragon_breath"), 0, "チャージは0に戻る")
	assert_false(s.has_action_left(dragon.handle), "発動者は行動完了")

# --- マナリーク（第1部ボスの弱い面攻撃。チャージはスポットでだけ溜まる）---

const SPOT := Vector2i(2, 2)  # チャージスポットの位置（col/row）

# 魔人の失敗作（敵・team1）＋射程内の味方の駒2体（隣接と距離3）＋失敗作の隣の敵側の駒＋チャージスポット (2,2)。
# caster=abomination(id1)。威力は駒の素の値（攻20・貫通0.5）なので、駒にそのまま持たせる。
func _leak_state(charge := 1) -> Dictionary:
	var s := BattleState.new(20, 20)  # 距離6の着弾先が盤に収まる広さ
	s.current_team = 1
	var c := Hex.offset_to_axial(10, 10)
	var boss := Unit.new(1, 1, c, 4, 8, 20, 50, 1, "abomination")
	boss.skin_id = "abomination"
	boss.pierce = 0.5
	var near := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 40, 30, 1, "fighter")
	var mid := Unit.new(3, 0, c + Hex.direction(3) * 3, 3, 8, 40, 30, 1, "fighter")
	var mate := Unit.new(4, 1, Hex.neighbor(c, 1), 3, 8, 30, 30, 1, "gear_soldier")  # near の隣＝同じ面に入る
	for u in [boss, near, mid, mate]:
		s.add_unit(u)
	s.add_gimmick(Gimmick.new("spot-a", "charge_spot", Hex.offset_to_axial(SPOT.x, SPOT.y), GimmickKinds.CHARGE_ON))
	s.set_charge(boss.handle, "mana_leak", charge)
	return {"s": s, "boss": boss, "near": near, "mid": mid, "mate": mate}

func _leak_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["boss"]):
		if o.skill == "mana_leak":
			return o
	return null

func test_leak_waits_for_charge() -> void:
	assert_null(_leak_option(_leak_state(0)), "チャージ0では撃てない")
	assert_not_null(_leak_option(_leak_state(1)), "チャージ1で撃てる")

func test_leak_not_by_other_skins() -> void:
	var f := _leak_state()
	(f["boss"] as Unit).skin_id = "chimera"
	assert_null(_leak_option(f), "魔人の失敗作以外は撃てない")

## 溜まり方が spot のスキルは、ターン開始の +1 が無い。
func test_leak_charge_does_not_build_over_turns() -> void:
	var f := _leak_state(0)
	var s: BattleState = f["s"]
	s.end_turn()  # プレイヤーターン
	s.end_turn()  # 敵ターン開始＝敵駒のチャージが +1 される番だが、マナリークは増えない
	assert_eq(s.get_charge(1, "mana_leak"), 0, "ターン開始では溜まらない")

## チャージスポットに止まると必要量まで満ちる。スポットの上に居続けても増えない。
func test_leak_charge_fills_on_charge_spot() -> void:
	var f := _leak_state(0)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var spot := Hex.offset_to_axial(SPOT.x, SPOT.y)
	boss.pos = spot
	assert_null(s.step_gimmick(spot, boss.team), "仕掛けの状態は変わらない（null）")
	assert_eq(s.get_charge(1, "mana_leak"), 1, "スポットに着くと必要量まで満ちる")
	s.end_turn()
	s.end_turn()
	assert_eq(s.get_charge(1, "mana_leak"), 1, "上に居続けても必要量を超えない")

## スポットを踏んでも、溜まり方が spot でないスキルや、持っていない駒には何も起きない。
func test_charge_spot_ignores_units_without_spot_skills() -> void:
	var f := _leak_state(0)
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var spot := Hex.offset_to_axial(SPOT.x, SPOT.y)
	near.pos = spot
	s.step_gimmick(spot, near.team)
	assert_eq(s.get_charge(near.handle, "mana_leak"), 0, "撃てない駒には溜まらない")
	assert_eq(s.get_charge(1, "mana_leak"), 0, "踏んでいない駒には溜まらない")

## 着弾先は発動者から 1〜6 のヘクス（自分のマスには撃てない）。面は中心＋周囲6の7ヘクス。
func test_leak_targets_ring_1_to_6_and_blasts_seven_cells() -> void:
	var f := _leak_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var o := _leak_option(f)
	var cells := Formation.targetable_cells(s, o)
	assert_false(boss.pos in cells, "自分のマスには撃てない")
	for h in cells:
		var d := Hex.distance(boss.pos, h)
		assert_true(d >= 1 and d <= 6, "着弾先 %s は距離1〜6" % h)
	assert_true(Hex.neighbor(boss.pos, 0) in cells, "隣にも撃てる")
	assert_true(boss.pos + Hex.direction(3) * 6 in cells, "距離6に撃てる")
	assert_false(boss.pos + Hex.direction(3) * 7 in cells, "距離7には撃てない")
	assert_eq(Formation.blast_cells(o, boss.pos + Hex.direction(3) * 3).size(), 7, "面は7ヘクス")

## 発動者以外は敵味方の別なく当たる。威力は駒の素の値（攻20・貫通0.5）＝上書きしない。
func test_leak_hits_everyone_but_itself_with_own_stats() -> void:
	var f := _leak_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var near: Unit = f["near"]
	var mate: Unit = f["mate"]
	var o := _leak_option(f)
	# 中心＝発動者の隣（near のマス）。面に boss・near・mate が入る。
	var pv := Formation.preview(s, o, near.pos)
	var ids: Array[int] = []
	for h: HitDetail in pv["hits"]:
		ids.append(h.target_id)
	assert_true(near.handle in ids, "味方側（プレイヤー）の駒に当たる")
	assert_true(mate.handle in ids, "自陣営の駒も巻き込む")
	assert_false(boss.handle in ids, "発動者は当たらない")
	for h: HitDetail in pv["hits"]:
		assert_eq(h.attack.stat, 20, "威力は駒の攻撃力そのまま（上書きしない）")
		assert_almost_eq(h.defense.pierce, 0.5, 0.001, "貫通は駒の値（防御半減）")

func test_leak_resets_charge_and_ends_action() -> void:
	var f := _leak_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var near: Unit = f["near"]
	var before := near.troops
	var res := FormationResolver.resolve(s, _leak_option(f), near.pos)
	assert_not_null(res)
	assert_lt(near.troops, before, "面の駒の兵数が減る")
	assert_eq(s.get_charge(boss.handle, "mana_leak"), 0, "チャージは0に戻る")
	assert_false(s.has_action_left(boss.handle), "発動者は行動完了")
	assert_null(_leak_option(f), "スポットに戻るまで撃てない")

# --- ランページ（第1部ボスの直線の突進。移動と単体攻撃を兼ねる）---

# 魔人の失敗作（敵・team1）を (12,12) に。direction(0) の直線上に味方側の歩兵（距離3）。direction(3) の直線上に
# 飛行の駒（距離2）と、その奥の歩兵（距離4）。caster=abomination(id1)。威力は駒の素の攻20。
func _rampage_state() -> Dictionary:
	var s := BattleState.new(24, 24)
	s.current_team = 1
	var c := Hex.offset_to_axial(12, 12)
	var boss := Unit.new(1, 1, c, 4, 8, 20, 50, 1, "abomination")
	boss.skin_id = "abomination"
	boss.pierce = 0.5
	var d0 := Hex.direction(0)
	var d3 := Hex.direction(3)
	var wall := Unit.new(2, 0, c + d0 * 3, 3, 8, 40, 30, 1, "fighter")
	var flyer := Unit.new(3, 0, c + d3 * 2, 5, 8, 10, 10, 1, "pixie")
	flyer.move_type = "flight"
	var behind := Unit.new(4, 0, c + d3 * 4, 3, 8, 40, 30, 1, "fighter")
	for u in [boss, wall, flyer, behind]:
		s.add_unit(u)
	return {"s": s, "boss": boss, "wall": wall, "flyer": flyer, "behind": behind, "c": c}

func _rampage_option(f: Dictionary) -> FormationOption:
	for o in Formation.available_for(f["s"], f["boss"]):
		if o.skill == "rampage":
			return o
	return null

func test_rampage_offered_without_charge() -> void:
	var f := _rampage_state()
	var o := _rampage_option(f)
	assert_not_null(o, "チャージ無し＝いつでも撃てる")
	assert_true(o.needs_target(), "止まる位置を選ぶ")
	assert_false(o.targets_unit(), "空きマスも選べる")
	(f["boss"] as Unit).skin_id = "chimera"
	assert_null(_rampage_option(f), "魔人の失敗作以外は撃てない")

## 選べる止まる位置＝6方向の直線上で、最初にぶつかる駒の手前までの空きマスと、その駒のマス。
## 駒の向こう側・飛行の駒のマス（通り抜ける）・直線上に無いマス・距離11以上は選べない。
func test_rampage_targets_follow_the_six_rays() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var c: Vector2i = f["c"]
	var d0 := Hex.direction(0)
	var d3 := Hex.direction(3)
	var cells := Formation.targetable_cells(s, _rampage_option(f))
	for h in cells:
		assert_true(Formation.ray_direction(c, h) != Vector2i.ZERO, "%s は6方向の直線上" % h)
		assert_true(Hex.distance(c, h) <= 10, "%s は距離10まで" % h)
	assert_true(c + d0 * 2 in cells, "ぶつかる駒の手前の空きマスは選べる")
	assert_true(c + d0 * 3 in cells, "ぶつかる駒のマス＝手前で止まって殴る")
	assert_false(c + d0 * 4 in cells, "駒の向こう側は選べない")
	assert_false(c + d3 * 2 in cells, "飛行の駒のマスには止まれない")
	assert_true(c + d3 * 3 in cells, "飛行の駒は通り抜ける")
	assert_true(c + d3 * 4 in cells, "通り抜けた先の駒にぶつかれる")
	assert_false(c + d3 * 5 in cells, "その向こう側は選べない")
	assert_false(c + d0 + Hex.direction(1) in cells, "直線上に無いマスは選べない")
	assert_true(c + Hex.direction(2) * 10 in cells, "距離10まで進める")
	assert_false(c + Hex.direction(2) * 11 in cells, "距離11は進めない")
	assert_false(c in cells, "自分のマスは選べない")

## ぶつかったらその手前で止まり、その駒へ攻撃力×3・貫通なしの一撃。反撃は起きず、発動者は行動完了・Lv+1。
func test_rampage_stops_short_and_strikes_with_triple_attack() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var wall: Unit = f["wall"]
	var c: Vector2i = f["c"]
	var d0 := Hex.direction(0)
	var res := FormationResolver.resolve(s, _rampage_option(f), wall.pos)
	assert_not_null(res)
	assert_eq(boss.pos, c + d0 * 2, "ぶつかる駒の手前で止まる")
	assert_eq(res.caster_moved_to, c + d0 * 2, "止まった位置を結果に持つ")
	assert_eq(res.dash_path, [c + d0, c + d0 * 2] as Array[Vector2i], "通ったマス（出発を含まず止まる位置まで）")
	assert_eq(res.caster.pos, c, "発動者のスナップショットは出発の位置")
	assert_eq(res.hits.size(), 1, "ぶつかった1体に当たる")
	var hit: SkillHit = res.hits[0]
	assert_eq(hit.target_id, wall.handle)
	assert_eq(hit.detail.attack.stat, 60, "攻撃力は駒の値×3（20→60）")
	assert_almost_eq(hit.detail.defense.pierce, 1.0, 0.001, "貫通なし（物理）")
	assert_lt(wall.troops, 8, "兵数が減る")
	assert_eq(boss.troops, 8, "反撃は起きない")
	assert_eq(boss.level, 2, "当たれば Lv+1")
	assert_false(s.has_action_left(boss.handle), "発動者は行動完了")
	assert_true(res.has_impact(), "盤に見せる着弾がある")

func test_rampage_passes_over_flyers() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var behind: Unit = f["behind"]
	var c: Vector2i = f["c"]
	var d3 := Hex.direction(3)
	var res := FormationResolver.resolve(s, _rampage_option(f), behind.pos)
	assert_not_null(res)
	assert_eq(boss.pos, c + d3 * 3, "飛行の駒を通り抜けて、奥の駒の手前で止まる")
	assert_eq(res.hits.size(), 1)
	assert_eq(res.hits[0].target_id, behind.handle, "奥の駒にぶつかる")
	assert_eq((f["flyer"] as Unit).troops, 8, "通り抜けた飛行の駒には当たらない")

## ぶつかる駒の手前のマスに飛行の駒が居れば、さらに手前の空きマスで止まる。攻撃はぶつかった駒へ。
func test_rampage_stops_before_a_flyer_in_front_of_the_blocker() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var behind: Unit = f["behind"]
	var c: Vector2i = f["c"]
	var d3 := Hex.direction(3)
	(f["flyer"] as Unit).pos = c + d3 * 3
	var res := FormationResolver.resolve(s, _rampage_option(f), behind.pos)
	assert_not_null(res)
	assert_eq(boss.pos, c + d3 * 2, "飛行の駒の手前の空きマスで止まる")
	assert_eq(res.dash_path, [c + d3, c + d3 * 2] as Array[Vector2i])
	assert_eq(res.hits.size(), 1)
	assert_eq(res.hits[0].target_id, behind.handle, "隣接していなくてもぶつかった駒へ当たる")

func test_rampage_move_only_gains_no_level() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var c: Vector2i = f["c"]
	var to: Vector2i = c + Hex.direction(2) * 5
	var res := FormationResolver.resolve(s, _rampage_option(f), to)
	assert_not_null(res)
	assert_eq(boss.pos, to, "選んだ位置まで進む")
	assert_eq(res.caster_moved_to, to)
	assert_eq(res.dash_path.size(), 5)
	assert_true(res.hits.is_empty(), "ぶつからなければ当たらない")
	assert_eq(boss.level, 1, "動いただけではレベルは上がらない")
	assert_true(res.has_impact(), "動いた＝盤に見せるものがある")
	assert_false(s.has_action_left(boss.handle), "発動者は行動完了")

func test_rampage_adjacent_unit_is_struck_without_moving() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var wall: Unit = f["wall"]
	var c: Vector2i = f["c"]
	wall.pos = c + Hex.direction(0)
	var res := FormationResolver.resolve(s, _rampage_option(f), wall.pos)
	assert_not_null(res)
	assert_eq(boss.pos, c, "隣なら動かない")
	assert_eq(res.caster_moved_to, Formation.NO_HEX, "動いていない印")
	assert_true(res.dash_path.is_empty())
	assert_eq(res.hits.size(), 1, "隣の駒を殴る")

## 直線の途中の地形は見ない＝壁の上も通り抜ける（止めるのは駒と盤の端だけ）。
func test_rampage_ignores_terrain() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var c: Vector2i = f["c"]
	var d2 := Hex.direction(2)
	s.set_terrain(c + d2 * 2, "wall")
	var res := FormationResolver.resolve(s, _rampage_option(f), c + d2 * 4)
	assert_not_null(res)
	assert_eq(boss.pos, c + d2 * 4, "壁を越えて進む")

## 盤の端を越えては進めない＝端の手前で止まる位置までしか選べない。
func test_rampage_cannot_leave_the_board() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	boss.pos = Hex.offset_to_axial(1, 12)
	var cells := Formation.targetable_cells(s, _rampage_option(f))
	for h in cells:
		assert_true(s.in_field(h), "%s は盤の中" % h)

## 突進の一撃は戦闘の結果の器に写せる（演出シーンが攻撃と同じ画で見せる）。反撃なし。
func test_rampage_hit_as_attack_result() -> void:
	var f := _rampage_state()
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var wall: Unit = f["wall"]
	var res := FormationResolver.resolve(s, _rampage_option(f), wall.pos)
	var attack := res.dash_as_attack(s.unit_snapshot(boss))
	assert_not_null(attack)
	assert_eq(attack.attacker.handle, boss.handle)
	assert_eq(attack.defender.handle, wall.handle)
	assert_false(attack.has_counter(), "反撃なし")
	assert_true(attack.melee, "止まった位置は隣接")
	assert_eq(attack.damage(), res.hits[0].loss)
	var moved_only := FormationResolver.resolve(_rampage_state()["s"], _rampage_option(_rampage_state()), Vector2i.ZERO)
	assert_null(moved_only, "前提: 直線上に無い着弾先は不成立")

# --- リペア（兵器・輸送の兵数を戻す）---

# 銃の技師＋隣接する馬車（損耗）＋隣接する歩兵（損耗）＋離れた馬車（損耗）＋隣接する敵の馬車（損耗）。
# caster=gunner(id1)。リペア可は型から写る値なので、ここでは駒に直接立てる。損耗した駒は 5/8。
func _repair_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var gunner := Unit.new(1, 0, c, 4, 8, 30, 30, 1, "gunner")
	var wagon := Unit.new(2, 0, Hex.neighbor(c, 0), 6, 5, 0, 10, 1, "wagon")
	var fighter := Unit.new(3, 0, Hex.neighbor(c, 1), 6, 5, 50, 40, 1, "fighter")
	var far := Unit.new(4, 0, Hex.offset_to_axial(8, 6), 6, 5, 0, 10, 1, "wagon")
	var foe := Unit.new(5, 1, Hex.neighbor(c, 3), 6, 5, 0, 10, 1, "wagon")
	for u in [wagon, far, foe]:
		u.repairable = true
	for u in [wagon, fighter, far, foe]:
		u.max_troops = 8  # 生成時の兵数が満員になる＝5/8 の損耗に直す
	for u in [gunner, wagon, fighter, far, foe]:
		s.add_unit(u)
	return {"s": s, "gunner": gunner, "wagon": wagon, "fighter": fighter, "far": far, "foe": foe}

func _repair_option(s: BattleState, caster: Unit) -> FormationOption:
	for o in Formation.available_for(s, caster):
		if o.skill == "repair":
			return o
	return null

func test_repair_offered_by_engineers_alone() -> void:
	var f := _repair_state()
	var o := _repair_option(f["s"], f["gunner"])
	assert_not_null(o, "銃の技師単独で成立する")
	assert_true(o.is_unit_skill(), "ユニットスキル扱い")
	assert_true(o.needs_target(), "直す相手を選ぶ")
	var s: BattleState = f["s"]
	var shieldwright := Unit.new(9, 0, Hex.offset_to_axial(6, 3), 5, 8, 20, 70, 1, "shieldwright")
	s.add_unit(shieldwright)
	assert_not_null(_repair_option(s, shieldwright), "盾の技師も撃てる")

func test_repair_not_offered_by_others() -> void:
	var f := _repair_state()
	assert_null(_repair_option(f["s"], f["fighter"]), "技師以外は撃てない")

func test_repair_targets_damaged_adjacent_repairable_ally_only() -> void:
	var f := _repair_state()
	var s: BattleState = f["s"]
	var o := _repair_option(s, f["gunner"])
	assert_true(Formation.can_target(s, o, f["wagon"].pos), "兵数の減った隣接の馬車は直せる")
	assert_false(Formation.can_target(s, o, f["fighter"].pos), "兵器・輸送でない駒は直せない")
	assert_false(Formation.can_target(s, o, f["far"].pos), "離れた馬車は直せない")
	assert_false(Formation.can_target(s, o, f["foe"].pos), "敵の馬車は直せない")
	assert_false(Formation.can_target(s, o, f["gunner"].pos), "技師自身は直せない")

## 満タンの駒は対象にならない＝空撃ちでレベルを上げさせない。直せる先が無ければメニューは項目を無効化する。
func test_repair_cannot_target_full_unit() -> void:
	var f := _repair_state()
	var s: BattleState = f["s"]
	var wagon: Unit = f["wagon"]
	wagon.troops = wagon.max_troops
	var o := _repair_option(s, f["gunner"])
	assert_false(Formation.can_target(s, o, wagon.pos), "満タンの馬車は直せない")
	assert_true(Formation.targetable_cells(s, o).is_empty(), "直せる先が無い")

func test_repair_restores_two_troops() -> void:
	var f := _repair_state()
	var s: BattleState = f["s"]
	var wagon: Unit = f["wagon"]
	var r := FormationResolver.resolve(s, _repair_option(s, f["gunner"]), wagon.pos)
	assert_not_null(r, "発動成功")
	assert_eq(wagon.troops, 7, "5 → 7")
	assert_true(r.hits.is_empty(), "着弾は起きない")
	assert_eq(r.cast.healed, 2, "戻した兵数を演出に渡す")
	assert_eq(r.cast.target.troops_before, 5, "演出の対象は戻す前の兵数から")
	assert_eq(r.cast.target.troops_after, 7, "戻した後の兵数まで")

func test_repair_stops_at_max_troops() -> void:
	var f := _repair_state()
	var s: BattleState = f["s"]
	var wagon: Unit = f["wagon"]
	wagon.troops = wagon.max_troops - 1
	var r := FormationResolver.resolve(s, _repair_option(s, f["gunner"]), wagon.pos)
	assert_eq(wagon.troops, wagon.max_troops, "最大兵数で打ち止め")
	assert_eq(r.cast.healed, 1, "戻せたのは1だけ")

func test_repair_consumes_the_casters_action() -> void:
	var f := _repair_state()
	var s: BattleState = f["s"]
	assert_not_null(FormationResolver.resolve(s, _repair_option(s, f["gunner"]), f["wagon"].pos), "発動成功")
	assert_true(s.is_done(1), "発動者は行動完了")
	assert_false(s.is_done(2), "直された側は行動を消費しない")
	assert_eq(f["gunner"].level, 2, "発動者に Lv+1（撃破は起きないので前半だけ）")
