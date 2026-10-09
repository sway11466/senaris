extends GutTest
## abomination（暴走する古代兵器）＝第1部ボス（魔人の失敗作）専用AI。スポットで溜め、ランページで寄り、
## マナリークを吐き、ランページで戻る。通常攻撃・通常移動はしない。仕様 → doc/gdd/ai.md abomination

var _brain: TraitBrain

func before_each() -> void:
	_brain = TraitBrain.new()
	_brain.presets = AiCatalog.load_default()

const C := Vector2i(20, 20)  # ボスの位置（col/row）

## 40×40 の盤に魔人の失敗作（敵・部隊 abomination）を (20,20) に置く。charge＝マナリークのチャージ。
## 盤を広くするのは、隅の敵が突進＋射程（10＋6）で届かない距離に置けるようにするため。
func _state(charge := 1) -> Dictionary:
	var s := BattleState.new(40, 40)
	s.current_team = 1
	s.squads.append({ "ai": "abomination", "order": 1 })
	var boss := Unit.new(1, 1, Hex.offset_to_axial(C.x, C.y), 4, 8, 20, 50, 1, "abomination")
	boss.skin_id = "abomination"
	boss.pierce = 0.5
	s.add_unit(boss)
	s.assign_squad(boss.handle, 0)
	s.set_charge(boss.handle, "mana_leak", charge)
	return {"s": s, "boss": boss}

func _pc(s: BattleState, id: int, hex: Vector2i) -> Unit:
	var u := Unit.new(id, 0, hex, 3, 8, 20, 30, 1, "fighter")
	u.move_type = "foot"
	s.add_unit(u)
	return u

func _spot(s: BattleState, hex: Vector2i) -> void:
	s.add_gimmick(Gimmick.new("spot", "charge_spot", hex, GimmickKinds.CHARGE_ON))

func _stop_of(s: BattleState, a: AiAction) -> Vector2i:
	return Formation.dash_plan(s, a.option, a.to)["stop"]

# --- 1 今の位置から吐く ---

func test_fires_mana_leak_at_the_cell_covering_most_enemies() -> void:
	var f := _state(1)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var d0 := Hex.direction(0)
	var d2 := Hex.direction(2)
	_pc(s, 2, boss.pos + d0 * 2)  # 近いが1体きり
	var pair_a := _pc(s, 3, boss.pos + d2 * 4)  # 離れているが隣り合う2体
	_pc(s, 4, boss.pos + d2 * 4 + Hex.direction(1))
	var a := _brain.next_action(s, 1)
	assert_not_null(a, "撃つ")
	assert_eq(a.kind, AiAction.Kind.SKILL)
	assert_eq(a.option.skill, "mana_leak", "溜まっていればマナリーク")
	var n := 0
	for h in Formation.blast_cells(a.option, a.to, boss.pos):
		var v := s.unit_at(h)
		if v != null and v.team == 0:
			n += 1
	assert_eq(n, 2, "範囲に入る敵の数が最大の着弾先（2体組）")
	assert_true(Hex.distance(a.to, pair_a.pos) <= 1, "着弾は2体組の上")

func test_does_not_use_normal_attack_even_when_adjacent() -> void:
	var f := _state(0)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	_pc(s, 2, boss.pos + Hex.direction(0))
	var a := _brain.next_action(s, 1)
	assert_null(a, "溜まっておらず、スポットも無い＝待機（通常攻撃はしない）")

# --- 2 寄る ---

func test_dashes_to_where_the_leak_reaches_the_most_enemies() -> void:
	var f := _state(1)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var d0 := Hex.direction(0)
	# 直線上の距離9に敵。今の位置からは射程6の外。
	var far := _pc(s, 2, boss.pos + d0 * 9)
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.SKILL)
	assert_eq(a.option.skill, "rampage", "射程外ならランページで寄る")
	var stop := _stop_of(s, a)
	assert_true(Hex.distance(stop, far.pos) <= 6, "止まった位置からマナリークが届く（距離 %d）" % Hex.distance(stop, far.pos))
	assert_true(FormationResolver.resolve(s, a.option, a.to) != null, "突進は妥当")
	assert_false(s.has_action_left(boss.handle), "突進で行動完了＝吐くのは次のターン")

