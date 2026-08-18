extends GutTest
## 地形スキン層（terrain_skin.json）と性能(terrain_type)の整合＋解決のテスト。
## 詳細 → doc/gdd/terrain.md。skin→type は1:1。地形には決まった絵（型IDと同名のスキン）があり、
## そぐわないマスだけステージが別スキンを当てる。引けなければ代替を出さずエラー。

func test_every_skin_type_exists() -> void:
	# 各スキンの terrain_type が terrain_type に実在する（参照切れ＝描画で null になる罠を封じる）。
	var type_ids := TerrainType.all_ids()
	assert_gt(type_ids.size(), 0, "地形タイプが読める")
	for s: TerrainSkin in TerrainSkinCatalog.all_skins():
		assert_true(s.terrain_type in type_ids, "スキン '%s' の terrain_type '%s' が実在" % [s.skin_id, s.terrain_type])

func test_footing_resolves_by_its_own_name() -> void:
	# 足場は skin_id == terrain_type。ステージが指定しないセルはこれで引ける。
	for tid in TerrainType.all_ids():
		if TerrainType.layer(tid) != "footing":
			continue
		var s := TerrainSkinCatalog.resolve("", tid)
		assert_not_null(s, "足場 %s に同名スキン" % tid)
		if s != null:
			assert_eq(s.skin_id, tid, "%s は同名 skin_id で引ける" % tid)

func test_object_has_no_same_name_skin() -> void:
	# オブジェクトの型には同名のスキンを置かない（足場を選ばせるため）＝ステージが必ず書く、を固定する。
	var checked := 0
	for tid in TerrainType.all_ids():
		if TerrainType.layer(tid) != "object":
			continue
		checked += 1
		assert_null(TerrainSkinCatalog.skin_by_id(tid), "オブジェクト %s に同名スキンは置かない" % tid)
	assert_gt(checked, 0, "オブジェクトの型が1つは居る")

func test_connect_to_defaults_to_self_only() -> void:
	# 繋がる相手を書いていないスキンは、同じスキンとだけ繋がる（従来どおり）。
	var road := TerrainSkinCatalog.skin_by_id("road")
	var fence := TerrainSkinCatalog.skin_by_id("plain_fence")
	assert_not_null(fence, "plain_fence スキンが引ける")
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

func test_resolve_does_not_substitute() -> void:
	# 未知の skin_id を書いたら、黙って別の絵で埋めずに null を返す（データの不備として声を上げる）。
	assert_eq(TerrainSkinCatalog.resolve("", "plain"), TerrainSkinCatalog.skin_by_id("plain"), "空なら型IDと同名")
	assert_null(TerrainSkinCatalog.resolve("no_such_skin", "plain"), "未知 skin_id は代替しない")
	assert_null(TerrainSkinCatalog.resolve("", "no_such_type"), "未知 type も代替しない")
	# 黙って代替しない代わりに声を上げる（データの不備を画面より先にログで気づく）。
	assert_push_error_count(2, "引けなかった2件をエラーで知らせる")

func test_resolve_prefers_explicit_skin() -> void:
	# skin_id が実在すればそれを優先（差分列挙の意図どおり）。
	var forest := TerrainSkinCatalog.skin_by_id("forest")
	assert_not_null(forest, "forest スキンが引ける")
	if forest != null:
		# 別 type を渡しても、実在 skin_id が優先される。
		assert_eq(TerrainSkinCatalog.resolve("forest", "plain"), forest, "実在 skin_id を優先")

func test_connecting_skins_are_never_oriented() -> void:
	# 繋がる地形（道・柵・川）は向きの組み合わせ別タイル（_c000000〜）を引く＝回しても反転しても
	# 隣との繋がりが壊れる。どのスキンをどう散らすかは CSV が持つので、ここでは一覧を書き写さず
	# 「繋がるなら散らさない」という関係だけを見る（書き写すと絵を足すたびに嘘になる）。
	var checked := 0
	for s: TerrainSkin in TerrainSkinCatalog.all_skins():
		if not s.connects():
			continue
		checked += 1
		assert_false(s.orients(), "%s は繋がる＝散らしてはいけない" % s.skin_id)
	assert_true(checked > 0, "繋がるスキンが1つは居る（1件も見ずに通っていない）")

func test_flip_x_skin_does_not_rotate() -> void:
	# 塊に向きがある絵（茂み）は回すと1マスごとに向きが変わる。左右反転だけで散らす。
	var bush := TerrainSkinCatalog.skin_by_id("bush")
	assert_not_null(bush, "bush が引ける")
	if bush != null:
		assert_eq(bush.orientable, TerrainSkin.ORIENT_FLIP_X, "茂みは flip_x")
		assert_true(bush.orients(), "散らしの対象ではある")
		assert_false(bush.rotates(), "回してはいけない")

