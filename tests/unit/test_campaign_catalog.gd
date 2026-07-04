extends GutTest
## CampaignCatalog（冒険譚マニフェスト読み込み）のテスト。仕様 → doc/gdd/stage_select.md

func test_load_all_puts_debug_last() -> void:
	var all := CampaignCatalog.load_all()
	assert_true(all.size() >= 2, "tutorial と debug がある")
	var last: Dictionary = all[all.size() - 1]
	assert_true(last["debug"], "デバッグ冒険譚は末尾")
	assert_eq(last["id"], "debug")

func test_tutorial_manifest() -> void:
	var c := CampaignCatalog.load_file("res://data/stages/tutorial1-goblin-raid/campaign.json")
	assert_eq(c["id"], "tutorial1-goblin-raid")
	assert_false(c["debug"], "debug 未指定は false")
	assert_eq(c["stages"].size(), 5)
	assert_eq(c["stages"][0]["unlock"], [], "1面は無条件解放")
	assert_eq(c["stages"][1]["unlock"][0]["type"], "cleared")
	assert_eq(c["stages"][1]["unlock"][0]["stage"], "st1")
	assert_eq(c["stages"][1]["path"], "res://data/stages/tutorial1-goblin-raid/st2.json", "path はフォルダ＋file")

func test_all_manifest_stage_files_exist() -> void:
	# マニフェストが指す先のステージJSONが実在する（消し忘れ・打ち間違いの検出）
	for c in CampaignCatalog.load_all():
		for s in c["stages"]:
			assert_true(FileAccess.file_exists(s["path"]), "実在する: %s" % s["path"])

func test_build_rejects_broken() -> void:
	assert_eq(CampaignCatalog.build({}, "x"), {}, "id 無しは不正")
	assert_eq(CampaignCatalog.build({ "id": "a", "stages": "oops" }, "x"), {}, "stages が配列でないのは不正")

func test_build_skips_broken_stage_entries() -> void:
	var c := CampaignCatalog.build({
		"id": "a",
		"stages": [
			{ "id": "s1", "file": "s1.json" },
			{ "id": "", "file": "x.json" },
			"garbage",
		],
	}, "res://x")
	assert_eq(c["stages"].size(), 1, "壊れたエントリはスキップ")
	assert_eq(c["stages"][0]["title"], "s1", "title 未指定は id で代用")
