extends GutTest
## 敵AIが標的をどう測るかのテスト＝攻撃可能なマスの集合と、そこまでの3つの距離
## （移動距離・地形距離・迂回距離）。詳細 → doc/gdd/ai.md（用語 > 距離）
##
## 移動そのもののルール（reachable・ZOC停止・地形コスト）は test_movement.gd の受け持ち。
## ここは「測れる／測れない」と、どのマスを数えるかだけを見る。

const PLAIN_FENCE := { "ground": { "plain": 1, "fence": 3 }, "flight": { "plain": 1, "fence": 1 } }
const PLAIN_WALL := { "ground": { "plain": 1, "wall": "x" } }

func _melee(id: int, team: int, pos: Vector2i, move := 3) -> Unit:
	var u := Unit.new(id, team, pos, move)
	u.move_type = "ground"
	return u

func _archer(id: int, team: int, pos: Vector2i, min_range := 2, max_range := 2) -> Unit:
	var u := _melee(id, team, pos)
	u.min_range = min_range
	u.attack_range = max_range
	return u

func _flyer(id: int, team: int, pos: Vector2i) -> Unit:
	var u := Unit.new(id, team, pos, 3)
	u.move_type = "flight"  # 飛行判定は move_type で行う
	u.atk_air = 10
	return u

# --- 攻撃可能なマスの集合 ---

func test_attack_cells_are_the_neighbors_for_melee() -> void:
	# 近接（射程1）＝標的の隣接6マス。標的自身のマスは射程の下限(min_range=1)で外れる。
	var s := BattleState.new(8, 8)
	var tp := Hex.offset_to_axial(4, 4)
	s.add_unit(_melee(1, 0, Hex.offset_to_axial(1, 4)))
	s.add_unit(_melee(2, 1, tp))
	var cells := s.attack_cells(1, 2)
	assert_eq(cells.size(), 6, "隣接6マス")
	assert_false(cells.has(tp), "標的のマス自身は入らない")
	for nb in Hex.neighbors(tp):
		assert_true(cells.has(nb), "隣接マスが入る")

func test_attack_cells_respect_min_range() -> void:
	# 射程2〜2の砲兵＝距離2のリングだけ。懐（距離1）は死角なので入らない。
	var s := BattleState.new(9, 9)
	var tp := Hex.offset_to_axial(4, 4)
	s.add_unit(_archer(1, 0, Hex.offset_to_axial(1, 4)))
	s.add_unit(_melee(2, 1, tp))
	var cells := s.attack_cells(1, 2)
	assert_false(cells.is_empty(), "距離2のマスがある")
	for hex in cells:
		assert_eq(Hex.distance(hex, tp), 2, "距離2のマスだけ")

func test_attack_cells_stay_in_field() -> void:
	# 盤の縁の標的では、盤外に出るマスは数えない（そこには立てない）。
	var s := BattleState.new(8, 8)
	var tp := Hex.offset_to_axial(0, 0)
	s.add_unit(_melee(1, 0, Hex.offset_to_axial(4, 4)))
	s.add_unit(_melee(2, 1, tp))
	var cells := s.attack_cells(1, 2)
	assert_lt(cells.size(), 6, "盤外へはみ出すぶんは落ちる")
	for hex in cells:
		assert_true(s.in_field(hex), "盤内のマスだけ")

func test_attack_cells_empty_without_antiair() -> void:
	# 対空攻撃力が無い駒にとって、飛行の標的は攻撃可能なマスを1つも持たない＝距離が測れない。
	var s := BattleState.new(8, 8)
	s.set_movement(PLAIN_FENCE)
	var ground := _melee(1, 0, Hex.offset_to_axial(1, 4))
	ground.atk_air = 0
	s.add_unit(ground)
	s.add_unit(_flyer(2, 1, Hex.offset_to_axial(4, 4)))
	assert_true(s.attack_cells(1, 2).is_empty(), "対空0は飛行を狙えない")
	assert_eq(s.move_distance(1, s.attack_cells(1, 2)), BattleState.UNREACHABLE,
		"攻撃可能なマスが無い＝移動距離も測れない")

