extends GutTest
## 移動システム（Movement 表 ＋ コスト付き reachable）のテスト。

func test_movement_table_loads() -> void:
	var t := Movement.load_default()
	assert_true(t.has("ground"), "ground 移動タイプがある")
	assert_eq(Movement.cost(t, "ground", "plain"), 1, "地上・平地=1")
	assert_eq(Movement.cost(t, "ground", "plateau"), 2, "地上・台地=2")
	assert_eq(Movement.cost(t, "flight", "plateau"), 1, "飛行・台地=1")

func test_cost_impassable_and_default() -> void:
	var t := { "ground": { "plain": 1, "plateau": "x" } }
	assert_eq(Movement.cost(t, "ground", "plateau"), Movement.IMPASSABLE, "x は進入不可")
	assert_eq(Movement.cost(t, "ground", "unknown"), 1, "表に無い地形は既定1")
	assert_eq(Movement.cost({}, "ground", "plain"), 1, "空表は全地形1（従来挙動）")

func test_reachable_default_uniform() -> void:
	# 移動表なし＝全地形コスト1。従来の一律移動と同じ。
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(3, 3)
	var u := Unit.new(1, 0, ap, 1)  # move 1
	s.add_unit(u)
	var reach := s.reachable(1)
	assert_true(reach.has(ap), "起点を含む")
	assert_eq(reach.size(), 7, "move1＝起点＋隣接6＝7マス")

func test_reachable_terrain_cost_shrinks_range() -> void:
	var s := BattleState.new(8, 8)
	s.set_movement({ "ground": { "plain": 1, "plateau": 2 } })
	var ap := Hex.offset_to_axial(3, 3)
	var u := Unit.new(1, 0, ap, 1)
	u.move_type = "ground"
	s.add_unit(u)
	var plateau_hex := Hex.neighbor(ap, 0)
	s.set_terrain(plateau_hex, "plateau")
	var reach := s.reachable(1)
	assert_false(reach.has(plateau_hex), "move1ではコスト2の台地に届かない")
	assert_true(reach.has(Hex.neighbor(ap, 2)), "コスト1の平地隣には届く")

func test_reachable_impassable_blocks() -> void:
	var s := BattleState.new(8, 8)
	s.set_movement({ "ground": { "plain": 1, "plateau": "x" } })
	var ap := Hex.offset_to_axial(3, 3)
	var u := Unit.new(1, 0, ap, 3)
	u.move_type = "ground"
	s.add_unit(u)
	var wall := Hex.neighbor(ap, 0)
	s.set_terrain(wall, "plateau")  # 進入不可
	var reach := s.reachable(1)
	assert_false(reach.has(wall), "進入不可の台地には入れない")

func test_zoc_stops_movement() -> void:
	# move2。p0→p1→p2 の直線で、p1 が敵ZOCなら p1で止まり p2に届かない。
	var s := BattleState.new(8, 8)
	var p0 := Hex.offset_to_axial(2, 3)
	var p1 := Hex.neighbor(p0, 0)
	var p2 := Hex.neighbor(p1, 0)
	s.add_unit(Unit.new(1, 0, p0, 2))
	s.add_unit(Unit.new(2, 1, p1 + Vector2i(1, -1), 3))  # p1 に隣接（p0 には非隣接）の敵
	var reach := s.reachable(1)
	assert_true(reach.has(p1), "敵ZOCのマスには入れる")
	assert_false(reach.has(p2), "ZOCで停止＝その先へは進めない")

func test_zoc_control_no_enemy() -> void:
	var s := BattleState.new(8, 8)
	var p0 := Hex.offset_to_axial(2, 3)
	var p2 := Hex.neighbor(Hex.neighbor(p0, 0), 0)
	s.add_unit(Unit.new(1, 0, p0, 2))
	assert_true(s.reachable(1).has(p2), "敵が居なければ2歩先に届く（対照）")

func test_zoc_applies_to_flight() -> void:
	var s := BattleState.new(8, 8)
	s.set_movement({ "flight": { "plain": 1, "plateau": 1 } })
	var p0 := Hex.offset_to_axial(2, 3)
	var p1 := Hex.neighbor(p0, 0)
	var p2 := Hex.neighbor(p1, 0)
	var u := Unit.new(1, 0, p0, 2)
	u.move_type = "flight"
	s.add_unit(u)
	s.add_unit(Unit.new(2, 1, p1 + Vector2i(1, -1), 3))
	var reach := s.reachable(1)
	assert_true(reach.has(p1))
	assert_false(reach.has(p2), "飛行もZOCで停止（移動タイプ非依存）")

func test_can_leave_enemy_zoc() -> void:
	# 起点が敵ZOC内でも動き出せる。
	var s := BattleState.new(8, 8)
	var p0 := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(1, 0, p0, 2))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(p0, 3), 3))  # 起点に隣接する敵
	var away := Hex.neighbor(p0, 0)  # 敵の反対側（ZOC外）
	assert_true(s.reachable(1).has(away), "ZOC内の起点からは動き出せる")

func test_flight_ignores_climb() -> void:
	var s := BattleState.new(8, 8)
	s.set_movement({ "ground": { "plain": 1, "plateau": 2 }, "flight": { "plain": 1, "plateau": 1 } })
	var ap := Hex.offset_to_axial(3, 3)
	var u := Unit.new(1, 0, ap, 1)
	u.move_type = "flight"
	s.add_unit(u)
	var plateau_hex := Hex.neighbor(ap, 0)
	s.set_terrain(plateau_hex, "plateau")
	var reach := s.reachable(1)
	assert_true(reach.has(plateau_hex), "飛行は台地コスト1なので隣の台地に届く")
