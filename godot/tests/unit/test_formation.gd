extends GutTest
## 陣形スキル（スライスA＝フレームワーク＋①トリニティノヴァ）の検出・威力・適用を検証する。
## 詳細 → doc/gdd/formations.md, doc/gdd/combat.md §2

func _state() -> BattleState:
	return BattleState.new(12, 8)

## そのレシピの選択肢だけを数える。聖職はピュリファイ（ユニットスキル）も単独で撃てるので、
## 選択肢の総数で陣形スキルの成立を判定すると混ざる。詳細 → doc/gdd/skills.md
func _count(opts: Array, recipe: String) -> int:
	var n := 0
	for o in opts:
		if String(o["recipe"]) == recipe:
			n += 1
	return n

## そのレシピの選択肢を1つ取り出す（無ければ空）。
func _pick(opts: Array, recipe: String) -> Dictionary:
	for o in opts:
		if String(o["recipe"]) == recipe:
			return o
	return {}

# 相互隣接の三角形を作る3つの axial（C, C+dir0, C+dir1 は互いに距離1）。
func _triangle(c: Vector2i) -> Array:
	return [c, Hex.neighbor(c, 0), Hex.neighbor(c, 1)]

# トリニティノヴァの成立盤：wizard 3体が三角形＋離れた位置に敵1体。leader=id1。
func _trinity_nova_state(enemy_def := 20) -> Dictionary:
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

func test_available_detects_trinity_nova_triangle() -> void:
	var f := _trinity_nova_state()
	var opts := Formation.available_for(f["s"], f["leader"])
	assert_eq(opts.size(), 1, "三角形のトリニティノヴァが1つ検出される")
	var o: Dictionary = opts[0]
	assert_eq(String(o["recipe"]), "trinity_nova", "レシピは trinity_nova")
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
	# クレリックを選んでもトリニティノヴァ（魔法兵）は出ない。
	var f := _trinity_nova_state()
	var cleric := Unit.new(20, 0, Hex.offset_to_axial(1, 1), 3, 8, 20, 20, 1, "cleric")
	f["s"].add_unit(cleric)
	assert_eq(_count(Formation.available_for(f["s"], cleric), "trinity_nova"), 0, "leader_type 不一致は検出0")

func test_done_member_excluded() -> void:
	var f := _trinity_nova_state()
	f["s"].set_done(2)  # member を行動済みに
	assert_eq(Formation.available_for(f["s"], f["leader"]).size(), 0, "行動済みメンバーは三角形に数えない")

## 発動に移動先も攻撃相手も要らない＝行き止まりのメンバーも参加できる。
## 囲まれて動けないだけの駒を除外すると、密集した盤で陣形が組めなくなる。
func test_stuck_member_still_counts() -> void:
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	s.unit_by_id(2).move = 0  # 行ける先が無い（瓦礫や味方に囲まれた駒と同じ状態）
	assert_true(s.is_stuck(2), "前提: メンバーに打つ手が無い")
	assert_false(s.is_done(2), "前提: 行動は使っていない")
	assert_eq(_count(Formation.available_for(s, f["leader"]), "trinity_nova"), 1,
		"動けないだけのメンバーも三角形に数える")
	var opt := _pick(Formation.available_for(s, f["leader"]), "trinity_nova")
	assert_false(s.resolve_formation(opt, f["enemy_hex"]).is_empty(), "そのまま発動できる")

## 発動者は移動してから発動してよい＝三角形の成立を移動先で判定する。
## 詳細 → doc/gdd/formations.md 発動ルール
func test_triangle_forms_at_move_destination() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var tri := _triangle(c)
	var w1 := Unit.new(1, 0, c + Hex.direction(3) * 2, 3, 8, 40, 30, 1, "wizard")  # 2マス離れて控える
	var w2 := Unit.new(2, 0, tri[1], 3, 8, 40, 30, 1, "wizard")
	var w3 := Unit.new(3, 0, tri[2], 3, 8, 40, 30, 1, "wizard")
	for u in [w1, w2, w3]:
		s.add_unit(u)
	assert_eq(_count(Formation.available_for(s, w1), "trinity_nova"), 0, "いまの位置では成立しない")
	assert_eq(_count(Formation.available_for(s, w1, tri[0]), "trinity_nova"), 1,
		"移動先に立てば三角形が成立する")
	assert_true(s.move_unit(1, tri[0]), "そこへ移動する")
	assert_true(s.has_action_left(1), "移動しただけでは行動を使い切らない")
	var opt := _pick(Formation.available_for(s, w1), "trinity_nova")
	assert_false(opt.is_empty(), "移動後の盤でも成立している")
	assert_false(s.resolve_formation(opt, c + Hex.direction(0) * 3).is_empty(), "移動後に発動できる")
	assert_true(s.is_done(1) and s.is_done(2) and s.is_done(3), "参加3体が行動完了")

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
	assert_eq(_count(opts, "holy_aria"), 1, "占領兵5体クラスタでホーリーアリア")
	var o := _pick(opts, "holy_aria")
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
	assert_eq(_count(Formation.available_for(s, leader), "holy_aria"), 0, "4体では不成立")

