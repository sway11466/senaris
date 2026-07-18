extends GutTest
## Unit の直列化（to_dict/from_dict）＝セーブの共有土台のテスト。詳細 → doc/tech/gamesystem.md
## スナップショット（継承）は「素性・成長・損耗だけを持ち、性能は type から再構築」を満たすことを固定する。

func _archer_type() -> UnitType:
	return UnitType.from_dict({
		"id": "archer", "atk_ground": 8, "atk_air": 0, "defense": 5,
		"move": 4, "move_type": "ground", "range": "1-2", "max_troops": 8,
	})

func test_to_dict_only_snapshot_fields() -> void:
	var u := Unit.new(5, 0, Vector2i(2, 3), 4, 6, 12, 8, 3, "archer")
	u.skin_id = "archer_red"
	u.max_troops = 8
	var d := u.to_dict()
	assert_eq(d, {
		"type": "archer", "skin": "archer_red", "level": 3, "troops": 6, "max_troops": 8,
	})
	# 盤依存の状態は焼かない
	assert_false(d.has("id"), "id は盤依存＝持たない")
	assert_false(d.has("pos"), "pos は盤依存＝持たない")
	assert_false(d.has("team"), "team は盤依存＝持たない")
	# 性能値は焼かない（type から再構築するため）
	assert_false(d.has("atk"), "攻撃力は焼かない")
	assert_false(d.has("attack_range"), "射程は焼かない")

func test_from_dict_rebuilds_stats_from_type() -> void:
	var d := { "type": "archer", "skin": "archer", "level": 3, "troops": 6, "max_troops": 8 }
	var u := Unit.from_dict(d, _archer_type())
	# 成長・損耗はスナップショットから
	assert_eq(u.type_id, "archer")
	assert_eq(u.level, 3)
	assert_eq(u.troops, 6)
	assert_eq(u.max_troops, 8)
	# 性能は type から再構築
	assert_eq(u.unit_attack, 8, "攻撃力は type.atk_ground")
	assert_eq(u.unit_defense, 5, "防御は type.defense")
	assert_eq(u.move, 4, "移動力は type.move")
	assert_eq(u.min_range, 1, "射程下限は type から")
	assert_eq(u.attack_range, 2, "射程上限は type から（1-2）")

func test_round_trip_preserves_snapshot() -> void:
	var t := _archer_type()
	var u0 := Unit.new(9, 0, Vector2i(1, 1), 4, 4, 8, 5, 5, "archer")
	u0.skin_id = "archer_blue"
	var u1 := Unit.from_dict(u0.to_dict(), t)
	assert_eq(u1.to_dict(), u0.to_dict(), "to_dict→from_dict→to_dict で一致")

func test_troops_survives_when_below_max() -> void:
	# 損耗（troops < max_troops）が type 再構築で満員に戻らないこと＝連戦の消耗管理の要。
	var d := { "type": "archer", "skin": "archer", "level": 1, "troops": 2, "max_troops": 8 }
	var u := Unit.from_dict(d, _archer_type())
	assert_eq(u.troops, 2, "損耗した兵数を保つ（満員に戻さない）")
	assert_eq(u.max_troops, 8, "満員値は維持")

func test_from_dict_without_type_uses_defaults() -> void:
	# catalog 未解決（未知 type）でも既定性能で復元＝データ欠損に耐える。
	var d := { "type": "mystery", "skin": "mystery", "level": 2, "troops": 3, "max_troops": 8 }
	var u := Unit.from_dict(d)
	assert_eq(u.type_id, "mystery")
	assert_eq(u.level, 2)
	assert_eq(u.troops, 3)
	assert_eq(u.move, 3, "既定 move")
	assert_eq(u.unit_attack, 10, "既定 atk")
	assert_eq(u.unit_defense, 10, "既定 def")

func test_from_dict_defaults_missing_keys() -> void:
	var u := Unit.from_dict({ "type": "archer" }, _archer_type())
	assert_eq(u.level, 1, "level 既定は 1")
	assert_eq(u.max_troops, 8, "max_troops 既定は 8")
	assert_eq(u.troops, 8, "troops 省略時は満員(max_troops)")
	assert_eq(u.skin_id, "archer", "skin 省略時は type_id")
