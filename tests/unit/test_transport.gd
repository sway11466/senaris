extends GutTest
## 輸送（積載・運搬・降車）のテスト。詳細 → doc/gdd/movement.md（輸送）

func _state() -> BattleState:
	var s := BattleState.new(10, 8)
	s.set_movement(Movement.load_default())  # 地形コスト（崖=進入不可 等）を有効化
	return s

## 輸送ユニット（capacity 指定）を作る。
func _transport(id: int, team: int, pos: Vector2i, cap := 4, move := 6) -> Unit:
	var u := Unit.new(id, team, pos, move)
	u.capacity = cap
	return u

# --- データ配線 ---

func test_catalog_wires_capacity() -> void:
	var cat := UnitCatalog.load_default()
	assert_eq(cat["wagon"].capacity, 4, "馬車=搭載4")
	assert_eq(cat["airship"].capacity, 6, "飛空艇=搭載6")
	assert_eq(cat["fighter"].capacity, 0, "歩兵=輸送不可")

func test_loader_wires_passengers() -> void:
	var data := { "cols": 8, "rows": 8, "units": [
		{ "type": "airship", "team": 0, "col": 1, "row": 1,
			"passengers": [ { "type": "paladin" }, { "type": "novice" } ] },
	] }
	var s := StageLoader.build(data, UnitCatalog.load_default())
	var airship := s.unit_by_id(1)
	assert_eq(airship.capacity, 6, "capacity が type から載る")
	assert_eq(s.passengers(1).size(), 2, "初期搭乗2体")
	assert_null(s.unit_by_id(2), "搭乗駒は盤上に居ない")
	assert_eq(s.passengers(1)[0].team, 0, "搭乗駒は輸送と同陣営")

# --- 乗車（board） ---

func test_move_onto_transport_boards() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	var rider := Unit.new(2, 0, Hex.offset_to_axial(2, 3), 3)
	s.add_unit(wagon)
	s.add_unit(rider)
	assert_true(s.reachable(2).has(wagon.pos), "味方輸送のマスは移動先に含まれる")
	assert_true(s.move_unit(2, wagon.pos), "輸送のマスへ移動＝乗車")
	assert_null(s.unit_by_id(2), "乗った駒は盤上から消える")
	assert_eq(s.passengers(1).size(), 1, "輸送の搭乗リストに載る")
	assert_true(s.has_moved(2) and s.has_attacked(2), "乗った駒は行動完了")

func test_cannot_board_enemy_full_or_transport() -> void:
	var s := _state()
	var wagon := _transport(1, 1, Hex.offset_to_axial(3, 3), 1)  # 敵の輸送・容量1
	var rider := Unit.new(2, 0, Hex.offset_to_axial(2, 3), 3)
	s.add_unit(wagon)
	s.add_unit(rider)
	assert_false(s.move_unit(2, wagon.pos), "敵の輸送には乗れない")
	wagon.team = 0
	s.put_passenger(1, Unit.new(9, 0, Vector2i.ZERO, 3))  # 満員にする
	assert_false(s.move_unit(2, wagon.pos), "満員の輸送には乗れない")
	var wagon2 := _transport(3, 0, Hex.offset_to_axial(2, 4), 4)
	s.add_unit(wagon2)
	assert_false(s.move_unit(3, wagon.pos), "輸送は輸送に乗れない")

func test_cannot_pass_through_transport() -> void:
	# 輸送のマスは「終点としてのみ」進入可＝すり抜けて先へは行けない。
	var s := BattleState.new(6, 1)
	s.set_movement(Movement.load_default())
	s.add_unit(_transport(1, 0, Hex.offset_to_axial(1, 0)))
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(0, 0), 3))
	var reach := s.reachable(2)
	assert_true(reach.has(Hex.offset_to_axial(1, 0)), "輸送のマスには入れる（乗車）")
	assert_false(reach.has(Hex.offset_to_axial(2, 0)), "その先へは通り抜けられない（1本道）")

func test_transport_moves_after_loading_same_turn() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(2, 3), 3))
	s.move_unit(2, wagon.pos)  # 乗車
	assert_true(s.move_unit(1, Hex.offset_to_axial(6, 3)), "輸送は別ユニット＝同ターンに運搬できる")
	assert_eq(s.passengers(1).size(), 1, "載せたまま動く")

# --- 降車（unload） ---

