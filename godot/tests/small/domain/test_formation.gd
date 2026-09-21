extends GutTest
## 陣形スキル（スライスA＝フレームワーク＋①トリニティノヴァ）の検出・威力・適用を検証する。
## 詳細 → doc/gdd/formations.md, doc/gdd/combat.md §2

func _state() -> BattleState:
	return BattleState.new(12, 8)

## そのスキルの選択肢だけを数える。聖職はピュリファイ（ユニットスキル）も単独で撃てるので、
## 選択肢の総数で陣形スキルの成立を判定すると混ざる。詳細 → doc/gdd/skills.md
func _count(opts: Array[FormationOption], skill: String) -> int:
	var n := 0
	for o in opts:
		if o.skill == skill:
			n += 1
	return n

## そのスキルの選択肢を1つ取り出す（無ければ null）。
func _pick(opts: Array[FormationOption], skill: String) -> FormationOption:
	for o in opts:
		if o.skill == skill:
			return o
	return null

# 相互隣接の三角形を作る3つの axial（C, C+dir0, C+dir1 は互いに距離1）。
func _triangle(c: Vector2i) -> Array:
	return [c, Hex.neighbor(c, 0), Hex.neighbor(c, 1)]

# トリニティノヴァの成立盤：wizard 3体が三角形＋離れた位置に敵1体。caster=id1。
func _trinity_nova_state(enemy_def := 20) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var tri := _triangle(c)
	var w1 := Unit.new(1, 0, tri[0], 3, 8, 40, 30, 1, "wizard")
	var w2 := Unit.new(2, 0, tri[1], 3, 8, 40, 30, 1, "wizard")
	var w3 := Unit.new(3, 0, tri[2], 3, 8, 40, 30, 1, "wizard")
	w1.pierce = 0.5  # 発動者＝魔法兵（貫通の出どころ）
	var enemy_hex := c + Hex.direction(0) * 3  # caster から距離3（射程5内・面には他の駒なし）
	var enemy := Unit.new(9, 1, enemy_hex, 3, 8, 10, enemy_def)
	for u in [w1, w2, w3, enemy]:
		s.add_unit(u)
	return {"s": s, "caster": w1, "enemy": enemy, "enemy_hex": enemy_hex}

# --- 検出 ---

## 陣形スキルは必ず分類（表Aの「分類」列）を持つ＝クロニクルの束ね。ユニットスキルは持たない。
## 詳細 → doc/gdd/chronicle.md 陣形スキル
func test_formation_skills_have_category() -> void:
	for rid in Formation.SKILLS:
		var r: Dictionary = Formation.SKILLS[rid]
		if Formation.is_unit_skill(rid):
			assert_false(r.has("category"), "%s: ユニットスキルは分類を持たない" % rid)
		else:
			assert_true(Formation.CATEGORIES.has(r.get("category", "")),
				"%s: 分類が表Aの値でない" % rid)

func test_available_detects_trinity_nova_triangle() -> void:
	var f := _trinity_nova_state()
	var opts := Formation.available_for(f["s"], f["caster"])
	assert_eq(opts.size(), 1, "三角形のトリニティノヴァが1つ検出される")
	var o: FormationOption = opts[0]
	assert_eq(o.skill, "trinity_nova", "スキルは trinity_nova")
	assert_eq(o.participants.size(), 3, "参加3体")
	assert_true(o.needs_target(), "面攻撃は対象指定が要る")

func test_no_triangle_when_not_adjacent() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var w1 := Unit.new(1, 0, c, 3, 8, 40, 30, 1, "wizard")
	var w2 := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 40, 30, 1, "wizard")
	var w3 := Unit.new(3, 0, c + Hex.direction(0) * 4, 3, 8, 40, 30, 1, "wizard")  # 離れている
	for u in [w1, w2, w3]:
		s.add_unit(u)
	assert_eq(Formation.available_for(s, w1).size(), 0, "三角形にならなければ検出0")

## ①は三角形のまま＝発動者を挟んで左右対称（dir0 と dir3）では成立しない（③との違い）。
func test_trinity_nova_rejects_flanking_members() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var w1 := Unit.new(1, 0, c, 3, 8, 40, 30, 1, "wizard")
	var w2 := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 40, 30, 1, "wizard")
	var w3 := Unit.new(3, 0, Hex.neighbor(c, 3), 3, 8, 40, 30, 1, "wizard")
	for u in [w1, w2, w3]:
		s.add_unit(u)
	assert_eq(_count(Formation.available_for(s, w1), "trinity_nova"), 0,
		"メンバー同士が隣接していなければ三角形にならない")

func test_caster_type_gates_skill() -> void:
	# クレリックを選んでもトリニティノヴァ（魔法兵）は出ない。
	var f := _trinity_nova_state()
	var cleric := Unit.new(20, 0, Hex.offset_to_axial(1, 1), 3, 8, 20, 20, 1, "cleric")
	f["s"].add_unit(cleric)
	assert_eq(_count(Formation.available_for(f["s"], cleric), "trinity_nova"), 0, "caster_type 不一致は検出0")

func test_done_member_excluded() -> void:
	var f := _trinity_nova_state()
	f["s"].set_done(2)  # member を行動済みに
	assert_eq(Formation.available_for(f["s"], f["caster"]).size(), 0, "行動済みメンバーは三角形に数えない")

## 発動に移動先も攻撃相手も要らない＝行き止まりのメンバーも参加できる。
## 囲まれて動けないだけの駒を除外すると、密集した盤で陣形が組めなくなる。
func test_stuck_member_still_counts() -> void:
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	s.unit_by_handle(2).move = 0  # 行ける先が無い（瓦礫や味方に囲まれた駒と同じ状態）
	assert_true(s.is_stuck(2), "前提: メンバーに打つ手が無い")
	assert_false(s.is_done(2), "前提: 行動は使っていない")
	assert_eq(_count(Formation.available_for(s, f["caster"]), "trinity_nova"), 1,
		"動けないだけのメンバーも三角形に数える")
	var opt := _pick(Formation.available_for(s, f["caster"]), "trinity_nova")
	assert_not_null(FormationResolver.resolve(s, opt, f["enemy_hex"]), "そのまま発動できる")

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
	assert_not_null(opt, "移動後の盤でも成立している")
	assert_not_null(FormationResolver.resolve(s, opt, c + Hex.direction(0) * 3), "移動後に発動できる")
	assert_true(s.is_done(1) and s.is_done(2) and s.is_done(3), "参加3体が行動完了")

# ②グレイスの成立盤：占領兵5体が隣接連結（一列）＋離れた味方(fighter)＋敵。caster=id1。
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
	return {"s": s, "caster": clerics[0], "ally": ally, "foe": foe}

func test_grace_offered_with_five_clustered() -> void:
	var f := _aria_state()
	var opts := Formation.available_for(f["s"], f["caster"])
	assert_eq(_count(opts, "grace"), 1, "占領兵5体クラスタでグレイス")
	var o := _pick(opts, "grace")
	assert_eq(o.skill, "grace", "スキルは grace")
	assert_eq(o.effect, FormationOption.Effect.BUFF, "バフ効果")
	assert_false(o.needs_target(), "バフは対象指定不要")

## 占領兵 n 体を一列に並べた盤。先頭（id 1）が発動者。全体バフ確認用の fighter と敵も置く。
func _cluster_state(n: int) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var caster: Unit = null
	for i in n:
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		if i == 0:
			caster = u
	var ally := Unit.new(10, 0, Hex.offset_to_axial(4, 6), 3, 8, 40, 40, 1, "fighter")
	var foe := Unit.new(11, 1, Hex.neighbor(ally.pos, 0), 3, 8, 30, 30)
	s.add_unit(ally)
	s.add_unit(foe)
	return {"s": s, "caster": caster, "ally": ally, "foe": foe}

