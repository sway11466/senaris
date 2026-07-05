extends GutTest
## 地形スキン層（terrain_skin.json）と性能(terrain_type)の整合＋解決のテスト。
## refactoring-2（案P）＝skin→type 1:1・各 type に既定スキン・未指定セルは type 既定へフォールバック。

func test_every_skin_type_exists() -> void:
	# 各スキンの terrain_type が terrain_type に実在する（参照切れ＝描画で null になる罠を封じる）。
	var type_ids := TerrainType.all_ids()
	assert_gt(type_ids.size(), 0, "地形タイプが読める")
	for tid in type_ids:
		var s := TerrainSkinCatalog.for_type(tid)
		assert_not_null(s, "terrain_type '%s' に既定スキンがある" % tid)
		if s != null:
			assert_true(tid in type_ids, "スキンの terrain_type '%s' が実在" % s.terrain_type)

func test_default_skin_is_same_name() -> void:
	# 既定スキンは skin_id == terrain_type（type 指定/未指定セルの解決先）。
	for tid in TerrainType.all_ids():
		var s := TerrainSkinCatalog.for_type(tid)
		assert_not_null(s, "%s に既定スキン" % tid)
		if s != null:
			assert_eq(s.skin_id, tid, "%s の既定スキンは同名 skin_id" % tid)

func test_resolve_falls_back_to_type_default() -> void:
	# 未収録セル（skin_id=""）／未知 skin_id は terrain_type の既定スキンにフォールバックする。
	var default_plain := TerrainSkinCatalog.for_type("plain")
	assert_not_null(default_plain, "plain に既定スキン")
	assert_eq(TerrainSkinCatalog.resolve("", "plain"), default_plain, "空 skin_id は type 既定へ")
	assert_eq(TerrainSkinCatalog.resolve("no_such_skin", "plain"), default_plain, "未知 skin_id は type 既定へ")

func test_resolve_prefers_explicit_skin() -> void:
	# skin_id が実在すればそれを優先（差分列挙の意図どおり）。
	var forest := TerrainSkinCatalog.skin_by_id("forest")
	assert_not_null(forest, "forest スキンが引ける")
	if forest != null:
		# 別 type を渡しても、実在 skin_id が優先される。
		assert_eq(TerrainSkinCatalog.resolve("forest", "plain"), forest, "実在 skin_id を優先")

func test_orientable_matches_natural_terrain() -> void:
	# 向きの無い自然地形は orientable=true、道/壁など構造物は false（旧ハードコードの移設先）。
	for tid in ["plain", "forest", "mountain", "wasteland", "bush", "plateau"]:
		var s := TerrainSkinCatalog.for_type(tid)
		assert_true(s != null and s.orientable, "%s は orientable" % tid)
	for tid in ["road", "fence", "wall", "cliff", "rampart", "trap", "fort"]:
		var s := TerrainSkinCatalog.for_type(tid)
		assert_true(s != null and not s.orientable, "%s は非 orientable" % tid)

func test_parse_terrain_skins_maps_coords() -> void:
	# ステージの terrain_skins（[{col,row,skin}]）→ { Vector2i: skin_id } に正しく畳む。
	var data := { "terrain_skins": [
		{ "col": 2, "row": 3, "skin": "plain_snow" },
		{ "col": 0, "row": 0, "skin": "forest" },
	] }
	var m := StageLoader.parse_terrain_skins(data)
	assert_eq(m.size(), 2, "2セル分")
	assert_eq(m.get(Hex.offset_to_axial(2, 3), ""), "plain_snow", "座標→skin_id")
	assert_eq(m.get(Hex.offset_to_axial(0, 0), ""), "forest", "座標→skin_id")

func test_parse_terrain_skins_empty_when_absent() -> void:
	# terrain_skins が無いステージは空マップ（既存ステージは skin 追記ゼロで現状描画）。
	assert_eq(StageLoader.parse_terrain_skins({}).size(), 0, "未指定は空")
