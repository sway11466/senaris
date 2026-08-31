extends GutTest
## domain/battle_state.gd と domain/unit/unit.gd のテスト。

func _state() -> BattleState:
	return BattleState.new(6, 6)

func test_add_and_query() -> void:
	var s := _state()
	var u := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3)
	s.add_unit(u)
	assert_eq(s.unit_by_id(1), u)
	assert_eq(s.unit_at(u.pos), u, "座標からユニットを引ける")
	assert_null(s.unit_at(Hex.offset_to_axial(0, 0)), "空きマスは null")
	assert_null(s.unit_by_id(999), "未知IDは null")

func test_can_reach_respects_min_and_max() -> void:
	var u := Unit.new(1, 0, Vector2i.ZERO, 3)
	u.min_range = 2
	u.attack_range = 3                                          # 砲兵（射程2-3）
	assert_false(u.can_reach(1), "下限未満(距離1＝死角)は狙えない")
	assert_true(u.can_reach(2), "下限ちょうどは狙える")
	assert_true(u.can_reach(3), "上限ちょうどは狙える")
	assert_false(u.can_reach(4), "上限超は狙えない")

func test_reachable_includes_start_excludes_occupied() -> void:
	var s := _state()
	var a := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 2)
	s.add_unit(a)
	assert_true(s.reachable(1).has(a.pos), "起点を含む")
	var blocked := Hex.neighbor(a.pos, 0)
	s.add_unit(Unit.new(2, 1, blocked, 1))
	assert_false(s.reachable(1).has(blocked), "他ユニットのマスは到達不可")

func test_move_valid() -> void:
	var s := _state()
	var start := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, start, 2))
	var dest := Hex.neighbor(start, 0)
	assert_true(s.move_unit(1, dest), "妥当な移動は成功")
	assert_eq(s.unit_by_id(1).pos, dest, "座標が更新される")

func test_hit_and_run_move_after_attack() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var rabbit := Unit.new(1, 0, ap, 4, 8, 20, 10)
	rabbit.move_after_attack = true
	s.add_unit(rabbit)
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))  # 隣接敵
	assert_false(s.attack(1, 2).is_empty(), "攻撃成功")
	assert_true(s.can_still_move(1), "再移動ユニットは攻撃後も動ける")
	assert_false(s.is_done(1), "攻撃後もまだ完了しない")
	var away := Hex.neighbor(ap, 3)  # 敵の反対側へ離脱
	assert_true(s.move_unit(1, away), "攻撃後に離脱移動できる")
	assert_eq(s.unit_by_id(1).pos, away)
	assert_true(s.is_done(1), "再移動を使い切ったら完了")

func test_normal_unit_done_after_attack() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 4, 8, 20, 10))  # move_after_attack 既定 false
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 10, 10))
	s.attack(1, 2)
	assert_false(s.can_still_move(1), "通常ユニットは攻撃後に動けない")
	assert_true(s.is_done(1), "通常ユニットは攻撃で完了")

## 出口を塞がれた駒は「打つ手が無い（is_stuck）」だけで、行動を終えた（is_done）わけではない。
## ターン開始から行動完了にしてしまうと、暗く落ちて選択できず、陣形スキルにも参加できなくなる。
func test_blocked_unit_is_stuck_but_not_done() -> void:
	var s := _state()
	var c := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, c, 1, 8, 20, 20))  # 移動1＝味方のマスは通過できても先へ抜けられない
	for i in 6:
		s.add_unit(Unit.new(10 + i, 0, Hex.neighbor(c, i), 1, 8, 20, 20))
	assert_eq(s.reachable(1).size(), 1, "前提: 味方に囲まれて止まれる先が自分のマスしか無い")
	assert_true(s.attack_targets(1).is_empty(), "前提: 撃てる相手も居ない")
	assert_true(s.is_stuck(1), "打つ手が無い")
	assert_false(s.is_done(1), "このターンまだ何も使っていない＝行動完了ではない")
	assert_true(s.can_select(1), "選択できる（待機も陣形スキルも選べる）")

