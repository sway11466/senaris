extends GutTest
## SkinCatalog（スキン表 → {type_id:{ally/enemy:[UnitSkin]}}）のテスト。

func test_build_and_resolve() -> void:
	var cat := SkinCatalog.build({ "skins": {
		"cleric": {
			"ally":  [ { "name": "クレリック" } ],
			"enemy": [ { "name": "ゴブリン" }, { "name": "守護像" } ],
		},
	} })
	assert_true(cat.has("cleric"))
	assert_eq(SkinCatalog.skin(cat, "cleric", 0).name, "クレリック", "味方")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1).name, "ゴブリン", "敵 既定(index0)")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1, 1).name, "守護像", "敵 エイリアス(index1)")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1, 9).name, "ゴブリン", "範囲外は先頭")

func test_resolve_missing_type_returns_null() -> void:
	var cat := SkinCatalog.build({ "skins": {} })
	assert_null(SkinCatalog.skin(cat, "unknown", 0))

func test_load_standard() -> void:
	var cat := SkinCatalog.load_standard()
	assert_true(cat.has("cleric"))
	assert_eq(SkinCatalog.skin(cat, "cleric", 0).name, "クレリック")
	assert_eq(SkinCatalog.skin(cat, "cleric", 1).name, "ゴブリン", "敵名はミラー")
	assert_eq(SkinCatalog.skin(cat, "paladin", 1).name, "ゴブリンロード")
