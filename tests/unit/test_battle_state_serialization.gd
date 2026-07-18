extends GutTest
## BattleState の中断セーブ直列化（to_dict/from_dict）ラウンドトリップテスト。詳細 → doc/tech/gamesystem.md
## 実際のセーブと同じく JSON を通す＝数値の float 化・キーの文字列化まで含めて状態が保たれることを固定する。

func _cat() -> Dictionary:
	return {
		"archer": UnitType.from_dict({ "id": "archer", "atk_ground": 8, "defense": 5, "move": 4, "range": "1-2", "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 8 }),
		"wagon": UnitType.from_dict({ "id": "wagon", "atk_ground": 0, "defense": 3, "move": 5, "max_troops": 8, "capacity": 4 }),
	}

func _rich_state() -> BattleState:
	var data := {
		"cols": 8, "rows": 6, "turn_limit": 15, "roster": "carryover", "ai": "charge",
		"terrain": ["........", "..PP....", "........", "........", "........", "........"],
		"player": [
			{ "type": "archer", "col": 1, "row": 1 },
			{ "type": "wagon", "col": 2, "row": 1, "passengers": [{ "type": "knight" }] },
		],
		"enemy": [{ "ai": "charge", "units": [{ "type": "knight", "col": 6, "row": 1, "id": 99 }] }],
		"bases": [{ "col": 4, "row": 3, "team": "player", "kind": "hq", "garrison": [{ "type": "archer", "count": 1 }] }],
		"victory": [{ "type": "defeat_unit", "unit_id": 99 }],
	}
	var s := StageLoader.build(data, _cat())
	# 進行中の状態を模す：手番・行動フラグ・損耗・状態補正・撃破記録を仕込む。
	s.current_team = 1
	s.turn_number = 3
	s.unit_by_id(1).troops = 5      # archer 損耗
	s.unit_by_id(1).add_experience(2)  # level 1→3
	s.set_done(1)
	s.mark_engaged(99)
	s._moved[1] = true
	s._attacked[99] = true
	s._post_moved[2] = true
	s._spent[1] = 2
	s._defeated[42] = true          # 盤外で撃破済みのボス（ボス撃破判定用）
	s.add_status_mod({ "scope": "team", "team": 0, "op": "mul", "target": "attack", "value": 1.3, "owner_team": 0, "remaining": 2 })
	return s

## to_dict → JSON → from_dict を通した復元状態を返す。
func _roundtrip(s: BattleState) -> BattleState:
	var raw := JSON.stringify(s.to_dict())
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "直列化 JSON がパースできる")
	return BattleState.from_dict(parsed, _cat())

func test_scalars_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	assert_eq(s2.cols, 8)
	assert_eq(s2.rows, 6)
	assert_eq(s2.current_team, 1, "手番の陣営")
	assert_eq(s2.turn_number, 3)
	assert_eq(s2.turn_limit, 15)
	assert_eq(s2.roster, "carryover")
	assert_eq(s2.enemy_ai, "charge")

func test_units_roundtrip_with_board_and_growth() -> void:
	var s2 := _roundtrip(_rich_state())
	assert_eq(s2.units().size(), 3, "盤上3体（archer/wagon/敵knight）")
	var a := s2.unit_by_id(1)
	assert_eq(a.type_id, "archer")
	assert_eq(a.team, 0)
	assert_eq(a.pos, Hex.offset_to_axial(1, 1), "位置を保つ")
	assert_eq(a.troops, 5, "損耗を保つ")
	assert_eq(a.level, 3, "経験を保つ")
	assert_eq(a.unit_attack, 8, "性能は type から再構築")
	assert_eq(a.attack_range, 2)
	var e := s2.unit_by_id(99)
	assert_eq(e.team, 1, "敵の陣営を保つ")
	assert_eq(e.pos, Hex.offset_to_axial(6, 1))

func test_action_flags_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	assert_true(s2.has_moved(1), "移動済みフラグ")
	assert_true(s2.has_attacked(99), "攻撃済みフラグ")
	assert_true(s2._post_moved.has(2), "攻撃後移動フラグ")
	assert_true(s2._done.has(1), "待機フラグ")
	assert_true(s2.is_engaged(99), "AI起動フラグ")
	assert_eq(int(s2._spent.get(1, 0)), 2, "使った移動コスト")
	assert_true(s2._defeated.has(42), "撃破記録（ボス撃破判定用）")

func test_terrain_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	assert_eq(s2.terrain_at(Hex.offset_to_axial(2, 1)), "plateau", "地形を保つ")
	assert_eq(s2.terrain_at(Hex.offset_to_axial(3, 1)), "plateau")
	assert_eq(s2.terrain_at(Hex.offset_to_axial(0, 0)), "plain", "未指定は平地")

func test_bases_and_garrison_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	assert_eq(s2.bases().size(), 1)
	var b := s2.bases()[0]
	assert_eq(b.hex, Hex.offset_to_axial(4, 3), "拠点位置")
	assert_eq(b.team, 0, "所属")
	assert_eq(b.native_team, 0, "本来の持ち主")
	assert_true(b.is_hq(), "hq 種別")
	assert_eq(b.garrison.size(), 1, "garrison 1体")
	assert_eq(b.garrison[0].type_id, "archer", "garrison の type を再構築")

func test_squads_and_membership_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	assert_eq(s2.squads.size(), 1, "敵の charge 部隊")
	assert_eq(s2.squad_index_of(99), 0, "敵knight は部隊0所属")
	assert_eq(String(s2.squad_of(99).get("ai", "")), "charge", "部隊のプリセット")

func test_passengers_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	var riders := s2.passengers(2)  # wagon id=2
	assert_eq(riders.size(), 1, "搭乗1体")
	assert_eq(riders[0].type_id, "knight", "搭乗兵の type")
	assert_eq(riders[0].id, 3, "搭乗兵の id")

func test_status_mods_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	var agg := s2.status_aggregate(s2.unit_by_id(1), "attack")
	assert_almost_eq(float(agg["mul"]), 1.3, 0.001, "team バフが復元され攻撃に係数")

func test_victory_conditions_roundtrip() -> void:
	var s2 := _roundtrip(_rich_state())
	assert_eq(s2.victory_conditions.size(), 1)
	assert_eq(int(s2.victory_conditions[0]["unit_id"]), 99, "ボス撃破条件の対象id")

func test_empty_state_roundtrips() -> void:
	# 最小状態（既定値）でも壊れない。
	var s2 := _roundtrip(BattleState.new(4, 4))
	assert_eq(s2.cols, 4)
	assert_eq(s2.units().size(), 0)
	assert_eq(s2.bases().size(), 0)
	assert_eq(s2.roster, "fresh")
