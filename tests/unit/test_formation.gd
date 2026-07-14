extends GutTest
## 陣形スキル（スライスA＝フレームワーク＋①三重詠唱）の検出・威力・適用を検証する。
## 詳細 → doc/gdd/formations.md, doc/gdd/combat.md §2

func _state() -> BattleState:
	return BattleState.new(12, 8)

# 相互隣接の三角形を作る3つの axial（C, C+dir0, C+dir1 は互いに距離1）。
func _triangle(c: Vector2i) -> Array:
	return [c, Hex.neighbor(c, 0), Hex.neighbor(c, 1)]

# 三重詠唱の成立盤：wizard 3体が三角形＋離れた位置に敵1体。leader=id1。
func _trinity_state(enemy_def := 20) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var tri := _triangle(c)
	var w1 := Unit.new(1, 0, tri[0], 3, 8, 40, 30, 1, "wizard")
	var w2 := Unit.new(2, 0, tri[1], 3, 8, 40, 30, 1, "wizard")
	var w3 := Unit.new(3, 0, tri[2], 3, 8, 40, 30, 1, "wizard")
	w1.pierce = 0.5  # 発動者＝魔法兵（貫通の出どころ）
	var enemy_hex := c + Hex.direction(0) * 3  # leader から距離3（射程5内・面には他の駒なし）
	var enemy := Unit.new(9, 1, enemy_hex, 3, 8, 10, enemy_def)
	for u in [w1, w2, w3, enemy]:
		s.add_unit(u)
	return {"s": s, "leader": w1, "enemy": enemy, "enemy_hex": enemy_hex}

# --- 検出 ---

func test_available_detects_trinity_triangle() -> void:
	var f := _trinity_state()
	var opts := Formation.available_for(f["s"], f["leader"])
	assert_eq(opts.size(), 1, "三角形の三重詠唱が1つ検出される")
	var o: Dictionary = opts[0]
	assert_eq(String(o["recipe"]), "trinity", "レシピは trinity")
	assert_eq((o["participants"] as Array).size(), 3, "参加3体")
	assert_true(bool(o["needs_target"]), "面攻撃は対象指定が要る")

func test_no_triangle_when_not_adjacent() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var w1 := Unit.new(1, 0, c, 3, 8, 40, 30, 1, "wizard")
	var w2 := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 40, 30, 1, "wizard")
	var w3 := Unit.new(3, 0, c + Hex.direction(0) * 4, 3, 8, 40, 30, 1, "wizard")  # 離れている
	for u in [w1, w2, w3]:
		s.add_unit(u)
	assert_eq(Formation.available_for(s, w1).size(), 0, "三角形にならなければ検出0")

func test_leader_type_gates_recipe() -> void:
	# クレリックを選んでも三重詠唱（魔法兵）は出ない。
	var f := _trinity_state()
	var cleric := Unit.new(20, 0, Hex.offset_to_axial(1, 1), 3, 8, 20, 20, 1, "cleric")
	f["s"].add_unit(cleric)
	assert_eq(Formation.available_for(f["s"], cleric).size(), 0, "leader_type 不一致は検出0")

func test_done_member_excluded() -> void:
	var f := _trinity_state()
	f["s"].set_done(2)  # member を行動済みに
	assert_eq(Formation.available_for(f["s"], f["leader"]).size(), 0, "行動済みメンバーは三角形に数えない")

# ②ホーリーアリアの成立盤：占領兵5体が隣接連結（一列）＋離れた味方(fighter)＋敵。leader=id1。
func _aria_state() -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var clerics: Array = []
	for i in 5:
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		clerics.append(u)
	var ally := Unit.new(10, 0, Hex.offset_to_axial(2, 6), 3, 8, 40, 40, 1, "fighter")  # 全体バフ確認用
	var foe := Unit.new(11, 1, Hex.neighbor(ally.pos, 0), 3, 8, 30, 30)
	s.add_unit(ally)
	s.add_unit(foe)
	return {"s": s, "leader": clerics[0], "ally": ally, "foe": foe}

func test_holy_aria_offered_with_five_clustered() -> void:
	var f := _aria_state()
	var opts := Formation.available_for(f["s"], f["leader"])
	assert_eq(opts.size(), 1, "占領兵5体クラスタでホーリーアリア")
	var o: Dictionary = opts[0]
	assert_eq(String(o["recipe"]), "holy_aria", "レシピは holy_aria")
	assert_eq(String(o["effect"]), "buff", "バフ効果")
	assert_false(bool(o["needs_target"]), "バフは対象指定不要")

func test_holy_aria_needs_five() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var leader: Unit = null
	for i in 4:  # 4体だけ＝不成立
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		if i == 0:
			leader = u
	assert_eq(Formation.available_for(s, leader).size(), 0, "4体では不成立")

func test_holy_aria_buffs_whole_team() -> void:
	var f := _aria_state()
	var s: BattleState = f["s"]
	var ally: Unit = f["ally"]
	var foe: Unit = f["foe"]
	var before := Combat.effective_attack(s, ally, foe, true)
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, Vector2i(-9999, -9999))
	assert_false(res.is_empty(), "対象なしでも発動成功")
	assert_almost_eq(Combat.effective_attack(s, ally, foe, true), before * 1.3, 1.0, "離れた味方(fighter)の攻撃も×1.3")
	assert_true(s.is_done(1) and s.is_done(5), "クラスタ全員が行動完了")

