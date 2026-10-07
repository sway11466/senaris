extends GutTest
## 罠発見（ユニットスキル trap_scan＝斥候のアクティブ／trap_scan_drone＝調査ドローンの行動完了スキル）。
## 発動者の位置から、移動力を予算に視線の届く範囲の隠れた罠を見つかった状態にする。
## 仕様 → doc/gdd/skills.md 罠発見, doc/gdd/gimmicks.md 罠発見

const WALL := "wall"

func _at(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(col, row)

## 12×8 の盤。視線コスト表は壁だけ遮蔽（他は1）。
func _state() -> BattleState:
	var s := BattleState.new(12, 8)
	s.set_sight_cost({ WALL: TerrainType.SIGHT_OPAQUE })
	return s

## 斥候（シーフ性能・移動7・攻撃後の再移動あり）を (col,row) に置く。
func _scout(s: BattleState, handle: int, col: int, row: int, team := 0) -> Unit:
	var u := Unit.new(handle, team, _at(col, row), 7, 8, 50, 20, 1, "thief")
	u.move_after_attack = true
	s.add_unit(u)
	return u

## 調査ドローン（ピクシー性能・移動5）を (col,row) に置く。発動者の照合はスキンID。
func _drone(s: BattleState, handle: int, col: int, row: int, team := 0) -> Unit:
	var u := Unit.new(handle, team, _at(col, row), 5, 8, 10, 10, 1, "pixie")
	u.skin_id = "survey_drone"
	u.move_type = "flight"
	s.add_unit(u)
	return u

func _trap(s: BattleState, id: String, col: int, row: int, kind := "thunder_sigil", state := GimmickKinds.HIDDEN) -> Gimmick:
	var g := Gimmick.new(id, kind, _at(col, row), state)
	s.add_gimmick(g)
	return g

func _scan_option(s: BattleState, u: Unit) -> FormationOption:
	for o in Formation.available_for(s, u):
		if o.skill == "trap_scan":
			return o
	return null

# --- 成立 ---

func test_offered_by_scout_without_target() -> void:
	var s := _state()
	var u := _scout(s, 1, 2, 2)
	var o := _scan_option(s, u)
	assert_not_null(o, "斥候単独で成立する")
	assert_false(o.needs_target(), "対象を選ばない＝押したら即発動")
	assert_true(Formation.can_target(s, o, Formation.NO_HEX), "対象なしで撃てる")

func test_offered_even_when_no_hidden_trap_is_near() -> void:
	var s := _state()
	var u := _scout(s, 1, 2, 2)
	assert_not_null(_scan_option(s, u), "範囲に罠が無くても撃てる（無いと分かることが成果）")

func test_not_offered_by_other_types_or_drone() -> void:
	var s := _state()
	var f := Unit.new(1, 0, _at(2, 2), 3, 8, 40, 40, 1, "fighter")
	s.add_unit(f)
	var d := _drone(s, 2, 4, 4)
	assert_null(_scan_option(s, f), "斥候以外は撃てない")
	assert_null(_scan_option(s, d), "調査ドローンの罠発見は行動完了スキル＝メニューには出ない")
	assert_true(Formation.unit_skills_of(d).has("trap_scan_drone"), "能力タブには載る")

# --- 効果 ---

func test_reveals_hidden_traps_in_sight_only() -> void:
	var s := _state()
	var u := _scout(s, 1, 2, 2)
	var near := _trap(s, "near", 4, 2)             # 距離2＝範囲内
	var edge := _trap(s, "edge", 9, 2, "landmine")  # 距離7＝範囲の端
	var far := _trap(s, "far", 10, 2)              # 距離8＝範囲外
	var found_already := _trap(s, "found", 3, 3, "thunder_sigil", GimmickKinds.FOUND)
	var spent := _trap(s, "spent", 3, 4, "landmine", GimmickKinds.SPENT)
	var r := FormationResolver.resolve(s, _scan_option(s, u), Formation.NO_HEX)
	assert_not_null(r)
	assert_eq(near.state, GimmickKinds.FOUND, "範囲内の隠れた罠は見つかる")
	assert_eq(edge.state, GimmickKinds.FOUND, "移動力ちょうどの距離も見つかる")
	assert_eq(far.state, GimmickKinds.HIDDEN, "範囲外は隠れたまま")
	assert_eq(found_already.state, GimmickKinds.FOUND)
	assert_eq(spent.state, GimmickKinds.SPENT, "撃ち終えた地雷は変わらない")
	assert_eq(r.detected.size(), 2)
	assert_true(r.detected.has("near") and r.detected.has("edge"))
	assert_eq(r.cells.size(), 2, "見つけた罠のマスを光らせる")
	assert_true(r.cells.has(near.hex) and r.cells.has(edge.hex))
	assert_eq(r.center, u.pos, "調べた起点は発動者の位置")
	assert_true(r.scanned.has(u.pos) and r.scanned.has(far.hex) == false, "調べた範囲は視線の届いたマス")
	assert_true(r.hits.is_empty(), "着弾は起きない")

func test_wall_blocks_the_scan() -> void:
	var s := _state()
	var u := _scout(s, 1, 2, 3)
	for row in s.rows:
		s.set_terrain(_at(4, row), WALL)  # col 4 を壁の列で塞ぐ
	var behind := _trap(s, "behind", 6, 3)
	var front := _trap(s, "front", 3, 3)
	FormationResolver.resolve(s, _scan_option(s, u), Formation.NO_HEX)
	assert_eq(front.state, GimmickKinds.FOUND, "壁の手前は見つかる")
	assert_eq(behind.state, GimmickKinds.HIDDEN, "壁の向こうは見えない")

func test_scout_can_move_after_scan_but_not_attack() -> void:
	var s := _state()
	var u := _scout(s, 1, 2, 2)
	var foe := Unit.new(9, 1, _at(3, 2), 3, 8, 10, 10)
	s.add_unit(foe)
	assert_true(s.move_unit(1, _at(2, 3)), "前提: 先に1歩動いておく")
	var r := FormationResolver.resolve(s, _scan_option(s, u), Formation.NO_HEX)
	assert_not_null(r)
	assert_true(s.has_attacked(1), "使った後は攻撃済みの扱い")
	assert_false(s.has_action_left(1), "もう攻撃・スキルはできない")
	assert_true(s.can_still_move(1), "残り移動力で再移動できる（攻撃後の再移動と同じ）")
	assert_null(_scan_option(s, u), "二度は撃てない")

func test_level_rises_only_when_a_trap_is_found() -> void:
	var s := _state()
	var u := _scout(s, 1, 2, 2)
	var lv := u.level
	FormationResolver.resolve(s, _scan_option(s, u), Formation.NO_HEX)
	assert_eq(u.level, lv, "何も見つからなければ上がらない")
	s.end_turn()
	s.end_turn()  # 自軍のターンへ戻す
	_trap(s, "near", 3, 2)
	FormationResolver.resolve(s, _scan_option(s, u), Formation.NO_HEX)
	assert_eq(u.level, lv + 1, "罠を1つ以上見つけたら +1")

# --- 調査ドローン（行動完了スキル） ---

func test_drone_scans_when_done_once_per_turn() -> void:
	var s := _state()
	var d := _drone(s, 1, 2, 2)
	var t := _trap(s, "near", 4, 2)
	assert_true(FormationResolver.on_done(s, 1).is_empty(), "行動完了していなければ発動しない")
	assert_eq(t.state, GimmickKinds.HIDDEN)
	s.set_done(1)
	var rs := FormationResolver.on_done(s, 1)
	assert_eq(rs.size(), 1, "待機した場所で発動する")
	assert_eq(rs[0].skill, "trap_scan_drone")
	assert_eq(t.state, GimmickKinds.FOUND)
	assert_eq(d.level, 2, "見つけたので +1")
	assert_true(FormationResolver.on_done(s, 1, true).is_empty(), "同じターンにターン終了時は二度発動しない")

func test_drone_scans_at_turn_end_if_it_did_nothing() -> void:
	var s := _state()
	_drone(s, 1, 2, 2)
	var t := _trap(s, "near", 4, 2)
	assert_true(FormationResolver.on_done(s, 1).is_empty(), "何もしていない駒は行動完了ではない")
	assert_eq(FormationResolver.on_done(s, 1, true).size(), 1, "ターン終了時はその場所で発動する")
	assert_eq(t.state, GimmickKinds.FOUND)

func test_drone_fires_again_next_turn() -> void:
	var s := _state()
	_drone(s, 1, 2, 2)
	s.set_done(1)
	assert_eq(FormationResolver.on_done(s, 1).size(), 1)
	s.end_turn()
	s.end_turn()
	s.set_done(1)
	assert_eq(FormationResolver.on_done(s, 1).size(), 1, "ターンが変われば発動済みの印は消える")

func test_enemy_never_scans() -> void:
	var s := _state()
	_drone(s, 1, 2, 2, 1)
	var e := _scout(s, 2, 3, 3, 1)
	_trap(s, "near", 4, 2)
	s.end_turn()  # 敵のターンへ
	s.set_done(1)
	assert_true(FormationResolver.on_done(s, 1).is_empty(), "敵の調査ドローンは発動しない")
	assert_true(FormationResolver.on_done(s, 1, true).is_empty())
	var params := AiParams.new([] as Array[String])
	var rows := AiRows.new(params, AiPick.new(params))
	assert_null(rows.skill_row(s, e, AiPick.PICK_NEAR), "敵AIは罠発見を撃たない")

# --- 進行（MatchController） ---

func test_controller_fires_drone_scan_on_stand_and_turn_end() -> void:
	var s := _state()
	_drone(s, 1, 2, 2)
	_drone(s, 2, 2, 5)
	var t1 := _trap(s, "near1", 4, 2)
	var t2 := _trap(s, "near2", 4, 5)
	var mc: MatchController = autofree(MatchController.new())
	mc.setup(s)
	watch_signals(mc)
	mc.stand(1)
	assert_signal_emit_count(mc, "formation_resolved", 1, "待機で発動＝陣形スキルと同じ口で上がる")
	assert_eq(t1.state, GimmickKinds.FOUND)
	mc.end_turn()
	assert_signal_emit_count(mc, "formation_resolved", 2, "ターン終了時に、何もしなかった駒だけが発動する")
	assert_eq(t2.state, GimmickKinds.FOUND)
	assert_eq(s.current_team, 1, "そのあとターンが進む")
