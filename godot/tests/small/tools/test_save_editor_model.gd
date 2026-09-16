extends GutTest
## SaveEditorModel（tools/save_editor/save_editor_model.gd）のテスト。
## セーブエディタが名簿の候補をどう集めるか（roster_from の鎖・player と拠点の控え）と、
## クロニクルの「全部ON」が並べる全スキン・全レシピの定義を固定する。仕様 → doc/backlog.md feature-130

const T3 := "res://data/stages/tutorial3-dragon-hunt/campaign.json"

func _manifest(stages: Array) -> Dictionary:
	return { "id": "camp", "stages": stages }

func test_roster_chain_follows_roster_from_root_first() -> void:
	var c := _manifest([
		{ "id": "s1", "roster_from": "" },
		{ "id": "s2", "roster_from": "s1" },
		{ "id": "s3", "roster_from": "s2" },
		{ "id": "side", "roster_from": "s1" },
	])
	var ids: Array = []
	for s in SaveEditorModel.roster_chain(c, "s3"):
		ids.append(s["id"])
	assert_eq(ids, ["s1", "s2", "s3"], "root が先・自分が最後")
	ids.clear()
	for s in SaveEditorModel.roster_chain(c, "side"):
		ids.append(s["id"])
	assert_eq(ids, ["s1", "side"], "分岐は自分の引き継ぎ元だけをたどる")
	assert_eq(SaveEditorModel.roster_chain(c, "s1").size(), 1, "引き継ぎ元が無ければ自分だけ")
	assert_eq(SaveEditorModel.roster_chain(c, "nope"), [], "無いステージは空")

func test_roster_chain_stops_on_cycle() -> void:
	var c := _manifest([{ "id": "a", "roster_from": "b" }, { "id": "b", "roster_from": "a" }])
	assert_eq(SaveEditorModel.roster_chain(c, "a").size(), 2, "輪になっていても止まる")

func test_actor_pieces_collects_player_and_garrison() -> void:
	var data := {
		"player": [ { "units": [
			{ "type": "fighter", "actor": "hero", "col": 0, "row": 0 },
			{ "type": "fighter", "col": 1, "row": 0 },  # 名前なし＝対象外
		] } ],
		"bases": [ { "col": 3, "row": 3, "garrison": [ { "type": "dwarf", "actor": "dwarf", "native": "neutral" } ] } ],
	}
	var pieces := SaveEditorModel.actor_pieces(data)
	assert_eq(pieces.size(), 2)
	assert_eq(pieces[0]["actor"], "hero")
	assert_eq(pieces[1]["actor"], "dwarf", "拠点の控え（勧誘対象）も候補")

func test_candidates_dedupes_by_first_appearance_and_resolves_max_troops() -> void:
	var catalog := UnitCatalog.load_default()
	var skins := SkinCatalog.load_standard()
	var s1 := { "player": [ { "units": [ { "type": "fighter", "actor": "a", "supply": "join" } ] } ] }
	var s2 := { "player": [ { "units": [
			{ "type": "archer", "actor": "b", "supply": "join" },
			{ "type": "fighter", "actor": "a", "supply": "refill" },
		] } ],
		"bases": [ { "garrison": [ { "type": "dwarf", "actor": "d", "native": "neutral" } ] } ] }
	var cands := SaveEditorModel.candidates([s1, s2], catalog, skins)
	var actors: Array = []
	for c in cands:
		actors.append(c["actor"])
	assert_eq(actors, ["a", "b", "d"], "初登場の順・重複なし")
	assert_eq(cands[0]["max_troops"], (catalog["fighter"] as UnitType).max_troops, "満員値は性能表から")
	assert_eq(cands[0]["skin"], "fighter", "skin 省略は type を入れる")

func test_candidates_drops_unresolvable_type_with_warning() -> void:
	var cands := SaveEditorModel.candidates(
			[ { "player": [ { "units": [ { "type": "no_such_type", "actor": "x" } ] } ] } ],
			UnitCatalog.load_default(), SkinCatalog.load_standard())
	assert_eq(cands, [], "性能を引けない駒は候補にしない")
	assert_push_warning("性能を引けない")

func test_candidates_for_tutorial3_includes_recruits_of_passed_stages() -> void:
	# 竜狩り：ドワーフは st3 の中立拠点、エルフは st4 の中立拠点。st3 の候補にエルフは居ない。
	var c := CampaignCatalog.load_file(T3)
	var catalog := UnitCatalog.load_default()
	var skins := SkinCatalog.load_standard()
	var st3: Array = []
	for cand in SaveEditorModel.candidates_for(c, "dragon-hunt-st3", catalog, skins):
		st3.append(cand["actor"])
	assert_true(st3.has("fighter"), "st1 の仲間")
	assert_true(st3.has("pixie"), "st3 で合流")
	assert_true(st3.has("dwarf"), "st3 の勧誘対象")
	assert_false(st3.has("elf"), "st4 の勧誘対象はまだ居ない")
	var st4: Array = []
	for cand in SaveEditorModel.candidates_for(c, "dragon-hunt-st4", catalog, skins):
		st4.append(cand["actor"])
	assert_true(st4.has("elf"), "st4 の候補にはエルフが入る")

func test_roster_entry_clamps_values() -> void:
	var cand := { "actor": "a", "type": "fighter", "skin": "fighter", "max_troops": 8 }
	var e := SaveEditorModel.roster_entry(cand, 0, 99)
	assert_eq(e["level"], 1, "Lv は 1 以上")
	assert_eq(e["troops"], 8, "兵数は満員まで")
	assert_eq(SaveEditorModel.roster_entry(cand, 3, -1)["troops"], 0, "兵数は 0 以上")
	assert_eq(e.keys().size(), 6, "Unit.to_dict と同じ6項目")

func test_formation_recipe_ids_exclude_unit_skills() -> void:
	var ids := SaveEditorModel.formation_recipe_ids()
	assert_gt(ids.size(), 0)
	for id in ids:
		assert_false(Formation.is_unit_skill(id), "ユニットスキル（solo）は陣形スキルの章に並ばない: %s" % id)
	assert_lt(ids.size(), Formation.RECIPES.size(), "solo を除いている")

func test_all_skin_ids_matches_skin_table() -> void:
	var skins := SkinCatalog.load_standard()
	var ids := SaveEditorModel.all_skin_ids(skins)
	assert_eq(ids.size(), (skins[SkinCatalog.BY_ID_KEY] as Dictionary).size(), "スキン表の全行")
