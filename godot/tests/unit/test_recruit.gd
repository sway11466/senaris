extends GutTest
## 帰属（recruited_team）＝中立ユニットを解放した側で確定し、以後は寝返らない規則。
## 仕様 → doc/gdd/map.md（帰属・出撃）

func _catalog() -> Dictionary:
	return {
		"elf": UnitType.from_dict({ "id": "elf", "atk_ground": 6, "defense": 5, "move": 5, "max_troops": 8 }),
		"cleric": UnitType.from_dict({ "id": "cleric", "atk_ground": 4, "defense": 4, "move": 4, "max_troops": 8, "can_capture": true }),
	}

## 中立拠点1つ（garrison=elf）＋自軍の占領兵1体、という最小の盤を作る。
func _stage(player_col: int = 1) -> BattleState:
	return StageLoader.build({
		"cols": 8, "rows": 4,
		"player": [{ "type": "cleric", "col": player_col, "row": 1 }],
		"bases": [{ "col": 4, "row": 1, "team": "neutral",
			"garrison": [{ "type": "elf", "actor": "t3.elf", "native": "neutral" }] }],
	}, _catalog())

func test_neutral_garrison_starts_unclaimed() -> void:
	var s := _stage()
	var gu: Unit = s.bases()[0].garrison[0]
	assert_true(gu.is_unclaimed(), "中立拠点の控えは帰属未確定")
	assert_eq(gu.native_team, Base.NEUTRAL, "native も中立")
	assert_eq(gu.actor, "t3.elf", "actor を読み込む")

func test_player_units_are_claimed_by_default() -> void:
	var s := _stage()
	var c := s.unit_by_id(1)
	assert_eq(c.recruited_team, 0, "最初から味方の駒は帰属先＝自軍（既定は native と同じ）")
	assert_false(c.is_unclaimed())

func test_deploy_fixes_allegiance_to_the_liberator() -> void:
	var s := _stage()
	var base_hex := Hex.offset_to_axial(4, 1)
	# 占領兵を拠点へ入れて占領 → 隣へ出撃させる。
	s.move_unit(1, base_hex)
	assert_eq(s.base_at(base_hex).team, 0, "占領できている")
	assert_true(s.deploy(base_hex, 0, Hex.offset_to_axial(4, 0)), "解放できる")
	var elf := s.unit_at(Hex.offset_to_axial(4, 0))
	assert_eq(elf.team, 0, "解放した側の駒になる")
	assert_eq(elf.recruited_team, 0, "帰属が自軍で確定する")
	assert_eq(elf.native_team, Base.NEUTRAL, "native は初期状態のまま動かさない")

## 自軍のターンに戻す（敵ターンを1つ挟む）。行動済みフラグが一掃される。
func _next_own_turn(s: BattleState) -> void:
	s.end_turn()
	s.end_turn()

func test_released_unit_does_not_defect_when_base_is_retaken() -> void:
	# 一度味方が解放した駒は、拠点ごと奪われても敵の戦力にならない（捕虜＝出撃できないだけ）。
	var s := _stage()
	var base_hex := Hex.offset_to_axial(4, 1)
	s.move_unit(1, base_hex)
	s.deploy(base_hex, 0, Hex.offset_to_axial(4, 0))
	var elf := s.unit_at(Hex.offset_to_axial(4, 0))
	# 解放したエルフを拠点へ入れ直す（回復のために駐留した状態）。占領兵は先に退かせる。
	_next_own_turn(s)
	assert_true(s.move_unit(1, Hex.offset_to_axial(3, 1)), "占領兵が拠点から退く")
	_next_own_turn(s)
	assert_true(s.move_unit(elf.id, base_hex), "エルフが拠点へ")
	assert_true(s.enter_base(elf.id), "拠点に入る（駐留）")
	# 敵が拠点を奪う。
	s.base_at(base_hex).team = 1
	assert_false(s.can_deploy_garrison(base_hex, 0), "敵は解放済みの駒を出撃させられない＝捕虜")
	var captive: Unit = s.base_at(base_hex).garrison[0]
	assert_eq(captive.recruited_team, 0, "帰属は自軍のまま（寝返らない）")

func test_unclaimed_garrison_can_be_taken_by_either_side() -> void:
	# まだ誰も解放していない中立の控えは、取った側が出撃させられる（争奪の本体）。
	var s := _stage()
	var base_hex := Hex.offset_to_axial(4, 1)
	s.base_at(base_hex).team = 1  # 敵が先に確保
	assert_true(s.can_deploy_garrison(base_hex, 0), "帰属未確定なら敵からでも出せる")
	s.current_team = 1
	assert_true(s.deploy(base_hex, 0, Hex.offset_to_axial(4, 0)), "敵が解放できる")
	var elf := s.unit_at(Hex.offset_to_axial(4, 0))
	assert_eq(elf.recruited_team, 1, "先に取った敵で帰属が確定する")

func test_full_dict_round_trip_keeps_allegiance_and_actor() -> void:
	var s := _stage()
	var base_hex := Hex.offset_to_axial(4, 1)
	s.move_unit(1, base_hex)
	s.deploy(base_hex, 0, Hex.offset_to_axial(4, 0))
	var elf := s.unit_at(Hex.offset_to_axial(4, 0))
	var restored := Unit.from_full_dict(elf.to_full_dict(), _catalog()["elf"])
	assert_eq(restored.recruited_team, 0, "帰属が中断セーブで保たれる")
	assert_eq(restored.native_team, Base.NEUTRAL, "native も保たれる")
	assert_eq(restored.actor, "t3.elf", "actor が保たれる")

func test_from_full_dict_without_recruited_falls_back_to_native() -> void:
	# 旧セーブ（recruited キーなし）は native と同値で復元する＝読めなくならない。
	var d := { "type": "elf", "skin": "elf", "level": 1, "troops": 8, "max_troops": 8,
		"id": 7, "team": 1, "native": 1, "q": 0, "r": 0 }
	var u := Unit.from_full_dict(d, _catalog()["elf"])
	assert_eq(u.recruited_team, 1, "native と同値で復元")
