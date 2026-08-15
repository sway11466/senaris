extends GutTest
## 地形スキン層（terrain_skin.json）と性能(terrain_type)の整合＋解決のテスト。
## refactoring-2（案P）＝skin→type 1:1・各 type に既定スキン・未指定セルは type 既定へフォールバック。

func test_every_skin_type_exists() -> void:
	# 各スキンの terrain_type が terrain_type に実在する（参照切れ＝描画で null になる罠を封じる）。
	var type_ids := TerrainType.all_ids()
	assert_gt(type_ids.size(), 0, "地形タイプが読める")
	for tid in type_ids:
		var s := TerrainSkinCatalog.resolve("",tid)
		assert_not_null(s, "terrain_type '%s' に既定スキンがある" % tid)
		if s != null:
			assert_true(tid in type_ids, "スキンの terrain_type '%s' が実在" % s.terrain_type)

func test_default_skin_is_same_name() -> void:
	# 既定スキンは skin_id == terrain_type（type 指定/未指定セルの解決先）。
	for tid in TerrainType.all_ids():
		var s := TerrainSkinCatalog.resolve("",tid)
		assert_not_null(s, "%s に既定スキン" % tid)
		if s != null:
			assert_eq(s.skin_id, tid, "%s の既定スキンは同名 skin_id" % tid)

func test_connect_to_defaults_to_self_only() -> void:
	# 繋がる相手を書いていないスキンは、同じスキンとだけ繋がる（従来どおり）。
	var road := TerrainSkinCatalog.skin_by_id("road")
	var fence := TerrainSkinCatalog.skin_by_id("fence")
	assert_not_null(fence, "fence スキンが引ける")
	if fence != null and road != null:
		assert_true(fence.connects_with(fence), "自分自身とは常に繋がる")
		assert_false(fence.connects_with(road), "書いていない相手とは繋がらない")

func test_bridge_connects_one_way_with_river() -> void:
	# 橋の下を川がくぐるのは片方向の判定で作る＝川は橋へ伸びるが、橋は川へ伸びない。
	var river := TerrainSkinCatalog.skin_by_id("river")
	var bridge := TerrainSkinCatalog.skin_by_id("road_bridge1")
	var stone := TerrainSkinCatalog.skin_by_id("road_stone1")
	var road := TerrainSkinCatalog.skin_by_id("road")
	assert_not_null(bridge, "road_bridge1 スキンが引ける")
	if river == null or bridge == null or stone == null or road == null:
		return
	assert_true(river.connects_with(bridge), "川は橋へ帯を伸ばす")
	assert_false(bridge.connects_with(river), "橋は川へ石畳を伸ばさない")
	assert_true(bridge.connects_with(road), "橋は道と繋がる")
	assert_true(road.connects_with(bridge), "道は橋と繋がる")
	assert_true(stone.connects_with(bridge), "石畳は橋と繋がる")
	assert_eq(bridge.map_ground_id(), "river", "橋の下地は川")
	assert_eq(bridge.art_id(), "road_stone1", "橋は石畳の絵を借りる")

func test_resolve_falls_back_to_type_default() -> void:
	# 未収録セル（skin_id=""）／未知 skin_id は terrain_type の既定スキンにフォールバックする。
	var default_plain := TerrainSkinCatalog.resolve("","plain")
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
	# 向きの無い自然地形は full（回転＋反転）、道/壁など構造物は none（旧ハードコードの移設先）。
	for tid in ["plain", "forest", "mountain", "wasteland", "bush", "plateau"]:
		var s := TerrainSkinCatalog.resolve("",tid)
		assert_true(s != null and s.orients() and s.rotates(), "%s は full" % tid)
	for tid in ["road", "fence", "wall", "cliff", "rampart", "trap", "fort"]:
		var s := TerrainSkinCatalog.resolve("",tid)
		assert_true(s != null and not s.orients(), "%s は none" % tid)