## 補正は参加人数で伸びる＝基準5体 ×1.30、1体増えるごとに +0.05。詳細 → doc/gdd/formations.md ②
func test_grace_value_grows_with_participants() -> void:
	for pair in [[5, 1.30], [6, 1.35], [8, 1.45]]:
		var n: int = pair[0]
		var expected: float = pair[1]
		var f := _cluster_state(n)
		var s: BattleState = f["s"]
		var opt := _pick(Formation.available_for(s, f["caster"]), "grace")
		assert_eq(opt.participants.size(), n, "%d体全員が参加" % n)
		var before := Combat.attack_breakdown(s, f["ally"], f["foe"], true).total
		var res := FormationResolver.resolve(s, opt, Vector2i(-9999, -9999))
		assert_almost_eq(float(res.status["value"]), expected, 0.001, "%d体で ×%.2f" % [n, expected])
		assert_almost_eq(Combat.attack_breakdown(s, f["ally"], f["foe"], true).total,
			before * expected, 1.0, "%d体のグレイスで味方の攻撃が ×%.2f" % [n, expected])

## 発動後にクラスタが減っても、掛かった補正は発動時の人数のまま。
func test_grace_value_is_baked_at_cast() -> void:
	var f := _cluster_state(6)
	var s: BattleState = f["s"]
	var opt := _pick(Formation.available_for(s, f["caster"]), "grace")
	assert_not_null(FormationResolver.resolve(s, opt, Vector2i(-9999, -9999)), "発動成功")
	s.remove_unit(6)  # 参加者を1体失う
	var mods := s.status_mods_for(f["ally"])
	assert_eq(mods.size(), 1, "味方に掛かっている補正は1件")
	assert_almost_eq(float(mods[0]["value"]), 1.35, 0.001, "6体で発動した ×1.35 のまま")

func test_grace_needs_five() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var caster: Unit = null
	for i in 4:  # 4体だけ＝不成立
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		if i == 0:
			caster = u
	assert_eq(_count(Formation.available_for(s, caster), "grace"), 0, "4体では不成立")

## パラディンも占領兵＝グレイスの頭数に入る（クレリック4＋パラディン1で成立）。詳細 → doc/gdd/formations.md ②
func test_grace_counts_paladin() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var caster: Unit = null
	for i in 4:
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		s.add_unit(u)
		if i == 0:
			caster = u
	s.add_unit(Unit.new(5, 0, c + Hex.direction(0) * 4, 3, 8, 50, 50, 1, "paladin"))
	var opt := _pick(Formation.available_for(s, caster), "grace")
	assert_not_null(opt, "クレリック4＋パラディン1でグレイス")
	assert_eq(opt.participants.size(), 5, "パラディンを含む5体が参加")

## クラスタも三角形と同じ＝発動者が移動先で列に加われば成立する。
func test_cluster_forms_at_move_destination() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	for i in 4:  # 4体が一列に並んでいる（id 2..5）
		s.add_unit(Unit.new(i + 2, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric"))
	var caster := Unit.new(1, 0, c + Hex.direction(0) * 5, 3, 8, 20, 20, 1, "cleric")  # 列から離れている
	s.add_unit(caster)
	assert_eq(_count(Formation.available_for(s, caster), "grace"), 0, "離れていれば不成立")
	var join := c + Hex.direction(0) * 4  # 列の端に隣接する空きマス
	var opts := Formation.available_for(s, caster, join)
	assert_eq(_count(opts, "grace"), 1, "移動先で列に加われば5体クラスタが成立する")
	assert_eq(_pick(opts, "grace").participants.size(), 5, "参加は5体")

## スキルの照合はスキンID。性能(type)が cleric でも見た目がゴブリンなら聖歌隊にならない。
## 詳細 → doc/gdd/formations.md 共通ルール
func test_skill_matches_by_skin_not_type() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var caster: Unit = null
	for i in 5:
		var u := Unit.new(i + 1, 0, c + Hex.direction(0) * i, 3, 8, 20, 20, 1, "cleric")
		u.skin_id = "goblin"  # cleric 性能のゴブリン（unit_skin.json の実在スキン）
		s.add_unit(u)
		if i == 0:
			caster = u
	assert_eq(Formation.available_for(s, caster).size(), 0, "スキンが違えばグレイスは成立しない")

## スキンID明示でも成立する（skin_id 未指定＝type_id へフォールバックは _aria_state 側で担保）。
func test_skill_matches_with_explicit_skin() -> void:
	var f := _aria_state()
	for u in f["s"].units():
		if u.type_id == "cleric":
			u.skin_id = "cleric"
	assert_eq(_count(Formation.available_for(f["s"], f["caster"]), "grace"), 1, "基準スキン指定でも成立")

func test_grace_buffs_whole_team() -> void:
	var f := _aria_state()
	var s: BattleState = f["s"]
	var ally: Unit = f["ally"]
	var foe: Unit = f["foe"]
	var before := Combat.attack_breakdown(s, ally, foe, true).total
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	var res := FormationResolver.resolve(s, opt, Vector2i(-9999, -9999))
	assert_not_null(res, "対象なしでも発動成功")
	assert_almost_eq(Combat.attack_breakdown(s, ally, foe, true).total, before * 1.3, 1.0, "離れた味方(fighter)の攻撃も×1.3")
	assert_true(s.is_done(1) and s.is_done(5), "クラスタ全員が行動完了")

## グレイスの持続＝1ターン（自軍ターン1回＋間の敵ターン）。詳細 → doc/gdd/map.md 用語・ターン
func test_grace_lasts_one_round() -> void:
	var f := _aria_state()
	var s: BattleState = f["s"]
	var ally: Unit = f["ally"]
	var foe: Unit = f["foe"]
	var before := Combat.attack_breakdown(s, ally, foe, true).total
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	assert_not_null(FormationResolver.resolve(s, opt, Vector2i(-9999, -9999)), "発動成功")
	s.end_turn()  # 敵ターンへ
	assert_almost_eq(Combat.attack_breakdown(s, ally, foe, true).total, before * 1.3, 1.0, "敵ターン中はまだ効く")
	s.end_turn()  # 次の自軍ターンへ＝ここで満了
	assert_almost_eq(Combat.attack_breakdown(s, ally, foe, true).total, before, 1.0, "次の自軍ターン開始で切れる")

# ③ディバインジャッジメントの成立盤：paladin の周囲に聖職2体＋射程内(距離 enemy_dist)の敵1体。
# caster=paladin(id1)。この盤は聖職同士も隣接する置き方（三角）だが、③の条件は発動者への隣接だけ。
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
	return {"s": s, "caster": pal, "enemy": enemy, "enemy_hex": enemy_hex}

func test_divine_judgment_offered() -> void:
	var f := _judgment_state()
	var opts := Formation.available_for(f["s"], f["caster"])
	assert_eq(opts.size(), 1, "ディバインジャッジメントが検出される")
	var o: FormationOption = opts[0]
	assert_eq(o.skill, "divine_judgment", "スキルは divine_judgment")
	assert_eq(o.effect, FormationOption.Effect.SINGLE, "単体効果")
	assert_eq(o.max_range, 10, "射程10")

func test_divine_judgment_caster_must_be_paladin() -> void:
	# 聖職を選んでもディバインジャッジメントは出ない（発動者はパラディンのみ）。
	var f := _judgment_state()
	var cleric: Unit = f["s"].unit_by_handle(2)
	assert_eq(_count(Formation.available_for(f["s"], cleric), "divine_judgment"), 0, "発動者がパラディンでなければ未提示")

## ③は「パラディンを中心に、周囲に聖職2体」＝聖職同士の隣接は問わない。
## 発動者を挟んで左右（dir0 と dir3）に置く形でも成立する。詳細 → doc/gdd/formations.md
func test_divine_judgment_allows_flanking_members() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var pal := Unit.new(1, 0, c, 3, 8, 50, 50, 1, "paladin")
	var c1 := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 20, 20, 1, "cleric")
	var c2 := Unit.new(3, 0, Hex.neighbor(c, 3), 3, 8, 20, 20, 1, "priest")
	for u in [pal, c1, c2]:
		s.add_unit(u)
	assert_eq(Hex.distance(c1.pos, c2.pos), 2, "前提: 聖職同士は隣接していない")
	assert_eq(_count(Formation.available_for(s, pal), "divine_judgment"), 1,
		"発動者を挟んで左右でも成立する")

func test_divine_judgment_needs_two_adjacent_clergy() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var pal := Unit.new(1, 0, c, 3, 8, 50, 50, 1, "paladin")
	var c1 := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 20, 20, 1, "cleric")
	var c2 := Unit.new(3, 0, c + Hex.direction(3) * 2, 3, 8, 20, 20, 1, "priest")  # 発動者に隣接しない
	for u in [pal, c1, c2]:
		s.add_unit(u)
	assert_eq(_count(Formation.available_for(s, pal), "divine_judgment"), 0,
		"発動者に隣接する聖職が1体では不成立")

