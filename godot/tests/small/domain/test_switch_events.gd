extends GutTest
## スイッチ＝引き金 step（マスを踏む）・条件 if・中身 neutralize（拠点を中立に戻す）と、勝利条件 deny_bases。
## 仕様 → doc/gdd/map.md イベント・勝敗条件

func _catalog() -> Dictionary:
	return {
		"fighter": UnitType.from_dict({ "id": "fighter", "atk_ground": 5, "defense": 5, "move": 4, "max_troops": 8 }),
		"cleric": UnitType.from_dict({ "id": "cleric", "atk_ground": 4, "defense": 4, "move": 4, "max_troops": 8, "can_capture": true }),
	}

const SWITCH := Vector2i(2, 2)  # col/row
const BASE := Vector2i(5, 2)    # col/row

func _hex(cr: Vector2i) -> Vector2i:
	return Hex.offset_to_axial(cr.x, cr.y)

## スイッチ (2,2) を踏むと、敵が持っている間だけ拠点 (5,2) を中立に戻すイベント。
func _switch_event(extra: Dictionary = {}) -> Dictionary:
	var e := { "id": "switch-a", "type": "step", "col": SWITCH.x, "row": SWITCH.y, "stepped_by": "player",
		"if": [ { "type": "base_owner", "col": BASE.x, "row": BASE.y, "team": "enemy" } ],
		"neutralize": [ { "col": BASE.x, "row": BASE.y } ] }
	for k in extra:
		e[k] = extra[k]
	return e

func _state(events: Array, victory: Array = []) -> BattleState:
	var s := StageLoader.build({
		"cols": 8, "rows": 5,
		"player": [ { "units": [ { "type": "fighter", "col": 1, "row": 2 } ] } ],
		"enemy": [ { "ai": "charge", "units": [ { "type": "fighter", "col": 7, "row": 4 } ] } ],
		"bases": [ { "col": BASE.x, "row": BASE.y, "team": "enemy" } ],
		"events": events,
		"victory": victory,
	}, _catalog())
	s.set_movement(Movement.load_default())
	return s

func _base(s: BattleState) -> Base:
	return s.base_at(_hex(BASE))

func test_step_neutralizes_the_enemy_base() -> void:
	var s := _state([_switch_event()])
	var fired := s.fire_step_events(_hex(SWITCH), 0)
	assert_eq(fired.size(), 1, "踏んだら起きる")
	assert_eq(_base(s).team, Base.NEUTRAL, "拠点が中立に戻る")

func test_step_ignores_the_other_team_and_other_cells() -> void:
	var s := _state([_switch_event()])
	assert_eq(s.fire_step_events(_hex(SWITCH), 1).size(), 0, "踏んだ側が違えば起きない")
	assert_eq(s.fire_step_events(_hex(Vector2i(3, 2)), 0).size(), 0, "別のマスでは起きない")
	assert_eq(_base(s).team, 1, "拠点はそのまま")

func test_condition_blocks_while_the_base_is_already_neutral() -> void:
	var s := _state([_switch_event()])
	s.fire_step_events(_hex(SWITCH), 0)
	assert_eq(s.fire_step_events(_hex(SWITCH), 0).size(), 0, "中立のあいだは条件を満たさず起きない")
	assert_eq(s.pending_events().size(), 1, "消えずに残る")

func test_switch_works_again_after_the_enemy_retakes_the_base() -> void:
	var s := _state([_switch_event()])
	s.fire_step_events(_hex(SWITCH), 0)
	_base(s).team = 1  # 敵の占領兵が取り返した
	assert_eq(s.fire_step_events(_hex(SWITCH), 0).size(), 1, "踏み直せばまた起きる")
	assert_eq(_base(s).team, Base.NEUTRAL)

func test_once_makes_the_switch_single_use() -> void:
	var s := _state([_switch_event({ "once": "switch-a" })])
	s.fire_step_events(_hex(SWITCH), 0)
	_base(s).team = 1
	assert_eq(s.fire_step_events(_hex(SWITCH), 0).size(), 0, "once を書けば1回だけ")

