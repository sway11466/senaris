extends GutTest
## 生成済みJSON（コミット物）のクロスファイル整合性テスト。
## convert 実行を忘れて手編集した/正本がドリフトした場合でも、committed な artifacts が
## 噛み合っていることを担保する（各 convert の生成時チェックを、成果物側からも網掛けする）。
## 詳細 → doc/tech/architecture.md「CSV→データ生成のバリデーション」

func test_unit_move_types_exist_in_movement() -> void:
	# 各ユニット種別の move_type が movement 表に存在する（typo→黙ってコスト1 の罠を封じる）。
	var types := UnitCatalog.load_default()
	var move := Movement.load_default()
	assert_gt(types.size(), 0, "ロスターが読める")
	for id in types:
		var mt: String = types[id].move_type
		assert_true(move.has(mt), "%s の move_type '%s' が movement 表にある" % [id, mt])

func test_skin_type_ids_exist_in_unit_types() -> void:
	# 各スキンの type_id（性能への参照）が unit_type に存在する（参照切れ→素の10/10 に化ける罠を封じる）。
	var types := UnitCatalog.load_default()
	var skins := SkinCatalog.load_standard()
	for key in skins:
		if key == SkinCatalog.BY_ID_KEY:
			continue  # skin_id 索引は type_id ではない
		assert_true(types.has(key), "スキンの type_id '%s' が unit_type にある" % key)

func test_movement_table_covers_all_terrain() -> void:
	# movement は完全表＝各 move_type が全地形のコストを持つ（新地形の入れ忘れ→黙ってコスト1 を封じる）。
	var move := Movement.load_default()
	var terrains := Terrain.all_ids()
	assert_gt(terrains.size(), 0, "地形が読める")
	for mt in move:
		var costs: Dictionary = move[mt]
		for t in terrains:
			assert_true(costs.has(t), "move_type '%s' に地形 '%s' のコストがある" % [mt, t])
