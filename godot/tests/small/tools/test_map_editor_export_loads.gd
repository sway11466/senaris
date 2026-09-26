extends GutTest
## マップエディタの書き出し（本体＋地形ファイル）を StageLoader が読めるか。
## 書き出した2つのテキストを、StageLoader.read_stage と同じ手順（地形キーを重ねる・盤の広さをグリッドから数える）
## でメモリ上で合流させ、StageLoader.build に通す。ファイルは書かない。
## 実ステージは「読込→無編集で書き出し→組み立て」が、元ファイルをそのまま組み立てたものと同じ盤になることを見る。

const STAGES_ROOT := "res://data/stages"


## 書き出した本体＋地形のテキストを、StageLoader が read_stage で作るのと同じ形の辞書にする。
## 本体に地形キー・盤の広さを書いていないこと、地形ファイルが地形キーだけを持つことも確かめる
## （read_stage は本体の地形キーを push_error で拒み、地形ファイルの他のキーは拾わない）。
func _exported(doc: MapEditorDoc) -> Dictionary:
	var body: Dictionary = JSON.parse_string(doc.to_stage_text())
	var terrain: Dictionary = JSON.parse_string(doc.to_terrain_text())
	for k in StageLoader.TERRAIN_KEYS + ["cols", "rows"]:
		assert_false(body.has(k), "本体に '%s' を書かない" % k)
	for k in terrain:
		assert_has(StageLoader.TERRAIN_KEYS, k, "地形ファイルに書くのは地形キーだけ")
	for k in terrain:
		body[k] = terrain[k]
	# 盤の広さ＝グリッドの寸法から外周ぶんを引く（doc/gdd/map.md ステージのファイル）
	var lines: Array = body["terrain"]
	var margin := int(body["margin"])
	body["cols"] = String(lines[0]).length() - 2 * margin
	body["rows"] = lines.size() - 2 * margin
	return body


func _build(data: Dictionary) -> BattleState:
	return StageLoader.build(data, UnitCatalog.load_default(), SkinCatalog.load_standard())


## 盤の中身を比べられる形に並べる（駒・拠点・地形・勝敗条件・増援の数）。
## 部隊は駒ごとの所属部隊の中身で見る（部隊の数・index では見ない）。エディタは味方部隊が無いステージにも
## 空の置き場を1つ足す（MapEditorDoc._migrate_legacy_player）ので、駒のいない部隊が増え index がずれうるため。
func _fingerprint(s: BattleState) -> Dictionary:
	var units: Array = []
	for u in s.units():
		units.append("%d|%s|%s|%s|%s|%s|%d|%d|%s" % [u.team, u.type_id, u.skin_id, u.unit_id, u.actor,
			str(Hex.axial_to_offset(u.pos)), u.troops, u.level, JSON.stringify(s.squad_of(u.handle))])
	units.sort()
	var bases: Array = []
	for b in s.bases():
		bases.append("%s|%d|%d|%s|%d|%s" % [str(Hex.axial_to_offset(b.hex)), b.team, b.hq, b.rest,
			b.garrison.size(), JSON.stringify(s.squads[b.squad_index]) if b.squad_index >= 0 else "-"])
	bases.sort()
	var terrain: Array = []
	for row in s.rows:
		for col in s.cols:
			terrain.append(s.terrain_at(Hex.offset_to_axial(col, row)))
	return {
		"size": Vector2i(s.cols, s.rows), "turn_limit": s.turn_limit, "units": units, "bases": bases,
		"terrain": terrain, "events": s.pending_events().size(),
		"victory": JSON.stringify(s.victory_conditions), "defeat": JSON.stringify(s.defeat_conditions),
	}


## data/stages/ 以下のステージ（冒険譚マニフェストと地形ファイルは除く）。
func _stage_paths() -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(STAGES_ROOT):
		for f in DirAccess.get_files_at("%s/%s" % [STAGES_ROOT, sub]):
			if f.ends_with(".json") and f != "campaign.json" and not f.ends_with(StageLoader.TERRAIN_SUFFIX):
				out.append("%s/%s/%s" % [STAGES_ROOT, sub, f])
	return out