## 着弾中心に選べるhex＝コマンドメニューの有効/無効の材料。空なら項目を無効化する
## （攻撃と同じ流儀 → doc/gdd/uiux.md）。単体狙撃は駒の居るhexだけ＝地面には撃てない。
func test_targetable_cells_empty_when_nothing_in_range() -> void:
	var f := _judgment_state(20, 6)
	var s: BattleState = f["s"]
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
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
	var opt: FormationOption = Formation.available_for(s, s.unit_by_handle(1))[0]
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
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	var res := FormationResolver.resolve(s, opt, center)
	var ids: Array = []
	for r in res.hits:
		ids.append(r.target_id)
	assert_true(9 in ids, "狙ったヘックスの敵に着弾")
	assert_false(10 in ids, "単体＝隣の敵には及ばない")

func test_single_uses_caster_attack() -> void:
	var f := _judgment_state(100)  # 硬い敵で非撃破
	var s: BattleState = f["s"]
	var enemy: Unit = f["enemy"]
	var caster: Unit = f["caster"]
	var opt: FormationOption = Formation.available_for(s, caster)[0]
	var single := Combat.attack_breakdown(s, caster, enemy, false)
	var df := Combat.defense_breakdown(s, enemy, caster, false)
	var expect := Combat.hit_from_breakdowns(single, df, enemy.troops).loss
	var res := FormationResolver.resolve(s, opt, f["enemy_hex"])
	assert_gt(expect, 0, "非撃破でも損害はある（テスト前提）")
	assert_eq(res.hits[0].loss, expect, "発動者(パラディン)の実効攻撃力での損害")

func test_single_hits_aerial_with_ground_attack() -> void:
	# 陣形スキルの威力は常に対地値＝atk_air 0 のパラディンでも飛行の敵に同じ威力で通る。
	# 詳細 → doc/gdd/formations.md「面・射程・持続で払わせ、威力では払わせない」
	var ground := _judgment_state(100)  # 硬い敵で非撃破
	var g_opt: FormationOption = Formation.available_for(ground["s"], ground["caster"])[0]
	var g_res := FormationResolver.resolve(ground["s"], g_opt, ground["enemy_hex"])
	var g_loss := g_res.hits[0].loss
	assert_gt(g_loss, 0, "対地の敵には損害が出る前提")
	var air := _judgment_state(100)
	var foe: Unit = air["enemy"]
	foe.move_type = "flight"  # 同条件の敵を飛行にする（テストのパラディンも実データ同様 atk_air=0）
	var a_opt: FormationOption = Formation.available_for(air["s"], air["caster"])[0]
	var a_res := FormationResolver.resolve(air["s"], a_opt, air["enemy_hex"])
	assert_eq(a_res.hits[0].loss, g_loss, "飛行の敵にも対地と同じ損害")

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
	var opt: FormationOption = Formation.available_for(s, pal)[0]
	assert_null(FormationResolver.resolve(s, opt, far_hex), "射程外は不成立（空dict）")

# --- 威力・適用 ---

func test_resolve_uses_caster_attack() -> void:
	# 面ダメージ＝発動者1体の実効攻撃力（合算しない）。単体の hit と一致する。
	var f := _trinity_nova_state(100)  # 硬い敵＝非撃破で損害が兵数上限に張り付かない範囲
	var s: BattleState = f["s"]
	var enemy: Unit = f["enemy"]
	var caster: Unit = f["caster"]
	var opt: FormationOption = Formation.available_for(s, caster)[0]
	var single := Combat.attack_breakdown(s, caster, enemy, false)
	var df := Combat.defense_breakdown(s, enemy, caster, false)
	var expect := Combat.hit_from_breakdowns(single, df, enemy.troops).loss
	var before := enemy.troops
	var res := FormationResolver.resolve(s, opt, f["enemy_hex"])
	assert_eq(res.hits.size(), 1, "敵1体に着弾")
	assert_gt(expect, 0, "非撃破でも損害はある（テスト前提）")
	assert_eq(res.hits[0].loss, expect, "発動者1体の実効攻撃力での損害と一致（合算しない）")
	assert_eq(enemy.troops, before - expect, "敵の兵数が損害ぶん減る")

func test_resolve_marks_participants_done() -> void:
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	FormationResolver.resolve(s, opt, f["enemy_hex"])
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
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	var res := FormationResolver.resolve(s, opt, center)
	var hit_ids: Array = []
	for r in res.hits:
		hit_ids.append(r.target_id)
	assert_true(9 in hit_ids and 10 in hit_ids, "面内の敵2体に着弾")
	assert_true(11 in hit_ids, "面内の味方も巻き込む")
	assert_lt(ally.troops, ally_before, "味方の兵数も減る")

func test_area_excludes_participants() -> void:
	# 発動者3体が着弾範囲に入っても自傷しない（詠唱の源）。caster を中心に撃つ。
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	var caster: Unit = f["caster"]
	var w2_before := s.unit_by_handle(2).troops
	var enemy := Unit.new(12, 1, Hex.neighbor(caster.pos, 2), 3, 8, 10, 20)  # caster隣接の敵
	s.add_unit(enemy)
	var opt: FormationOption = Formation.available_for(s, caster)[0]
	var res := FormationResolver.resolve(s, opt, caster.pos)  # 中心＝caster＝面に発動者3体が入る
	var hit_ids: Array = []
	for r in res.hits:
		hit_ids.append(r.target_id)
	assert_true(12 in hit_ids, "面内の敵には当たる")
	assert_false(1 in hit_ids or 2 in hit_ids or 3 in hit_ids, "発動者3体は着弾対象から除外")
	assert_eq(s.unit_by_handle(2).troops, w2_before, "発動者の兵数は不変")

func test_resolve_out_of_range_fails() -> void:
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	var far := Hex.offset_to_axial(3, 3) + Hex.direction(0) * 8  # 全参加者から射程5超
	assert_null(FormationResolver.resolve(s, opt, far), "射程外は不成立（空dict）")

func test_participants_gain_level() -> void:
	# 撃破なし＝発動で全員+1（Lv1→Lv2）。硬い敵で一撃では死なせない。
	var f := _trinity_nova_state(100)
	var s: BattleState = f["s"]
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	FormationResolver.resolve(s, opt, f["enemy_hex"])
	assert_not_null(s.unit_by_handle(9), "硬い敵は生存（非撃破ケースの前提）")
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_handle(pid).level, 2, "参加者%d は発動でLv+1" % pid)