# ③神の裁きの成立盤：paladin＋聖職2の三角形＋射程内(距離 enemy_dist)の敵1体。leader=paladin(id1)。
func _judgment_state(enemy_def := 20, enemy_dist := 6) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var tri := _triangle(c)
	var pal := Unit.new(1, 0, tri[0], 3, 8, 50, 50, 1, "paladin")
	var c1 := Unit.new(2, 0, tri[1], 3, 8, 20, 20, 1, "cleric")
	var c2 := Unit.new(3, 0, tri[2], 3, 8, 20, 20, 1, "priest")
	var enemy_hex := c + Hex.direction(0) * enemy_dist
	var enemy := Unit.new(9, 1, enemy_hex, 3, 8, 10, enemy_def)
	for u in [pal, c1, c2, enemy]:
		s.add_unit(u)
	return {"s": s, "leader": pal, "enemy": enemy, "enemy_hex": enemy_hex}

func test_divine_judgment_offered() -> void:
	var f := _judgment_state()
	var opts := Formation.available_for(f["s"], f["leader"])
	assert_eq(opts.size(), 1, "神の裁きが検出される")
	var o: Dictionary = opts[0]
	assert_eq(String(o["recipe"]), "divine_judgment", "レシピは divine_judgment")
	assert_eq(String(o["effect"]), "single", "単体効果")
	assert_eq(int(o["range"]), 10, "射程10")

func test_divine_judgment_leader_must_be_paladin() -> void:
	# 聖職を選んでも神の裁きは出ない（発動者はパラディンのみ）。
	var f := _judgment_state()
	var cleric: Unit = f["s"].unit_by_id(2)
	assert_eq(Formation.available_for(f["s"], cleric).size(), 0, "発動者がパラディンでなければ未提示")

func test_single_hits_only_target_hex() -> void:
	# 単体＝狙ったヘックスの敵だけ。隣の敵には及ばない（radius 0）。
	var f := _judgment_state()
	var s: BattleState = f["s"]
	var center: Vector2i = f["enemy_hex"]
	var enemy2 := Unit.new(10, 1, Hex.neighbor(center, 2), 3, 8, 10, 20)
	s.add_unit(enemy2)
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, center)
	var ids: Array = []
	for r in res["results"]:
		ids.append(int(r["target_id"]))
	assert_true(9 in ids, "狙ったヘックスの敵に着弾")
	assert_false(10 in ids, "単体＝隣の敵には及ばない")

func test_single_uses_leader_attack() -> void:
	var f := _judgment_state(100)  # 硬い敵で非撃破
	var s: BattleState = f["s"]
	var enemy: Unit = f["enemy"]
	var leader: Unit = f["leader"]
	var opt: Dictionary = Formation.available_for(s, leader)[0]
	var single := {"kind": "attack", "total": float(Combat.attack_breakdown(s, leader, enemy, false)["total"])}
	var df := Combat.defense_breakdown(s, enemy, leader, false)
	var expect := int(Combat.hit_from_breakdowns(single, df, enemy.troops)["loss"])
	var res := s.resolve_formation(opt, f["enemy_hex"])
	assert_gt(expect, 0, "非撃破でも損害はある（テスト前提）")
	assert_eq(int(res["results"][0]["loss"]), expect, "発動者(パラディン)の実効攻撃力での損害")

func test_single_out_of_range_fails() -> void:
	var s := BattleState.new(20, 8)
	var c := Hex.offset_to_axial(2, 3)
	var tri := _triangle(c)
	var pal := Unit.new(1, 0, tri[0], 3, 8, 50, 50, 1, "paladin")
	var c1 := Unit.new(2, 0, tri[1], 3, 8, 20, 20, 1, "cleric")
	var c2 := Unit.new(3, 0, tri[2], 3, 8, 20, 20, 1, "priest")
	var far_hex := c + Hex.direction(0) * 11  # 射程10超
	var enemy := Unit.new(9, 1, far_hex, 3, 8, 10, 20)
	for u in [pal, c1, c2, enemy]:
		s.add_unit(u)
	var opt: Dictionary = Formation.available_for(s, pal)[0]
	assert_true(s.resolve_formation(opt, far_hex).is_empty(), "射程外は不成立（空dict）")

# --- 威力・適用 ---

