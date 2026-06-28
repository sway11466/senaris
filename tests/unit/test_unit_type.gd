extends GutTest
## UnitType（性能＝ステータスのみ。名前/画像は UnitSkin に分離）のテスト。

func test_from_dict_fields() -> void:
	var t := UnitType.from_dict({
		"id": "cleric",
		"atk_ground": 10, "atk_air": 10, "defense": 4,
		"move": 3, "move_type": "ground", "range": 1,
		"can_capture": true, "max_troops": 8,
	})
	assert_eq(t.id, "cleric")
	assert_eq(t.atk_ground, 10)
	assert_eq(t.atk_air, 10)
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