func test_empty_cast_grants_no_level() -> void:
	# 面に敵が1体も居ない空撃ちはLv+0（ただし参加者は行動完了）。
	var f := _trinity_nova_state()
	var s: BattleState = f["s"]
	var empty := Hex.offset_to_axial(3, 3) + Hex.direction(3) * 2  # 射程内・面に駒なし
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	var res := FormationResolver.resolve(s, opt, empty)
	assert_eq(res.hits.size(), 0, "空撃ち＝着弾なし")
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_handle(pid).level, 1, "空撃ちはLv+0（Lv1のまま）")
	assert_true(s.is_done(1), "空撃ちでも行動完了")

func test_kill_grants_extra_level() -> void:
	# 撃破が1体でもあれば +2（Lv1→Lv3）。
	var f := _trinity_nova_state(1)  # 低防御＝撃破される
	var s: BattleState = f["s"]
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	FormationResolver.resolve(s, opt, f["enemy_hex"])
	for pid in [1, 2, 3]:
		assert_eq(s.unit_by_handle(pid).level, 3, "撃破時は参加者%d がLv+2" % pid)

func test_resolve_kills_when_lethal() -> void:
	# 防御が薄い敵は撃破され盤から消える。
	var f := _trinity_nova_state(1)  # 低防御
	var s: BattleState = f["s"]
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	var res := FormationResolver.resolve(s, opt, f["enemy_hex"])
	assert_true(res.hits[0].killed, "撃破フラグ")
	assert_null(s.unit_by_handle(9), "撃破された敵は盤から消える")

func test_is_unit_skill_splits_catalog_by_shape() -> void:
	# 演出・効果音の出し分けが読む区別（陣形＝カットインあり／ユニットスキル＝音だけ）。
	assert_true(Formation.is_unit_skill("pixie_dust"), "単独発動(shape=solo)はユニットスキル")
	assert_false(Formation.is_unit_skill("trinity_nova"), "複数人のスキルは陣形")
	assert_false(Formation.is_unit_skill("grace"), "クラスタも陣形")
	assert_false(Formation.is_unit_skill("no_such_skill"), "未知のIDは陣形扱い（落ちない）")

# --- スキルレポート用の result（→ doc/tech/combat_scene.md 右パネル（スキルレポート）） ---

func test_result_carries_snapshots_and_attack_breakdown() -> void:
	# 撃破で盤から消えても名前と兵数を出せるよう、発動者・対象のスナップショットを result に載せる。
	# 攻撃側の内訳は total だけでなく係数ごと＝レポートが戦闘と同じ3列表を出せる。
	var f := _trinity_nova_state(1)  # 低防御＝撃破
	var s: BattleState = f["s"]
	var caster_unit: Unit = f["caster"]
	var opt: FormationOption = Formation.available_for(s, caster_unit)[0]
	var res := FormationResolver.resolve(s, opt, f["enemy_hex"])
	var caster := res.caster
	assert_eq(caster.handle, caster_unit.handle, "発動者のスナップショット")
	assert_eq(caster.level, 1, "スナップショットは発動前（Lv加算前）に固める")
	var r := res.hits[0]
	var v := r.victim
	assert_eq(v.troops_before, 8, "対象の発動前兵数")
	assert_eq(v.troops_after, 0, "撃破＝0")
	var atk := r.detail.attack
	for key in ["troops", "stat", "level", "surround", "terrain", "total"]:
		assert_not_null(atk.get(key), "攻撃側の内訳に %s が載る" % key)

func test_grace_result_carries_status_entry() -> void:
	# 損害の出ないスキルはレポートが効果と持続を出す＝積んだ状態補正エントリを result にも載せる。
	var f := _aria_state()
	var s: BattleState = f["s"]
	var opt: FormationOption = Formation.available_for(s, f["caster"])[0]
	var res := FormationResolver.resolve(s, opt, Vector2i(-9999, -9999))
	var st := res.status
	assert_eq(String(st["op"]), "mul", "グレイスは乗算バフ")
	assert_almost_eq(float(st["value"]), 1.3, 0.001, "×1.3")
	assert_eq(int(st["remaining"]), 1, "持続1ターン")
	assert_not_null(res.caster, "バフでも発動者スナップショットが載る")

# --- レシピ単位のまとめ（参加者を選ぶ）---

## そのスキルのまとめを取り出す（無ければ null）。
func _choice(cs: Array[FormationChoice], skill: String) -> FormationChoice:
	for c in cs:
		if c.skill == skill:
			return c
	return null

## 発動者の周囲3方向（dir0/dir1/dir2）に候補を置いた盤。dir0-dir1・dir1-dir2 は隣接、dir0-dir2 は距離2。
## ①は三角が2通り（caster+dir0+dir1／caster+dir1+dir2）、③は組が3通りになる。
func _fan_state(caster_skin: String, member_skin: String) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(4, 4)
	var lead := Unit.new(1, 0, c, 3, 8, 50, 50, 1, caster_skin)
	var m0 := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 20, 20, 1, member_skin)
	var m1 := Unit.new(3, 0, Hex.neighbor(c, 1), 3, 8, 20, 20, 1, member_skin)
	var m2 := Unit.new(4, 0, Hex.neighbor(c, 2), 3, 8, 20, 20, 1, member_skin)
	for u in [lead, m0, m1, m2]:
		s.add_unit(u)
	return {"s": s, "caster": lead}

## 組が複数あってもメニューの項目は1つ＝レシピ単位に畳む（組は member_sets に内包する）。
func test_choices_fold_sets_into_one_item() -> void:
	var f := _fan_state("paladin", "cleric")
	var s: BattleState = f["s"]
	assert_eq(_count(Formation.available_for(s, f["caster"]), "divine_judgment"), 3, "前提: 組は3通り")
	var cs := Formation.choices_for(s, f["caster"])
	var c := _choice(cs, "divine_judgment")
	assert_not_null(c, "ディバインジャッジメントの項目が1つ出る")
	assert_eq(c.member_sets.size(), 3, "3組を内包する")
	assert_eq(c.pool.size(), 3, "候補の駒は3体")
	assert_true(c.needs_choice(), "組が複数＝参加者を選ぶ段を挟む")

## 組が1つしかない固定人数のスキルは参加者選びの段を飛ばす。
func test_choice_skipped_when_single_set() -> void:
	var f := _judgment_state()
	var c := _choice(Formation.choices_for(f["s"], f["caster"]), "divine_judgment")
	assert_false(c.needs_choice(), "組が1つ＝選ぶ余地が無い")
	assert_eq(c.forced_members(), [2, 3] as Array[int], "そのまま参加者が決まる")

## ①は1体目を確定すると2体目の候補が絞られる（1体目と組める駒だけ）。
func test_member_candidates_narrow_after_first_pick() -> void:
	var f := _fan_state("wizard", "wizard")
	var s: BattleState = f["s"]
	var c := _choice(Formation.choices_for(s, f["caster"]), "trinity_nova")
	var none: Array[int] = []
	assert_eq(Formation.member_candidates(s, c, none), [2, 3, 4] as Array[int], "はじめは3体とも候補")
	assert_eq(Formation.member_candidates(s, c, [2] as Array[int]), [3] as Array[int],
		"dir0 を選んだら、それと隣接する dir1 だけが残る")
	assert_eq(Formation.member_candidates(s, c, [3] as Array[int]), [2, 4] as Array[int],
		"dir1 を選んだら両隣が残る")

