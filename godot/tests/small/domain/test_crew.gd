extends GutTest
## 兵器の移動（人手が要る駒は、隣のマスに味方がいるときだけ動ける）のテスト。
## 詳細 → doc/gdd/movement.md 兵器の移動

func _state() -> BattleState:
	return BattleState.new(8, 8)

func _at(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(col, row)

## 人手が要る兵器（移動砲などの形）。
func _engine(id: int, pos: Vector2i) -> Unit:
	var u := Unit.new(id, 0, pos, 2)
	u.needs_crew = true
	u.category = "war_machine"
	return u

## 人手が要る輸送（トロッコの形）。
func _cart(id: int, pos: Vector2i) -> Unit:
	var u := Unit.new(id, 0, pos, 8)
	u.needs_crew = true
	u.category = "transport"
	u.capacity = 4
	return u

func _foot(id: int, team: int, pos: Vector2i) -> Unit:
	var u := Unit.new(id, team, pos, 3)
	u.category = "infantry"
	return u

# --- データ配線 ---

func test_catalog_wires_needs_crew_and_category() -> void:
	var cat := UnitCatalog.load_default()
	for id in ["cannon", "mantlet", "drill", "minecart", "railcar"]:
		assert_true(cat[id].needs_crew, "%s は人手が要る" % id)
	assert_false(cat["ballista"].needs_crew, "据え置きのバリスタは人手の列を持たない")
	assert_false(cat["wagon"].needs_crew, "馬車は馬が引く＝人手は要らない")
	assert_eq(cat["cannon"].category, "war_machine", "兵種が型から載る")
	assert_eq(cat["wagon"].category, "transport", "兵種が型から載る")

# --- 隣の味方 ---

func test_alone_cannot_move() -> void:
	var s := _state()
	s.add_unit(_engine(1, _at(3, 3)))
	assert_false(s.has_crew(s.unit_by_handle(1)), "隣に誰もいない＝人手なし")
	assert_false(s.can_still_move(1), "人手なしでは動けない")
	assert_false(s.move_unit(1, Hex.neighbor(_at(3, 3), 0)), "move_unit も弾く")

func test_adjacent_ally_lets_it_move() -> void:
	var s := _state()
	var p := _at(3, 3)
	s.add_unit(_engine(1, p))
	s.add_unit(_foot(2, 0, Hex.neighbor(p, 3)))
	assert_true(s.can_still_move(1), "隣に味方の歩兵＝動ける")
	assert_true(s.move_unit(1, Hex.neighbor(p, 0)), "実際に動かせる")

func test_acted_ally_still_counts() -> void:
	var s := _state()
	var p := _at(3, 3)
	var helper_from := Hex.neighbor(Hex.neighbor(p, 3), 3)
	s.add_unit(_engine(1, p))
	s.add_unit(_foot(2, 0, helper_from))
	assert_true(s.move_unit(2, Hex.neighbor(p, 3)), "味方が隣へ来て行動を終える")
	assert_false(s.can_still_move(2), "味方は行動済み")
	assert_true(s.can_still_move(1), "行動済みの味方も人手に数える")

func test_enemy_neighbor_does_not_count() -> void:
	var s := _state()
	var p := _at(3, 3)
	s.add_unit(_engine(1, p))
	s.add_unit(_foot(2, 1, Hex.neighbor(p, 3)))
	assert_false(s.can_still_move(1), "隣が敵だけ＝人手なし")

func test_engine_and_transport_neighbors_do_not_count() -> void:
	var s := _state()
	var p := _at(3, 3)
	s.add_unit(_engine(1, p))
	s.add_unit(_engine(2, Hex.neighbor(p, 3)))
	s.add_unit(_cart(3, Hex.neighbor(p, 1)))
	assert_false(s.can_still_move(1), "兵器・輸送どうしが並んでも動けない")

func test_unflagged_unit_moves_alone() -> void:
	var s := _state()
	s.add_unit(_foot(1, 0, _at(3, 3)))
	assert_true(s.can_still_move(1), "人手の要らない駒は1体でも動ける")

# --- 輸送（トロッコ） ---

func test_cart_with_passenger_moves_alone() -> void:
	var s := _state()
	s.add_unit(_cart(1, _at(3, 3)))
	assert_false(s.can_still_move(1), "空のトロッコは隣に味方がいなければ動けない")
	s.put_passenger(1, _foot(2, 0, _at(3, 3)))
	assert_true(s.can_still_move(1), "誰かが乗っていれば隣の味方は要らない")

func test_empty_cart_moves_with_adjacent_ally() -> void:
	var s := _state()
	var p := _at(3, 3)
	s.add_unit(_cart(1, p))
	s.add_unit(_foot(2, 0, Hex.neighbor(p, 3)))
	assert_true(s.can_still_move(1), "空でも隣に味方がいれば動ける")