func test_move_budget_shared_across_attack() -> void:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var rabbit := Unit.new(1, 0, ap, 1, 8, 20, 10)  # 移動力1だけ
	rabbit.move_after_attack = true
	s.add_unit(rabbit)
	s.add_unit(Unit.new(2, 1, Hex.neighbor(Hex.neighbor(ap, 0), 0), 3, 8, 10, 10))  # 2マス先
	var adj := Hex.neighbor(ap, 0)
	assert_true(s.move_unit(1, adj), "前進1（予算1を消費）")
	assert_false(s.attack(1, 2).is_empty(), "隣接して攻撃")
	assert_false(s.can_still_move(1), "予算を使い切ったので再移動不可（予算は移動と共有）")
	assert_true(s.is_done(1))

func test_move_rejects_occupied_and_out_of_range() -> void:
	var s := _state()
	var start := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, start, 2))
	var occupied := Hex.neighbor(start, 0)
	s.add_unit(Unit.new(2, 1, occupied, 2))
	assert_false(s.move_unit(1, occupied), "他ユニットの上には移動不可")
	assert_false(s.move_unit(1, Hex.offset_to_axial(5, 5)), "移動力を超える先は不可")
	assert_eq(s.unit_by_id(1).pos, start, "不正な移動では動かない")

func test_remove_unit_takes_off_board_and_records_defeat() -> void:
	var s := _state()
	var pos := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 1, pos, 3))
	assert_true(s.remove_unit(1), "盤上の駒は除去できる")
	assert_null(s.unit_by_id(1), "盤上リストから消える")
	assert_null(s.unit_at(pos), "座標からも引けない")
	assert_eq(s.team_unit_count(1), 0, "陣営の頭数が減る（殲滅＝勝利判定の材料）")
	assert_true(s.is_defeated(1), "撃破として記録される（ボス撃破の勝利条件に効く）")

## 生存の数え方（評価ランクが読む）＝盤上＋輸送の中＋拠点の中。詳細 → doc/gdd/rank.md
func test_survivor_count_includes_garrison_and_passengers() -> void:
	var s := _state()
	var pos := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, pos, 3))
	assert_eq(s.ally_survivor_count(), 1, "盤上の駒を数える")
	# 拠点の中（自陣拠点へ退避した駒）
	var base_hex := Hex.offset_to_axial(3, 2)
	var b := Base.new(base_hex, 0)
	s.add_base(b)
	assert_true(s.move_unit(1, base_hex))
	assert_true(s.enter_base(1), "自陣拠点に入る")
	assert_eq(s.team_unit_count(0), 0, "盤上からは消える")
	assert_eq(s.ally_survivor_count(), 1, "拠点に退避しても生存に数える")
	# 輸送の中
	var wagon := Unit.new(2, 0, Hex.offset_to_axial(1, 1), 3)
	wagon.capacity = 4
	s.add_unit(wagon)
	var rider := Unit.new(3, 0, Hex.offset_to_axial(1, 2), 3)
	s.put_passenger(wagon.id, rider)
	assert_eq(s.ally_survivor_count(), 3, "搭乗中の駒も生存に数える")
	# 失われた駒だけが落ちる
	assert_true(s.remove_unit(wagon.id), "輸送を撃破（搭乗駒も巻き添え）")
	assert_eq(s.ally_survivor_count(), 1, "撃破された駒と搭乗駒は数から落ちる")

func test_survivor_count_includes_unclaimed_garrison() -> void:
	# まだ解放されていない中立の控えは自軍の生存に数える（doc/gdd/rank.md 生存）。
	var s := _state()
	var b := Base.new(Hex.offset_to_axial(3, 2), 0)
	var neutral := Unit.new(1, 0, Vector2i.ZERO, 3)
	neutral.set_native_team(Unit.NEUTRAL_TEAM)  # 中立＝帰属未確定
	b.garrison.append(neutral)
	var ours := Unit.new(2, 0, Vector2i.ZERO, 3)  # native 0＝自軍の控え
	b.garrison.append(ours)
	var theirs := Unit.new(3, 1, Vector2i.ZERO, 3)  # native 1＝敵の控え（閉じ込め）
	b.garrison.append(theirs)
	s.add_base(b)
	assert_eq(s.ally_survivor_count(), 2, "自軍の控えと未解放の中立を数える")
	neutral.recruited_team = 1  # 敵に解放された＝ここで自軍の生存から落ちる
	assert_eq(s.ally_survivor_count(), 1, "敵に解放された中立は落ちる")