func test_orient_values_allow_exactly_what_they_name() -> void:
	# 値の名前と、効く操作（回転・左右・上下）を1対1で固定する。名前を読めば挙動が分かる状態を守る。
	var table := {
		TerrainSkin.ORIENT_NONE:    [false, false, false],
		TerrainSkin.ORIENT_FLIP_X:  [false, true,  false],
		TerrainSkin.ORIENT_FLIP_Y:  [false, false, true],
		TerrainSkin.ORIENT_FLIP_XY: [false, true,  true],
		TerrainSkin.ORIENT_FULL:    [true,  true,  true],
	}
	for mode: String in table:
		var want: Array = table[mode]
		var s := TerrainSkin.from_dict({ "skin_id": "x", "orientable": mode })
		assert_eq(s.rotates(), want[0], "%s の回転" % mode)
		assert_eq(s.flips_horizontally(), want[1], "%s の左右反転" % mode)
		assert_eq(s.flips_vertically(), want[2], "%s の上下反転" % mode)
		assert_eq(s.orients(), mode != TerrainSkin.ORIENT_NONE, "%s の散らし対象か" % mode)

func test_objects_are_never_oriented() -> void:
	# オブジェクトは立ち絵＝回しも反転もしない（→ doc/gdd/terrain.md）。
	for s: TerrainSkin in TerrainSkinCatalog.all_skins():
		if TerrainType.layer(s.terrain_type) != "object":
			continue
		assert_false(s.orients(), "%s はオブジェクト＝散らさない" % s.skin_id)
		assert_eq(s.elevation, 0.0, "%s はオブジェクト＝高さは立ち絵が持つ" % s.skin_id)

func test_unknown_orientable_falls_back_to_none() -> void:
	# 旧データの bool や打ち間違いが来ても、勝手に回して絵を倒すより散らさないほうが害が小さい。
	for bad in [true, false, "maybe", 1]:
		var s := TerrainSkin.from_dict({ "skin_id": "x", "orientable": bad })
		assert_eq(s.orientable, TerrainSkin.ORIENT_NONE, "不正値(%s)は none に倒す" % [bad])

func test_connect_is_line_or_area() -> void:
	# 繋がる地形は柵（線）と道（面）だけ。他は繋がらない＝向き別タイルを探しに行かせない。
	var fence := TerrainSkinCatalog.skin_by_id("plain_fence")
	assert_true(fence != null and fence.connects(), "柵は繋がる")
	assert_false(fence != null and fence.connects_as_area(), "柵は線＝面ではない")
	var road := TerrainSkinCatalog.resolve("","road")
	assert_true(road != null and road.connects(), "road は繋がる")
	assert_true(road != null and road.connects_as_area(), "road は面")
	for sid in ["plain", "forest", "bedrock", "wall", "plain_fort", "plain_rock"]:
		var s := TerrainSkinCatalog.skin_by_id(sid)
		assert_false(s != null and s.connects(), "%s は繋がらない" % sid)

func test_map_overlay_borrows_the_art_of_another_skin() -> void:
	# 地面を絵に焼き込まないので、同じ柵の絵を別の地面の上に置ける＝画像を複製しない。
	var grave := TerrainSkinCatalog.skin_by_id("plain_grave1_fence")
	assert_not_null(grave, "墓地の柵スキン")
	if grave == null:
		return
	assert_eq(grave.art_id(), "plain_fence", "絵は柵から借りる")
	assert_eq(grave.map_ground_id(), "plain_grave1", "下地は墓地の草地")
	assert_eq(grave.image_path(), "res://assets/terrain/plain_fence.png", "基本タイルも借りた絵")
	assert_eq(grave.connected_image_path([false, false, true, false, false, true]),
		"res://assets/terrain/plain_fence_c001001.png", "接続タイルも借りた絵")

func test_art_id_defaults_to_self() -> void:
	# map_overlay を書いていないスキンは自分の絵。既存スキンの引き方は変わらない。
	var fence := TerrainSkinCatalog.skin_by_id("plain_fence")
	assert_true(fence != null and fence.art_id() == "plain_fence", "既定は自分自身")
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
	var fence := TerrainSkinCatalog.skin_by_id("plain_fence")
	assert_not_null(fence, "柵スキン")
	if fence == null:
		return
	assert_eq(fence.connected_image_path([false, false, true, false, false, true]),
		"res://assets/terrain/plain_fence_c001001.png", "上下だけ繋がる＝縦の直線")
	assert_eq(fence.connected_image_path([false, false, false, false, false, false]),
		"res://assets/terrain/plain_fence_c000000.png", "どこにも繋がらない＝独立した柱")

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

func test_parse_board_height_reads_both_axes() -> void:
	# 盤の基準高さは行と列の2本。あるマスの高さは 行＋列＋スキンの elevation（見た目のみ）。
	var d := { "height": { "row": [0, 0.18, 0.36], "col": [0, 0.5] } }
	var h := StageLoader.parse_board_height(d, 2, 3)
	assert_eq(h["row"], [0.0, 0.18, 0.36], "行の基準")
	assert_eq(h["col"], [0.0, 0.5], "列の基準")

func test_parse_board_height_rejects_wrong_length() -> void:
	# 長さが盤と違う配列を黙って0で埋めると、どこまで指定したつもりか分からなくなる。
	var d := { "height": { "row": [0, 0.18], "col": [0, 0.5] } }
	var h := StageLoader.parse_board_height(d, 2, 3)  # 盤は3行なのに2つしかない
	assert_eq(h["row"], [], "長さ違いの軸は平らに倒す")
	assert_eq(h["col"], [0.0, 0.5], "もう一方の軸は生きる")
	assert_push_error_count(1, "理由をログに出す")

func test_parse_board_height_absent_is_flat() -> void:
	assert_eq(StageLoader.parse_board_height({}, 5, 5), { "row": [], "col": [] }, "未指定は平ら")
