extends GutTest
## イベント（途中で起きること）。引き金（ターン／拠点の占領）・排他（once）・置き場所・
## 搭載駒・残りターン・直列化を検証する。
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
	paladin.move_type = "foot"
	var fighter := UnitType.new()
	fighter.id = "fighter"
	fighter.move = 6
	fighter.move_type = "foot"
	var cleric := UnitType.new()
	cleric.id = "cleric"
	cleric.move = 5
	cleric.move_type = "foot"
	cleric.can_capture = true
	return { "airship": airship, "paladin": paladin, "fighter": fighter, "cleric": cleric }

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

# --- 会話（イベントに付ける台本キー） ---

## イベントが預かるのは台本のキーだけ（台本そのものは presentation が読む＝案P）。
## 起きたイベントは last_fired_events に控える＝end_turn の内側で発火しても上へ届く。
func test_event_carries_dialogue_key() -> void:
	var s := _state([_reinforce(2, { "dialogue": "arrive" })])
	assert_eq(String(s.pending_events()[0].get("dialogue", "")), "arrive", "台本キーを預かる")
	assert_true(s.last_fired_events.is_empty(), "まだ起きていない")
	s.end_turn(); s.end_turn()  # ターン2 自軍＝発生
	assert_eq(s.last_fired_events.size(), 1, "起きたイベントを控える")
	assert_eq(String(s.last_fired_events[0].get("dialogue", "")), "arrive", "台本キーごと渡す")

## 台本キーを書かないイベントは空のまま（会話なしで黙って加わる）。カメラも既定は寄せない。
func test_event_without_dialogue_key_is_empty() -> void:
	var s := _state([_reinforce(1)])
	assert_eq(String(s.last_fired_events[0].get("dialogue", "")), "", "既定は会話なし")
	assert_false(bool(s.last_fired_events[0].get("focus", false)), "既定はカメラを寄せない")

# --- カメラ（focus）と、実際に駒が出た場所 ---

## focus は指定をそのまま預かり、placed に「実際に出た hex」が入る＝カメラの行き先になる。
func test_event_records_where_units_landed() -> void:
	var s := _state([_reinforce(1, { "focus": true })])
	var fired: Dictionary = s.last_fired_events[0]
	assert_true(bool(fired.get("focus", false)), "カメラ指定を預かる")
	assert_eq(fired.get("placed", []), [Hex.offset_to_axial(5, 3)], "出た hex を控える")

## ずれて出たときは、指定座標ではなくずれた先を控える（カメラは本当の場所を見る）。
func test_placed_hex_follows_the_shift() -> void:
	var data := _data([_reinforce(1, { "focus": true })])
	data["player"].append({ "type": "fighter", "col": 5, "row": 3 })  # 指定先を先に埋める
	var s := _build(data)
	var placed: Array = s.last_fired_events[0].get("placed", [])
	assert_eq(placed.size(), 1, "1体ぶん控える")
	assert_ne(placed[0], Hex.offset_to_axial(5, 3), "指定座標ではない")
	assert_eq(Hex.distance(placed[0], Hex.offset_to_axial(5, 3)), 1, "ずれた先＝隣を控える")

func test_focus_survives_serialization() -> void:
	var s := _state([_reinforce(4, { "focus": true })])
	var back := BattleState.from_dict(s.to_dict(), _catalog())
	assert_true(bool(back.pending_events()[0].get("focus", false)), "中断セーブでもカメラ指定は残る")

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

func test_dialogue_key_survives_serialization() -> void:
	var s := _state([_reinforce(4, { "dialogue": "arrive" })])
	var back := BattleState.from_dict(s.to_dict(), _catalog())
	assert_eq(String(back.pending_events()[0].get("dialogue", "")), "arrive", "中断セーブでも台本キーは残る")

func test_fired_event_is_not_serialized() -> void:
	var s := _state([_reinforce(1)])
	var back := BattleState.from_dict(s.to_dict(), _catalog())
	assert_true(back.pending_events().is_empty(), "発生済みは持ち越さない")
	assert_eq(back.team_unit_count(0), 2, "盤の駒としては残る")

# --- 引き金＝拠点の占領（on: "capture"） ---

const BASE_COL := 3
const BASE_ROW := 2

func _base_hex() -> Vector2i:
	return Hex.offset_to_axial(BASE_COL, BASE_ROW)

## (3,2) に中立拠点、その隣（2,2）に占領できるクレリック。敵は置かない（決着はここでは見ない）。
func _capture_state(events: Array) -> BattleState:
	var data := _data(events)
	data["player"] = [ { "type": "cleric", "col": 2, "row": 2 } ]
	data["bases"] = [ { "col": BASE_COL, "row": BASE_ROW, "team": "neutral" } ]
	return _build(data)