func test_boarded_this_turn_cannot_unload() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(2, 3), 3))
	s.move_unit(2, wagon.pos)
	assert_true(s.unload_cells(1, 0).is_empty(), "乗車したターンは降りられない")
	s.end_turn()
	s.end_turn()  # 自軍手番に戻る＝行動フラグが流れる
	assert_false(s.unload_cells(1, 0).is_empty(), "翌ターンは降りられる")

func test_unload_respects_move_type_and_occupancy() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	var ground := Unit.new(2, 0, Vector2i.ZERO, 3)
	ground.move_type = "ground"
	s.put_passenger(1, ground)
	var cliff := Hex.offset_to_axial(3, 2)
	s.set_terrain(cliff, "cliff")  # 地上は進入不可
	var blocker := Unit.new(3, 0, Hex.offset_to_axial(3, 4), 3)
	s.add_unit(blocker)
	var cells := s.unload_cells(1, 0)
	assert_false(cells.has(cliff), "地上駒は崖へ降りられない")
	assert_false(cells.has(blocker.pos), "占有マスへは降りられない")
	assert_false(cells.has(wagon.pos), "輸送自身のマスは降車先でない")
	assert_true(cells.size() > 0, "他の空きへは降りられる")

func test_flight_passenger_can_unload_onto_cliff() -> void:
	var s := _state()
	var airship := _transport(1, 0, Hex.offset_to_axial(3, 3), 6)
	s.add_unit(airship)
	var flyer := Unit.new(2, 0, Vector2i.ZERO, 3)
	flyer.move_type = "flight"
	s.put_passenger(1, flyer)
	var cliff := Hex.offset_to_axial(3, 2)
	s.set_terrain(cliff, "cliff")
	assert_true(s.unload_cells(1, 0).has(cliff), "飛行駒は崖の上にも降りられる")

func test_unload_places_unit_and_allows_attack() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	var fighter := Unit.new(2, 0, Vector2i.ZERO, 5, 8, 50, 40)
	s.put_passenger(1, fighter)
	var enemy := Unit.new(9, 1, Hex.offset_to_axial(3, 5), 3, 8, 10, 4)
	s.add_unit(enemy)
	var dest := Hex.offset_to_axial(3, 4)  # 敵の隣
	assert_true(s.unload(1, 0, dest), "降車できる")
	assert_eq(s.unit_by_id(2).pos, dest, "盤上に配置される")
	assert_true(s.has_moved(2), "降車＝移動を消費")
	assert_true(s.can_attack(2, 9), "降車後に攻撃できる（通常の移動→攻撃と同じ）")
	assert_eq(s.passengers(1).size(), 0, "搭乗リストから抜ける")

func test_unload_onto_base_captures() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	var cleric := Unit.new(2, 0, Vector2i.ZERO, 3)
	cleric.can_capture = true
	s.put_passenger(1, cleric)
	var base_hex := Hex.offset_to_axial(3, 4)
	s.add_base(Base.new(base_hex, 1))
	assert_true(s.unload(1, 0, base_hex), "拠点hexへ降車")
	assert_eq(s.base_at(base_hex).team, 0, "降りた瞬間に占領（移動と同じ扱い）")

func test_unload_attack_targets_from_hypothetical_hex() -> void:
	# 降車確認メニュー用: 盤上に居ない搭乗駒でも「その位置に降りたら攻撃できるか」を引ける。
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	s.put_passenger(1, Unit.new(2, 0, Vector2i.ZERO, 5, 8, 50, 40))
	var enemy := Unit.new(9, 1, Hex.offset_to_axial(3, 5), 3)
	s.add_unit(enemy)
	var near := Hex.offset_to_axial(3, 4)  # 敵の隣
	var far := Hex.offset_to_axial(3, 2)   # 敵から遠い
	assert_true(s.unload_attack_targets(1, 0, near).has(9), "敵の隣に降りれば攻撃できる")
	assert_true(s.unload_attack_targets(1, 0, far).is_empty(), "遠くに降りれば対象なし")

func test_unload_allowed_after_transport_done() -> void:
	# 降車は搭乗駒の行動＝輸送が移動・待機で行動完了になっていても、未行動の駒は降ろせる。
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	s.put_passenger(1, Unit.new(2, 0, Vector2i.ZERO, 3))  # 前ターンから搭乗（未行動）
	assert_true(s.move_unit(1, Hex.offset_to_axial(5, 3)), "輸送が移動")
	s.set_done(1)  # コマンドメニューの「待機」相当
	assert_true(s.can_select(1), "待機済みでも降車のために選択できる")
	assert_false(s.unload_cells(1, 0).is_empty(), "降車先も出る")
	assert_true(s.unload(1, 0, Hex.offset_to_axial(5, 2)), "降車できる")
	assert_true(s.is_done(1), "降ろせる駒が尽きれば待機どおり行動終了")

