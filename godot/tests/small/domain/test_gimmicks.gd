extends GutTest
## 仕掛け（gimmicks）＝地形とは別の層に置き、種類ごとの振る舞いで盤に効く。1件目は生産装置のスイッチ。
## 勝利条件 gimmick_state と勝敗条件の文言 label も見る。仕様 → doc/gdd/gimmicks.md・doc/gdd/map.md 勝敗条件

func _catalog() -> Dictionary:
	return {
		"fighter": UnitType.from_dict({ "id": "fighter", "atk_ground": 5, "defense": 5, "move": 4, "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 7, "defense": 7, "move": 4, "max_troops": 6 }),
	}

const SWITCH := Vector2i(2, 2)  # col/row
const BASE := Vector2i(5, 2)    # col/row

func _hex(cr: Vector2i) -> Vector2i:
	return Hex.offset_to_axial(cr.x, cr.y)

func _switch(extra: Dictionary = {}) -> Dictionary:
	var g := { "id": "switch-a", "kind": "production_switch", "col": SWITCH.x, "row": SWITCH.y, "state": "on",
		"base": { "col": BASE.x, "row": BASE.y } }
	for k in extra:
		g[k] = extra[k]
	return g

## 敵の生産拠点 (5,2)（毎敵ターン1体）と、それを止めるスイッチ (2,2)。
func _data(gimmicks: Array, victory: Array = []) -> Dictionary:
	return {
		"cols": 8, "rows": 5,
		"player": [ { "units": [ { "type": "fighter", "col": 1, "row": 2 } ] } ],
		"enemy": [ { "ai": "charge", "units": [ { "type": "fighter", "col": 7, "row": 4 } ] } ],
		"bases": [ { "col": BASE.x, "row": BASE.y, "team": "enemy",
			"production": { "charge_turns": 1, "units": [ { "type": "knight", "native": "enemy" } ] } } ],
		"gimmicks": gimmicks,
		"victory": victory,
	}

func _state(gimmicks: Array, victory: Array = []) -> BattleState:
	return StageLoader.build(_data(gimmicks, victory), _catalog())

func _base(s: BattleState) -> Base:
	return s.base_at(_hex(BASE))

# --- 読み込み ---

func test_loader_places_a_gimmick_with_its_params() -> void:
	var s := _state([_switch()])
	var g := s.gimmick_by_id("switch-a")
	assert_not_null(g)
	assert_eq(g.kind, "production_switch")
	assert_eq(g.hex, _hex(SWITCH))
	assert_eq(g.state, "on", "最初の状態はステージが書く")
	assert_eq(g.params["base"], _hex(BASE), "固有の要素（対象の拠点）")
	assert_eq(s.gimmick_at(_hex(SWITCH)), g)

## チャージスポット＝状態は on だけ・固有の要素なし。踏むと溜まり方が spot のスキルのチャージを満たす
## （中身は test_skill.gd マナリーク）。on の間は床が光る。仕様 → doc/gdd/gimmicks.md チャージスポット
func test_loader_places_a_charge_spot() -> void:
	var s := _state([{ "id": "spot-a", "kind": "charge_spot", "col": 3, "row": 2, "state": "on" }])
	var g := s.gimmick_by_id("spot-a")
	assert_not_null(g)
	assert_eq(g.state, GimmickKinds.CHARGE_ON)
	assert_true(GimmickKinds.is_charge_spot(g))
	assert_not_null(GimmickKinds.glow_color(g), "on の間は床が光る")
	assert_eq(GimmickKinds.state_after_step(g, 0), "", "踏んでも状態は変わらない")
	assert_false(GimmickKinds.is_trap(g.kind), "罠ではない")

func test_loader_rejects_unknown_kind_and_state() -> void:
	var s := _state([_switch({ "kind": "no_such_kind" })])
	assert_push_warning("kind が未知")
	assert_true(s.gimmicks().is_empty())
	var s2 := _state([_switch({ "state": "half" })])
	assert_push_warning("state が")
	assert_true(s2.gimmicks().is_empty(), "種類に無い状態は置かない")

func test_loader_requires_the_kind_params() -> void:
	var g := _switch()
	g.erase("base")
	var s := _state([g])
	assert_push_warning("base")
	assert_true(s.gimmicks().is_empty(), "生産装置のスイッチは対象の拠点が必須")

func test_one_gimmick_per_cell() -> void:
	var s := _state([_switch(), _switch({ "id": "switch-b" })])
	assert_push_warning("既に仕掛けがある")
	assert_eq(s.gimmicks().size(), 1)

func test_gimmick_id_is_required_and_unique() -> void:
	var g := _switch()
	g.erase("id")
	_state([g])
	assert_push_error("仕掛けの id")
	_state([_switch(), _switch({ "col": 3 })])
	assert_push_error("重複")

# --- 踏む（生産装置のスイッチ） ---

func test_player_step_turns_the_switch_off_and_enemy_step_turns_it_on() -> void:
	var s := _state([_switch()])
	assert_eq(s.step_gimmick(_hex(SWITCH), 0).state, "off", "味方が踏むと止まる")
	assert_null(s.step_gimmick(_hex(SWITCH), 0), "止まっているときに味方が踏んでも変わらない")
	assert_eq(s.step_gimmick(_hex(SWITCH), 1).state, "on", "敵が踏むと再開する")
	assert_null(s.step_gimmick(_hex(SWITCH), 1), "動いているときに敵が踏んでも変わらない")

func test_switch_glows_only_while_on() -> void:
	# 駒が乗って絵が隠れても状態が読めるよう、on の間だけ床を光らせる（doc/gdd/gimmicks.md 絵）。
	var s := _state([_switch()])
	var g: Gimmick = s.gimmick_by_id("switch-a")
	assert_eq(GimmickKinds.glow_color(g), Color("#C85750"), "on の間は紋の赤で光る")
	s.step_gimmick(_hex(SWITCH), 0)
	assert_null(GimmickKinds.glow_color(g), "off にすると消える")

func test_every_kind_says_whether_it_glows() -> void:
	# 光らせるかは種類ごとに明示する（書き忘れを「光らない」に倒さない）。
	for k in GimmickKinds.KINDS:
		assert_true((GimmickKinds.KINDS[k] as Dictionary).has("glow"), "種類 '%s' に glow がある" % k)

func test_switch_does_not_change_the_base_owner() -> void:
	var s := _state([_switch()])
	s.step_gimmick(_hex(SWITCH), 0)
	assert_eq(_base(s).team, 1, "拠点は敵の持ち物のまま")

func test_step_on_an_empty_cell_does_nothing() -> void:
	var s := _state([_switch()])
	assert_null(s.step_gimmick(_hex(Vector2i(3, 2)), 0))

# --- 生産の停止 ---

func test_off_switch_stops_production_and_freezes_the_charge() -> void:
	var s := _state([_switch()])
	s.step_gimmick(_hex(SWITCH), 0)  # off
	s.end_turn()  # 敵のターン開始
	assert_eq(_base(s).garrison.size(), 0, "止めている間は生まない")
	assert_eq(_base(s).production_charge, 0, "チャージも溜まらない")
	s.step_gimmick(_hex(SWITCH), 1)  # on
	s.end_turn()
	s.end_turn()  # 次の敵のターン開始
	assert_eq(_base(s).garrison.size(), 1, "再開したら生む")

func test_switch_only_blocks_its_own_base() -> void:
	var data := _data([_switch({ "base": { "col": 0, "row": 0 } })])
	var s := StageLoader.build(data, _catalog())
	s.step_gimmick(_hex(SWITCH), 0)
	s.end_turn()
	assert_eq(_base(s).garrison.size(), 1, "別の拠点を指すスイッチは、この拠点の生産を止めない")

# --- セーブ ---

func test_gimmick_state_round_trips_through_the_save_diff() -> void:
	var s := _state([_switch()])
	s.step_gimmick(_hex(SWITCH), 0)
	var diff := s.to_save_diff()
	assert_eq(diff["gimmicks"], { "switch-a": "off" }, "id → 状態だけを持つ（座標は持たない）")
	var s2 := _state([_switch()])
	s2.apply_save_diff(diff, _catalog())
	assert_eq(s2.gimmick_by_id("switch-a").state, "off")

func test_restore_follows_the_id_when_the_gimmick_moved() -> void:
	var s := _state([_switch()])
	s.step_gimmick(_hex(SWITCH), 0)
	var diff := s.to_save_diff()
	var s2 := _state([_switch({ "col": 3, "row": 3 })])  # マップを直して動かした
	s2.apply_save_diff(diff, _catalog())
	assert_eq(s2.gimmick_by_id("switch-a").state, "off", "座標が変わっても id で追える")

func test_restore_ignores_unknown_ids_and_states() -> void:
	var s := _state([_switch()])
	s.apply_save_diff({ "gimmicks": { "gone": "off", "switch-a": "half" } }, _catalog())
	assert_eq(s.gimmick_by_id("switch-a").state, "on", "種類に無い状態は被せない")

# --- 勝利条件 gimmick_state ---

func _all_off(ids: Array) -> Array:
	return [ { "type": "gimmick_state", "gimmicks": ids, "state": "off", "label": "test.switches" } ]

func test_gimmick_state_wins_when_every_named_gimmick_is_in_the_state() -> void:
	var s := _state([_switch(), _switch({ "id": "switch-b", "col": 3 })], _all_off(["switch-a", "switch-b"]))
	var c: Dictionary = s.victory_conditions[0]
	assert_false(Victory.condition_met(s, c))
	s.step_gimmick(_hex(SWITCH), 0)
	assert_false(Victory.condition_met(s, c), "1つだけでは不成立（AND）")
	s.step_gimmick(_hex(Vector2i(3, 2)), 0)
	assert_true(Victory.condition_met(s, c), "全部 off で成立")
	s.step_gimmick(_hex(SWITCH), 1)
	assert_false(Victory.condition_met(s, c), "敵が戻したら不成立に戻る")

func test_gimmick_state_needs_every_id_on_the_board() -> void:
	var s := _state([_switch({ "state": "off" })], _all_off(["switch-a", "missing"]))
	assert_false(Victory.condition_met(s, s.victory_conditions[0]), "盤に無い id は不成立")

func test_gimmick_state_without_label_is_warned() -> void:
	_state([_switch()], [ { "type": "gimmick_state", "gimmicks": ["switch-a"], "state": "off" } ])
	assert_push_warning("label")

# --- 勝敗条件の文言 label ---

func test_label_replaces_the_built_line() -> void:
	var data := _data([_switch()], _all_off(["switch-a"]))
	data["victory"].append({ "type": "capture_base", "bases": [ { "col": BASE.x, "row": BASE.y } ], "label": "test.capture" })
	data["victory"].append({ "type": "capture_base", "bases": [ { "col": BASE.x, "row": BASE.y } ] })
	var lines: PackedStringArray = ObjectiveText.build(StageLoader.build(data, _catalog()), {})["victory"]
	assert_eq(lines[0], "test.switches", "gimmick_state は label の文言（訳が無ければキーのまま）")
	assert_eq(lines[1], "test.capture", "ほかの条件も label を書けば上書き")
	assert_ne(lines[2], "test.capture", "書かなければ種類ごとの文言")
