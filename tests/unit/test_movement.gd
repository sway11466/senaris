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
	s.set_terrain(plateau_hex, Terrain.PLATEAU)
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
	s.set_terrain(wall, Terrain.PLATEAU)  # 進入不可
	var reach := s.reachable(1)
	assert_false(reach.has(wall), "進入不可の台地には入れない")

func test_flight_ignores_climb() -> void:
	var s := BattleState.new(8, 8)
	s.set_movement({ "ground": { "plain": 1, "plateau": 2 }, "flight": { "plain": 1, "plateau": 1 } })
	var ap := Hex.offset_to_axial(3, 3)
	var u := Unit.new(1, 0, ap, 1)
	u.move_type = "flight"
	s.add_unit(u)
	var plateau_hex := Hex.neighbor(ap, 0)
	s.set_terrain(plateau_hex, Terrain.PLATEAU)
	var reach := s.reachable(1)
	assert_true(reach.has(plateau_hex), "飛行は台地コスト1なので隣の台地に届く")
