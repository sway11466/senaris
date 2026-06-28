extends GutTest
## UnitType（種別テンプレ＋テーマ別名）のテスト。

func test_from_dict_fields() -> void:
	var t := UnitType.from_dict({
		"id": "cleric", "role": "infantry",
		"atk_ground": 10, "atk_air": 10, "defense": 4,
		"move": 3, "move_type": "ground", "range": 1,
		"can_capture": true, "max_troops": 8,
	})
	assert_eq(t.id, "cleric")
	assert_eq(t.role, "infantry")
	assert_eq(t.atk_ground, 10)
	assert_eq(t.defense, 4)
	assert_eq(t.move, 3)
	assert_eq(t.move_type, "ground")
	assert_eq(t.attack_range, 1)
	assert_true(t.can_capture)
	assert_eq(t.max_troops, 8)

func test_from_dict_defaults() -> void:
	var t := UnitType.from_dict({ "id": "mystery" })
	assert_eq(t.atk_ground, 0)
	assert_eq(t.move_type, "ground", "move_type 既定は ground")
	assert_eq(t.attack_range, 1, "range 既定は 1（近接）")
	assert_false(t.can_capture)
	assert_eq(t.max_troops, 8)

func test_display_name_by_team_and_alias() -> void:
	var t := UnitType.from_dict({
		"id": "cleric",
		"names": {
			"ally": ["クレリック"],
			"enemy": ["ゴブリン", "守護像"],  # 同性能・別名のエイリアス
		},
	})
	assert_eq(t.display_name(0), "クレリック", "味方の既定名")
	assert_eq(t.display_name(1), "ゴブリン", "敵の既定名(index0)")
	assert_eq(t.display_name(1, 1), "守護像", "敵のエイリアス(index1)")
	assert_eq(t.display_name(1, 9), "ゴブリン", "範囲外は先頭にフォールバック")

func test_display_name_falls_back_to_id() -> void:
	var t := UnitType.from_dict({ "id": "mystery" })
	assert_eq(t.display_name(0), "mystery", "名前が無ければ id")
