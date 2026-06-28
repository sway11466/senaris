extends GutTest
## 拠点（占領・出撃・回復）のテスト。詳細 → doc/gdd/map.md（拠点・占領）

func _state() -> BattleState:
	return BattleState.new(8, 8)

# --- 占領（即時） ---

func test_capture_unit_taking_enemy_base() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 1))  # 敵所属の拠点
	var start := Hex.neighbor(base_hex, 0)
	var u := Unit.new(1, 0, start, 3)
	u.can_capture = true
	s.add_unit(u)
	assert_true(s.move_unit(1, base_hex), "拠点hexへ移動できる")
	assert_eq(s.base_at(base_hex).team, 0, "占領可ユニットが入ると即・自軍所属に")

func test_non_capture_unit_does_not_capture() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 1))
	var u := Unit.new(1, 0, Hex.neighbor(base_hex, 0), 3)  # can_capture=false（既定）
	s.add_unit(u)
	assert_true(s.move_unit(1, base_hex))
	assert_eq(s.base_at(base_hex).team, 1, "占領不可ユニットでは所属は変わらない")

func test_capture_neutral_base() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex))  # 既定＝中立(NEUTRAL)
	assert_eq(s.base_at(base_hex).team, Base.NEUTRAL)
	var u := Unit.new(1, 0, Hex.neighbor(base_hex, 0), 3)
	u.can_capture = true
	s.add_unit(u)
	assert_true(s.move_unit(1, base_hex))
	assert_eq(s.base_at(base_hex).team, 0, "中立拠点は占領可ユニットで自軍化")

# --- 出撃（ネクタリス方式・1歩・行動完了） ---

func _captured_base_with_garrison(s: BattleState, base_hex: Vector2i, n: int) -> Base:
	var b := Base.new(base_hex, 0)  # 自軍占領済み
	for i in n:
		var g := Unit.new(100 + i, 1, Vector2i.ZERO, 3)  # team はダミー（出撃時に上書き）
		b.garrison.append(g)
	s.add_base(b)
	return b

func test_deploy_places_unit_and_marks_done() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := _captured_base_with_garrison(s, base_hex, 2)
	var to := Hex.neighbor(base_hex, 0)
	assert_true(s.deploy(base_hex, 0, to), "隣接空きhexへ出撃成功")
	var u := s.unit_at(to)
	assert_not_null(u, "出撃先に駒が出る")
	assert_eq(u.team, 0, "出撃した駒は占領陣営につく")
	assert_eq(b.garrison.size(), 1, "garrison から1体減る")
	assert_true(s.is_done(u.id), "出撃した駒はそのターン行動完了（1歩のみ）")
	assert_false(s.can_still_move(u.id), "これ以上移動できない")

func test_deploy_only_one_step_out() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	_captured_base_with_garrison(s, base_hex, 1)
	var far := base_hex + Vector2i(2, 0)  # 距離2（隣接でない）
	assert_false(s.deploy(base_hex, 0, far), "2歩先へは出撃できない（出口は1歩）")

func test_deploy_fails_on_occupied_or_unowned() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	_captured_base_with_garrison(s, base_hex, 1)
	var to := Hex.neighbor(base_hex, 0)
	s.add_unit(Unit.new(1, 0, to, 3))  # 出撃先が埋まっている
	assert_false(s.deploy(base_hex, 0, to), "占有マスへは出撃不可")
	# 敵所属の拠点からは出撃できない
	var enemy_base := Hex.offset_to_axial(1, 1)
	var eb := Base.new(enemy_base, 1)
	eb.garrison.append(Unit.new(200, 1, Vector2i.ZERO, 3))
	s.add_base(eb)
	assert_false(s.deploy(enemy_base, 0, Hex.neighbor(enemy_base, 0)), "自軍所属でない拠点からは出撃不可")

func test_deploy_cells_and_can_deploy() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	_captured_base_with_garrison(s, base_hex, 1)
	assert_true(s.can_deploy(base_hex), "控えあり・空きありなら出撃可")
	assert_eq(s.deploy_cells(base_hex).size(), 6, "開けた拠点の周囲6マスが出撃先")

func test_empty_base_capture_is_noop() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))  # garrison 空・自軍所属
	assert_false(s.can_deploy(base_hex), "空の拠点からは出撃できない（出す駒が無い）")
	assert_eq(s.deploy_cells(base_hex).size(), 0)

# --- 回復（休憩） ---

func test_heal_on_own_base_at_turn_start() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 1))  # 敵所属の拠点
	var u := Unit.new(1, 1, base_hex, 3, 8, 10, 10)  # 兵数8満員
	u.troops = 3  # 損耗
	s.add_unit(u)
	# current_team=0 → end_turn で team1 の手番開始 → team1 拠点上の team1 ユニットが回復
	s.end_turn()
	assert_eq(s.current_team, 1)
	assert_eq(s.unit_by_id(1).troops, 8, "自軍拠点に乗っていれば手番開始時に満員へ回復")

func test_no_heal_off_base_or_enemy_base() -> void:
	var s := _state()
	var own_base := Hex.offset_to_axial(4, 4)
	var enemy_base := Hex.offset_to_axial(2, 2)
	s.add_base(Base.new(own_base, 1))
	s.add_base(Base.new(enemy_base, 0))  # team1 から見て敵の拠点
	var off := Unit.new(1, 1, Hex.offset_to_axial(6, 6), 3); off.troops = 2
	var on_enemy := Unit.new(2, 1, enemy_base, 3); on_enemy.troops = 2
	s.add_unit(off)
	s.add_unit(on_enemy)
	s.end_turn()  # team1 手番開始
	assert_eq(s.unit_by_id(1).troops, 2, "拠点に乗っていなければ回復しない")
	assert_eq(s.unit_by_id(2).troops, 2, "敵所属の拠点では回復しない")
