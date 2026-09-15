extends GutTest
## BattleState の視線（索敵の遮蔽・減衰）テスト。詳細 → doc/gdd/movement.md（視線）, doc/gdd/ai.md（起動）
## visible_hexes＝範囲内の各マスへ引いた直線上で、累積視線コストが budget 以内のマス全部（検知域）。
## sight_reaches＝to がその検知域に入っているか。全地形1なら距離判定に一致。

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

func test_grazing_wall_corner_has_no_hole() -> void:
	# 壁の角をかすめる位置が「1マスだけ穴」にならない（±両側判定の回帰）。真後ろの遮断は維持。
	var s := _state(13, 11)
	for row in range(2, 7):  # col8 rows2-6 を壁に
		s.set_terrain(Hex.offset_to_axial(8, row), "wall")
	var g := Hex.offset_to_axial(6, 4)
	assert_true(s.sight_reaches(g, Hex.offset_to_axial(8, 1), 5), "壁の角の上(8,1)は見える（穴でない）")
	assert_true(s.sight_reaches(g, Hex.offset_to_axial(8, 0), 5), "その先(8,0)も見える")
	assert_false(s.sight_reaches(g, Hex.offset_to_axial(9, 4), 9), "壁の真後ろは遮断のまま")

func test_visible_hexes_within_board_only() -> void:
	var s := _state(3, 3)
	var vis := s.visible_hexes(Vector2i(0, 0), 5)
	for h in vis:
		assert_true(s.in_field(h), "盤外は含めない")

# --- Sight ヘルパー（BattleState.sight_reaches の実体） ---

func test_sight_helper_matches_state_query() -> void:
	# state 側は委譲の薄い口＝どちらから聞いても同じ答えになる。表は state が持ち続ける。
	var s := _state(8, 4)
	s.set_terrain(Vector2i(1, 0), "forest")
	assert_eq(Sight.reaches(s, Vector2i(0, 0), Vector2i(2, 0), 3),
		s.sight_reaches(Vector2i(0, 0), Vector2i(2, 0), 3), "森ごし・届く側で一致")
	assert_eq(Sight.reaches(s, Vector2i(0, 0), Vector2i(2, 0), 2),
		s.sight_reaches(Vector2i(0, 0), Vector2i(2, 0), 2), "届かない側でも一致")
	assert_eq(Sight.visible_hexes(s, Vector2i(0, 0), 3).size(),
		s.visible_hexes(Vector2i(0, 0), 3).size(), "可視集合も一致")

func test_sight_helper_reads_injected_cost_table() -> void:
	# 表を差し替えると規則側の答えも変わる＝Sight は state の表を読んでいる（焼き込んでいない）。
	var s := BattleState.new(8, 4)
	s.set_terrain(Vector2i(1, 0), "forest")
	assert_true(Sight.reaches(s, Vector2i(0, 0), Vector2i(2, 0), 2), "表なし＝全地形1＝距離2で届く")
	s.set_sight_cost(COST)
	assert_false(Sight.reaches(s, Vector2i(0, 0), Vector2i(2, 0), 2), "森(2)を注入すると同じ経路で届かない")

func test_visible_hexes_is_bounded_by_the_board() -> void:
	# sight `*`（上限なし）の予算は盤より桁違いに大きい。候補の輪を盤の広さで頭打ちにしないと
	# 盤外を億単位で走査して固まる。結果は「盤内の見えるマス」だけなので変わらない。
	var s := _state(6, 4)
	s.set_terrain(Vector2i(2, 0), "wall")
	var huge := s.visible_hexes(Vector2i(0, 0), TraitBrain.SIGHT_UNLIMITED)
	for h in huge:
		assert_true(s.in_field(h), "盤外は含めない")
	assert_lt(huge.size(), 6 * 4 + 1, "壁の影のぶんだけ盤の全マスより少ない")
	assert_false(huge.has(Vector2i(3, 0)), "壁の裏は上限なしでも見えない")

# --- 検知域はひと続き（線の途中のマスも見える） ---

func test_hex_on_a_seen_line_is_seen() -> void:
	# 奥のマスへの線が通っている途中のマスは、自分宛ての線が壁に当たっていても見える（飛び地の回帰）。
	# 竜狩り st3 で出た実例: (11,14) の見張りから (5,9) への線は (6,11)→(6,10)→(5,9) と抜けるが、
	# (6,10) 宛ての線は角度が少し違い (7,10) を通る。(7,10) が壁だと、マスごとの判定では (6,10) だけ見えず飛び地になった。
	var s := _state(13, 16)
	s.set_terrain(Hex.offset_to_axial(7, 10), "wall")
	var vis := s.visible_hexes(Hex.offset_to_axial(11, 14), 9)
	assert_true(vis.has(Hex.offset_to_axial(5, 9)), "奥の (5,9) は見える")
	assert_true(vis.has(Hex.offset_to_axial(6, 10)), "その線の途中 (6,10) も見える")
	assert_false(vis.has(Hex.offset_to_axial(7, 10)), "壁自身は見えない")

func test_visible_hexes_is_connected() -> void:
	# 検知域は見張りからひと続き＝見えるマスは全部、見えるマスだけを隣にたどって見張りへ戻れる。
	var s := _state(13, 16)
	for o in [Vector2i(7, 10), Vector2i(8, 12), Vector2i(9, 9), Vector2i(6, 13), Vector2i(10, 11), Vector2i(12, 9)]:
		s.set_terrain(Hex.offset_to_axial(o.x, o.y), "wall")
	var g := Hex.offset_to_axial(11, 14)
	var vis := s.visible_hexes(g, 9)
	var linked := Hex.flood_reach(g, 99, func(h: Vector2i) -> bool: return vis.has(h))
	assert_eq(linked.size(), vis.size(), "見えるマスは全部つながっている")

func test_shadow_directly_behind_wall_stays_hidden() -> void:
	# 線の途中を拾うようにしても、壁の真後ろは見えない＝真後ろへ向かうどの線も壁を通る。
	var s := _state(8, 4)
	s.set_terrain(Vector2i(1, 0), "wall")
	var vis := s.visible_hexes(Vector2i(0, 0), 6)
	assert_false(vis.has(Vector2i(2, 0)), "壁の真後ろ")
	assert_false(vis.has(Vector2i(3, 0)), "その先も")

# --- 位置ごとの記憶（地形・視線コスト表が変わるまで有効） ---

func test_visible_hexes_is_remembered_per_position() -> void:
	var s := _state(8, 4)
	var first := s.visible_hexes(Vector2i(0, 0), 4)
	assert_true(is_same(first, s.visible_hexes(Vector2i(0, 0), 4)), "同じ位置・同じ sight は同じ辞書を返す")
	assert_false(is_same(first, s.visible_hexes(Vector2i(0, 0), 3)), "sight が違えば別の集合")
	assert_false(is_same(first, s.visible_hexes(Vector2i(1, 0), 4)), "位置が違えば別の集合")

func test_remembered_sight_is_dropped_when_terrain_changes() -> void:
	var s := _state(8, 4)
	assert_true(s.visible_hexes(Vector2i(0, 0), 4).has(Vector2i(3, 0)), "壁が無ければ (3,0) は見える")
	s.set_terrain(Vector2i(2, 0), "wall")
	assert_false(s.visible_hexes(Vector2i(0, 0), 4).has(Vector2i(3, 0)), "壁を置くと記憶を捨てて見えなくなる")
	s.set_sight_cost({})
	assert_true(s.visible_hexes(Vector2i(0, 0), 4).has(Vector2i(3, 0)), "表を差し替えると記憶を捨てる（表なし＝壁もコスト1）")