## クラスタも三角形と同じ＝発動者が移動先で列に加われば成立する。
func test_cluster_forms_at_move_destination() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	for i in 4:  # 4体が一列に並んでいる（id 2..5）
		s.add_unit(Unit.new(i + 2, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric"))
	var leader := Unit.new(1, 0, c + Hex.direction(0) * 5, 3, 8, 20, 20, 1, "cleric")  # 列から離れている
	s.add_unit(leader)
	assert_eq(_count(Formation.available_for(s, leader), "holy_aria"), 0, "離れていれば不成立")
	var join := c + Hex.direction(0) * 4  # 列の端に隣接する空きマス
	var opts := Formation.available_for(s, leader, join)
	assert_eq(_count(opts, "holy_aria"), 1, "移動先で列に加われば5体クラスタが成立する")
	assert_eq((_pick(opts, "holy_aria")["participants"] as Array).size(), 5, "参加は5体")

## レシピの照合はスキンID。性能(type)が cleric でも見た目がゴブリンなら聖歌隊にならない。
## 詳細 → doc/gdd/formations.md 共通ルール
func test_recipe_matches_by_skin_not_type() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var leader: Unit = null
	for i in 5:
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		u.skin_id = "goblin"  # cleric 性能のゴブリン（unit_skin.json の実在スキン）
		s.add_unit(u)
		if i == 0:
			leader = u
	assert_eq(Formation.available_for(s, leader).size(), 0, "スキンが違えばホーリーアリアは成立しない")

## スキンID明示でも成立する（skin_id 未指定＝type_id へフォールバックは _aria_state 側で担保）。
func test_recipe_matches_with_explicit_skin() -> void:
	var f := _aria_state()
	for u in f["s"].units():
		if u.type_id == "cleric":
			u.skin_id = "cleric"
	assert_eq(_count(Formation.available_for(f["s"], f["leader"]), "holy_aria"), 1, "基準スキン指定でも成立")

func test_holy_aria_buffs_whole_team() -> void:
	var f := _aria_state()
	var s: BattleState = f["s"]
	var ally: Unit = f["ally"]
	var foe: Unit = f["foe"]
	var before := float(Combat.attack_breakdown(s, ally, foe, true)["total"])
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, Vector2i(-9999, -9999))
	assert_false(res.is_empty(), "対象なしでも発動成功")
	assert_almost_eq(float(Combat.attack_breakdown(s, ally, foe, true)["total"]), before * 1.3, 1.0, "離れた味方(fighter)の攻撃も×1.3")
	assert_true(s.is_done(1) and s.is_done(5), "クラスタ全員が行動完了")

## ホーリーアリアの持続＝1ターン（自軍ターン1回＋間の敵ターン）。詳細 → doc/gdd/map.md 用語・ターン
func test_holy_aria_lasts_one_round() -> void:
	var f := _aria_state()
	var s: BattleState = f["s"]
	var ally: Unit = f["ally"]
	var foe: Unit = f["foe"]
	var before := float(Combat.attack_breakdown(s, ally, foe, true)["total"])
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	assert_false(s.resolve_formation(opt, Vector2i(-9999, -9999)).is_empty(), "発動成功")
	s.end_turn()  # 敵ターンへ
	assert_almost_eq(float(Combat.attack_breakdown(s, ally, foe, true)["total"]), before * 1.3, 1.0, "敵ターン中はまだ効く")
	s.end_turn()  # 次の自軍ターンへ＝ここで満了
	assert_almost_eq(float(Combat.attack_breakdown(s, ally, foe, true)["total"]), before, 1.0, "次の自軍ターン開始で切れる")

# ③ディバインジャッジメントの成立盤：paladin＋聖職2の三角形＋射程内(距離 enemy_dist)の敵1体。leader=paladin(id1)。
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
	assert_eq(opts.size(), 1, "ディバインジャッジメントが検出される")
	var o: Dictionary = opts[0]
	assert_eq(String(o["recipe"]), "divine_judgment", "レシピは divine_judgment")
	assert_eq(String(o["effect"]), "single", "単体効果")
	assert_eq(int(o["range"]), 10, "射程10")

func test_divine_judgment_leader_must_be_paladin() -> void:
	# 聖職を選んでもディバインジャッジメントは出ない（発動者はパラディンのみ）。
	var f := _judgment_state()
	var cleric: Unit = f["s"].unit_by_id(2)
	assert_eq(_count(Formation.available_for(f["s"], cleric), "divine_judgment"), 0, "発動者がパラディンでなければ未提示")

## 着弾中心に選べるhex＝コマンドメニューの有効/無効の材料。空なら項目を無効化する
## （攻撃と同じ流儀 → doc/gdd/uiux.md）。単体狙撃は駒の居るhexだけ＝地面には撃てない。
func test_targetable_cells_empty_when_nothing_in_range() -> void:
	var f := _judgment_state(20, 6)
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	assert_true(f["enemy_hex"] in Formation.targetable_cells(s, opt), "射程内の敵は選べる")
	assert_true(s.remove_unit(9), "その敵を盤から外す")
	assert_true(Formation.targetable_cells(s, opt).is_empty(), "狙える駒が無ければ選べる先も無い")

## 射程は移動先から測る＝いま届かなくても、寄れば届く。
func test_targetable_cells_measured_from_move_destination() -> void:
	# 射程10の外に敵を置ける広さ。dir0（axial +q）へ進むと offset の行も q/2 ぶん下がるので、
	# 12マス伸ばすには列だけでなく行も要る（_state() の 12x8 では盤外に落ちる）。
	var s := BattleState.new(24, 16)
	var c := Hex.offset_to_axial(3, 3)
	var tri := _triangle(c)
	s.add_unit(Unit.new(1, 0, tri[0], 3, 8, 50, 50, 1, "paladin"))
	s.add_unit(Unit.new(2, 0, tri[1], 3, 8, 20, 20, 1, "cleric"))
	s.add_unit(Unit.new(3, 0, tri[2], 3, 8, 20, 20, 1, "priest"))
	var enemy_hex := c + Hex.direction(0) * 12  # 発動者から距離12＝射程10の外
	s.add_unit(Unit.new(9, 1, enemy_hex, 3, 8, 10, 20))
	var opt: Dictionary = Formation.available_for(s, s.unit_by_id(1))[0]
	assert_true(Formation.targetable_cells(s, opt).is_empty(), "いまの位置からは射程外")
	assert_true(enemy_hex in Formation.targetable_cells(s, opt, c + Hex.direction(0) * 2),
		"2マス寄った位置からなら射程内")

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
	var f := _trinity_nova_state(100)  # 硬い敵＝非撃破で損害が兵数上限に張り付かない範囲
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
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	s.resolve_formation(opt, f["enemy_hex"])
	assert_true(s.is_done(1) and s.is_done(2) and s.is_done(3), "参加3体が行動完了")

func test_area_hits_allies_too() -> void:
	# フレンドリーファイア: 着弾中心の7hexに居る敵も味方も当たる（発動者3体は除外）。
	var f := _trinity_nova_state()
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
	var f := _trinity_nova_state()
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
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var far := Hex.offset_to_axial(3, 3) + Hex.direction(0) * 8  # 全参加者から射程5超
	assert_true(s.resolve_formation(opt, far).is_empty(), "射程外は不成立（空dict）")

func test_participants_gain_level() -> void:
	# 撃破なし＝発動で全員+1（Lv1→Lv2）。硬い敵で一撃では死なせない。
	var f := _trinity_nova_state(100)
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	s.resolve_formation(opt, f["enemy_hex"])
	assert_not_null(s.unit_by_id(9), "硬い敵は生存（非撃破ケースの前提）")
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_id(pid).level, 2, "参加者%d は発動でLv+1" % pid)

