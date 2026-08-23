extends GutTest
## domain/hex/hex.gd の単体テスト。

func test_neighbors_count() -> void:
	assert_eq(Hex.neighbors(Vector2i(0, 0)).size(), 6, "6近傍が返る")

func test_neighbor_is_distance_one() -> void:
	var c := Vector2i(2, -1)
	for dir in 6:
		assert_eq(Hex.distance(c, Hex.neighbor(c, dir)), 1, "隣は距離1")

func test_distance_self_is_zero() -> void:
	assert_eq(Hex.distance(Vector2i(3, -2), Vector2i(3, -2)), 0)

func test_distance_symmetric() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(2, -1)
	assert_eq(Hex.distance(a, b), Hex.distance(b, a))

func test_distance_known_values() -> void:
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, 0)), 3)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 3)), 3)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(-1, -1)), 2)

func test_direction_wraps() -> void:
	assert_eq(Hex.direction(6), Hex.direction(0), "6は0に折り返す")
	assert_eq(Hex.direction(-1), Hex.direction(5))

func test_line_same_hex_is_single() -> void:
	assert_eq(Hex.line(Vector2i(2, -1), Vector2i(2, -1)), [Vector2i(2, -1)] as Array[Vector2i])

func test_line_length_is_distance_plus_one() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(3, -1)
	assert_eq(Hex.line(a, b).size(), Hex.distance(a, b) + 1, "両端含めて距離+1個")

func test_line_endpoints_and_contiguity() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(4, -2)
	var path := Hex.line(a, b)
	assert_eq(path[0], a, "始点")
	assert_eq(path[-1], b, "終点")
	for i in range(1, path.size()):
		assert_eq(Hex.distance(path[i - 1], path[i]), 1, "隣接して繋がる")

func test_line_straight_row() -> void:
	# q 方向にまっすぐ＝各マスが q+1
	var path := Hex.line(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i])

func test_line_deterministic() -> void:
	# 際どい線でも毎回同じ（決定的＝セーブ/リプレイに安全）
	var a := Vector2i(0, 0)
	var b := Vector2i(2, 1)
	assert_eq(Hex.line(a, b), Hex.line(a, b))

func test_within_range_counts() -> void:
	# 距離 n 以内のヘックス数は 1 + 3n(n+1)。
	assert_eq(Hex.within_range(Vector2i(0, 0), 0).size(), 1)
	assert_eq(Hex.within_range(Vector2i(0, 0), 1).size(), 7)
	assert_eq(Hex.within_range(Vector2i(0, 0), 2).size(), 19)

func test_within_range_all_within_distance() -> void:
	var c := Vector2i(1, 1)
	for h in Hex.within_range(c, 3):
		assert_lte(Hex.distance(c, h), 3, "範囲内は距離3以下")

func test_ring_zero_is_center() -> void:
	var r := Hex.ring(Vector2i(5, 5), 0)
	assert_eq(r.size(), 1)
	assert_eq(r[0], Vector2i(5, 5))

func test_ring_size_and_distance() -> void:
	var c := Vector2i(0, 0)
	for radius in range(1, 4):
		var r := Hex.ring(c, radius)
		assert_eq(r.size(), 6 * radius, "リングのヘックス数は 6*radius")
		for h in r:
			assert_eq(Hex.distance(c, h), radius, "リング上は距離=radius")

func test_pixel_round_trip() -> void:
	# axial → pixel → axial が同値に戻る。
	var size := 32.0
	for q in range(-4, 5):
		for r in range(-4, 5):
			var h := Vector2i(q, r)
			assert_eq(Hex.from_pixel(Hex.to_pixel(h, size), size), h, "round-trip %s" % h)

func test_offset_axial_round_trip() -> void:
	for col in range(0, 12):
		for row in range(0, 8):
			var axial := Hex.offset_to_axial(col, row)
			assert_eq(Hex.axial_to_offset(axial), Vector2i(col, row), "offset round-trip (%d,%d)" % [col, row])

func test_origin_maps_to_zero_pixel() -> void:
	assert_eq(Hex.to_pixel(Vector2i(0, 0), 32.0), Vector2.ZERO)

func test_flood_open_equals_within_range() -> void:
	# 障害なしなら到達集合は within_range と一致する。
	var always := func(_h: Vector2i) -> bool: return true
	for n in range(0, 4):
		var reach := Hex.flood_reach(Vector2i(0, 0), n, always)
		assert_eq(reach.size(), Hex.within_range(Vector2i(0, 0), n).size(), "n=%d の到達数" % n)

func test_flood_includes_start() -> void:
	var none := func(_h: Vector2i) -> bool: return false
	var reach := Hex.flood_reach(Vector2i(2, -1), 3, none)
	assert_eq(reach, [Vector2i(2, -1)], "全方向ブロックでも start は含む")

func test_flood_respects_walls() -> void:
	# q == 1 の列を壁にすると、原点からは q<=0 側にしか出られない。
	var passable := func(h: Vector2i) -> bool: return h.x != 1
	var reach := Hex.flood_reach(Vector2i(0, 0), 5, passable)
	for h in reach:
		assert_ne(h.x, 1, "壁の列には入らない")
	assert_true(reach.has(Vector2i(-1, 0)), "壁の手前側へは到達できる")