func test_neutralize_keeps_the_garrison_inside() -> void:
	var s := StageLoader.build({
		"cols": 8, "rows": 5,
		"player": [ { "units": [ { "type": "fighter", "col": 1, "row": 2 } ] } ],
		"bases": [ { "col": BASE.x, "row": BASE.y, "team": "enemy",
			"garrison": [ { "type": "fighter", "native": "enemy" } ] } ],
		"events": [ _switch_event() ],
	}, _catalog())
	s.fire_step_events(_hex(SWITCH), 0)
	assert_eq(_base(s).garrison.size(), 1, "控えは中に残る")
	assert_false(_base(s).has_deployable_garrison(), "中立の持ち物＝敵 native の控えは誰も出せない")

func test_repeating_event_places_copies_with_new_handles() -> void:
	var s := _state([ { "id": "rein", "type": "step", "col": SWITCH.x, "row": SWITCH.y, "stepped_by": "player",
		"entry": "fade", "enemy": [ { "order": 5, "ai": "charge", "units": [ { "type": "fighter", "col": 6, "row": 0 } ] } ] } ])
	s.fire_step_events(_hex(SWITCH), 0)
	s.fire_step_events(_hex(SWITCH), 0)
	var handles := {}
	for u in s.units():
		assert_false(handles.has(u.handle), "盤の駒の番号が重ならない")
		handles[u.handle] = true
	assert_eq(s.team_unit_count(1), 3, "開始時の1体＋2回ぶん")
	var template: Unit = s.pending_events()[0].units[0].unit
	assert_false(handles.has(template.handle), "型紙の駒そのものは盤に出さない")

func test_invalid_condition_drops_the_event() -> void:
	var s := _state([_switch_event({ "if": [ { "type": "no_such_condition" } ] })])
	assert_push_warning("未知の条件")
	assert_true(s.pending_events().is_empty(), "読めない条件のイベントは捨てる（無条件で起きるほうへ倒さない）")

func test_step_without_stepped_by_is_dropped() -> void:
	var e := _switch_event()
	e.erase("stepped_by")
	var s := _state([e])
	assert_push_warning("stepped_by")
	assert_true(s.pending_events().is_empty())

# --- 勝利条件 deny_bases ---

func _deny(bases: Array) -> Array:
	return [ { "type": "deny_bases", "bases": bases } ]

func test_deny_bases_wins_when_every_base_is_out_of_enemy_hands() -> void:
	var s := _state([_switch_event()], _deny([ { "col": BASE.x, "row": BASE.y } ]))
	assert_false(Victory.condition_met(s, s.victory_conditions[0]), "敵が持っている間は不成立")
	s.fire_step_events(_hex(SWITCH), 0)
	assert_true(Victory.condition_met(s, s.victory_conditions[0]), "中立に戻したら成立")
	_base(s).team = 0
	assert_true(Victory.condition_met(s, s.victory_conditions[0]), "自軍が持っていても成立")
	_base(s).team = 1
	assert_false(Victory.condition_met(s, s.victory_conditions[0]), "取り返されたら不成立に戻る")

func test_deny_bases_needs_a_base_at_every_coordinate() -> void:
	var s := _state([], _deny([ { "col": 0, "row": 0 } ]))
	assert_false(Victory.condition_met(s, s.victory_conditions[0]), "拠点の無い座標は不成立")
	var empty := _state([], _deny([]))
	assert_false(Victory.condition_met(empty, empty.victory_conditions[0]), "空指定は不成立")

# --- コマンドメニューの「スイッチ停止」（doc/gdd/uiux.md）が引く問い合わせ ---

func test_step_neutralizes_at_tells_whether_stopping_there_stops_a_base() -> void:
	var s := _state([_switch_event()])
	assert_true(s.step_neutralizes_at(_hex(SWITCH), 0), "敵が持っている間は止まる")
	assert_false(s.step_neutralizes_at(_hex(SWITCH), 1), "踏む側が違えば止まらない")
	assert_false(s.step_neutralizes_at(_hex(Vector2i(3, 2)), 0), "スイッチでないマス")
	s.fire_step_events(_hex(SWITCH), 0)
	assert_false(s.step_neutralizes_at(_hex(SWITCH), 0), "止めた後は条件を満たさない＝待機のまま")
	assert_eq(_base(s).team, Base.NEUTRAL, "問い合わせは状態を変えない（止めたのは fire のほう）")

func test_step_without_neutralize_is_not_a_switch_stop() -> void:
	var e := _switch_event()
	e.erase("neutralize")
	e["dialogue"] = "talk"
	var s := _state([e])
	assert_false(s.step_neutralizes_at(_hex(SWITCH), 0), "拠点を止めない踏むイベントは「スイッチ停止」にしない")