func _open(path: String) -> MapEditorDoc:
	return MapEditorDoc.from_text(FileAccess.get_file_as_string(path),
		FileAccess.get_file_as_string(StageLoader.terrain_path(path)))


# --- 実ステージの無編集の書き出し ---

func test_every_stage_exports_to_the_same_board() -> void:
	var paths := _stage_paths()
	assert_gt(paths.size(), 0, "前提：ステージが見つかる")
	for path in paths:
		var doc := _open(path)
		assert_not_null(doc, "%s を読める" % path)
		if doc == null:
			continue
		var original := StageLoader.read_stage(path)
		var exported := _exported(doc)
		var got := _fingerprint(_build(exported))
		var want := _fingerprint(_build(original))
		for k in want:
			assert_eq(got[k], want[k], "%s の %s" % [path, k])
		# 盤の外の見た目（presentation へ渡す分）も同じ
		assert_eq(StageLoader.parse_terrain_skins(exported), StageLoader.parse_terrain_skins(original),
			"%s の terrain_skins" % path)
		assert_eq(StageLoader.parse_margin_terrain(exported), StageLoader.parse_margin_terrain(original),
			"%s の外周" % path)
		assert_eq(StageLoader.parse_height_overrides(exported), StageLoader.parse_height_overrides(original),
			"%s の高さ上書き" % path)
		assert_eq(StageLoader.unit_id_problems(exported), [], "%s の unit_id が壊れない" % path)


# --- 編集したものの書き出し ---

func test_edited_stage_builds_with_the_edits() -> void:
	var doc := MapEditorDoc.new_stage(6, 4, 1)
	doc.set_terrain_char(2, 1, "F")    # 盤の中の森
	doc.set_terrain_char(-1, 0, "P")   # 外周の台地（盤には入らない）
	doc.set_terrain_skin(3, 2, "road")
	assert_true(doc.add_player("fighter", 1, 1), "前提：味方を置ける")
	var sq := doc.add_squad("charge", "本隊")
	assert_true(doc.add_enemy(sq, "goblin", 4, 2), "前提：敵を置ける")
	assert_true(doc.add_base(5, 3, "enemy", "enemy"), "前提：拠点を置ける")

	var data := _exported(doc)
	var s := _build(data)
	assert_eq(Vector2i(s.cols, s.rows), Vector2i(6, 4), "盤の広さは外周を除いた寸法")
	assert_eq(s.turn_limit, 30)
	assert_eq(s.terrain_at(Hex.offset_to_axial(2, 1)), "forest", "塗った森が盤に入る")
	assert_eq(s.terrain_at(Hex.offset_to_axial(0, 0)), "plain", "外周の台地は盤に入らない")
	assert_eq(String(StageLoader.parse_margin_terrain(data)[Hex.offset_to_axial(-1, 0)]), "plateau",
		"外周の台地は外周として読める")
	assert_eq(String(StageLoader.parse_terrain_skins(data)[Hex.offset_to_axial(3, 2)]), "road", "skin 指定が読める")

	var fighter := s.unit_at(Hex.offset_to_axial(1, 1))
	assert_not_null(fighter, "置いた味方が盤にいる")
	if fighter != null:
		assert_eq(fighter.team, 0)
		assert_eq(fighter.type_id, "fighter")
	var goblin := s.unit_at(Hex.offset_to_axial(4, 2))
	assert_not_null(goblin, "置いた敵が盤にいる")
	if goblin != null:
		assert_eq(goblin.team, 1)
		assert_eq(goblin.skin_id, "goblin")
		assert_eq(String(s.squad_of(goblin.handle).get("ai", "")), "charge", "部隊の特性が付く")
	assert_eq(s.bases().size(), 1, "置いた拠点が盤にある")
	if s.bases().size() == 1:
		assert_eq(s.bases()[0].hex, Hex.offset_to_axial(5, 3))
		assert_eq(s.bases()[0].team, 1)