## ③は発動者への隣接だけを見るので、1体目を確定しても候補は絞られない。
func test_escort_candidates_not_narrowed() -> void:
	var f := _fan_state("paladin", "cleric")
	var s: BattleState = f["s"]
	var c := _choice(Formation.choices_for(s, f["caster"]), "divine_judgment")
	assert_eq(Formation.member_candidates(s, c, [2] as Array[int]), [3, 4] as Array[int],
		"メンバー同士の隣接は問わない")

## 人数が固定のスキルは人数ちょうどで発動できる（足りなければ不可）。
func test_can_activate_fixed_count() -> void:
	var f := _fan_state("paladin", "cleric")
	var c := _choice(Formation.choices_for(f["s"], f["caster"]), "divine_judgment")
	assert_false(Formation.can_activate(c, [2] as Array[int]), "発動者＋1体では足りない")
	assert_true(Formation.can_activate(c, [2, 3] as Array[int]), "発動者＋2体で発動できる")

## ②は最低人数を超える候補があれば参加者を選ぶ。候補は連結を保つ駒だけ＝端から伸ばす。
func test_cluster_candidates_keep_connection() -> void:
	var f := _cluster_state(7)
	var s: BattleState = f["s"]
	var c := _choice(Formation.choices_for(s, f["caster"]), "grace")
	assert_true(c.variable_count, "②は人数が可変")
	assert_eq(c.pool.size(), 6, "発動者を除く候補は6体")
	assert_true(c.needs_choice(), "候補が最低人数を超える＝参加者を選ぶ")
	var none: Array[int] = []
	assert_eq(Formation.member_candidates(s, c, none), [2] as Array[int], "列の隣だけが候補")
	assert_eq(Formation.member_candidates(s, c, [2] as Array[int]), [3] as Array[int], "確定した先の隣へ伸びる")
	assert_false(Formation.can_activate(c, [2, 3] as Array[int]), "5体に満たなければ発動できない")
	assert_true(Formation.can_activate(c, [2, 3, 4, 5] as Array[int]), "最低人数に達したら発動できる")
	assert_true(Formation.can_activate(c, [2, 3, 4, 5, 6] as Array[int]), "さらに足しても発動できる")

## 候補が最低人数ちょうどなら選ぶ余地が無い＝段を飛ばして全員が参加する。
func test_cluster_choice_skipped_at_minimum() -> void:
	var f := _cluster_state(5)
	var c := _choice(Formation.choices_for(f["s"], f["caster"]), "grace")
	assert_false(c.needs_choice(), "5体ちょうど＝選ぶ余地が無い")
	assert_eq(c.forced_members().size(), 4, "発動者を除く4体がそのまま参加者")

## 効果は選んだ人数で決まる＝8体固まっていても5体だけ供出すれば基準の補正になる。
func test_grace_value_follows_chosen_members() -> void:
	var f := _cluster_state(8)
	var s: BattleState = f["s"]
	var c := _choice(Formation.choices_for(s, f["caster"]), "grace")
	var opt := Formation.option_of(s, c, [2, 3, 4, 5] as Array[int])
	assert_eq(opt.participants.size(), 5, "発動者＋4体＝5体で撃つ")
	assert_eq(opt.caster_id, 1, "先頭が発動者")
	var res := FormationResolver.resolve(s, opt, Vector2i(-9999, -9999))
	assert_almost_eq(float(res.status["value"]), 1.3, 0.001, "5体ぶんの補正")
	assert_false(s.is_done(6), "選ばなかった駒は行動を残す")

## メニューの無効化の判断＝どの組でも撃てる先が無いときだけ無効。
func test_choice_has_target() -> void:
	var f := _judgment_state()
	var s: BattleState = f["s"]
	var c := _choice(Formation.choices_for(s, f["caster"]), "divine_judgment")
	assert_true(Formation.choice_has_target(s, c), "射程内に敵が居る")
	s.remove_unit(9)
	var c2 := _choice(Formation.choices_for(s, f["caster"]), "divine_judgment")
	assert_false(Formation.choice_has_target(s, c2), "撃てる先が無い")

## ユニットスキル（単独発動）も同じ器に乗る＝参加者を選ぶ段は無い。
func test_unit_skill_choice_has_no_members() -> void:
	var f := _judgment_state()
	var cleric: Unit = f["s"].unit_by_handle(2)
	var c := _choice(Formation.choices_for(f["s"], cleric), "purify")
	assert_not_null(c, "ピュリファイの項目が出る")
	assert_false(c.needs_choice(), "単独で撃つ＝選ぶ余地が無い")
	assert_true(c.forced_members().is_empty(), "参加者は発動者だけ")

# --- ④トリックショット（弓兵＋斥候・貫通0.5・相手で対空／対地）---

## ④の成立盤：アーチャー（射程1-3・対地30／対空40）と、そこから距離3の敵、その敵に張り付く
## スカウト。弓兵と斥候は隣り合わない＝参加者の形ではなく対象の周りを見る形。
func _trick_shot_state(enemy_def := 40) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var archer := Unit.new(1, 0, c, 4, 8, 30, 30, 1, "archer")
	archer.atk_air = 40
	archer.min_range = 1
	archer.attack_range = 3
	var enemy_hex := c + Hex.direction(0) * 3
	var enemy := Unit.new(9, 1, enemy_hex, 3, 8, 10, enemy_def)
	var scout := Unit.new(2, 0, enemy_hex + Hex.direction(0), 7, 8, 20, 20, 1, "thief")
	for u in [archer, enemy, scout]:
		s.add_unit(u)
	return {"s": s, "archer": archer, "enemy": enemy, "enemy_hex": enemy_hex, "scout": scout}

func _trick_shot_option(f: Dictionary) -> FormationOption:
	return _pick(Formation.available_for(f["s"], f["archer"]), "trick_shot")

func test_trick_shot_detected_when_scout_pins_target() -> void:
	var f := _trick_shot_state()
	var o := _trick_shot_option(f)
	assert_not_null(o, "斥候が敵に張り付いていれば成立する")
	assert_eq(o.participants, [1, 2] as Array[int], "参加者は弓兵と斥候の2体")
	assert_eq(o.max_range, 3, "射程上限は弓兵の通常射程")
	assert_eq(o.min_range, 1, "射程下限も弓兵の通常射程")

## 斥候が発動者にだけ隣接していても成立しない＝見るのは対象の周り。
func test_trick_shot_not_detected_when_scout_only_near_caster() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var archer := Unit.new(1, 0, c, 4, 8, 30, 30, 1, "archer")
	archer.min_range = 1
	archer.attack_range = 3
	s.add_unit(archer)
	s.add_unit(Unit.new(2, 0, Hex.neighbor(c, 0), 7, 8, 20, 20, 1, "thief"))  # 弓兵の隣
	s.add_unit(Unit.new(9, 1, c + Hex.direction(0) * 3, 3, 8, 10, 40))  # 射程内だが誰も張り付いていない
	assert_eq(_count(Formation.available_for(s, archer), "trick_shot"), 0,
		"敵に張り付いていない斥候では成立しない")

## 対象は斥候が張り付いた駒だけ＝射程内でも隣に斥候が居なければ選べない。
func test_trick_shot_target_must_be_pinned() -> void:
	var f := _trick_shot_state()
	var s: BattleState = f["s"]
	var loose_hex: Vector2i = f["archer"].pos + Hex.direction(0) * 2  # 射程内だが斥候から離れている
	s.add_unit(Unit.new(10, 1, loose_hex, 3, 8, 10, 40))
	var cells := Formation.targetable_cells(s, _trick_shot_option(f))
	assert_true(f["enemy_hex"] in cells, "張り付かれた敵は選べる")
	assert_false(loose_hex in cells, "張り付かれていない敵は選べない")

