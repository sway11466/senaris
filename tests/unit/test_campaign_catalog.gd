extends GutTest
## CampaignCatalog（冒険譚マニフェスト読み込み）のテスト。仕様 → doc/gdd/stage_select.md

func test_load_all_groups_debug_last() -> void:
	# デバッグ冒険譚（機能別に6分割）は本編の後ろへまとめて寄る。仕様 → doc/tech/debug-stages.md
	var all := CampaignCatalog.load_all()
	assert_true(all.size() >= 2, "tutorial と debug がある")
	# 一度 debug が現れたら以降はすべて debug（本編→デバッグの順で切れ目がある）。
	var seen_debug := false
	for c in all:
		if c["debug"]:
			seen_debug = true
		else:
			assert_false(seen_debug, "本編の冒険譚がデバッグ群より後ろに来ない: %s" % c["id"])
	assert_true(all[all.size() - 1]["debug"], "末尾はデバッグ冒険譚")
	# 6つの機能別デバッグ冒険譚がすべて存在する。
	var debug_ids := {}
	for c in all:
		if c["debug"]:
			debug_ids[c["id"]] = true
	for want in ["debug-combat", "debug-ai", "debug-victory", "debug-mapops", "debug-skins", "debug-misc"]:
		assert_true(debug_ids.has(want), "デバッグ冒険譚が存在: %s" % want)

func test_tutorial_manifest() -> void:
	var c := CampaignCatalog.load_file("res://data/stages/tutorial1-goblin-raid/campaign.json")
	assert_eq(c["id"], "tutorial1-goblin-raid")
	assert_false(c["debug"], "debug 未指定は false")
	assert_eq(c["difficulty"], 1, "星レーティング")
	assert_eq(c["tier"], "tutorial", "所属ボード")
	assert_eq(c["title"], "t1.title", "title は翻訳キー")
	assert_eq(c["desc"], "t1.desc", "desc は翻訳キー")
	assert_eq(c["stages"][0]["title"], "t1.st1.title", "stage.title も翻訳キー")
	assert_eq(c["stages"].size(), 7)
	assert_eq(c["stages"][0]["unlock"], [], "1面は無条件解放")
	assert_eq(c["stages"][1]["unlock"][0]["type"], "cleared")
	assert_eq(c["stages"][1]["unlock"][0]["stage"], "st1")
	assert_eq(c["stages"][1]["path"], "res://data/stages/tutorial1-goblin-raid/st2.json", "path はフォルダ＋file")

func test_all_manifest_stage_files_exist() -> void:
	# マニフェストが指す先のステージJSONが実在する（消し忘れ・打ち間違いの検出）
	for c in CampaignCatalog.load_all():
		for s in c["stages"]:
			assert_true(FileAccess.file_exists(s["path"]), "実在する: %s" % s["path"])

func test_all_unlock_refs_resolve() -> void:
	# 実データ: unlock の参照先 stage がすべて同じ冒険譚に実在する（打ち間違い・消し忘れの dangling 検出）。
	for c in CampaignCatalog.load_all():
		var ids := {}
		for s in c["stages"]:
			ids[s["id"]] = true
		for s in c["stages"]:
			for cond in s["unlock"]:
				if typeof(cond) != TYPE_DICTIONARY:
					continue
				var ref := String(cond.get("stage", ""))
				if ref.is_empty():
					continue  # stage を参照しない条件（entitlement 等）
				assert_true(ids.has(ref), "%s/%s の unlock 参照 '%s' が実在" % [c["id"], s["id"], ref])

func test_build_rejects_broken() -> void:
	assert_eq(CampaignCatalog.build({}, "x"), {}, "id 無しは不正")
	assert_eq(CampaignCatalog.build({ "id": "a", "stages": "oops" }, "x"), {}, "stages が配列でないのは不正")

func test_build_defaults_difficulty_and_desc() -> void:
	var c := CampaignCatalog.build({ "id": "a", "stages": [] }, "res://x")
	assert_eq(c["difficulty"], 0, "difficulty 未指定は 0")
	assert_eq(c["desc"], "", "desc 未指定は空文字")
	assert_eq(c["tier"], "rookie", "tier 未指定は rookie")

func test_build_clamps_difficulty() -> void:
	var c := CampaignCatalog.build({ "id": "a", "stages": [], "difficulty": 9 }, "res://x")
	assert_eq(c["difficulty"], 5, "0〜5 にクランプ")

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