func test_approaches_the_nearest_enemy_when_no_stop_reaches() -> void:
	var f := _state(1)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	# 直線上に無く、どの止まる位置からも射程6に入らない遠い敵（盤の隅）。
	var far := _pc(s, 2, Hex.offset_to_axial(0, 0))
	var before := Hex.distance(boss.pos, far.pos)
	var a := _brain.next_action(s, 1)
	assert_not_null(a, "近づける位置があれば突進する")
	assert_eq(a.option.skill, "rampage")
	assert_lt(Hex.distance(_stop_of(s, a), far.pos), before, "盤上距離が最小の敵へ近づく")

# --- 3 戻る ---

func test_returns_to_the_charge_spot_when_empty() -> void:
	var f := _state(0)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var spot: Vector2i = boss.pos + Hex.direction(3) * 5
	_spot(s, spot)
	_pc(s, 2, boss.pos + Hex.direction(0) * 2)  # 近くに敵が居ても殴らない
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.option.skill, "rampage", "溜まっていなければ戻る")
	assert_eq(_stop_of(s, a), spot, "直線上ならスポットの上で止まる")

func test_rams_the_unit_sitting_on_the_spot() -> void:
	var f := _state(0)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var spot: Vector2i = boss.pos + Hex.direction(3) * 5
	_spot(s, spot)
	var blocker := _pc(s, 2, spot)
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.option.skill, "rampage")
	assert_eq(a.to, spot, "スポットの上の駒へぶつかる着弾先を選ぶ")
	var plan := Formation.dash_plan(s, a.option, a.to)
	assert_eq((plan["victim"] as Unit).handle, blocker.handle, "塞いだ駒を轢く")

func test_closes_in_on_the_spot_when_not_on_a_ray() -> void:
	var f := _state(0)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var spot: Vector2i = boss.pos + Hex.direction(3) * 4 + Hex.direction(4) * 2  # 直線上に無い
	_spot(s, spot)
	var before := Hex.distance(boss.pos, spot)
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.option.skill, "rampage")
	assert_lt(Hex.distance(_stop_of(s, a), spot), before, "スポットへ最も近づく止まる位置へ")

## 往復の型＝寄る → 吐く → 戻る（満タン）→ 寄る。application が踏む分は手で満たす。
func test_full_cycle_over_turns() -> void:
	var f := _state(0)
	var s: BattleState = f["s"]
	var boss: Unit = f["boss"]
	var d0 := Hex.direction(0)
	var d3 := Hex.direction(3)
	var spot: Vector2i = boss.pos + d3 * 3
	_spot(s, spot)
	var foe := _pc(s, 2, boss.pos + d0 * 8)
	var log: Array[String] = []
	for turn in 4:
		s.current_team = 1
		var a := _brain.next_action(s, 1)
		assert_not_null(a, "ターン %d に手がある" % turn)
		assert_eq(a.kind, AiAction.Kind.SKILL, "手は常にスキル（通常攻撃・通常移動はしない）")
		log.append(a.option.skill)
		assert_not_null(FormationResolver.resolve(s, a.option, a.to), "手は妥当")
		if boss.pos == spot:
			s.set_charge(boss.handle, "mana_leak", 1)  # 踏んだぶん（application の口）
		s.end_turn()
		s.end_turn()
	# 0: 溜まっていない→スポットへ戻る（踏んで満タン）／1: スポットから敵は射程外→寄る／2: 隣に居る→吐く／
	# 3: 空になった→スポットへ戻る（直線上の距離10＝一気に戻る）
	assert_eq(log, ["rampage", "rampage", "mana_leak", "rampage"] as Array[String], "往復の型")
	assert_eq(boss.pos, spot, "最後はスポットの上")
