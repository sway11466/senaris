extends GutTest
## イベント（時限発生）＝増援。発生ターン・置き場所・搭載駒・残りターン・直列化を検証する。
## 増援は「開始時に盤に存在しない駒が加わること」だけを指す（拠点の出撃・起動は別物）。
## 仕様 → doc/gdd/map.md イベント

func _catalog() -> Dictionary:
	var airship := UnitType.new()
	airship.id = "airship"
	airship.move = 9
	airship.move_type = "flight"
	airship.capacity = 6
	var paladin := UnitType.new()
	paladin.id = "paladin"
	paladin.move = 5
	paladin.move_type = "ground"
	var fighter := UnitType.new()
	fighter.id = "fighter"
	fighter.move = 6
	fighter.move_type = "ground"
	return { "airship": airship, "paladin": paladin, "fighter": fighter }

# 6x4 の平地。自軍1体だけ置いて、あとはイベントで足す。
func _data(events: Array) -> Dictionary:
	return {
		"cols": 6, "rows": 4,
		"terrain": ["......", "......", "......", "......"],
		"player": [ { "type": "fighter", "col": 0, "row": 0 } ],
		"enemy": [],
		"events": events,
	}

## build → 移動コスト表 → 1ターン目の増援を出す、の順（load_file と同じ）。
func _build(data: Dictionary) -> BattleState:
	var s := StageLoader.build(data, _catalog())
	s.set_movement(Movement.load_default())
	s.fire_due_events()
	return s

func _state(events: Array) -> BattleState:
	return _build(_data(events))

func _reinforce(turn: int, extra: Dictionary = {}) -> Dictionary:
	var e := { "turn": turn, "type": "reinforce", "team": "player",
		"units": [ { "type": "fighter", "col": 5, "row": 3 } ] }
	for k in extra:
		e[k] = extra[k]
	return e

# --- 発生ターン ---

func test_not_on_board_before_the_turn() -> void:
	var s := _state([_reinforce(3)])
	assert_eq(s.team_unit_count(0), 1, "開始時は増援がまだ盤に居ない")
	assert_eq(s.pending_events().size(), 1, "未発生として持っている")

func test_arrives_on_the_given_turn() -> void:
	var s := _state([_reinforce(3)])
	s.end_turn()  # ターン1 敵
	s.end_turn()  # ターン2 自軍
	assert_eq(s.team_unit_count(0), 1, "2ターン目にはまだ来ない")
	s.end_turn()  # ターン2 敵
	s.end_turn()  # ターン3 自軍＝発生
	assert_eq(s.team_unit_count(0), 2, "3ターン目の自軍の手番で加わる")
	assert_true(s.pending_events().is_empty(), "発生したイベントは消える")
	assert_not_null(s.unit_at(Hex.offset_to_axial(5, 3)), "指定した座標に出る")

## 1ターン目に指定した自軍の増援は、開始時点で盤に居る（end_turn を待たない）。
func test_turn_one_fires_at_start() -> void:
	var s := _state([_reinforce(1)])
	assert_eq(s.team_unit_count(0), 2, "開始時点で加わっている")

func test_fires_only_once() -> void:
	var s := _state([_reinforce(2)])
	s.end_turn(); s.end_turn()  # ターン2 自軍
	assert_eq(s.team_unit_count(0), 2, "1回加わる")
	s.end_turn(); s.end_turn()  # ターン3 自軍
	assert_eq(s.team_unit_count(0), 2, "2回目は起きない")

## 敵の増援は敵の手番で起きる（同じターン番号でも自軍の手番では出ない）。
func test_enemy_reinforcement_fires_on_enemy_turn() -> void:
	var e := _reinforce(2, { "team": "enemy", "ai": "charge" })
	var s := _state([e])
	s.end_turn(); s.end_turn()  # ターン2 自軍
	assert_eq(s.team_unit_count(1), 0, "自軍の手番では出ない")
	s.end_turn()  # ターン2 敵
	assert_eq(s.team_unit_count(1), 1, "敵の手番で加わる")

func test_enemy_reinforcement_joins_a_squad() -> void:
	var s := _state([_reinforce(1, { "team": "enemy", "ai": "charge" })])
	s.end_turn()  # ターン1 敵
	var foe: Unit = null
	for u in s.units():
		if u.team == 1:
			foe = u
	assert_not_null(foe, "敵の増援が盤に居る")
	if foe != null:
		assert_eq(String(s.squad_of(foe.id).get("ai", "")), "charge", "部隊のAIプリセットを持つ")

# --- 置き場所 ---

