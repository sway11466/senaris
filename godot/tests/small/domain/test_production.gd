extends GutTest
## 拠点の生産＝持ち主のターン開始時にチャージを +1、規定量でリストの次の駒を控えに生む規則。
## 仕様 → doc/gdd/map.md（生産）

func _catalog() -> Dictionary:
	return {
		"cleric": UnitType.from_dict({ "id": "cleric", "atk_ground": 4, "defense": 4, "move": 4, "max_troops": 8, "can_capture": true }),
		"elf": UnitType.from_dict({ "id": "elf", "atk_ground": 6, "defense": 5, "move": 5, "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 7, "defense": 7, "move": 4, "max_troops": 6 }),
	}

const BASE_COL := 4
const BASE_ROW := 1

## 生産拠点1つ＋自軍の占領兵1体（拠点から離れた所）の盤。
func _stage(team: String, units: Array, charge_turns: int = 3) -> BattleState:
	return StageLoader.build({
		"cols": 8, "rows": 4,
		"player": [ { "units": [{ "type": "cleric", "col": 0, "row": 3 }] } ],
		"bases": [{ "col": BASE_COL, "row": BASE_ROW, "team": team,
			"production": { "charge_turns": charge_turns, "units": units } }],
	}, _catalog())

func _base(s: BattleState) -> Base:
	return s.base_at(Hex.offset_to_axial(BASE_COL, BASE_ROW))

## 敵のターン開始まで進める（自軍→敵）。敵のターン開始が1回来る。
func _to_enemy_turn(s: BattleState) -> void:
	if s.current_team == 1:
		s.end_turn()
	s.end_turn()

## 自軍のターン開始まで進める（敵→自軍）。自軍のターン開始が1回来る。
func _to_player_turn(s: BattleState) -> void:
	if s.current_team == 0:
		s.end_turn()
	s.end_turn()

func test_produces_when_charge_reaches_the_threshold() -> void:
	var s := _stage("enemy", [{ "type": "knight", "native": "enemy" }])
	var b := _base(s)
	_to_enemy_turn(s)
	_to_enemy_turn(s)
	assert_eq(b.garrison.size(), 0, "2回目のターン開始ではまだ生まない")
	assert_eq(b.production_charge, 2)
	_to_enemy_turn(s)
	assert_eq(b.garrison.size(), 1, "3回目のターン開始で1体生む")
	assert_eq(b.production_charge, 0, "生んだらチャージは 0 に戻る")

func test_charge_counts_only_on_the_owners_turn_start() -> void:
	var s := _stage("enemy", [{ "type": "knight", "native": "enemy" }])
	_to_player_turn(s)
	_to_player_turn(s)
	assert_eq(_base(s).production_charge, 2, "自軍のターン開始では数えない（敵の開始2回ぶんだけ）")

func test_produced_unit_carries_type_skin_and_native() -> void:
	var s := _stage("enemy", [{ "type": "knight", "native": "enemy" }], 1)
	_to_enemy_turn(s)
	var u: Unit = _base(s).garrison[0]
	assert_eq(u.type_id, "knight")
	assert_eq(u.skin_id, "knight", "type 指定は同名スキン")
	assert_eq(u.native_team, 1, "リストの native を持つ")
	assert_eq(u.recruited_team, 1, "帰属先も native に揃う")
	assert_eq(u.troops, 6, "満員で生まれる")
	assert_eq(u.level, 1)
	assert_ne(u.handle, s.unit_at(Hex.offset_to_axial(0, 3)).handle, "盤の駒と番号が衝突しない")

func test_list_is_produced_in_order_and_wraps() -> void:
	var s := _stage("enemy", [{ "type": "knight", "native": "enemy" }, { "type": "elf", "native": "enemy" }], 1)
	for _i in 3:
		_to_enemy_turn(s)
	var types: Array = []
	for u in _base(s).garrison:
		types.append(u.type_id)
	assert_eq(types, ["knight", "elf", "knight"], "上から順に生み、末尾の次は先頭")

func test_produced_units_are_appended_after_the_initial_garrison() -> void:
	var s := StageLoader.build({
		"cols": 8, "rows": 4,
		"player": [ { "units": [{ "type": "cleric", "col": 0, "row": 3 }] } ],
		"bases": [{ "col": BASE_COL, "row": BASE_ROW, "team": "enemy",
			"garrison": [{ "type": "elf", "native": "enemy" }],
			"production": { "charge_turns": 1, "units": [{ "type": "knight", "native": "enemy" }] } }],
	}, _catalog())
	_to_enemy_turn(s)
	var b := _base(s)
	assert_eq(b.garrison[0].type_id, "elf", "既存の控えが先")
	assert_eq(b.garrison[1].type_id, "knight", "生まれた駒は末尾")

func test_enemy_native_production_stops_while_the_player_holds_the_base() -> void:
	var s := _stage("enemy", [{ "type": "knight", "native": "enemy" }])
	_to_enemy_turn(s)
	var b := _base(s)
	assert_eq(b.production_charge, 1)
	b.team = 0  # 味方が取った
	_to_player_turn(s)
	_to_player_turn(s)
	assert_eq(b.production_charge, 1, "敵 native の駒は味方が出せない＝チャージは止まる")
	assert_eq(b.garrison.size(), 0)
	b.team = 1  # 敵が取り返した
	_to_enemy_turn(s)
	assert_eq(b.production_charge, 2, "戻さない＝止まった所の続きから")

func test_neutral_native_is_produced_for_either_owner() -> void:
	var s := _stage("player", [{ "type": "elf", "native": "neutral" }], 1)
	_to_player_turn(s)
	var b := _base(s)
	assert_eq(b.garrison.size(), 1, "中立 native は味方が持っていても生む")
	assert_true((b.garrison[0] as Unit).is_unclaimed(), "帰属は未確定のまま＝出した側に付く")

func test_neutral_owned_base_does_not_produce() -> void:
	var s := _stage("neutral", [{ "type": "elf", "native": "neutral" }], 1)
	_to_enemy_turn(s)
	_to_player_turn(s)
	assert_eq(_base(s).garrison.size(), 0, "中立には手番が無い")
	assert_eq(_base(s).production_charge, 0)

func test_list_position_is_kept_across_owner_changes() -> void:
	var s := _stage("enemy", [{ "type": "knight", "native": "enemy" }, { "type": "elf", "native": "enemy" }], 1)
	_to_enemy_turn(s)  # knight を生む＝次は elf
	var b := _base(s)
	b.team = 0
	_to_player_turn(s)
	b.team = 1
	_to_enemy_turn(s)
	assert_eq(b.garrison[1].type_id, "elf", "持ち主が変わってもリストの位置は戻さない")

func test_production_round_trips_through_the_save_diff() -> void:
	var data := {
		"cols": 8, "rows": 4,
		"player": [ { "units": [{ "type": "cleric", "col": 0, "row": 3 }] } ],
		"bases": [{ "col": BASE_COL, "row": BASE_ROW, "team": "enemy",
			"production": { "charge_turns": 3, "units": [{ "type": "knight", "native": "enemy" }, { "type": "elf", "native": "enemy" }] } }],
	}
	var s := StageLoader.build(data, _catalog())
	var b := _base(s)
	b.production_charge = 2
	b.production_next = 1
	var diff := s.to_save_diff()
	var s2 := StageLoader.build(data, _catalog())
	s2.apply_save_diff(diff, _catalog())
	var b2 := _base(s2)
	assert_eq(b2.production_charge, 2, "チャージを保つ")
	assert_eq(b2.production_next, 1, "リストの位置を保つ")
	assert_eq(b2.production_charge_turns, 3, "規定量とリストはステージから引き直す")

func test_production_key_does_not_leak_into_the_base_squad() -> void:
	var s := StageLoader.build({
		"cols": 8, "rows": 4,
		"player": [ { "units": [{ "type": "cleric", "col": 0, "row": 3 }] } ],
		"bases": [{ "col": BASE_COL, "row": BASE_ROW, "team": "enemy", "ai": "charge", "order": 1,
			"production": { "charge_turns": 3, "units": [{ "type": "knight", "native": "enemy" }] } }],
	}, _catalog())
	var squad: Dictionary = s.squads[_base(s).squad_index]
	assert_false(squad.has("production"), "生産は部隊定義に混ぜない")
