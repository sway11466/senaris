extends GutTest
## BattleState の視線（索敵の遮蔽・減衰）テスト。詳細 → doc/gdd/movement.md（視線）, doc/gdd/ai.md（起動）
## sight_reaches＝from→to のヘックス直線の視線コスト積算 ≤ budget。全地形1なら距離判定に一致。

# 視線コスト表（テスト用・地形id→コスト）。wall は完全遮蔽。
const COST := { "plain": 1, "forest": 2, "wall": 1 << 20 }

func _state(cols: int, rows: int) -> BattleState:
	var s := BattleState.new(cols, rows)
	s.set_sight_cost(COST)
	return s

func test_no_table_reduces_to_distance() -> void:
	# 視線コスト表を入れない＝全地形1扱い＝累積コスト＝距離。既存の純距離の索敵と一致。
	var s := BattleState.new(8, 4)
	assert_true(s.sight_reaches(Vector2i(0, 0), Vector2i(3, 0), 3), "距離3 ≤ budget3")
	assert_false(s.sight_reaches(Vector2i(0, 0), Vector2i(4, 0), 3), "距離4 > budget3")

func test_plain_reduces_to_distance() -> void:
	var s := _state(8, 4)
	assert_true(s.sight_reaches(Vector2i(0, 0), Vector2i(3, 0), 3), "平地は距離どおり")
	assert_false(s.sight_reaches(Vector2i(0, 0), Vector2i(4, 0), 3))

func test_forest_attenuates_range() -> void:
	# (1,0) を森にすると、そこを通る視線は +1 余分に食う＝森ごしは短く見通す。
	var s := _state(8, 4)
	s.set_terrain(Vector2i(1, 0), "forest")
	# (0,0)→(2,0) は plain(1)+... 経路は (1,0)=forest(2)+(2,0)=plain(1)=3。budget3 ならギリ届く。
	assert_true(s.sight_reaches(Vector2i(0, 0), Vector2i(2, 0), 3), "森1マスごし・累積3 ≤ 3")
	assert_false(s.sight_reaches(Vector2i(0, 0), Vector2i(2, 0), 2), "同じ経路・budget2 では届かない")

func test_wall_blocks_line_of_sight() -> void:
	# 壁が直線上にあると裏には届かない（累積が跳ね上がる）。
	var s := _state(8, 4)
	s.set_terrain(Vector2i(1, 0), "wall")
	assert_false(s.sight_reaches(Vector2i(0, 0), Vector2i(2, 0), 5), "壁の裏は遮蔽")
	assert_false(s.sight_reaches(Vector2i(0, 0), Vector2i(3, 0), 99), "budget を上げても壁は越えない")

func test_wall_does_not_block_off_line() -> void:
	# 壁は直線上のときだけ遮る＝別方向（直線が壁を通らない）は見える。
	var s := _state(8, 4)
	s.set_terrain(Vector2i(1, 0), "wall")
	# (0,0)→(0,2) の直線は (0,1) を通り、壁(1,0) を通らない＝見える
	assert_true(s.sight_reaches(Vector2i(0, 0), Vector2i(0, 2), 2), "壁を通らない方向は見える")

func test_visible_hexes_excludes_shadow_behind_wall() -> void:
	var s := _state(8, 4)
	s.set_terrain(Vector2i(2, 0), "wall")
	var vis := s.visible_hexes(Vector2i(0, 0), 4)
	assert_true(vis.has(Vector2i(0, 0)), "自マスは可視")
	assert_true(vis.has(Vector2i(1, 0)), "壁の手前は可視")
	assert_false(vis.has(Vector2i(3, 0)), "壁の真後ろは影＝不可視")
	assert_false(vis.has(Vector2i(2, 0)), "壁自身は不可視（遮蔽コスト）")

func test_visible_hexes_within_board_only() -> void:
	var s := _state(3, 3)
	var vis := s.visible_hexes(Vector2i(0, 0), 5)
	for h in vis:
		assert_true(s.in_field(h), "盤外は含めない")