func test_resolve_uses_leader_attack() -> void:
	# 面ダメージ＝発動者1体の実効攻撃力（合算しない）。単体の hit と一致する。
	var f := _trinity_state(100)  # 硬い敵＝非撃破で損害が兵数上限に張り付かない範囲
	var s: BattleState = f["s"]
	var enemy: Unit = f["enemy"]
	var leader: Unit = f["leader"]
	var opt: Dictionary = Formation.available_for(s, leader)[0]
	var single := {"kind": "attack", "total": float(Combat.attack_breakdown(s, leader, enemy, false)["total"])}
	var df := Combat.defense_breakdown(s, enemy, leader, false)
	var expect := int(Combat.hit_from_breakdowns(single, df, enemy.troops)["loss"])
	var before := enemy.troops
	var res := s.resolve_formation(opt, f["enemy_hex"])
	assert_eq((res["results"] as Array).size(), 1, "敵1体に着弾")
	assert_gt(expect, 0, "非撃破でも損害はある（テスト前提）")
	assert_eq(int(res["results"][0]["loss"]), expect, "発動者1体の実効攻撃力での損害と一致（合算しない）")
	assert_eq(enemy.troops, before - expect, "敵の兵数が損害ぶん減る")

func test_resolve_marks_participants_done() -> void:
	var f := _trinity_state()
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	s.resolve_formation(opt, f["enemy_hex"])
	assert_true(s.is_done(1) and s.is_done(2) and s.is_done(3), "参加3体が行動完了")

func test_area_hits_allies_too() -> void:
	# フレンドリーファイア: 着弾中心の7hexに居る敵も味方も当たる（発動者3体は除外）。
	var f := _trinity_state()
	var s: BattleState = f["s"]
	var center: Vector2i = f["enemy_hex"]
	var enemy2 := Unit.new(10, 1, Hex.neighbor(center, 2), 3, 8, 10, 20)  # 面内の別の敵
	var ally := Unit.new(11, 0, Hex.neighbor(center, 3), 3, 8, 10, 20)    # 面内の味方（非参加）
	s.add_unit(enemy2)
	s.add_unit(ally)
	var ally_before := ally.troops
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, center)
	var hit_ids: Array = []
	for r in res["results"]:
		hit_ids.append(int(r["target_id"]))
	assert_true(9 in hit_ids and 10 in hit_ids, "面内の敵2体に着弾")
	assert_true(11 in hit_ids, "面内の味方も巻き込む")
	assert_lt(ally.troops, ally_before, "味方の兵数も減る")

func test_area_excludes_participants() -> void:
	# 発動者3体が着弾範囲に入っても自傷しない（詠唱の源）。leader を中心に撃つ。
	var f := _trinity_state()
	var s: BattleState = f["s"]
	var leader: Unit = f["leader"]
	var w2_before := s.unit_by_id(2).troops
	var enemy := Unit.new(12, 1, Hex.neighbor(leader.pos, 2), 3, 8, 10, 20)  # leader隣接の敵
	s.add_unit(enemy)
	var opt: Dictionary = Formation.available_for(s, leader)[0]
	var res := s.resolve_formation(opt, leader.pos)  # 中心＝leader＝面に発動者3体が入る
	var hit_ids: Array = []
	for r in res["results"]:
		hit_ids.append(int(r["target_id"]))
	assert_true(12 in hit_ids, "面内の敵には当たる")
	assert_false(1 in hit_ids or 2 in hit_ids or 3 in hit_ids, "発動者3体は着弾対象から除外")
	assert_eq(s.unit_by_id(2).troops, w2_before, "発動者の兵数は不変")

func test_resolve_out_of_range_fails() -> void:
	var f := _trinity_state()
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var far := Hex.offset_to_axial(3, 3) + Hex.direction(0) * 8  # 全参加者から射程5超
	assert_true(s.resolve_formation(opt, far).is_empty(), "射程外は不成立（空dict）")

func test_participants_gain_experience() -> void:
	# 撃破なし＝発動で全員+1（Lv1→Lv2）。硬い敵で一撃では死なせない。
	var f := _trinity_state(100)
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	s.resolve_formation(opt, f["enemy_hex"])
	assert_not_null(s.unit_by_id(9), "硬い敵は生存（非撃破ケースの前提）")
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_id(pid).level, 2, "参加者%d は発動で経験+1" % pid)

func test_empty_cast_grants_no_experience() -> void:
	# 面に敵が1体も居ない空撃ちは経験0（ただし参加者は行動完了）。
	var f := _trinity_state()
	var s: BattleState = f["s"]
	var empty := Hex.offset_to_axial(3, 3) + Hex.direction(3) * 2  # 射程内・面に駒なし
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, empty)
	assert_eq((res["results"] as Array).size(), 0, "空撃ち＝着弾なし")
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_id(pid).level, 1, "空撃ちは経験0（Lv1のまま）")
	assert_true(s.is_done(1), "空撃ちでも行動完了")

func test_kill_grants_extra_experience() -> void:
	# 撃破が1体でもあれば +2（Lv1→Lv3）。
	var f := _trinity_state(1)  # 低防御＝撃破される
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	s.resolve_formation(opt, f["enemy_hex"])
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_id(pid).level, 3, "撃破時は参加者%d が経験+2" % pid)

func test_resolve_kills_when_lethal() -> void:
	# 防御が薄い敵は撃破され盤から消える。
	var f := _trinity_state(1)  # 低防御
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, f["enemy_hex"])
	assert_true(bool(res["results"][0]["killed"]), "撃破フラグ")
	assert_null(s.unit_by_id(9), "撃破された敵は盤から消える")
