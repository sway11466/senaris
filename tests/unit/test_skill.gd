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

## 陣形スキルは配置そのものがレシピなので自マスでしか撃てないが、ユニットスキルは移動後でも撃てる。
func test_can_cast_after_moving() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var far: Unit = f["far"]
	var o := _dust_option(f)
	assert_eq(String(o["kind"]), "skill", "ユニットスキル扱い")
	assert_true(bool(o["after_move"]), "移動後でも撃てる印が立つ")
	assert_false(Formation.can_target(s, o, far.pos), "移動前は離れた味方に届かない")
	assert_true(s.move_unit(1, far.pos + Vector2i(-1, 0)), "far の隣へ飛ぶ")
	assert_true(Formation.can_target(s, o, far.pos), "移動先から隣接になれば掛けられる")
	assert_true(s.has_action_left(1), "移動しただけでは行動を使い切らない")
	assert_false(s.resolve_formation(o, far.pos).is_empty(), "移動後に発動できる")
	assert_true(s.is_done(1), "発動者は行動完了")

func test_formation_stays_stationary_only() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var leader: Unit = null
	for i in 5:  # ホーリーアリア＝聖職5体の隣接クラスタ
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		if i == 0:
			leader = u
	var opts := Formation.available_for(s, leader)
	assert_gt(opts.size(), 0, "ホーリーアリアが成立している前提")
	assert_eq(String(opts[0]["kind"]), "formation", "陣形スキル扱い")
	assert_false(bool(opts[0]["after_move"]), "陣形は移動後に撃てない印")

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
	var foe: Unit = f["foe"]
	var before := float(Combat.defense_breakdown(s, pixie, foe, true)["total"])
	assert_false(s.resolve_formation(_dust_option(f), pixie.pos).is_empty(), "自分に掛けられる")
	assert_almost_eq(float(Combat.defense_breakdown(s, pixie, foe, true)["total"]), before + 10.0 * pixie.troops, 0.001,
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

func test_expires_after_one_round() -> void:
	var f := _dust_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	var foe: Unit = f["foe"]
	var before := float(Combat.attack_breakdown(s, near, foe, true)["total"])
	assert_false(s.resolve_formation(_dust_option(f), near.pos).is_empty(), "発動成功")
	s.end_turn()  # 敵ターンへ
	assert_almost_eq(float(Combat.attack_breakdown(s, near, foe, true)["total"]), before + 80.0, 0.001, "敵ターン中はまだ効く")
	s.end_turn()  # 次の自軍ターンへ＝満了
	assert_almost_eq(float(Combat.attack_breakdown(s, near, foe, true)["total"]), before, 0.001, "次の自軍ターン開始で切れる")

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
	assert_true(bool(o["after_move"]), "移動後でも撃てる")
	assert_true(bool(o["buff_harmful"]), "有害な補正＝ピュリファイが落とす対象")

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

func test_dread_expires_after_one_round() -> void:
	var f := _dread_state()
	var s: BattleState = f["s"]
	var foe: Unit = f["foe"]
	var ghost: Unit = f["ghost"]
	var before := float(Combat.attack_breakdown(s, foe, ghost, true)["total"])
	assert_false(s.resolve_formation(_dread_option(f), foe.pos).is_empty(), "発動成功")
	s.end_turn()  # 相手ターンへ
	assert_almost_eq(float(Combat.attack_breakdown(s, foe, ghost, true)["total"]), before - 80.0, 0.001, "相手ターン中は効いている")
	s.end_turn()  # 次の発動側ターンへ＝満了
	assert_almost_eq(float(Combat.attack_breakdown(s, foe, ghost, true)["total"]), before, 0.001, "次の発動側ターン開始で切れる")

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
		"value": -80.0, "owner_team": 1, "remaining": 1, "name": "ドレッドタッチ", "harmful": true})
	s.add_status_mod({"scope": "unit", "unit_id": u.id, "op": "add", "target": "both",
		"value": 80.0, "owner_team": 0, "remaining": 1, "name": "ピクシーダスト", "harmful": false})

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
	assert_true(Formation.can_target(s, o, f["priest"].pos), "自分自身に掛けられる")
	assert_true(Formation.can_target(s, o, f["near"].pos), "隣接する味方に掛けられる")
	assert_false(Formation.can_target(s, o, f["far"].pos), "離れた味方には掛けられない")
	assert_false(Formation.can_target(s, o, f["foe"].pos), "敵には掛けられない")
	assert_false(Formation.can_target(s, o, Hex.neighbor(f["priest"].pos, 1)), "空きマスには掛けられない")

func test_purify_drops_harmful_and_keeps_buff() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	_afflict(s, near)
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 0.0, 0.001, "掛ける前は -80 と +80 で相殺")
	assert_false(s.resolve_formation(_purify_option(f), near.pos).is_empty(), "発動成功")
	assert_almost_eq(float(s.status_aggregate(near, "attack")["add"]), 80.0, 0.001, "弱体だけ落ちて強化は残る")
	assert_almost_eq(float(s.status_aggregate(near, "defense")["add"]), 80.0, 0.001, "防御側も同じ")

## 掛けられた数がいくつでも1回の発動で全部落ちる（ヴェノムファングが3本刺さっていても1回で済む）。
func test_purify_drops_every_harmful_at_once() -> void:
	var f := _purify_state()
	var s: BattleState = f["s"]
	var near: Unit = f["near"]
	for i in 3:
		s.add_status_mod({"scope": "unit", "unit_id": near.id, "op": "add", "target": "both",
			"value": -50.0, "owner_team": 1, "remaining": 1, "harmful": true})
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
		"value": 0.7, "owner_team": 1, "remaining": 1, "harmful": true})
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
	assert_eq(f["priest"].level, 1, "着弾が無いので経験は増えない")
