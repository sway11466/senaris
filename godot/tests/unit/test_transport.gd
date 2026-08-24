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
	assert_eq(cat["airship"].capacity, 4, "飛空艇=搭載4")
	assert_eq(cat["fighter"].capacity, 0, "歩兵=輸送不可")

func test_loader_wires_passengers() -> void:
	var data := { "cols": 8, "rows": 8, "player": [
		{ "type": "airship", "col": 1, "row": 1,
			"passengers": [ { "type": "paladin" }, { "type": "novice" } ] },
	] }
	var s := StageLoader.build(data, UnitCatalog.load_default())
	var airship := s.unit_by_id(1)
	assert_eq(airship.capacity, 4, "capacity が type から載る")
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

func test_can_pass_through_transport() -> void:
	# 輸送のマスは他の味方のマスと同じ＝すり抜けて先へ行ける（止まれば乗車）。
	var s := BattleState.new(6, 1)
	s.set_movement(Movement.load_default())
	s.add_unit(_transport(1, 0, Hex.offset_to_axial(1, 0)))
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(0, 0), 3))
	var reach := s.reachable(2)
	assert_true(reach.has(Hex.offset_to_axial(1, 0)), "輸送のマスには入れる（乗車）")
	assert_true(reach.has(Hex.offset_to_axial(2, 0)), "その先へも通り抜けられる（1本道）")
	assert_eq(s.path_to(2, Hex.offset_to_axial(3, 0)).size(), 4, "経路は輸送のマスを通る")

func test_full_transport_does_not_change_pass_through() -> void:
	# 満員かどうかで通り抜けの可否が変わらない（空き有無で壁になっていた不具合）。
	var s := BattleState.new(6, 1)
	s.set_movement(Movement.load_default())
	var wagon := _transport(1, 0, Hex.offset_to_axial(1, 0), 1)
	s.add_unit(wagon)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(0, 0), 3))
	assert_true(s.reachable(2).has(Hex.offset_to_axial(2, 0)), "空きあり: 先へ抜けられる")
	s.put_passenger(1, Unit.new(9, 0, Vector2i.ZERO, 3))  # 満員にする
	var reach := s.reachable(2)
	assert_true(reach.has(Hex.offset_to_axial(2, 0)), "満員でも先へ抜けられる")
	assert_false(reach.has(Hex.offset_to_axial(1, 0)), "満員の輸送のマスでは止まれない")

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
	s.end_turn()  # 自軍ターンに戻る＝行動フラグが流れる
	assert_false(s.unload_cells(1, 0).is_empty(), "翌ターンは降りられる")

func test_unload_respects_move_type_and_occupancy() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	var ground := Unit.new(2, 0, Vector2i.ZERO, 3)
	ground.move_type = "foot"
	s.put_passenger(1, ground)
	var rock := Hex.offset_to_axial(3, 2)
	s.set_terrain(rock, "rock")  # 地上は進入不可
	var blocker := Unit.new(3, 0, Hex.offset_to_axial(3, 4), 3)
	s.add_unit(blocker)
	var cells := s.unload_cells(1, 0)
	assert_false(cells.has(rock), "地上駒は大岩へ降りられない")
	assert_false(cells.has(blocker.pos), "占有マスへは降りられない")
	assert_false(cells.has(wagon.pos), "輸送自身のマスは降車先でない")
	assert_true(cells.size() > 0, "他の空きへは降りられる")

func test_flight_passenger_can_unload_onto_rock() -> void:
	var s := _state()
	var airship := _transport(1, 0, Hex.offset_to_axial(3, 3), 6)
	s.add_unit(airship)
	var flyer := Unit.new(2, 0, Vector2i.ZERO, 3)
	flyer.move_type = "flight"
	s.put_passenger(1, flyer)
	var rock := Hex.offset_to_axial(3, 2)
	s.set_terrain(rock, "rock")
	assert_true(s.unload_cells(1, 0).has(rock), "飛行駒は大岩の上にも降りられる")

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
	s.set_terrain(wagon_hex, "bedrock")  # foot の進入コスト3 ＞ 移動1
	s.add_unit(_transport(1, 0, wagon_hex))
	var rider := Unit.new(2, 0, Hex.offset_to_axial(2, 3), 1)
	rider.move_type = "foot"
	s.add_unit(rider)
	assert_true(s.move_unit(2, wagon_hex), "高コスト地形上の輸送にも隣接からは乗れる")

