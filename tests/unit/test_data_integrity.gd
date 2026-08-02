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
	var terrains := TerrainType.all_ids()
	assert_gt(terrains.size(), 0, "地形が読める")
	for mt in move:
		var costs: Dictionary = move[mt]
		for t in terrains:
			assert_true(costs.has(t), "move_type '%s' に地形 '%s' のコストがある" % [mt, t])

func test_stage_squad_ai_labels_exist() -> void:
	# ステージの squad が参照する ai ラベルが ai.json に実在する（打ち間違い→黙って charge 化 を封じる）。
	# doc/gdd/ai.md「既定と省略のポリシー」の欠損検出＝「存在しないラベル参照」の網。
	var presets := AiCatalog.load_default()
	var files := _all_stage_files("res://data/stages")
	assert_gt(files.size(), 0, "ステージJSONが見つかる")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for squad in data.get("enemy", []):
			if typeof(squad) != TYPE_DICTIONARY:
				continue
			var label := str(squad.get("ai", "")).strip_edges()
			if label.is_empty():
				continue  # 未指定＝charge 既定（正当）
			assert_true(presets.has(label), "%s の squad.ai '%s' が ai.json に実在" % [path, label])
		# 旧スキーマの squad 外フォールバック（トップレベル "ai"）も、あれば実在チェック。
		var top := str(data.get("ai", "")).strip_edges()
		if not top.is_empty():
			assert_true(presets.has(top), "%s のトップレベル ai '%s' が ai.json に実在" % [path, top])

func test_stage_squads_and_ai_bases_have_order() -> void:
	# 行動順 order は全部隊・AI出撃する全拠点に書く（doc/gdd/ai.md 行動順）。
	# 省略はコード側では登録順にフォールバックするので黙って通ってしまう＝ここで抜けを捕まえる。
	# 同一ステージ内で重複していると順番が記述順に落ちるので、一意であることも見る。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var seen := {}
		for squad in data.get("enemy", []):
			if typeof(squad) != TYPE_DICTIONARY:
				continue
			_assert_order(path, squad, "squad '%s'" % str(squad.get("name", "無名")), seen)
		for base in data.get("bases", []):
			if typeof(base) != TYPE_DICTIONARY or not (base as Dictionary).has("ai"):
				continue  # ai 無し＝AI出撃しない拠点は行動順の列に並ばない
			_assert_order(path, base, "base (%s, %s)" % [str(base.get("col")), str(base.get("row"))], seen)

func _assert_order(path: String, holder: Dictionary, label: String, seen: Dictionary) -> void:
	var v: Variant = holder.get("order")
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		assert_true(false, "%s の %s に order がある" % [path, label])
		return
	var n := int(v)
	assert_false(seen.has(n), "%s の %s の order %d が他と重複しない" % [path, label, n])
	seen[n] = true

## data/stages 以下を再帰し、ステージJSON（campaign.json マニフェストは除く）のパス配列を返す。
func _all_stage_files(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := "%s/%s" % [root, name]
		if dir.current_is_dir():
			if not name.begins_with("."):
				out += _all_stage_files(full)
		elif name.ends_with(".json") and name != "campaign.json":
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
