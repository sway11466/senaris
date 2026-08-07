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

func test_capture_grants_experience() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 1))
	var u := Unit.new(1, 0, Hex.neighbor(base_hex, 0), 3)
	u.can_capture = true
	s.add_unit(u)
	assert_eq(u.level, 1, "初期Lv1")
	assert_true(s.move_unit(1, base_hex))
	assert_eq(u.level, 1 + BattleState.CAPTURE_EXPERIENCE, "占領で経験+10")

func test_entering_own_base_grants_no_experience() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))  # はじめから自軍所属
	var u := Unit.new(1, 0, Hex.neighbor(base_hex, 0), 3)
	u.can_capture = true
	s.add_unit(u)
	assert_true(s.move_unit(1, base_hex))
	assert_eq(u.level, 1, "所属が変わらなければ経験は入らない")

func test_capture_experience_clamps_at_max_level() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 1))
	var u := Unit.new(1, 0, Hex.neighbor(base_hex, 0), 3)
	u.can_capture = true
	u.level = Unit.MAX_LEVEL - 2
	s.add_unit(u)
	assert_true(s.move_unit(1, base_hex))
	assert_eq(u.level, Unit.MAX_LEVEL, "上限を超えない")

# --- 出撃（ネクタリス方式・1歩・行動完了） ---

func _captured_base_with_garrison(s: BattleState, base_hex: Vector2i, n: int) -> Base:
	var b := Base.new(base_hex, 0)  # 自軍占領済み
	for i in n:
		var g := Unit.new(100 + i, Base.NEUTRAL, Vector2i.ZERO, 3)  # 中立native＝取った側が出せる（寝返り）
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
	assert_false(s.deploy_cells(base_hex).is_empty(), "控えあり・空きありなら出撃可")
	assert_eq(s.deploy_cells(base_hex).size(), 6, "開けた拠点の周囲6マスが出撃先")

func test_deploy_skips_terrain_the_unit_cannot_enter() -> void:
	# 進入不可の地形（壁・瓦礫）は出撃先にしない＝出た瞬間に動かせない駒を作らない。
	# 冒険譚2 st4 で、瓦礫（rampart）に囲まれた拠点からゾンビが壁の上に湧いていた。
	var s := _state()
	s.set_movement({ "ground": { "plain": 1, "rampart": "x" }, "flight": { "plain": 1, "rampart": 1 } })
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := _captured_base_with_garrison(s, base_hex, 1)
	(b.garrison[0] as Unit).move_type = "ground"
	var blocked := Hex.neighbor(base_hex, 0)
	s.set_terrain(blocked, "rampart")
	assert_false(s.deploy_cells(base_hex, 0).has(blocked), "歩行は瓦礫を出撃先にしない")
	assert_false(s.deploy(base_hex, 0, blocked), "候補外なので出撃もできない")
	assert_eq(b.garrison.size(), 1, "控えは減っていない")
	assert_true(s.deploy(base_hex, 0, Hex.neighbor(base_hex, 1)), "入れる隣接マスへは出せる")

func test_deploy_allows_terrain_the_unit_can_enter() -> void:
	# 同じ地形でも、飛行なら入れる＝移動タイプごとに判定する。
	var s := _state()
	s.set_movement({ "ground": { "plain": 1, "rampart": "x" }, "flight": { "plain": 1, "rampart": 1 } })
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := _captured_base_with_garrison(s, base_hex, 1)
	(b.garrison[0] as Unit).move_type = "flight"
	var rampart := Hex.neighbor(base_hex, 0)
	s.set_terrain(rampart, "rampart")
	assert_true(s.deploy_cells(base_hex, 0).has(rampart), "飛行は瓦礫にも出せる")
	assert_true(s.deploy(base_hex, 0, rampart))