func _capture_event(team: String, extra: Dictionary = {}) -> Dictionary:
	var e := { "on": "capture", "col": BASE_COL, "row": BASE_ROW, "team": team,
		"type": "talk", "dialogue": "taken_by_%s" % team }
	for k in extra:
		e[k] = extra[k]
	return e

## クレリックを拠点へ入れて占領する（所属が変わることを確かめてから返す）。
func _capture_with_cleric(s: BattleState) -> void:
	var u := s.unit_at(Hex.offset_to_axial(2, 2))
	assert_not_null(u, "前提: クレリックが盤に居る")
	assert_true(s.move_unit(u.id, _base_hex()), "前提: 拠点hexへ入れる")
	assert_eq(s.base_at(_base_hex()).team, 0, "前提: 占領で自軍所属になる")

## 引き金が占領のイベントは、ターンが進んでも起きない。
func test_capture_event_does_not_fire_on_turns() -> void:
	var s := _capture_state([_capture_event("player")])
	s.end_turn(); s.end_turn(); s.end_turn(); s.end_turn()
	assert_eq(s.pending_events().size(), 1, "ターンでは起きない")
	assert_true(s.last_fired_events.is_empty(), "ターンの発火にも混ざらない")

## 駒を出さないイベント（type: "talk"）は盤を変えない。
func test_talk_event_places_no_units() -> void:
	var s := _capture_state([_capture_event("player")])
	assert_eq(s.team_unit_count(0), 1, "駒は増えない")
	assert_true((s.pending_events()[0].get("units", []) as Array).is_empty(), "駒を持たない")

func test_capture_event_fires_when_the_base_changes_hands() -> void:
	var s := _capture_state([_capture_event("player")])
	_capture_with_cleric(s)
	var fired := s.fire_capture_events(_base_hex(), 0)
	assert_eq(fired.size(), 1, "占領した瞬間に起きる")
	assert_eq(String(fired[0].get("dialogue", "")), "taken_by_player", "台本キーごと渡す")
	assert_true(s.pending_events().is_empty(), "起きたイベントは消える")

func test_capture_event_fires_once() -> void:
	var s := _capture_state([_capture_event("player")])
	_capture_with_cleric(s)
	assert_eq(s.fire_capture_events(_base_hex(), 0).size(), 1, "1回起きる")
	assert_eq(s.fire_capture_events(_base_hex(), 0).size(), 0, "取り返しても2回目は起きない")

func test_capture_event_ignores_another_base() -> void:
	var s := _capture_state([_capture_event("player")])
	assert_eq(s.fire_capture_events(Hex.offset_to_axial(5, 3), 0).size(), 0, "別の拠点では起きない")
	assert_eq(s.pending_events().size(), 1, "未発生のまま残る")

func test_capture_event_ignores_the_other_team() -> void:
	var s := _capture_state([_capture_event("player")])
	assert_eq(s.fire_capture_events(_base_hex(), 1).size(), 0, "取った側が違えば起きない")
	assert_eq(s.pending_events().size(), 1, "未発生のまま残る")

## 敵が取ったときのイベントは team:"enemy" で書く（増援と違い、駒ではなく取った側を指す）。
func test_enemy_capture_event_fires_for_the_enemy() -> void:
	var s := _capture_state([_capture_event("enemy")])
	var fired := s.fire_capture_events(_base_hex(), 1)
	assert_eq(fired.size(), 1, "敵が取れば起きる")
	assert_eq(String(fired[0].get("dialogue", "")), "taken_by_enemy", "敵側の台本キーを渡す")

# --- 排他（once） ---

## 味方版と敵版に同じ名前を書くと、先に起きたほうだけが流れる。
func test_once_lets_only_one_of_them_fire() -> void:
	var s := _capture_state([
		_capture_event("player", { "once": "elf_village" }),
		_capture_event("enemy", { "once": "elf_village" }),
	])
	assert_eq(s.fire_capture_events(_base_hex(), 0).size(), 1, "味方が取ったぶんが起きる")
	assert_true(s.pending_events().is_empty(), "敵版は以後起きない")
	assert_eq(s.fire_capture_events(_base_hex(), 1).size(), 0, "後から敵に奪われても流れない")

func test_once_does_not_touch_other_names() -> void:
	var s := _capture_state([
		_capture_event("player", { "once": "elf_village" }),
		_capture_event("enemy", { "once": "dwarf_hall" }),
	])
	assert_eq(s.fire_capture_events(_base_hex(), 0).size(), 1, "味方版が起きる")
	assert_eq(s.pending_events().size(), 1, "名前が違うイベントは残る")

