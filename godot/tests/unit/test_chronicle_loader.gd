extends GutTest
## ChronicleLoader（chronicle.json 読み込み）のテスト。設定集・物語のマニフェストを
## CampaignCatalog（ゲーム進行）とは分離して読み込む。

func test_load_for_tutorial_has_lore() -> void:
	var data := ChronicleLoader.load_for("tutorial1-goblin-raid")
	assert_true(data["lore"].size() > 0, "tutorial1 は設定集の節を持つ")
	assert_eq(data["lore"][0]["id"], "stage", "先頭の節は stage")
	assert_eq(data["lore"][0]["unlock"], [], "stage は無条件解放")

func test_load_for_tutorial_has_story() -> void:
	var data := ChronicleLoader.load_for("tutorial1-goblin-raid")
	assert_true(data["story"].size() > 0, "tutorial1 は物語のステージを持つ")
	assert_eq(data["story"][0]["stage"], "goblin-raid-st1", "先頭のステージ")

func test_load_for_missing_returns_empty() -> void:
	var data := ChronicleLoader.load_for("nonexistent-campaign")
	assert_eq(data["lore"], [], "存在しない冒険譚は空")
	assert_eq(data["story"], [], "存在しない冒険譚は空")

func test_parse_lore_skips_invalid() -> void:
	# _parse_lore は static なので直接は呼べない。_parse 経由で検証する。
	# ChronicleLoader._parse を通して、不正エントリがスキップされることを確認。
	var data := ChronicleLoader._parse({
		"lore": [
			{ "id": "intro", "unlock": [] },
			{ "id": "secret", "unlock": [{ "type": "cleared", "stage": "s1" }] },
			"garbage",
			{ "file": "oops" },
		],
		"story": [],
	})
	assert_eq(data["lore"].size(), 2, "不正エントリはスキップ")
	assert_eq(data["lore"][0]["id"], "intro")
	assert_eq(data["lore"][1]["unlock"][0]["stage"], "s1")

func test_parse_story_skips_invalid() -> void:
	var data := ChronicleLoader._parse({
		"lore": [],
		"story": [
			{ "stage": "st1" },
			{ "stage": "st2", "events": ["ev1", "ev2"] },
			"garbage",
			{ "events": ["orphan"] },
		],
	})
	assert_eq(data["story"].size(), 2, "不正エントリはスキップ")
	assert_eq(data["story"][0]["stage"], "st1")
	assert_eq(data["story"][0]["events"], [], "events 未指定は空配列")
	assert_eq(data["story"][1]["events"].size(), 2)

func test_all_lore_unlock_refs_resolve() -> void:
	# chronicle.json の lore.unlock の参照先 stage が同じ冒険譚の campaign.json に実在する。
	var chronicles := ChronicleLoader.load_all()
	for campaign_id in chronicles:
		var chronicle: Dictionary = chronicles[campaign_id]
		var c := CampaignCatalog.load_file("res://data/stages/%s/campaign.json" % campaign_id)
		if c.is_empty():
			continue
		var stage_ids := {}
		for s in c["stages"]:
			stage_ids[s["id"]] = true
		for section in chronicle["lore"]:
			for cond in section["unlock"]:
				if typeof(cond) != TYPE_DICTIONARY:
					continue
				var ref := String(cond.get("stage", ""))
				if ref.is_empty():
					continue
				assert_true(stage_ids.has(ref), "%s/lore.%s の unlock 参照 '%s' が campaign.json に実在" % [campaign_id, section["id"], ref])

func test_lore_csv_matches_chronicle() -> void:
	# chronicle.json の設定集の節に対応する翻訳キーが lore.csv に在る。
	var chronicles := ChronicleLoader.load_all()
	for campaign_id in chronicles:
		var chronicle: Dictionary = chronicles[campaign_id]
		for section in chronicle["lore"]:
			var sid: String = section["id"]
			var title_key := "lore.%s.%s.title" % [campaign_id, sid]
			var title := TranslationServer.translate(title_key)
			assert_ne(title, title_key, "%s: 節 %s の title が翻訳にある" % [campaign_id, sid])
			var p1_key := "lore.%s.%s.1" % [campaign_id, sid]
			var p1 := TranslationServer.translate(p1_key)
			assert_ne(p1, p1_key, "%s: 節 %s の段落1が翻訳にある" % [campaign_id, sid])

func test_all_story_stages_exist_in_campaign() -> void:
	# chronicle.json の story.stage が同じ冒険譚の campaign.json に実在する。
	var chronicles := ChronicleLoader.load_all()
	for campaign_id in chronicles:
		var chronicle: Dictionary = chronicles[campaign_id]
		var c := CampaignCatalog.load_file("res://data/stages/%s/campaign.json" % campaign_id)
		if c.is_empty():
			continue
		var stage_ids := {}
		for s in c["stages"]:
			stage_ids[s["id"]] = true
		for entry in chronicle["story"]:
			var stage: String = entry["stage"]
			assert_true(stage_ids.has(stage), "%s/story の stage '%s' が campaign.json に実在" % [campaign_id, stage])