func test_special_unload_respects_impassable_terrain() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3))
	s.add_unit(wagon)
	var ground := Unit.new(2, 0, Vector2i.ZERO, 0)  # 移動0の地上駒
	ground.move_type = "foot"
	s.put_passenger(1, ground)
	var rock := Hex.offset_to_axial(3, 2)
	s.set_terrain(rock, "rock")  # 地上は進入不可
	var cells := s.unload_cells(1, 0)
	assert_false(cells.has(rock), "進入不可地形へは特例でも降ろせない")
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

# --- 出撃→直接乗車（拠点に隣接する輸送へ garrison から乗る。doc/gdd/movement.md） ---

func test_deploy_onto_adjacent_transport_boards() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(3, 3)
	var b := Base.new(base_hex, 0)
	b.garrison.append(Unit.new(9, 0, Vector2i.ZERO, 0))  # 移動0のバリケード相当
	s.add_base(b)
	var wagon := _transport(1, 0, Hex.offset_to_axial(4, 3))
	s.add_unit(wagon)
	assert_true(s.deploy_cells(base_hex, 0).has(wagon.pos), "隣接する乗れる輸送のマスが出撃先に含まれる")
	assert_true(s.deploy(base_hex, 0, wagon.pos), "輸送のマスへ出撃＝直接乗車")
	assert_null(s.unit_by_id(9), "盤上には出ない")
	assert_eq(s.passengers(1).size(), 1, "搭乗リストに載る")
	assert_eq(b.garrison.size(), 0, "garrison から抜ける")
	assert_true(s.unload_cells(1, 0).is_empty(), "出撃（乗車）したターンは降ろせない")
	s.end_turn()
	s.end_turn()
	assert_false(s.unload_cells(1, 0).is_empty(), "翌ターンは降ろせる")

func test_deploy_cells_exclude_enemy_or_full_transport() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(3, 3)
	var b := Base.new(base_hex, 0)
	b.garrison.append(Unit.new(9, 0, Vector2i.ZERO, 3))
	s.add_base(b)
	var enemy_wagon := _transport(1, 1, Hex.offset_to_axial(4, 3))
	s.add_unit(enemy_wagon)
	var full_wagon := _transport(2, 0, Hex.offset_to_axial(2, 3), 1)
	s.put_passenger(2, Unit.new(8, 0, Vector2i.ZERO, 3))  # 満員
	s.add_unit(full_wagon)
	var cells := s.deploy_cells(base_hex, 0)
	assert_false(cells.has(enemy_wagon.pos), "敵の輸送は出撃先にならない")
	assert_false(cells.has(full_wagon.pos), "満員の輸送は出撃先にならない")
	assert_false(s.deploy(base_hex, 0, enemy_wagon.pos), "敵の輸送へは出撃できない")
	assert_false(s.deploy(base_hex, 0, full_wagon.pos), "満員の輸送へは出撃できない")

func test_transport_garrison_cannot_deploy_onto_transport() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(3, 3)
	var b := Base.new(base_hex, 0)
	var garrison_wagon := _transport(9, 0, Vector2i.ZERO)
	b.garrison.append(garrison_wagon)
	s.add_base(b)
	var wagon := _transport(1, 0, Hex.offset_to_axial(4, 3))
	s.add_unit(wagon)
	assert_false(s.deploy_cells(base_hex, 0).has(wagon.pos), "輸送の控えに輸送のマスは出ない")
	assert_false(s.deploy(base_hex, 0, wagon.pos), "輸送は輸送に乗れない（出撃でも）")
	assert_true(s.deploy(base_hex, 0, Hex.offset_to_axial(3, 2)), "空きマスへの出撃は通常どおり")