## 排他はターン起点のイベントにも効く（引き金の種類は問わない）。
func test_once_spans_triggers() -> void:
	var s := _capture_state([
		_capture_event("player", { "once": "elf_village" }),
		{ "turn": 2, "type": "talk", "team": "player", "once": "elf_village", "dialogue": "too_late" },
	])
	_capture_with_cleric(s)
	assert_eq(s.fire_capture_events(_base_hex(), 0).size(), 1, "先に占領で起きる")
	s.end_turn(); s.end_turn()  # ターン2 自軍
	assert_true(s.last_fired_events.is_empty(), "同じ名前のターンイベントは起きない")

## 同じ名前が同時に条件を満たしたら、先に書いたほうが起きる。
func test_once_prefers_the_first_written() -> void:
	var s := _capture_state([
		_capture_event("player", { "once": "elf_village", "dialogue": "first" }),
		_capture_event("player", { "once": "elf_village", "dialogue": "second" }),
	])
	var fired := s.fire_capture_events(_base_hex(), 0)
	assert_eq(fired.size(), 1, "起きるのは1つだけ")
	assert_eq(String(fired[0].get("dialogue", "")), "first", "先に書いたほう")

# --- 中断セーブ（占領イベント） ---

func test_capture_event_survives_serialization() -> void:
	var s := _capture_state([_capture_event("player", { "once": "elf_village", "focus": true })])
	var back := BattleState.from_dict(s.to_dict(), _catalog())
	back.set_movement(Movement.load_default())
	assert_eq(back.pending_events().size(), 1, "未発生のまま復元される")
	var e: Dictionary = back.pending_events()[0]
	assert_eq(String(e.get("on", "")), "capture", "引き金が残る")
	assert_eq(e.get("hex", Vector2i.MAX), _base_hex(), "拠点の hex が残る")
	assert_eq(String(e.get("once", "")), "elf_village", "排他の名前が残る")
	assert_eq(back.fire_capture_events(_base_hex(), 0).size(), 1, "復元後も占領で起きる")

## 占領イベントは残りターン板に出さない（あと何ターンかを数えられない）。
func test_capture_event_is_not_announced_as_a_countdown() -> void:
	var s := _capture_state([_capture_event("player", { "label": "ui.test.village" })])
	assert_true(s.next_event().is_empty(), "残りターンには出ない")


# --- デバッグ発火（fire_event）。引き金を問わず1件を起こす。仕様 → doc/gdd/uiux.md デバッグメニュー ---

## ターン起点のイベントを、発生ターン前でも起こせる。
func test_fire_event_ignores_the_turn_trigger() -> void:
	var s := _state([_reinforce(5)])
	assert_true(s.fire_event(s.pending_events()[0]), "起こせた")
	assert_eq(s.team_unit_count(0), 2, "増援が盤に出る")
	assert_true(s.pending_events().is_empty(), "未発生から消える")

## 占領起点のイベントも、拠点を取らずに起こせる。ただし拠点の所属は動かない
## ＝会話だけが流れる（デバッグの用途＝台本の確認）。
func test_fire_event_does_not_change_the_board() -> void:
	var s := _capture_state([_capture_event("player")])
	assert_true(s.fire_event(s.pending_events()[0]), "起こせた")
	assert_eq(s.base_at(_base_hex()).team, Base.NEUTRAL, "拠点は中立のまま")
	assert_true(s.pending_events().is_empty(), "未発生から消える")

## 同じ once の兄弟は道連れに捨てられる（通常の発火と同じ）。
func test_fire_event_discards_the_once_siblings() -> void:
	var s := _capture_state([
		_capture_event("player", { "once": "village" }),
		_capture_event("enemy", { "once": "village" }),
	])
	assert_true(s.fire_event(s.pending_events()[0]), "味方版が起きる")
	assert_true(s.pending_events().is_empty(), "敵版は以後起きない")

## 既に起きたイベントは2度目を起こせない。
func test_fire_event_rejects_a_fired_event() -> void:
	var s := _state([_reinforce(5)])
	var e: Dictionary = s.pending_events()[0]
	assert_true(s.fire_event(e), "1回目は起きる")
	assert_false(s.fire_event(e), "2回目は起きない")
	assert_eq(s.team_unit_count(0), 2, "駒も増えない")

## デバッグ発火は last_fired_events を触らない（そちらは end_turn 用の控え）。
func test_fire_event_leaves_last_fired_events_alone() -> void:
	var s := _state([_reinforce(5)])
	s.fire_event(s.pending_events()[0])
	assert_true(s.last_fired_events.is_empty(), "ターンの控えには混ざらない")