## 射程は弓兵の通常射程そのもの＝下限を持つ弓兵は懐の敵を撃てない。
## 判定は移動先の位置で行う（発動者は移動してから撃てる）＝from_hex で寄った先を見る。
func test_trick_shot_respects_range_floor() -> void:
	var f := _trick_shot_state()
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var close := Hex.neighbor(f["enemy_hex"], 3)  # 敵の隣＝距離1
	archer.min_range = 1
	assert_eq(_count(Formation.available_for(s, archer, close), "trick_shot"), 1,
		"下限1なら隣接からでも撃てる")
	archer.min_range = 2
	assert_eq(_count(Formation.available_for(s, archer, close), "trick_shot"), 0,
		"下限を割る距離では成立しない")

## 貫通0.5の上書き＝弓（素の貫通0）でも相手の防御が半分になる。
func test_trick_shot_pierces_half() -> void:
	var f := _trick_shot_state(40)
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var enemy: Unit = f["enemy"]
	assert_eq(archer.pierce, 0.0, "前提: 弓兵は素で貫通を持たない")
	var atk := Combat.attack_breakdown_from(archer.troops, archer.unit_attack,
		Combat.level_factor(archer), Combat.surround_factor(s, archer),
		TerrainType.attack_factor(s.terrain_at(archer.pos)), 0.0)
	var bare := Combat.defense_breakdown_from(enemy.troops, enemy.unit_defense,
		Combat.level_factor(enemy), Combat.surround_factor(s, enemy),
		TerrainType.defense_factor(s.terrain_at(enemy.pos)), 0.0, 0.0)
	var half := Combat.defense_breakdown_from(enemy.troops, enemy.unit_defense,
		Combat.level_factor(enemy), Combat.surround_factor(s, enemy),
		TerrainType.defense_factor(s.terrain_at(enemy.pos)), 0.0, 0.5)
	var expect := Combat.hit_from_breakdowns(atk, half, enemy.troops).loss
	assert_gt(expect, Combat.hit_from_breakdowns(atk, bare, enemy.troops).loss,
		"前提: 貫通が乗ると損害が増える")
	var res := FormationResolver.resolve(s, _trick_shot_option(f), f["enemy_hex"])
	assert_eq(res.hits[0].loss, expect, "貫通0.5を上書きした損害")

## 矢のレシピは通常攻撃と同じく相手で切り替える＝飛行の敵には対空値（設計原則3の例外）。
func test_trick_shot_uses_air_attack_vs_aerial() -> void:
	var f := _trick_shot_state(40)
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var enemy: Unit = f["enemy"]
	enemy.move_type = "flight"
	var atk := Combat.attack_breakdown_from(archer.troops, archer.atk_air,
		Combat.level_factor(archer), Combat.surround_factor(s, archer),
		TerrainType.attack_factor(s.terrain_at(archer.pos)), 0.0)
	var df := Combat.defense_breakdown_from(enemy.troops, enemy.unit_defense,
		Combat.level_factor(enemy), Combat.surround_factor(s, enemy),
		TerrainType.defense_factor(s.terrain_at(enemy.pos)), 0.0, 0.5)
	var expect := Combat.hit_from_breakdowns(atk, df, enemy.troops).loss
	var res := FormationResolver.resolve(s, _trick_shot_option(f), f["enemy_hex"])
	assert_eq(res.hits[0].loss, expect, "飛行の敵には対空値で撃つ")

## 着弾先を先に選ぶスキル＝相方は対象が決まってから引く。
func test_trick_shot_choice_is_target_first() -> void:
	var f := _trick_shot_state()
	var s: BattleState = f["s"]
	var c := _choice(Formation.choices_for(s, f["archer"]), "trick_shot")
	assert_not_null(c, "トリックショットの項目が出る")
	assert_true(c.target_first, "着弾先が先の形")
	assert_true(f["enemy_hex"] in Formation.choice_targetable_cells(s, c),
		"相方が決まる前でも撃てる先が出る")
	assert_eq(Formation.members_for_target(s, c, f["enemy_hex"]), [2] as Array[int],
		"その敵に張り付いている斥候が相方になる")

## 同じ敵に斥候が2体張り付いていれば、どちらを供出するかを選ぶ。
func test_trick_shot_two_spotters_offer_both() -> void:
	var f := _trick_shot_state()
	var s: BattleState = f["s"]
	s.add_unit(Unit.new(3, 0, Hex.neighbor(f["enemy_hex"], 3), 7, 8, 50, 20, 1, "thief"))
	var c := _choice(Formation.choices_for(s, f["archer"]), "trick_shot")
	assert_eq(c.member_sets.size(), 2, "組は斥候1体ごとに1つ")
	assert_eq(Formation.members_for_target(s, c, f["enemy_hex"]).size(), 2,
		"同じ敵に張り付く2体がどちらも相方の候補")

## 参加者は弓兵と斥候の2体とも行動完了＝殴るか撃つかの二択になる。
func test_trick_shot_spends_both() -> void:
	var f := _trick_shot_state()
	var s: BattleState = f["s"]
	FormationResolver.resolve(s, _trick_shot_option(f), f["enemy_hex"])
	assert_true(s.is_done(1), "弓兵は行動完了")
	assert_true(s.is_done(2), "斥候も行動完了")

# --- 単体を狙うスキルの対象（③④共通）---

## 単体狙撃が選べるのは敵の駒だけ。面（①）に巻き込まれるのとは別の話。
## 詳細 → doc/gdd/formations.md 共通ルール
func test_single_cannot_target_ally() -> void:
	var f := _judgment_state()
	var s: BattleState = f["s"]
	var ally_hex: Vector2i = f["caster"].pos + Hex.direction(0) * 3  # 射程内の味方（参加者ではない）
	s.add_unit(Unit.new(5, 0, ally_hex, 3, 8, 20, 20, 1, "fighter"))
	var opt := _pick(Formation.available_for(s, f["caster"]), "divine_judgment")
	var cells := Formation.targetable_cells(s, opt)
	assert_true(f["enemy_hex"] in cells, "敵は選べる")
	assert_false(ally_hex in cells, "味方は選べない")
	assert_null(FormationResolver.resolve(s, opt, ally_hex), "味方を指定しても発動しない")

## ④も同じ＝斥候に隣接していても味方は着弾先にならない。
func test_trick_shot_cannot_target_ally() -> void:
	var f := _trick_shot_state()
	var s: BattleState = f["s"]
	var scout: Unit = f["scout"]
	var ally_hex := Hex.neighbor(scout.pos, 3)  # 斥候の隣に味方を置く
	if s.unit_at(ally_hex) != null:
		ally_hex = Hex.neighbor(scout.pos, 4)
	s.add_unit(Unit.new(5, 0, ally_hex, 3, 8, 20, 20, 1, "fighter"))
	var cells := Formation.targetable_cells(s, _trick_shot_option(f))
	assert_true(f["enemy_hex"] in cells, "張り付かれた敵は選べる")
	assert_false(ally_hex in cells, "斥候の隣でも味方は選べない")

# --- ⑥アローレイン（弓兵3体の三角・19ヘクス・発動者の射程・貫通なし・相手で対空／対地）---