# --- 拠点に入る（輸送は積載ごと。doc/gdd/movement.md・doc/gdd/map.md） ---

func test_enter_base_moves_passengers_into_garrison() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(3, 3)
	var b := Base.new(base_hex, 0)
	s.add_base(b)
	s.add_unit(_transport(1, 0, base_hex))
	var rider := Unit.new(2, 0, Vector2i.ZERO, 3)
	rider.troops = 3  # 傷んだ状態で運ばれてきた
	s.put_passenger(1, rider)
	s.add_unit(Unit.new(3, 0, Hex.offset_to_axial(6, 6), 3))  # 盤上最後の1体にならないよう相棒
	assert_true(s.enter_base(1), "積んだまま拠点に入れる")
	assert_eq(s.passengers(1).size(), 0, "積載は空になる")
	assert_eq(b.garrison.size(), 2, "輸送も搭乗駒も garrison に入る")
	assert_eq(b.garrison[1].id, 2, "搭乗駒は輸送の次に並ぶ")
	assert_false(s.can_deploy_garrison(base_hex, 0), "入ったターンは輸送を出せない")
	assert_false(s.can_deploy_garrison(base_hex, 1), "搭乗駒もそのターンは出せない（バラまき再配置の防止）")
	s.end_turn()
	s.end_turn()
	assert_eq(b.garrison[1].troops, b.garrison[1].max_troops, "中で回復する＝搭乗駒も回復の対象")
	assert_true(s.can_deploy_garrison(base_hex, 1), "翌ターンからは出撃できる")

func test_deploy_from_base_brings_no_passengers() -> void:
	# 積載は拠点で空になっているので、出撃した輸送は空のまま出る。
	var s := _state()
	var base_hex := Hex.offset_to_axial(3, 3)
	var b := Base.new(base_hex, 0)
	s.add_base(b)
	s.add_unit(_transport(1, 0, base_hex))
	s.put_passenger(1, Unit.new(2, 0, Vector2i.ZERO, 3))
	s.add_unit(Unit.new(3, 0, Hex.offset_to_axial(6, 6), 3))
	assert_true(s.enter_base(1), "拠点に入る")
	s.end_turn()
	s.end_turn()
	assert_true(s.deploy(base_hex, 0, Hex.neighbor(base_hex, 0)), "輸送を出撃させる")
	assert_eq(s.passengers(1).size(), 0, "出てきた輸送は空")
	assert_eq(b.garrison.size(), 1, "元の搭乗駒は控えとして拠点に残る")

# --- 輸送の撃破 ---

func test_transport_death_kills_passengers() -> void:
	var s := _state()
	var wagon := _transport(1, 0, Hex.offset_to_axial(3, 3), 4, 6)
	wagon.troops = 1  # 一撃で落ちる
	s.add_unit(wagon)
	var vip := Unit.new(2, 0, Vector2i.ZERO, 3)
	vip.actor = "vip"
	s.put_passenger(1, vip)
	s.victory_conditions = [{ "type": "defeat_unit", "actor": "vip" }]  # 搭乗駒がボスの場合も撃破扱い
	var killer := Unit.new(9, 1, Hex.neighbor(wagon.pos, 0), 3, 8, 90, 40)
	s.add_unit(killer)
	s.add_unit(Unit.new(3, 0, Hex.offset_to_axial(0, 0), 3))  # 全滅回避用の自軍
	s.current_team = 1
	var r := s.attack(9, 1)
	assert_true(bool(r["killed"]), "輸送が落ちる")
	assert_eq(s.passengers(1).size(), 0, "中の駒も失われる")
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "巻き添えは撃破扱い（defeat_unit が成立）")