func test_empty_cast_grants_no_level() -> void:
	# 面に敵が1体も居ない空撃ちはLv+0（ただし参加者は行動完了）。
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	var empty := Hex.offset_to_axial(3, 3) + Hex.direction(3) * 2  # 射程内・面に駒なし
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, empty)
	assert_eq((res["results"] as Array).size(), 0, "空撃ち＝着弾なし")
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_id(pid).level, 1, "空撃ちはLv+0（Lv1のまま）")
	assert_true(s.is_done(1), "空撃ちでも行動完了")

func test_kill_grants_extra_level() -> void:
	# 撃破が1体でもあれば +2（Lv1→Lv3）。
	var f := _trinity_nova_state(1)  # 低防御＝撃破される
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	s.resolve_formation(opt, f["enemy_hex"])
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_id(pid).level, 3, "撃破時は参加者%d がLv+2" % pid)

func test_resolve_kills_when_lethal() -> void:
	# 防御が薄い敵は撃破され盤から消える。
	var f := _trinity_nova_state(1)  # 低防御
	var s: BattleState = f["s"]
	var opt: Dictionary = Formation.available_for(s, f["leader"])[0]
	var res := s.resolve_formation(opt, f["enemy_hex"])
	assert_true(bool(res["results"][0]["killed"]), "撃破フラグ")
	assert_null(s.unit_by_id(9), "撃破された敵は盤から消える")

func test_is_unit_skill_splits_catalog_by_shape() -> void:
	# 演出・効果音の出し分けが読む区別（陣形＝カットインあり／ユニットスキル＝音だけ）。
	assert_true(Formation.is_unit_skill("pixie_dust"), "単独発動(shape=solo)はユニットスキル")
	assert_false(Formation.is_unit_skill("trinity_nova"), "複数人のレシピは陣形")
	assert_false(Formation.is_unit_skill("holy_aria"), "クラスタも陣形")
	assert_false(Formation.is_unit_skill("no_such_recipe"), "未知のIDは陣形扱い（落ちない）")