# --- 隣接1マスの特例（乗降は隣接なら移動力・地形コスト無関係。doc/gdd/movement.md） ---

func test_move0_unit_boards_adjacent_transport() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	var barricade := Unit.new(2, 0, Hex.offset_to_axial(2, 3), 0)  # 移動0
	s.add_unit(wagon)
	s.add_unit(barricade)
	var reach := s.reachable(2)
	assert_true(reach.has(wagon.pos), "移動0でも隣接する輸送のマスは候補に入る")
	assert_eq(reach.size(), 2, "盤上を歩けるようにはならない（自マス＋輸送のみ）")
	assert_true(s.move_unit(2, wagon.pos), "移動0の駒が隣接輸送に乗れる")
	assert_eq(s.passengers(1).size(), 1, "搭乗リストに載る")

func test_move0_unit_cannot_board_distant_transport() -> void:
	var s := _state()
	s.add_unit(_transport(1, 0, Hex.offset_to_axial(4, 3)))  # 2マス先
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(2, 3), 0))
	assert_false(s.move_unit(2, Hex.offset_to_axial(4, 3)), "特例は隣接1マスだけ＝離れた輸送には乗れない")

func test_move0_passenger_unloads_to_adjacent() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	s.put_passenger(1, Unit.new(2, 0, Vector2i.ZERO, 0))  # 移動0（前ターンから搭乗）
	var cells := s.unload_cells(1, 0)
	assert_eq(cells.size(), 6, "移動0でも隣接6マスへ降ろせる")
	var dest := Hex.offset_to_axial(3, 4)
	assert_true(s.unload(1, 0, dest), "隣接マスへ降車できる")
	assert_eq(s.unit_by_id(2).pos, dest, "盤上に配置される")

func test_move1_unit_boards_transport_on_costly_terrain() -> void:
	var s := _state()
	var wagon_hex := Hex.offset_to_axial(3, 3)
	s.set_terrain(wagon_hex, "mountain")  # ground の進入コスト3 ＞ 移動1
	s.add_unit(_transport(1, 0, wagon_hex))
	var rider := Unit.new(2, 0, Hex.offset_to_axial(2, 3), 1)
	rider.move_type = "ground"
	s.add_unit(rider)
	assert_true(s.move_unit(2, wagon_hex), "高コスト地形上の輸送にも隣接からは乗れる")

func test_special_unload_respects_impassable_terrain() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	var ground := Unit.new(2, 0, Vector2i.ZERO, 0)  # 移動0の地上駒
	ground.move_type = "ground"
	s.put_passenger(1, ground)
	var cliff := Hex.offset_to_axial(3, 2)
	s.set_terrain(cliff, "cliff")  # 地上は進入不可
	var cells := s.unload_cells(1, 0)
	assert_false(cells.has(cliff), "進入不可地形へは特例でも降ろせない")
	assert_eq(cells.size(), 5, "残りの隣接5マスへは降ろせる")

func test_special_board_then_unload_same_turn_denied() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(2, 3), 0))
	s.move_unit(2, wagon.pos)  # 特例で乗車
	assert_true(s.unload_cells(1, 0).is_empty(), "乗車したターンは降りられない（特例でも維持）")
	s.end_turn()
	s.end_turn()
	assert_false(s.unload_cells(1, 0).is_empty(), "翌ターンは降ろせる")

# --- 輸送の撃破 ---

func test_transport_death_kills_passengers() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3), 4, 6)
	wagon.troops = 1  # 一撃で落ちる
	s.add_unit(wagon)
	var vip := Unit.new(2, 0, Vector2i.ZERO, 3)
	s.put_passenger(1, vip)
	s.victory_conditions = [{ "type": "defeat_unit", "unit_id": 2 }]  # 搭乗駒がボスの場合も撃破扱い
	var killer := Unit.new(9, 1, Hex.neighbor(wagon.pos, 0), 3, 8, 90, 40)
	s.add_unit(killer)
	s.add_unit(Unit.new(3, 0, Hex.offset_to_axial(0, 0), 3))  # 全滅回避用の自軍
	s.current_team = 1
	var r := s.attack(9, 1)
	assert_true(bool(r["killed"]), "輸送が落ちる")
	assert_eq(s.passengers(1).size(), 0, "中の駒も失われる")
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "巻き添えは撃破扱い（defeat_unit が成立）")
