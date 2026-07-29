extends GutTest
## UnitCatalog（ロスター表 → { id: UnitType }）のテスト。

func test_build_indexes_by_id() -> void:
	var cat := UnitCatalog.build({ "types": [
		{ "id": "a", "atk_ground": 5 },
		{ "id": "b", "atk_ground": 7 },
	] })
	assert_eq(cat.size(), 2)
	assert_true(cat.has("a") and cat.has("b"))
	assert_eq(cat["a"].atk_ground, 5)

func test_build_skips_idless() -> void:
	var cat := UnitCatalog.build({ "types": [
		{ "atk_ground": 5 },          # id 無し → スキップ
		{ "id": "b", "atk_ground": 7 },
	] })
	assert_push_warning("id 無しの種別をスキップ")
	assert_eq(cat.size(), 1)
	assert_true(cat.has("b"))

func test_load_default_roster() -> void:
	# 既定ロスターが読めて、cleric のフィールドが載ることを確認する。
	# 具体ステータス(atk/defense)は CSV側のバランス値なので決め打ちしない（調整で壊さない）。
	var cat := UnitCatalog.load_default()
	assert_true(cat.has("cleric"), "既定ロスターに cleric")
	var c: UnitType = cat["cleric"]
	assert_eq(c.id, "cleric")
	assert_true(c.can_capture, "cleric は占領兵")
	assert_eq(c.max_troops, 8)
	assert_gt(c.atk_ground, 0, "ステータスが読めている（値はバランス調整で変わりうる）")
	assert_gt(c.defense, 0)

func test_build_categories_keeps_only_filled_rows() -> void:
	var cats := UnitCatalog.build_categories({ "types": [
		{ "id": "a", "category": "歩兵" },
		{ "id": "b", "category": "" },   # 空欄 → 落とす
		{ "category": "弓兵" },          # id 無し → 落とす
	] })
	assert_eq(cats, { "a": "歩兵" })

func test_display_category_falls_back_to_empty() -> void:
	# 兵種名は表示専用（unit_type.csv の category 列）。未知idは空＝行ごと出さない。
	assert_ne(UnitCatalog.display_category("fighter"), "", "既定ロスターの fighter に兵種名がある")
	assert_eq(UnitCatalog.display_category("no_such_type"), "")
