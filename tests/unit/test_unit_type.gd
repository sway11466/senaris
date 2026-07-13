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
	assert_eq(t.min_range, 1, "min_range 既定は 1（近接可）")
	assert_eq(t.attack_range, 1, "range 既定は 1（近接）")
	assert_false(t.can_capture)
	assert_eq(t.max_troops, 8)

func test_parse_range_single_is_melee() -> void:
	assert_eq(UnitType.parse_range(1), Vector2i(1, 1), "1＝近接(1,1)")
	assert_eq(UnitType.parse_range("1"), Vector2i(1, 1), "文字列 '1' も同じ")

func test_parse_range_single_number_is_max_with_min1() -> void:
	# 後方互換: 単数 N は下限1・上限N（旧CSVの 2/3/5 がそのまま動く）。
	assert_eq(UnitType.parse_range(3), Vector2i(1, 3))
	assert_eq(UnitType.parse_range("2"), Vector2i(1, 2))

func test_parse_range_span() -> void:
	assert_eq(UnitType.parse_range("1-2"), Vector2i(1, 2), "弓（射程1-2）")
	assert_eq(UnitType.parse_range("3-5"), Vector2i(3, 5), "砲兵の死角（射程3-5）")

func test_parse_range_invalid_defaults_to_melee() -> void:
	assert_eq(UnitType.parse_range(""), Vector2i(1, 1), "空は近接(1,1)")

func test_from_dict_parses_range_span() -> void:
	var t := UnitType.from_dict({ "id": "cat", "range": "3-5" })
	assert_eq(t.min_range, 3, "レンジ表記の下限を min_range に")
	assert_eq(t.attack_range, 5, "レンジ表記の上限を attack_range に")