func test_capture_then_deploy_same_turn() -> void:
	# 占領した同じターンに、中の控えを出撃させられる（即解放）。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := Base.new(base_hex)  # 中立
	b.garrison.append(Unit.new(100, Base.NEUTRAL, Vector2i.ZERO, 3))  # 中立拠点の駒＝中立native（寝返る）
	s.add_base(b)
	var u := Unit.new(1, 0, Hex.neighbor(base_hex, 0), 3)
	u.can_capture = true
	s.add_unit(u)
	assert_true(s.move_unit(1, base_hex), "占領兵が拠点へ進入")
	assert_eq(b.team, 0, "進入で即占領")
	# 同ターンに出撃（拠点に乗った占領兵の隣の空きへ）
	var to := Hex.neighbor(base_hex, 2)
	assert_false(s.deploy_cells(base_hex).is_empty(), "占領した同じターンに出撃できる")
	assert_true(s.deploy(base_hex, 0, to), "控えを隣接へ出撃")
	assert_eq(s.unit_at(to).team, 0, "出た駒は自軍")
	assert_eq(b.garrison.size(), 0, "garrison が減る")

func test_empty_base_capture_is_noop() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))  # garrison 空・自軍所属
	assert_true(s.deploy_cells(base_hex).is_empty(), "空の拠点からは出撃できない（出す駒が無い）")
	assert_eq(s.deploy_cells(base_hex).size(), 0)

# --- 回復（休憩＝拠点の中に入るモデル） ---

func test_enter_own_base_and_heal() -> void:
	# 自軍拠点に「入る」＝garrison になり盤上から消える。ターン開始で満員へ回復（経験Lvは据え置き）。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))
	var u := Unit.new(1, 0, base_hex, 3, 8, 10, 10)
	u.troops = 3
	u.level = 4
	s.add_unit(u)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(6, 6), 3))  # 盤上最後の1体にならないよう相棒
	assert_true(s.enter_base(1), "自軍拠点の上から中に入れる")
	assert_null(s.unit_by_id(1), "駐留中は盤上に居ない")
	assert_eq(s.base_at(base_hex).garrison.size(), 1, "garrison に載る")
	s.end_turn()
	s.end_turn()  # 自軍ターン開始 → 駐留駒が回復
	var healed: Unit = s.base_at(base_hex).garrison[0]
	assert_eq(healed.troops, 8, "駐留中はターン開始時に満員へ回復")
	assert_eq(healed.level, 4, "経験Lvは据え置き")

func test_standing_on_base_no_longer_heals() -> void:
	# 旧モデル（hexの上に立つと回復）は廃止＝中に入らない限り回復しない。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 1))
	var u := Unit.new(1, 1, base_hex, 3); u.troops = 3
	s.add_unit(u)
	s.end_turn()  # team1 ターン開始
	assert_eq(s.unit_by_id(1).troops, 3, "上に立っているだけでは回復しない（中に入るモデル）")

func test_cannot_enter_enemy_base_or_off_base() -> void:
	var s := _state()
	s.add_base(Base.new(Hex.offset_to_axial(4, 4), 1))  # 敵所属
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(4, 4), 3))
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(6, 6), 3))  # 拠点でないマス
	assert_false(s.enter_base(1), "敵所属の拠点には入れない")
	assert_false(s.enter_base(2), "拠点の無いマスでは入れない")

func test_last_unit_can_enter_if_reinforcement() -> void:
	# 案B: 盤上最後の1体でも、入った直後に復帰手段が残る（拠点に空き隣接がある）なら入れる。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))
	s.add_unit(Unit.new(1, 0, base_hex, 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))  # 敵は盤上に健在
	assert_true(s.can_enter_base(1), "最後の1体でも復帰余地があれば入れる")
	assert_true(s.enter_base(1), "実際に入れる")
	assert_false(s.is_over(), "盤上0でも復帰手段が残るので敗北にならない")

func test_last_unit_cannot_enter_when_blockaded() -> void:
	# 案B: 入ると即「盤上0かつ復帰なし」になる場合は入れない（即敗北の footgun 防止）。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))
	s.add_unit(Unit.new(1, 0, base_hex, 3))
	for i in 6:
		s.add_unit(Unit.new(100 + i, 1, Hex.neighbor(base_hex, i), 3))  # 全周を敵で封鎖
	assert_false(s.can_enter_base(1), "全周封鎖では最後の1体は入れない（入れば即敗北）")
	assert_false(s.enter_base(1), "enter_base も拒否される")