func test_flip_only_skin_does_not_rotate() -> void:
	# 立てて描いた物がある絵（墓標）は回すと倒れる。左右反転だけで散らす。
	var tomb := TerrainSkinCatalog.skin_by_id("wasteland_tomb1")
	assert_not_null(tomb, "wasteland_tomb1 が引ける")
	if tomb != null:
		assert_eq(tomb.orientable, TerrainSkin.ORIENT_FLIP, "墓標は flip")
		assert_true(tomb.orients(), "散らしの対象ではある")
		assert_false(tomb.rotates(), "回してはいけない")

func test_flip_xy_skin_flips_both_ways_without_rotating() -> void:
	# 向き別スキンとして作者が塗り分ける絵（街区）は、回すと指定した向きが崩れる。反転だけで散らす。
	var town := TerrainSkinCatalog.skin_by_id("plateau_town_v")
	assert_not_null(town, "plateau_town_v が引ける")
	if town != null:
		assert_eq(town.orientable, TerrainSkin.ORIENT_FLIP_XY, "街区は flip_xy")
		assert_true(town.orients(), "散らしの対象ではある")
		assert_false(town.rotates(), "回してはいけない")
		assert_true(town.flips_vertically(), "上下反転はしてよい")

func test_only_flip_xy_flips_vertically() -> void:
	# 上下反転は flip_xy だけの手。full まで巻き込むと、既存の自然地形の見え方が変わってしまう。
	for mode in [TerrainSkin.ORIENT_NONE, TerrainSkin.ORIENT_FLIP, TerrainSkin.ORIENT_FULL]:
		var s := TerrainSkin.from_dict({ "skin_id": "x", "orientable": mode })
		assert_false(s.flips_vertically(), "%s は上下反転しない" % mode)

func test_unknown_orientable_falls_back_to_none() -> void:
	# 旧データの bool や打ち間違いが来ても、勝手に回して絵を倒すより散らさないほうが害が小さい。
	for bad in [true, false, "maybe", 1]:
		var s := TerrainSkin.from_dict({ "skin_id": "x", "orientable": bad })
		assert_eq(s.orientable, TerrainSkin.ORIENT_NONE, "不正値(%s)は none に倒す" % [bad])

func test_connect_is_line_or_area() -> void:
	# 繋がる地形は柵（線）と道（面）だけ。他は繋がらない＝向き別タイルを探しに行かせない。
	var fence := TerrainSkinCatalog.resolve("","fence")
	assert_true(fence != null and fence.connects(), "fence は繋がる")
	assert_false(fence != null and fence.connects_as_area(), "fence は線＝面ではない")
	var road := TerrainSkinCatalog.resolve("","road")
	assert_true(road != null and road.connects(), "road は繋がる")
	assert_true(road != null and road.connects_as_area(), "road は面")
	for tid in ["plain", "forest", "mountain", "wall", "fort", "cliff"]:
		var s := TerrainSkinCatalog.resolve("",tid)
		assert_false(s != null and s.connects(), "%s は繋がらない" % tid)

func test_map_overlay_borrows_the_art_of_another_skin() -> void:
	# 地面を絵に焼き込まないので、同じ柵の絵を別の地面の上に置ける＝画像を複製しない。
	var grave := TerrainSkinCatalog.resolve("fence_grave1", "")
	assert_not_null(grave, "墓地の柵スキン")
	if grave == null:
		return
	assert_eq(grave.art_id(), "fence", "絵は柵から借りる")
	assert_eq(grave.map_ground_id(), "plain_grave1", "下地は墓地の草地")
	assert_eq(grave.image_path(), "res://assets/terrain/fence.png", "基本タイルも借りた絵")
	assert_eq(grave.connected_image_path([false, false, true, false, false, true]),
		"res://assets/terrain/fence_c001001.png", "接続タイルも借りた絵")

