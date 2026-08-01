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

func test_connect_only_on_line_terrain() -> void:
	# 線地形（隣と繋がる）は柵だけ。面で覆う地形・構造物は false（向き別タイルを探しに行かせない）。
	var fence := TerrainSkinCatalog.for_type("fence")
	assert_true(fence != null and fence.connect, "fence は connect")
	for tid in ["plain", "forest", "mountain", "wall", "fort", "cliff"]:
		var s := TerrainSkinCatalog.for_type(tid)
		assert_true(s != null and not s.connect, "%s は非 connect" % tid)

func test_connected_image_path_bits() -> void:
	# 6要素（Hex.DIRECTIONS 順）がそのまま 0/1 の6桁になる。生成物のファイル名規約。
	var fence := TerrainSkinCatalog.for_type("fence")
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

func test_extend_off_board_grows_no_comb_along_the_rim() -> void:
	# 盤の縁と平行に走る線に、外向きの腕は生えない。腕が生えるには「その向きの反対側が
	# 繋がっている」＝線が盤の外を向いている必要があり、縁と平行な線はこれを満たさない。
	# 最終列を縦に走る柵: dir2/dir5 で繋がり、盤外は dir0/dir1。
	var connected := [false, false, true, false, false, true]
	var on_board := [false, false, true, true, true, true]
	assert_eq(TerrainSkin.extend_off_board(connected, on_board), connected, "縁沿いの通過マスは変えない")

func test_extend_off_board_fills_an_area_out_to_the_rim() -> void:
	# 面地形（道）が盤の縁に乗ったとき、盤外を向いた向きが複数あればその全部へ伸びる。
	# 蓋（輪郭付きの終端）を縁に作らないための挙動。tutorial2-st1 の右端がこの形。
	var connected := [false, false, false, false, true, true]   # dir4/dir5 で繋がる
	var on_board := [false, false, true, true, true, true]      # dir0/dir1 が盤外
	# dir4 の反対 dir1 が盤外 → 伸ばす。dir5 の反対 dir2 は盤内 → 伸ばさない。
	assert_eq(TerrainSkin.extend_off_board(connected, on_board),
		[false, true, false, false, true, true], "盤外を向いた軸だけ伸びる")

func test_extend_off_board_forks_at_a_corner_bend() -> void:
	# 盤の角で線が曲がると、曲がりの両側とも盤外を向くので二又に伸びる（許容した挙動）。
	var connected := [true, false, true, false, false, false]
	var on_board := [true, false, true, false, false, false]
	assert_eq(TerrainSkin.extend_off_board(connected, on_board),
		[true, false, true, true, false, true], "dir0→dir3・dir2→dir5 の両方へ伸びる")

func test_connect_tiles_all_present() -> void:
	# connect スキンは64通りぜんぶ揃っている必要がある（1つでも欠けるとそのマスだけ絵が化ける）。
	for s: TerrainSkin in TerrainSkinCatalog.all_skins():
		if not s.connect:
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
