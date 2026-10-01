extends GutTest
## 罠（仕掛けの種類のうち、踏むと撃つもの）。ダメージの罠＝雷の紋（thunder_sigil）と地雷（landmine）。
## 撃つ側は兵数8・補正なし、受ける側はふだんどおり。仕様 → doc/gdd/gimmicks.md 罠・ダメージの罠

const TRAP := Vector2i(3, 3)  # col/row

func _at(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(col, row)

## 罠1つと駒を置いた盤。駒は { handle, team, pos, troops, def, aerial } の辞書で渡す。
func _state(kind: String, units: Array, state := GimmickKinds.HIDDEN) -> BattleState:
	var s := BattleState.new(8, 8)
	s.add_gimmick(Gimmick.new("trap-a", kind, _at(TRAP.x, TRAP.y), state))
	for d in units:
		var u := Unit.new(int(d["handle"]), int(d.get("team", 0)), d["pos"], 4,
				int(d.get("troops", 8)), 10, int(d.get("def", 40)))
		if bool(d.get("aerial", false)):
			u.move_type = "flight"
		s.add_unit(u)
	return s

func _trap_hex() -> Vector2i:
	return _at(TRAP.x, TRAP.y)

## 罠の一撃で u が失う兵数（Combat の式そのまま）。
func _expected_loss(s: BattleState, kind: String, u: Unit) -> int:
	var spec := GimmickKinds.trap_spec(kind)
	return Combat.trap_hit_detail(s, GimmickKinds.TRAP_TROOPS, int(spec["atk_ground"]), int(spec["atk_air"]),
			float(spec["pierce"]), u).loss

# --- 雷の紋 ---

func test_sigil_hits_the_stepper_and_is_found() -> void:
	var s := _state("thunder_sigil", [{ "handle": 1, "pos": _trap_hex() }])
	var u := s.unit_by_handle(1)
	var want := _expected_loss(s, "thunder_sigil", u)
	assert_gt(want, 0, "前提: 満員の一撃で兵数が減る")
	var g := s.step_gimmick(_trap_hex(), 0)
	assert_not_null(g, "撃った罠を返す")
	assert_eq(u.troops, 8 - want)
	assert_eq(g.state, GimmickKinds.FOUND, "撃ったら見つかった扱い")
	assert_eq(s.last_trap_hits.size(), 1)
	assert_eq(int(s.last_trap_hits[0]["troops_before"]), 8)
	assert_false(bool(s.last_trap_hits[0]["killed"]))

func test_sigil_fires_every_time_it_is_stepped() -> void:
	var s := _state("thunder_sigil", [{ "handle": 1, "pos": _trap_hex() }], GimmickKinds.FOUND)
	var u := s.unit_by_handle(1)
	s.step_gimmick(_trap_hex(), 0)
	var after_first := u.troops
	assert_lt(after_first, 8, "見つかった後も撃つ")
	s.step_gimmick(_trap_hex(), 0)
	assert_lt(u.troops, after_first, "踏むたびに撃つ")

func test_sigil_hits_only_the_stepper() -> void:
	var s := _state("thunder_sigil", [
		{ "handle": 1, "pos": _trap_hex() },
		{ "handle": 2, "pos": Hex.neighbor(_trap_hex(), 0) },
	])
	s.step_gimmick(_trap_hex(), 0)
	assert_eq(s.unit_by_handle(2).troops, 8, "隣の駒には効かない")

func test_sigil_hits_both_sides() -> void:
	var s := _state("thunder_sigil", [{ "handle": 1, "team": 1, "pos": _trap_hex() }])
	s.step_gimmick(_trap_hex(), 1)
	assert_lt(s.unit_by_handle(1).troops, 8, "敵が踏んでも撃つ")

# --- 地雷 ---

func test_landmine_hits_the_cell_and_its_neighbours_once() -> void:
	var near := Hex.neighbor(_trap_hex(), 1)
	var far := _trap_hex() + Hex.direction(1) * 2
	var s := _state("landmine", [
		{ "handle": 1, "pos": _trap_hex() },
		{ "handle": 2, "team": 1, "pos": near },
		{ "handle": 3, "pos": far },
	])
	s.step_gimmick(_trap_hex(), 0)
	assert_lt(s.unit_by_handle(1).troops, 8, "踏んだ駒")
	assert_lt(s.unit_by_handle(2).troops, 8, "隣の駒（敵味方とも）")
	assert_eq(s.unit_by_handle(3).troops, 8, "2マス先には効かない")
	assert_eq(s.gimmick_by_id("trap-a").state, GimmickKinds.SPENT, "一度きり")
	assert_eq(int(s.last_trap_hits[0]["unit"]), 1, "踏んだ駒が先頭")
	var t1 := s.unit_by_handle(1).troops
	assert_null(s.step_gimmick(_trap_hex(), 0), "撃ち終えた地雷は何もしない")
	assert_eq(s.unit_by_handle(1).troops, t1)
	assert_true(s.last_trap_hits.is_empty())

func test_landmine_losses_are_settled_before_applying() -> void:
	# 隣の駒の支援で防御が上がる＝撃つ前の盤で全員の損害を決める（先に撃たれた駒の支援が減らない）。
	var near := Hex.neighbor(_trap_hex(), 2)
	var s := _state("landmine", [
		{ "handle": 1, "pos": _trap_hex() },
		{ "handle": 2, "pos": near },
	])
	var want1 := _expected_loss(s, "landmine", s.unit_by_handle(1))
	var want2 := _expected_loss(s, "landmine", s.unit_by_handle(2))
	s.step_gimmick(_trap_hex(), 0)
	assert_eq(s.unit_by_handle(1).troops, 8 - want1)
	assert_eq(s.unit_by_handle(2).troops, 8 - want2)

func test_landmine_uses_its_anti_air_value_on_fliers() -> void:
	var s := _state("landmine", [{ "handle": 1, "pos": _trap_hex(), "aerial": true }])
	var h := Combat.trap_hit_detail(s, GimmickKinds.TRAP_TROOPS, 40, 20, 0.0, s.unit_by_handle(1))
	assert_eq(h.attack.stat, 20, "飛行には対空の値")
	assert_true(h.attack.vs_aerial)

# --- 共通 ---

func test_trap_can_kill() -> void:
	var s := _state("thunder_sigil", [{ "handle": 1, "pos": _trap_hex(), "troops": 1, "def": 1 }])
	s.step_gimmick(_trap_hex(), 0)
	assert_null(s.unit_by_handle(1), "罠で倒れる")
	assert_true(s.is_defeated(1))
	assert_true(bool(s.last_trap_hits[0]["killed"]))

func test_trap_attack_has_no_attacker_modifiers() -> void:
	var s := _state("thunder_sigil", [{ "handle": 1, "pos": _trap_hex() }])
	var h := Combat.trap_hit_detail(s, 8, 40, 40, 0.5, s.unit_by_handle(1))
	assert_eq(h.attack.total, 8.0 * 40.0, "兵数8 × 攻撃力、補正なし")

func test_trap_pierce_halves_defense() -> void:
	var s := _state("thunder_sigil", [{ "handle": 1, "pos": _trap_hex(), "def": 40 }])
	var u := s.unit_by_handle(1)
	var with_pierce := Combat.trap_hit_detail(s, 8, 40, 40, 0.5, u)
	var without := Combat.trap_hit_detail(s, 8, 40, 40, 0.0, u)
	assert_almost_eq(with_pierce.defense.total, without.defense.total * 0.5, 0.001)

func test_nobody_levels_up_from_a_trap() -> void:
	var s := _state("thunder_sigil", [{ "handle": 1, "pos": _trap_hex() }])
	s.step_gimmick(_trap_hex(), 0)
	assert_eq(s.unit_by_handle(1).level, 1)

func test_trap_does_not_rename_the_wait_command() -> void:
	# コマンドメニューの言い換えは state_after_step を見る＝罠は "" を返して正体を明かさない。
	var g := Gimmick.new("a", "thunder_sigil", Vector2i.ZERO, GimmickKinds.HIDDEN)
	assert_eq(GimmickKinds.state_after_step(g, 0), "")

func test_trap_state_survives_save() -> void:
	var s := _state("landmine", [{ "handle": 1, "pos": _trap_hex() }])
	s.step_gimmick(_trap_hex(), 0)
	var diff := s.to_save_diff()
	var s2 := _state("landmine", [])
	s2.apply_save_diff(diff)
	assert_eq(s2.gimmick_by_id("trap-a").state, GimmickKinds.SPENT)

# --- 進行（MatchController） ---

func test_controller_reports_trap_and_deaths() -> void:
	var s := _state("thunder_sigil", [
		{ "handle": 1, "pos": Hex.neighbor(_trap_hex(), 3), "troops": 1, "def": 1 },
		{ "handle": 2, "team": 1, "pos": _at(7, 7) },
	])
	var mc: MatchController = autofree(MatchController.new())
	mc.setup(s)
	watch_signals(mc)
	assert_true(mc.execute(MoveCommand.new(1, _trap_hex())))
	assert_signal_emitted(mc, "trap_fired")
	assert_signal_emitted_with_parameters(mc, "unit_died", [1])
	assert_signal_emitted(mc, "battle_finished", "罠で最後の駒を失えば決着する")

func test_boarding_a_transport_on_a_trap_does_not_step() -> void:
	var s := _state("thunder_sigil", [{ "handle": 2, "team": 1, "pos": _at(7, 7) }])
	var carrier := Unit.new(3, 0, _trap_hex(), 4, 8, 10, 10)
	carrier.capacity = 4
	s.add_unit(carrier)
	var rider := Unit.new(1, 0, Hex.neighbor(_trap_hex(), 3), 4)
	s.add_unit(rider)
	assert_true(s.can_board(rider, carrier), "前提: 乗れる")
	var mc: MatchController = autofree(MatchController.new())
	mc.setup(s)
	watch_signals(mc)
	assert_true(mc.execute(MoveCommand.new(1, _trap_hex())))
	assert_signal_not_emitted(mc, "trap_fired", "乗り込んだ駒は盤に立たない＝踏まない")
	assert_eq(carrier.troops, 8)