func test_art_id_defaults_to_self() -> void:
	# map_overlay を書いていないスキンは自分の絵。既存スキンの引き方は変わらない。
	var fence := TerrainSkinCatalog.resolve("fence", "")
	assert_true(fence != null and fence.art_id() == "fence", "既定は自分自身")
	assert_true(fence != null and fence.map_ground_id() == "plain", "柵の下地は平地")
	var plain := TerrainSkinCatalog.resolve("plain", "")
	assert_true(plain != null and plain.map_ground_id() == "", "下地を持たないスキンは空")

func test_connect_falls_back_when_the_value_is_unknown() -> void:
	# 旧データの true/false や打ち間違いは「繋がらない」に倒す。false が真になる事故を防ぐ。
	for v: Variant in [true, false, "true", "", "LINE", "wall"]:
		var s := TerrainSkin.from_dict({ "skin_id": "x", "connect": v })
		assert_false(s.connects(), "connect=%s は繋がらない扱い" % [v])

func test_connected_image_path_bits() -> void:
	# 6要素（Hex.DIRECTIONS 順）がそのまま 0/1 の6桁になる。生成物のファイル名規約。
	var fence := TerrainSkinCatalog.resolve("","fence")
	assert_not_null(fence, "fence スキン")
	if fence == null:
		return
	assert_eq(fence.connected_image_path([false, false, true, false, false, true]),
		"res://assets/terrain/fence_c001001.png", "上下だけ繋がる＝縦の直線")
	assert_eq(fence.connected_image_path([false, false, false, false, false, false]),
		"res://assets/terrain/fence_c000000.png", "どこにも繋がらない＝独立した柱")

func test_extend_off_board_continues_a_line_past_the_edge() -> void:
	# 端点（隣1つ）で、その反対側が盤の外なら、そちらへ腕を伸ばす＝盤の縁で柵が途切れない。
	var connected := [true, false, false, false, false, false]   # dir0 だけ繋がる
	var on_board := [true, true, true, false, true, true]        # その反対 dir3 が盤外
	var out := TerrainSkin.extend_off_board(connected, on_board)
	assert_eq(out, [true, false, false, true, false, false], "反対側 dir3 へ伸びる")

func test_extend_off_board_keeps_inner_ends_capped() -> void:
	# 反対側が盤の中なら伸ばさない（盤の途中で終わる柵は端点のまま）。
	var connected := [true, false, false, false, false, false]
	var on_board := [true, true, true, true, true, true]
	assert_eq(TerrainSkin.extend_off_board(connected, on_board), connected, "盤内の端点は変えない")

func test_extend_off_board_ignores_lone_cells() -> void:
	# どこにも繋がらないマスは何をしても変わらない（伸ばす向きの根拠が無い）。
	var lone := [false, false, false, false, false, false]
	var on_board := [true, false, true, false, false, false]
	assert_eq(TerrainSkin.extend_off_board(lone, on_board), lone, "孤立した柱は柱のまま")

func test_extend_off_board_skips_non_ends() -> void:
	# 隣が2つ以上あるマスには効かせない。外周に沿って走る柵が外向きの腕を櫛のように生やすため。
	# 面（道）はこの関数を通らない＝盤外の座標を盤に丸めて引くので、縁で蓋にならない。
	var connected := [true, false, true, false, false, false]
	var on_board := [true, false, true, false, false, false]
	assert_eq(TerrainSkin.extend_off_board(connected, on_board), connected, "通過マスは変えない")

func test_connect_tiles_all_present() -> void:
	# connect スキンは64通りぜんぶ揃っている必要がある（1つでも欠けるとそのマスだけ絵が化ける）。
	for s: TerrainSkin in TerrainSkinCatalog.all_skins():
		if not s.connects():
			continue
		for mask in 64:
			var bits: Array = []
			for i in 6:
				bits.append((mask & (1 << i)) != 0)
			var p: String = s.connected_image_path(bits)
			assert_true(ResourceLoader.exists(p), "%s の接続タイルがある: %s" % [s.skin_id, p])

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