## ⑥の成立盤：アーチャー（射程1-3・対地30／対空40）・ハンター（1-4・30／50）・エルフ（1-5・30／60）が
## 三角形。caster=アーチャー（id1）で、そこから距離3の敵1体。
func _arrow_rain_state(enemy_def := 40) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var tri := _triangle(c)
	var archer := Unit.new(1, 0, tri[0], 4, 8, 30, 30, 1, "archer")
	archer.atk_air = 40
	archer.min_range = 1
	archer.attack_range = 3
	var hunter := Unit.new(2, 0, tri[1], 5, 8, 30, 30, 1, "hunter")
	hunter.atk_air = 50
	hunter.min_range = 1
	hunter.attack_range = 4
	var elf := Unit.new(3, 0, tri[2], 4, 8, 30, 20, 1, "elf")
	elf.atk_air = 60
	elf.min_range = 1
	elf.attack_range = 5
	var enemy_hex := c + Hex.direction(0) * 3
	var enemy := Unit.new(9, 1, enemy_hex, 3, 8, 10, enemy_def)
	for u in [archer, hunter, elf, enemy]:
		s.add_unit(u)
	return {"s": s, "archer": archer, "hunter": hunter, "elf": elf,
		"enemy": enemy, "enemy_hex": enemy_hex}

func _arrow_rain_option(f: Dictionary, caster := "archer") -> FormationOption:
	return _pick(Formation.available_for(f["s"], f[caster]), "arrow_rain")

## 弓兵3体が三角なら成立する（アーチャー・ハンター・エルフの混在可）。
func test_arrow_rain_detected_with_three_archers() -> void:
	var f := _arrow_rain_state()
	var o := _arrow_rain_option(f)
	assert_not_null(o, "弓兵3体の三角で成立する")
	assert_eq(o.shape, FormationOption.Shape.TRIANGLE, "形は triangle")
	assert_eq(o.participants.size(), 3, "参加者は3体")
	assert_eq(o.effect, FormationOption.Effect.AREA, "効果は面")

## スリンガー系は投石なので対象外＝混ざると三角が成立しない。
func test_arrow_rain_rejects_slinger() -> void:
	var f := _arrow_rain_state()
	var s: BattleState = f["s"]
	var elf: Unit = f["elf"]
	elf.type_id = "slinger"
	assert_eq(_count(Formation.available_for(s, f["archer"]), "arrow_rain"), 0,
		"スリンガーが混ざると成立しない")
	assert_eq(_count(Formation.available_for(s, elf), "arrow_rain"), 0,
		"スリンガーからは発動できない")

## 面は中心から2ヘクス以内＝19ヘクス（①の7ヘクスより一回り広い）。
func test_arrow_rain_blast_is_nineteen_hexes() -> void:
	var f := _arrow_rain_state()
	var o := _arrow_rain_option(f)
	assert_eq(o.radius, 2, "半径2")
	assert_eq(Formation.blast_cells(o, f["enemy_hex"]).size(), 19, "中心＋6＋外周12＝19ヘクス")

## 射程は発動者の射程上限＝誰が号令をかけるかで変わる。
func test_arrow_rain_range_comes_from_caster() -> void:
	var f := _arrow_rain_state()
	assert_eq(_arrow_rain_option(f, "archer").max_range, 3, "アーチャーが発動者なら3")
	assert_eq(_arrow_rain_option(f, "hunter").max_range, 4, "ハンターなら4")
	assert_eq(_arrow_rain_option(f, "elf").max_range, 5, "エルフなら5")

## 起点は3体のどれからでも＝発動者の射程を、参加者それぞれの位置から測る。
func test_arrow_rain_measured_from_any_participant() -> void:
	var f := _arrow_rain_state()
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var hunter: Unit = f["hunter"]
	var far_hex: Vector2i = hunter.pos + Hex.direction(0) * 3  # ハンターから3・アーチャーから4
	assert_eq(Hex.distance(archer.pos, far_hex), 4, "発動者からは射程3を超えている")
	var cells := Formation.targetable_cells(s, _arrow_rain_option(f))
	assert_true(far_hex in cells, "ハンターの位置から測れば射程内＝撃てる")

## 参加者は当たらない・他の味方は当たる（①と同じ）。
func test_arrow_rain_excludes_participants_not_allies() -> void:
	var f := _arrow_rain_state()
	var s: BattleState = f["s"]
	var ally_hex: Vector2i = f["enemy_hex"] + Hex.direction(1) * 2  # 中心から2＝面の外周
	s.add_unit(Unit.new(4, 0, ally_hex, 3, 8, 20, 20, 1, "novice"))
	var res := FormationResolver.resolve(s, _arrow_rain_option(f), f["enemy_hex"])
	var hit_ids: Array[int] = []
	for h in res.hits:
		hit_ids.append(h.target_id)
	assert_true(9 in hit_ids, "敵は当たる")
	assert_true(4 in hit_ids, "参加していない味方は当たる（外周まで焼く）")
	for pid in [1, 2, 3]:
		assert_false(pid in hit_ids, "参加者は当たらない（id %d）" % pid)

## 威力は発動者1体の実効攻撃力・貫通なし（弓の素の0）。
func test_arrow_rain_uses_caster_attack_without_pierce() -> void:
	var f := _arrow_rain_state(40)
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	archer.troops = 5  # 発動者の兵数で撃つことを見るため他の参加者（8）とずらす
	var expect := _expect_loss(s, archer, 30, f["enemy"], 0.0)  # 発動前の盤で
	var res := FormationResolver.resolve(s, _arrow_rain_option(f), f["enemy_hex"])
	var atk: StatBreakdown = res.hits[0].detail.attack
	assert_eq(atk.stat, 30, "アーチャーの対地30")
	assert_eq(atk.troops, 5, "兵数は発動者のもの")
	assert_eq(res.hits[0].loss, expect, "貫通なしで撃った損害")

## 矢のレシピ＝相手が飛行なら対空値（①の対地固定と違う）。
func test_arrow_rain_uses_air_attack_vs_aerial() -> void:
	var f := _arrow_rain_state(40)
	var s: BattleState = f["s"]
	var enemy: Unit = f["enemy"]
	enemy.move_type = "flight"
	var expect := _expect_loss(s, f["archer"], 40, enemy, 0.0)  # 発動前の盤で
	var res := FormationResolver.resolve(s, _arrow_rain_option(f), f["enemy_hex"])
	var atk: StatBreakdown = res.hits[0].detail.attack
	assert_eq(atk.stat, 40, "アーチャーの対空40")
	assert_true(atk.vs_aerial, "飛行の敵＝対空値")
	assert_eq(res.hits[0].loss, expect, "対空値・貫通なしで撃った損害")

## 参加者は3体とも行動完了。
func test_arrow_rain_spends_all_three() -> void:
	var f := _arrow_rain_state()
	var s: BattleState = f["s"]
	FormationResolver.resolve(s, _arrow_rain_option(f), f["enemy_hex"])
	for pid in [1, 2, 3]:
		assert_true(s.is_done(pid), "参加者は行動完了（id %d）" % pid)

# --- ⑨マジックアロー（弓兵＋魔法兵の隣接・大きい方＋10・貫通0.5・射程は長い方＋1）---

## ⑨の成立盤：アーチャー（射程1-3・対地30／対空40）の隣にウィザード（射程2-4・対地40／対空40）、
## アーチャーから距離3の敵。
func _magic_arrow_state(enemy_def := 40) -> Dictionary:
	var s := _state()
	var c := Hex.offset_to_axial(2, 3)
	var archer := Unit.new(1, 0, c, 4, 8, 30, 30, 1, "archer")
	archer.atk_air = 40
	archer.min_range = 1
	archer.attack_range = 3
	var wizard := Unit.new(2, 0, Hex.neighbor(c, 3), 4, 8, 40, 30, 1, "wizard")
	wizard.atk_air = 40
	wizard.pierce = 0.5
	wizard.min_range = 2
	wizard.attack_range = 4
	var enemy_hex := c + Hex.direction(0) * 3
	var enemy := Unit.new(9, 1, enemy_hex, 3, 8, 10, enemy_def)
	for u in [archer, wizard, enemy]:
		s.add_unit(u)
	return {"s": s, "archer": archer, "wizard": wizard, "enemy": enemy, "enemy_hex": enemy_hex}