func test_attack_cells_present_with_antiair() -> void:
	# 対空攻撃力があれば同じ配置で測れる（対照）。
	var s := BattleState.new(8, 8)
	s.set_movement(PLAIN_FENCE)
	var aa := _melee(1, 0, Hex.offset_to_axial(1, 4))
	aa.atk_air = 25
	s.add_unit(aa)
	s.add_unit(_flyer(2, 1, Hex.offset_to_axial(4, 4)))
	assert_eq(s.attack_cells(1, 2).size(), 6, "対空ありなら隣接6マス")
	assert_lt(s.move_distance(1, s.attack_cells(1, 2)), BattleState.UNREACHABLE, "距離が測れる")

func test_attack_cells_ignore_turn_state() -> void:
	# 距離は盤の形の話＝手番でない駒・攻撃済みの駒でも測れる。
	# （AIは自分の手番の前に敵味方どちらの駒からも距離を読む）
	var s := BattleState.new(8, 8)
	s.current_team = 0
	s.add_unit(_melee(1, 1, Hex.offset_to_axial(1, 4)))  # 手番でない陣営の駒
	s.add_unit(_melee(2, 0, Hex.offset_to_axial(4, 4)))
	assert_false(s.can_attack(1, 2), "手番でないので攻撃はできない（対照）")
	assert_eq(s.attack_cells(1, 2).size(), 6, "それでも攻撃可能なマスは数えられる")

func test_attack_cells_ignore_occupancy_and_terrain() -> void:
	# 空きも地形も見ない。駒で埋まったマスは移動距離の側で壁として落ち、
	# 地形距離では逆に数える（駒を壁にしない）。ここで絞ると2つの距離の使い分けが潰れる。
	var s := BattleState.new(8, 8)
	s.set_movement(PLAIN_WALL)
	var tp := Hex.offset_to_axial(4, 4)
	var occupied := Hex.neighbor(tp, 0)
	var walled := Hex.neighbor(tp, 3)
	s.set_terrain(walled, "wall")
	s.add_unit(_melee(1, 0, Hex.offset_to_axial(1, 4)))
	s.add_unit(_melee(2, 1, tp))
	s.add_unit(_melee(3, 1, occupied))
	var cells := s.attack_cells(1, 2)
	assert_true(cells.has(occupied), "駒がいるマスも集合には入る")
	assert_true(cells.has(walled), "進入不可の地形も集合には入る")

# --- 移動距離 ---

func test_move_distance_measures_to_the_attack_cell() -> void:
	# 開けた盤＝標的の手前まで＝盤上距離-1（隣に立てば攻撃できる）。
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 2)
	var tp := Hex.offset_to_axial(6, 2)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	assert_eq(s.move_distance(1, s.attack_cells(1, 2)), Hex.distance(from, tp) - 1,
		"隣まで歩くぶんの地形コスト")

func test_move_distance_blocked_by_pieces_but_terrain_distance_measures() -> void:
	# 駒で道が塞がれると移動距離は測れない。地形距離は駒を壁にしないので測れる
	# （塞いでいる駒はいずれ動くので、地形の上で最短になる位置へ詰めておく＝見込前進）。
	var s := BattleState.new(9, 3)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 1)
	var tp := Hex.offset_to_axial(6, 1)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	for row in 3:  # 3列目を駒で塞ぐ（味方2体・敵1体）
		s.add_unit(_melee(20 + row, 1 if row == 1 else 0, Hex.offset_to_axial(3, row)))
	var cells := s.attack_cells(1, 2)
	assert_eq(s.move_distance(1, cells), BattleState.UNREACHABLE, "駒の壁で道が無い")
	assert_eq(s.terrain_distance(1, cells), Hex.distance(from, tp) - 1, "地形だけなら測れる")

func test_move_distance_unreachable_when_target_is_walled_in() -> void:
	# 攻撃可能なマスが全部進入不可の地形＝標的の隣に立てない＝測れない。
	# 地形距離も同じく測れない（地形は駒と違ってどかない）。
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_WALL)
	var tp := Hex.offset_to_axial(6, 2)
	for nb in Hex.neighbors(tp):
		s.set_terrain(nb, "wall")
	s.add_unit(_melee(1, 0, Hex.offset_to_axial(1, 2)))
	s.add_unit(_melee(2, 1, tp))
	var cells := s.attack_cells(1, 2)
	assert_eq(s.move_distance(1, cells), BattleState.UNREACHABLE, "隣に立てない")
	assert_eq(s.terrain_distance(1, cells), BattleState.UNREACHABLE, "地形距離も測れない")