## 指定hexが埋まっていたら最寄りの空きへずらす（イベントは止まらない）。
func test_shifts_to_the_nearest_free_hex() -> void:
	var data := _data([_reinforce(1)])
	data["player"].append({ "type": "fighter", "col": 5, "row": 3 })  # 指定先を先に埋める
	var s := _build(data)
	assert_eq(s.team_unit_count(0), 3, "ずれても出る")
	var want := Hex.offset_to_axial(5, 3)
	var arrived: Unit = null
	for u in s.units():
		if u.pos != want and u.pos != Hex.offset_to_axial(0, 0):
			arrived = u
	assert_not_null(arrived, "指定先とは別のhexに出た")
	if arrived != null:
		assert_eq(Hex.distance(arrived.pos, want), 1, "最寄り＝隣に出る")

## 進入できない地形（壁）を指定したら、入れる最寄りへずらす。
func test_shifts_off_impassable_terrain() -> void:
	var data := _data([_reinforce(1)])
	data["terrain"] = ["......", "......", "......", ".....#"]  # (5,3) が壁
	var s := _build(data)
	assert_eq(s.team_unit_count(0), 2, "壁を指定しても出る")
	assert_null(s.unit_at(Hex.offset_to_axial(5, 3)), "壁の上には出ない")

# --- 搭載駒 ---

func test_transport_arrives_loaded() -> void:
	var e := { "turn": 2, "type": "reinforce", "team": "player",
		"units": [ { "type": "airship", "col": 5, "row": 3,
			"passengers": [ { "type": "paladin" } ] } ] }
	var s := _state([e])
	assert_eq(s.team_unit_count(0), 1, "開始時は居ない")
	s.end_turn(); s.end_turn()
	var ship := s.unit_at(Hex.offset_to_axial(5, 3))
	assert_not_null(ship, "飛空艇が来る")
	if ship != null:
		assert_eq(s.passengers(ship.id).size(), 1, "パラディンを乗せたまま来る")
		assert_eq(String((s.passengers(ship.id)[0] as Unit).type_id), "paladin", "中身はパラディン")

## 搭載駒は盤上に居ない＝殲滅の数には入らない（既存の輸送と同じ扱い）。
func test_passengers_are_not_on_board() -> void:
	var e := { "turn": 1, "type": "reinforce", "team": "player",
		"units": [ { "type": "airship", "col": 5, "row": 3,
			"passengers": [ { "type": "paladin" } ] } ] }
	var s := _state([e])
	assert_eq(s.team_unit_count(0), 2, "盤に居るのは元の1体＋飛空艇")

# --- 残りターン（表示用） ---

func test_next_event_counts_down() -> void:
	var s := _state([_reinforce(3, { "label": "ui.test.airship" })])
	assert_eq(int(s.next_event()["turns"]), 2, "1ターン目なら あと2")
	assert_eq(String(s.next_event()["label"]), "ui.test.airship", "label を返す")
	s.end_turn(); s.end_turn()
	assert_eq(int(s.next_event()["turns"]), 1, "2ターン目なら あと1")
	s.end_turn(); s.end_turn()
	assert_true(s.next_event().is_empty(), "発生したら表示は消える")

## label の無いイベントは予告しない（黙って加わる）。
func test_unlabeled_event_is_not_announced() -> void:
	var s := _state([_reinforce(3)])
	assert_true(s.next_event().is_empty(), "label が無ければ出さない")

func test_next_event_picks_the_soonest() -> void:
	var s := _state([
		_reinforce(5, { "label": "ui.test.late" }),
		_reinforce(2, { "label": "ui.test.soon" }),
	])
	assert_eq(String(s.next_event()["label"]), "ui.test.soon", "いちばん近いものを出す")

# --- 中断セーブ ---

func test_pending_event_survives_serialization() -> void:
	var e := { "turn": 4, "type": "reinforce", "team": "player", "label": "ui.test.airship",
		"units": [ { "type": "airship", "col": 5, "row": 3,
			"passengers": [ { "type": "paladin" } ] } ] }
	var s := _state([e])
	var back := BattleState.from_dict(s.to_dict(), _catalog())
	back.set_movement(Movement.load_default())
	assert_eq(back.pending_events().size(), 1, "未発生のまま復元される")
	assert_eq(int(back.next_event()["turns"]), 3, "残りターンも復元される")
	back.end_turn(); back.end_turn(); back.end_turn(); back.end_turn()
	back.end_turn(); back.end_turn()  # ターン4 自軍
	var ship := back.unit_at(Hex.offset_to_axial(5, 3))
	assert_not_null(ship, "復元後も発生ターンに来る")
	if ship != null:
		assert_eq(back.passengers(ship.id).size(), 1, "搭載駒も復元される")

func test_fired_event_is_not_serialized() -> void:
	var s := _state([_reinforce(1)])
	var back := BattleState.from_dict(s.to_dict(), _catalog())
	assert_true(back.pending_events().is_empty(), "発生済みは持ち越さない")
	assert_eq(back.team_unit_count(0), 2, "盤の駒としては残る")