## 兵器は生存に数えない（doc/gdd/rank.md）。盤上・輸送の中・拠点の控えのどこに居ても外れる。
func test_survivor_count_excludes_emplacements() -> void:
	var s := _state()
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	var barricade := Unit.new(2, 0, Hex.offset_to_axial(2, 3), 3)
	barricade.move_type = "stationary"
	s.add_unit(barricade)
	assert_eq(s.team_unit_count(0), 2, "頭数（勝敗が読む）には兵器も入る")
	assert_eq(s.ally_survivor_count(), 1, "盤上の兵器は生存に数えない")
	var wagon := Unit.new(3, 0, Hex.offset_to_axial(1, 1), 3)
	wagon.capacity = 4
	s.add_unit(wagon)
	var cargo := Unit.new(4, 0, Hex.offset_to_axial(1, 2), 3)
	cargo.move_type = "stationary"
	s.put_passenger(wagon.id, cargo)
	assert_eq(s.ally_survivor_count(), 2, "積荷の兵器も数えない（兵と馬車だけ）")
	var b := Base.new(Hex.offset_to_axial(3, 2), 0)
	var stored := Unit.new(5, 0, Vector2i.ZERO, 3)
	stored.move_type = "stationary"
	b.garrison.append(stored)
	s.add_base(b)
	assert_eq(s.ally_survivor_count(), 2, "拠点の控えの兵器も数えない")

## 未発火の自軍増援も生存に数える（来ていないだけで失われていない）。詳細 → doc/gdd/rank.md
func test_survivor_count_includes_pending_reinforcements() -> void:
	var s := _state()
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	var wagon := Unit.new(2, 0, Hex.offset_to_axial(0, 0), 3)
	wagon.capacity = 4
	var barricade := Unit.new(4, 0, Hex.offset_to_axial(0, 1), 3)
	barricade.move_type = "stationary"
	s.add_event({
		"id": "help", "turn": 5, "team": 0, "on": "", "hex": Vector2i.MAX,
		"units": [
			{ "unit": wagon, "passengers": [Unit.new(3, 0, Vector2i.ZERO, 3)] },
			{ "unit": barricade, "passengers": [] },
		],
	})
	s.add_event({
		"id": "foes", "turn": 6, "team": 1, "on": "", "hex": Vector2i.MAX,
		"units": [{ "unit": Unit.new(5, 1, Vector2i.ZERO, 3), "passengers": [] }],
	})
	assert_eq(s.ally_survivor_count(), 3, "盤上1＋未発火の増援2（兵器と敵の増援は数えない）")

## 撃破は実際に倒した駒の累積（戦果票が敵側を読む）。詳細 → doc/gdd/rank.md
func test_losses_count_defeated_units() -> void:
	var s := _state()
	var foe := Unit.new(1, 1, Hex.offset_to_axial(2, 2), 3)
	s.add_unit(foe)
	var wagon := Unit.new(2, 1, Hex.offset_to_axial(3, 2), 3)
	wagon.capacity = 4
	s.add_unit(wagon)
	s.put_passenger(wagon.id, Unit.new(3, 1, Vector2i.ZERO, 3))
	var barricade := Unit.new(4, 1, Hex.offset_to_axial(4, 2), 3)
	barricade.move_type = "stationary"
	s.add_unit(barricade)
	var ally := Unit.new(5, 0, Hex.offset_to_axial(1, 1), 3)
	s.add_unit(ally)
	assert_eq(s.losses(1), 0, "まだ何も倒していない")
	assert_true(s.remove_unit(foe.id))
	assert_eq(s.losses(1), 1, "倒した敵を数える")
	assert_true(s.remove_unit(wagon.id))
	assert_eq(s.losses(1), 3, "巻き添えの搭乗駒も数える")
	assert_true(s.remove_unit(barricade.id))
	assert_eq(s.losses(1), 3, "敵の兵器は撃破に乗らない")
	assert_true(s.remove_unit(ally.id))
	assert_eq(s.losses(1), 3, "自軍の損失は敵の撃破に混ざらない")
	assert_eq(s.losses(0), 1, "陣営ごとに数える")

func test_remove_unit_unknown_or_twice_is_false() -> void:
	var s := _state()
	s.add_unit(Unit.new(1, 1, Hex.offset_to_axial(2, 2), 3))
	assert_false(s.remove_unit(99), "盤に居ない id は false")
	assert_true(s.remove_unit(1))
	assert_false(s.remove_unit(1), "二度目は false（既に盤に居ない）")