## 3列目を柵で塞いだ盤（南に隙間1）。行動ユニットの移動力だけを変えて比べるための素。
func _fence_state(move: int) -> BattleState:
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_FENCE)
	for row in 4:
		s.set_terrain(Hex.offset_to_axial(3, row), "fence")
	s.add_unit(_melee(1, 0, Hex.offset_to_axial(1, 1), move))
	s.add_unit(_melee(2, 1, Hex.offset_to_axial(5, 1)))
	return s

func test_move_distance_excludes_steps_costlier_than_move() -> void:
	# 1マスの進入コストが移動力を超えるマスは、何ターンかけても入れない＝その駒には壁。
	# 柵＝コスト3は移動2の駒だけを締め出す。詳細 → doc/gdd/ai.md（用語 > 距離）
	var slow := _fence_state(2)
	var fast := _fence_state(3)
	var slow_d := slow.move_distance(1, slow.attack_cells(1, 2))
	var fast_d := fast.move_distance(1, fast.attack_cells(1, 2))
	assert_gt(slow_d, fast_d, "移動2の駒は柵を通れない＝迂回のぶん遠い")
	assert_lt(slow_d, BattleState.UNREACHABLE, "南の隙間から回れるので測れはする")

func test_distance_to_a_base_hex() -> void:
	# 拠点は攻撃の標的ではない＝拠点hexそのものまでを測る（raid が使う形）。
	# 同じ距離の口に、攻撃可能なマスの代わりに拠点hexを渡す。
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 2)
	var base_hex := Hex.offset_to_axial(5, 2)
	s.add_unit(_melee(1, 0, from))
	var cells: Array[Vector2i] = [base_hex]
	assert_eq(s.move_distance(1, cells), Hex.distance(from, base_hex), "拠点hexまで")

# --- 迂回距離 ---

func test_detour_distance_avoids_enemy_zoc() -> void:
	# 壁を2か所だけ開けた盤。近い抜け道(4,1)は敵のZOCが覆っているので、迂回は遠い抜け道(4,6)へ回る。
	# ZOCは踏んでも通れる（そこで移動が終わるだけ）ので、移動距離のほうは近い抜け道を通る。
	var s := BattleState.new(9, 7)
	s.set_movement(PLAIN_WALL)
	for row in [0, 2, 3, 4, 5]:  # 4列目を塞ぐ（抜け道は row 1 と row 6）
		s.set_terrain(Hex.offset_to_axial(4, row), "wall")
	var from := Hex.offset_to_axial(1, 0)
	var tp := Hex.offset_to_axial(7, 0)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	s.add_unit(_melee(3, 1, Hex.offset_to_axial(3, 1)))  # 近い抜け道の脇に立つ別の敵
	var cells := s.attack_cells(1, 2)
	var straight := s.move_distance(1, cells)
	var detour := s.detour_distance(1, cells, 2)
	assert_lt(straight, BattleState.UNREACHABLE, "素の移動距離は近い抜け道を通る（対照）")
	assert_lt(detour, BattleState.UNREACHABLE, "遠い抜け道があるので測れる")
	assert_gt(detour, straight, "ZOCの帯を避けるぶん遠い")

func test_detour_distance_keeps_the_targets_own_zoc() -> void:
	# 標的自身のZOCは除外しない。除外すると標的の隣へ入れず、必ず測れなくなる。
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 2)
	var tp := Hex.offset_to_axial(5, 2)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	var cells := s.attack_cells(1, 2)
	assert_eq(s.detour_distance(1, cells, 2), s.move_distance(1, cells),
		"他に敵がいなければ移動距離と同じ＝標的の隣までは入れる")
	assert_eq(s.detour_distance(1, cells), BattleState.UNREACHABLE,
		"標的のZOCまで避けると隣に入れない（除外しない理由）")

func test_detour_distance_unreachable_when_zoc_seals_the_gap() -> void:
	# 敵のZOCで通路が塞がれると迂回距離は測れない。移動距離は測れる（ZOCは通り抜けられる）。
	var s := BattleState.new(7, 3)
	s.set_movement(PLAIN_WALL)
	var from := Hex.offset_to_axial(0, 1)
	var tp := Hex.offset_to_axial(6, 1)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	s.add_unit(_melee(3, 1, Hex.offset_to_axial(3, 1)))  # 盤の高さ3＝この駒のZOCが盤を横切る
	var cells := s.attack_cells(1, 2)
	assert_lt(s.move_distance(1, cells), BattleState.UNREACHABLE, "移動距離は測れる")
	assert_eq(s.detour_distance(1, cells, 2), BattleState.UNREACHABLE, "ZOCの帯で道が消える")