func test_no_heal_in_captured_enemy_native_base() -> void:
	# 奪った敵 native の拠点は出撃拠点にはなるが回復しない。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := Base.new(base_hex, 1)  # 敵 native
	s.add_base(b)
	b.team = 0  # 自軍が占領済み
	var u := Unit.new(1, 0, base_hex, 3); u.troops = 3
	s.add_unit(u)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(6, 6), 3))
	assert_true(s.enter_base(1), "奪った拠点にも入れる")
	s.end_turn()
	s.end_turn()
	assert_eq(b.garrison[0].troops, 3, "敵 native の拠点では回復しない")

# --- native（生来の陣営）と出撃・閉じ込め ---

func test_locked_garrison_cannot_deploy() -> void:
	# 敵 native の garrison は、自軍が拠点を奪っても出撃させられない（閉じ込め）。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := Base.new(base_hex, 1)  # 敵拠点
	var goblin := Unit.new(10, 1, Vector2i.ZERO, 3)  # native=1（敵）
	b.garrison.append(goblin)
	s.add_base(b)
	b.team = 0  # 自軍が奪った
	s.current_team = 0
	assert_false(s.can_deploy_garrison(base_hex, 0), "敵 native は出撃不可＝閉じ込め")
	assert_false(s.deploy(base_hex, 0, Hex.neighbor(base_hex, 0)), "deploy も拒否される")
	b.team = 1  # 敵が奪還
	assert_true(s.can_deploy_garrison(base_hex, 0), "奪還されれば再び出撃できる（眠っていた敵が復活）")

func test_neutral_garrison_defects_to_captor() -> void:
	# 中立 native の garrison は占領した側に寝返る（出撃で所属が変わる）。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := Base.new(base_hex, Base.NEUTRAL)  # 中立拠点
	var villager := Unit.new(10, Base.NEUTRAL, Vector2i.ZERO, 3)
	villager.set_native_team(Base.NEUTRAL)
	b.garrison.append(villager)
	s.add_base(b)
	b.team = 0  # 自軍が占領
	s.current_team = 0
	assert_true(s.can_deploy_garrison(base_hex, 0), "帰属未確定なら取った側が出せる")
	assert_true(s.deploy(base_hex, 0, Hex.neighbor(base_hex, 0)))
	assert_eq(s.unit_by_id(10).team, 0, "出撃で自軍に寝返る")
	assert_eq(s.unit_by_id(10).native_team, Base.NEUTRAL, "native は不変")
	assert_eq(s.unit_by_id(10).recruited_team, 0, "帰属が自軍で確定する")

func test_entered_unit_cannot_deploy_same_turn() -> void:
	# 「入る」で収容した駒は、そのターン出撃させられない＝入って出るの往復を作らない。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))
	var u := Unit.new(1, 0, base_hex, 3)
	s.add_unit(u)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(6, 6), 3))  # 盤上最後の1体にならないよう相棒
	assert_true(s.enter_base(1), "自軍拠点の中に入れる")
	assert_false(s.can_deploy_garrison(base_hex, 0), "入ったターンは出せない")
	var out_hex := Hex.neighbor(base_hex, 0)
	assert_false(s.deploy(base_hex, 0, out_hex), "出撃コマンド自体も通らない")
	s.end_turn()
	s.end_turn()  # 次の自軍ターン
	assert_true(s.can_deploy_garrison(base_hex, 0), "次の自軍ターンからは出せる")
	assert_true(s.deploy(base_hex, 0, out_hex), "出撃できる")

func test_initial_garrison_can_deploy_on_first_turn() -> void:
	# 初期配置の控えは「入った」わけではない＝1ターン目から出せる（新ルールの巻き添えにしない）。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := Base.new(base_hex, 0)
	b.garrison.append(Unit.new(9, 0, base_hex, 3))
	s.add_base(b)
	assert_true(s.can_deploy_garrison(base_hex, 0), "初期配置の控えは初手から出せる")

func test_entering_marks_the_unit_done() -> void:
	# 「入る」も1手＝行動終了。この扱いが、そのターンの出撃を止める根拠になっている。
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))
	s.add_unit(Unit.new(1, 0, base_hex, 3))
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(6, 6), 3))
	assert_true(s.enter_base(1), "自軍拠点の中に入れる")
	assert_true(s.is_done(1), "入った駒はそのターン行動終了")