func _magic_arrow_option(f: Dictionary) -> FormationOption:
	return _pick(Formation.available_for(f["s"], f["archer"]), "magic_arrow")

## 陣形ダメージの期待値（発動者の兵数・レベル・包囲・地形に、指定のユニット攻撃力と貫通を当てる）。
func _expect_loss(s: BattleState, caster: Unit, stat: int, enemy: Unit, pierce: float) -> int:
	var atk := Combat.attack_breakdown_from(caster.troops, stat,
		Combat.level_factor(caster), Combat.surround_factor(s, caster),
		TerrainType.attack_factor(s.terrain_at(caster.pos)), 0.0)
	var df := Combat.defense_breakdown_from(enemy.troops, enemy.unit_defense,
		Combat.level_factor(enemy), Combat.surround_factor(s, enemy),
		TerrainType.defense_factor(s.terrain_at(enemy.pos)), 0.0, pierce)
	return Combat.hit_from_breakdowns(atk, df, enemy.troops).loss

func test_magic_arrow_detected_when_caster_adjacent() -> void:
	var f := _magic_arrow_state()
	var o := _magic_arrow_option(f)
	assert_not_null(o, "弓兵の隣に魔法兵が居れば成立する")
	assert_eq(o.participants, [1, 2] as Array[int], "参加者は弓兵と魔法兵の2体")
	assert_eq(o.shape, FormationOption.Shape.ESCORT, "形は escort（人数2）")

## 発動できるのは弓兵から＝ウィザードの選択肢には出ない。
func test_magic_arrow_only_from_archer() -> void:
	var f := _magic_arrow_state()
	assert_eq(_count(Formation.available_for(f["s"], f["wizard"]), "magic_arrow"), 0,
		"魔法兵からは発動できない")

## メイジは見習いのため対象外＝隣に居ても成立しない。
func test_magic_arrow_rejects_mage() -> void:
	var f := _magic_arrow_state()
	var s: BattleState = f["s"]
	var wizard: Unit = f["wizard"]
	wizard.type_id = "mage"
	assert_eq(_count(Formation.available_for(s, f["archer"]), "magic_arrow"), 0, "メイジでは成立しない")

## 射程は2体の射程上限の長い方＋1・下限なし。
func test_magic_arrow_range_is_longer_plus_one() -> void:
	var f := _magic_arrow_state()
	var o := _magic_arrow_option(f)
	assert_eq(o.max_range, 5, "アーチャー3／ウィザード4 → 長い方4＋1＝5")
	assert_eq(o.min_range, 0, "下限は無し")
	var archer: Unit = f["archer"]
	archer.type_id = "elf"
	archer.attack_range = 5
	assert_eq(_magic_arrow_option(f).max_range, 6, "エルフ5／ウィザード4 → 6")
	archer.type_id = "archer"
	archer.attack_range = 3
	var wizard: Unit = f["wizard"]
	wizard.type_id = "witch"
	wizard.attack_range = 5
	assert_eq(_magic_arrow_option(f).max_range, 6, "アーチャー3／ウィッチ5 → 6")

## 下限が無い＝隣接の敵にも撃てる。射程外（距離6）の敵は選べない。
func test_magic_arrow_targets_adjacent_and_within_range() -> void:
	var f := _magic_arrow_state()
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var near_hex := Hex.neighbor(archer.pos, 0)
	var edge_hex: Vector2i = archer.pos + Hex.direction(0) * 5
	var far_hex: Vector2i = archer.pos + Hex.direction(0) * 6
	s.add_unit(Unit.new(10, 1, near_hex, 3, 8, 10, 40))
	s.add_unit(Unit.new(11, 1, edge_hex, 3, 8, 10, 40))
	s.add_unit(Unit.new(12, 1, far_hex, 3, 8, 10, 40))
	var cells := Formation.targetable_cells(s, _magic_arrow_option(f))
	assert_true(near_hex in cells, "隣接の敵に撃てる（下限なし）")
	assert_true(edge_hex in cells, "距離5＝射程の端は撃てる")
	assert_false(far_hex in cells, "距離6は射程外")

## 威力＝2体の攻撃力の大きい方＋10・貫通0.5。地上の敵にはウィザード40＋10＝50 で撃つ。
## 兵数・レベル・包囲・地形は発動者（弓兵）のもの。
func test_magic_arrow_ground_uses_max_attack_plus_ten() -> void:
	var f := _magic_arrow_state(40)
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var enemy: Unit = f["enemy"]
	archer.troops = 5  # 発動者の兵数で撃つことを見るため魔法兵（8）とずらす
	var expect := _expect_loss(s, archer, 50, enemy, 0.5)  # 発動前の盤で（発動後は敵の兵数が減る）
	var res := FormationResolver.resolve(s, _magic_arrow_option(f), f["enemy_hex"])
	var atk: StatBreakdown = res.hits[0].detail.attack
	assert_eq(atk.stat, 50, "ウィザード40 と アーチャー30 の大きい方＋10")
	assert_eq(atk.troops, 5, "兵数は発動者のもの")
	assert_false(atk.vs_aerial, "地上の敵＝対地値")
	assert_eq(res.hits[0].loss, expect, "貫通0.5で撃った損害")

## 飛行の敵には対空値で大きい方を取る＝エルフ60＋10＝70（主役が入れ替わる）。
func test_magic_arrow_air_uses_max_air_attack_plus_ten() -> void:
	var f := _magic_arrow_state(40)
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var enemy: Unit = f["enemy"]
	archer.type_id = "elf"
	archer.atk_air = 60
	enemy.move_type = "flight"
	var expect := _expect_loss(s, archer, 70, enemy, 0.5)  # 発動前の盤で
	var res := FormationResolver.resolve(s, _magic_arrow_option(f), f["enemy_hex"])
	var atk: StatBreakdown = res.hits[0].detail.attack
	assert_eq(atk.stat, 70, "エルフ対空60 と ウィザード対空40 の大きい方＋10")
	assert_true(atk.vs_aerial, "飛行の敵＝対空値")
	assert_eq(res.hits[0].loss, expect, "対空値・貫通0.5で撃った損害")

## 参加者は2体とも行動完了。
func test_magic_arrow_spends_both() -> void:
	var f := _magic_arrow_state()
	var s: BattleState = f["s"]
	FormationResolver.resolve(s, _magic_arrow_option(f), f["enemy_hex"])
	assert_true(s.is_done(1), "弓兵は行動完了")
	assert_true(s.is_done(2), "魔法兵も行動完了")

## 隣に魔法兵が2体居れば、どちらを供出するかを選ぶ（組は魔法兵1体ごとに1つ）。
func test_magic_arrow_two_casters_offer_choice() -> void:
	var f := _magic_arrow_state()
	var s: BattleState = f["s"]
	var archer: Unit = f["archer"]
	var witch := Unit.new(3, 0, Hex.neighbor(archer.pos, 4), 4, 8, 30, 30, 1, "witch")
	witch.attack_range = 5
	s.add_unit(witch)
	assert_eq(_count(Formation.available_for(s, archer), "magic_arrow"), 2, "組は魔法兵1体ごとに1つ")
	var c := _choice(Formation.choices_for(s, archer), "magic_arrow")
	assert_true(c.needs_choice(), "組が複数＝参加者を選ぶ段を挟む")
	assert_eq(c.pool, [2, 3] as Array[int], "候補は隣の魔法兵2体")
	assert_eq(Formation.option_of(s, c, [3] as Array[int]).max_range, 6, "ウィッチを選べば射程6")
	assert_eq(Formation.option_of(s, c, [2] as Array[int]).max_range, 5, "ウィザードを選べば射程5")