func test_detour_distance_measurable_from_inside_zoc() -> void:
	# すでに敵ZOC内に立っている駒でも測れる＝行動ユニットが今いるマスは避ける対象にしない。
	# 起点から流すときと標的から流すときで値が食い違わないよう、両方向で同じ扱いにする。
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 2)
	var tp := Hex.offset_to_axial(6, 2)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	s.add_unit(_melee(3, 1, Hex.neighbor(from, 0)))  # 起点に隣接する別の敵
	assert_lt(s.detour_distance(1, s.attack_cells(1, 2), 2), BattleState.UNREACHABLE,
		"起点から流す＝ZOC内から歩き出せる")
	assert_true(s.detour_cost_field(1, tp, 2).has(from), "標的から流す＝自分のマスまで届く")

# --- 表（どちらから流すか） ---

func test_cost_fields_agree_in_both_directions() -> void:
	# 標的選び＝行動ユニットから流して攻撃可能なマスを読む。
	# 前進＝標的から流して移動範囲の各マスを読む。向きが違うだけで同じ規則＝値も噛み合う。
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 2)
	var tp := Hex.offset_to_axial(6, 2)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	var cells := s.attack_cells(1, 2)
	var mine := s.move_cost_field(1, from)
	var theirs := s.move_cost_field(1, tp)
	assert_eq(s.min_cost_in(mine, cells), s.min_cost_in(theirs, [from]) - 1,
		"標的から流した表で自分のマスを読むと、隣まで＋1マスぶん")
	assert_true(theirs.has(from), "標的から流した表に自分のマスが載る（自分は壁にしない）")

func test_terrain_cost_field_ignores_pieces_in_both_directions() -> void:
	# 地形距離の表は駒を壁にしない＝どちらから流しても同じ値になる（対称）。
	var s := BattleState.new(9, 3)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 1)
	var tp := Hex.offset_to_axial(6, 1)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	s.add_unit(_melee(3, 0, Hex.offset_to_axial(3, 1)))  # 間を塞ぐ味方
	assert_eq(int(s.terrain_cost_field(1, from)[tp]), int(s.terrain_cost_field(1, tp)[from]),
		"駒を数えないので向きによらず同じ")

func test_detour_cost_field_from_the_target() -> void:
	# 回り込み（前進）は標的から流した迂回の表を使う。標的自身のZOCを外す指定は同じ口で効く。
	var s := BattleState.new(9, 5)
	s.set_movement(PLAIN_FENCE)
	var from := Hex.offset_to_axial(1, 2)
	var tp := Hex.offset_to_axial(6, 2)
	s.add_unit(_melee(1, 0, from))
	s.add_unit(_melee(2, 1, tp))
	var field := s.detour_cost_field(1, tp, 2)
	for nb in Hex.neighbors(tp):
		assert_true(field.has(nb), "標的の隣は載る（標的のZOCは避けない）")
	assert_eq(int(field[from]), s.detour_distance(1, s.attack_cells(1, 2), 2) + 1,
		"標的から流した表で自分のマスを読むと、隣まで＋1マスぶん")

func test_cost_fields_are_empty_for_unknown_unit() -> void:
	# 居ない駒を渡したら空表・測れない（AIが撃破直後のIDを掴んでも落ちない）。
	var s := BattleState.new(5, 5)
	assert_true(s.move_cost_field(99, Hex.offset_to_axial(1, 1)).is_empty(), "移動の表は空")
	assert_true(s.terrain_cost_field(99, Hex.offset_to_axial(1, 1)).is_empty(), "地形の表は空")
	assert_true(s.detour_cost_field(99, Hex.offset_to_axial(1, 1)).is_empty(), "迂回の表は空")
	assert_eq(s.move_distance(99, [Hex.offset_to_axial(1, 1)]), BattleState.UNREACHABLE, "測れない")
	assert_true(s.attack_cells(99, 98).is_empty(), "攻撃可能なマスも空")
