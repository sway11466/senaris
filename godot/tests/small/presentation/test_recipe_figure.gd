extends GutTest
## presentation/chronicle/recipe_figure.gd の配置。形ごとの図が仕様の形（doc/gdd/formations.md）と
## 矛盾しないことを見る。描画そのものは見ない。

func test_every_layout_has_distinct_cells() -> void:
	for shape in ChronicleRecipeFigure.LAYOUTS:
		var cells: Array = ChronicleRecipeFigure.LAYOUTS[shape]
		var seen := {}
		for c in cells:
			seen[c] = true
		assert_eq(seen.size(), cells.size(), "%s のヘックスは重ならない" % shape)

func test_targets_only_for_known_shapes() -> void:
	for shape in ChronicleRecipeFigure.TARGETS:
		assert_true(ChronicleRecipeFigure.LAYOUTS.has(shape), "%s は LAYOUTS にもある" % shape)
		assert_false((ChronicleRecipeFigure.LAYOUTS[shape] as Array).has(ChronicleRecipeFigure.TARGETS[shape]),
			"%s の対象ヘクスは参加者と重ならない" % shape)

func test_spotter_member_adjacent_to_target() -> void:
	var cells: Array = ChronicleRecipeFigure.LAYOUTS["spotter"]
	var target: Vector2i = ChronicleRecipeFigure.TARGETS["spotter"]
	assert_eq(Hex.distance(cells[1], target), 1, "斥候は対象に隣接")

func test_spotter_caster_in_archer_range() -> void:
	var cells: Array = ChronicleRecipeFigure.LAYOUTS["spotter"]
	var target: Vector2i = ChronicleRecipeFigure.TARGETS["spotter"]
	var d := Hex.distance(cells[0], target)
	assert_true(d >= 2 and d <= 3, "弓兵は対象からアーチャーの射程 1〜3 の中、かつ隣接ではない（d=%d）" % d)

func test_spotter_pair_not_adjacent() -> void:
	var cells: Array = ChronicleRecipeFigure.LAYOUTS["spotter"]
	assert_true(Hex.distance(cells[0], cells[1]) > 1, "弓兵と斥候は隣り合わない＝隣接不要が図で読める")

func test_spotter_count_matches_recipe() -> void:
	assert_eq((ChronicleRecipeFigure.LAYOUTS["spotter"] as Array).size(), int(Formation.SKILLS["trick_shot"]["count"]),
		"図の参加者数はレシピの人数")

func test_thief_is_first_member_of_trick_shot() -> void:
	assert_eq(String(Formation.SKILLS["trick_shot"]["member_skins"][0]), "thief", "図と黒塗りの代表はシーフ")

## ⑤の図は一直線の3つで、発動者が真ん中＝列のどこからでも発動できることが図で読める。
func test_line_layout_is_straight_and_unbroken() -> void:
	var cells: Array = ChronicleRecipeFigure.LAYOUTS["line"]
	assert_eq(cells.size(), int(Formation.SKILLS["shield_wall"]["count"]),
		"図の参加者数はレシピの最低人数")
	for i in range(1, cells.size()):
		assert_eq(Hex.distance(cells[0], cells[i]), 1, "参加者は発動者の隣（%d番目）" % i)
	assert_eq(Hex.distance(cells[1], cells[2]), 2, "両隣どうしは正反対＝3つが一直線に並ぶ")
