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
	for want in ["debug-combat", "debug-ai", "debug-victory", "debug-map", "debug-skins", "debug-misc"]:
		assert_true(debug_ids.has(want), "デバッグ冒険譚が存在: %s" % want)

func test_tutorial_manifest() -> void:
	var c := CampaignCatalog.load_file("res://data/stages/tutorial1-goblin-raid/campaign.json")
	assert_eq(c["id"], "tutorial1-goblin-raid")
	assert_false(c["debug"], "debug 未指定は false")
	assert_eq(c["difficulty"], 1, "星レーティング")
	assert_eq(c["board"], "tutorial", "所属ボード")
	assert_eq(c["title"], "goblin-raid.title", "title は翻訳キー")
	assert_eq(c["desc"], "goblin-raid.desc", "desc は翻訳キー")
	assert_eq(c["stages"][0]["title"], "goblin-raid.st1.title", "stage.title も翻訳キー")
	assert_eq(c["stages"].size(), 7)
	assert_eq(c["stages"][0]["unlock"], [], "1面は無条件解放")
	assert_eq(c["stages"][1]["unlock"][0]["type"], "cleared")
	assert_eq(c["stages"][1]["unlock"][0]["stage"], "goblin-raid-st1")
	assert_eq(c["stages"][1]["path"], "res://data/stages/tutorial1-goblin-raid/goblin-raid-st2.json", "path はフォルダ＋file")

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
	assert_push_warning("マニフェストが不正")
	assert_eq(CampaignCatalog.build({ "id": "a", "stages": "oops" }, "x"), {}, "stages が配列でないのは不正")
	assert_push_warning("マニフェストが不正")

func test_build_defaults_difficulty_and_desc() -> void:
	var c := CampaignCatalog.build({ "id": "a", "stages": [] }, "res://x")
	assert_eq(c["difficulty"], 0, "difficulty 未指定は 0")
	assert_eq(c["desc"], "", "desc 未指定は空文字")
	assert_eq(c["board"], "", "board 未指定は空＝どのボードにも出ない（既定値で拾わない）")
	assert_push_warning("board 未指定")

func test_build_debug_needs_no_board() -> void:
	# デバッグ冒険譚は debug:true が Debug ボード行きを決める＝board を書かず、警告も出ない。
	var c := CampaignCatalog.build({ "id": "a", "debug": true, "stages": [] }, "res://x")
	assert_eq(c["board"], "", "debug は board を持たない")

func test_build_defaults_actor_lineup() -> void:
	var c := CampaignCatalog.build({ "id": "a", "stages": [] }, "res://x")
	assert_eq(c["actor_lineup"], "", "actor_lineup 未指定は空＝スキン任せ")
	assert_push_warning("board 未指定")

func test_build_actor_lineup_single() -> void:
	var c := CampaignCatalog.build({ "id": "a", "board": "b", "stages": [], "actor_lineup": "single" }, "res://x")
	assert_eq(c["actor_lineup"], "single")

func test_build_actor_lineup_rejects_unknown() -> void:
	var c := CampaignCatalog.build({ "id": "a", "board": "b", "stages": [], "actor_lineup": "bogus" }, "res://x")
	assert_eq(c["actor_lineup"], "", "未知の値は空に倒す")

func test_build_clamps_difficulty() -> void:
	var c := CampaignCatalog.build({ "id": "a", "board": "b", "stages": [], "difficulty": 9 }, "res://x")
	assert_eq(c["difficulty"], 5, "0〜5 にクランプ")

func test_build_skips_broken_stage_entries() -> void:
	var c := CampaignCatalog.build({
		"id": "a",
		"board": "b",
		"stages": [
			{ "id": "s1", "file": "s1.json" },
			{ "id": "", "file": "x.json" },
			"garbage",
		],
	}, "res://x")
	assert_push_warning("stage の id/file が空")
	assert_push_warning("stage エントリが辞書でない")
	assert_eq(c["stages"].size(), 1, "壊れたエントリはスキップ")
	assert_eq(c["stages"][0]["title"], "s1", "title 未指定は id で代用")

func test_tutorial3_roster_from() -> void:
	# 継承の冒険譚は各ステージが名簿の引き継ぎ元を持つ（doc/gdd/stage_select.md 冒険譚マニフェスト）。
	var c := CampaignCatalog.load_file("res://data/stages/tutorial3-dragon-hunt/campaign.json")
	assert_eq(c["stages"][0]["roster_from"], "", "1面は引き継ぎ元なし＝空の名簿で始める")
	assert_eq(c["stages"][1]["roster_from"], "dragon-hunt-st1", "2面は1面のクリア後の名簿で始める")

func test_build_defaults_roster_from_to_empty() -> void:
	var c := CampaignCatalog.build({ "id": "x", "board": "tutorial",
		"stages": [ { "id": "s1", "file": "s1.json" } ] }, "res://x")
	assert_eq(c["stages"][0]["roster_from"], "", "未指定は空文字")

func test_build_defaults_interlude_to_empty() -> void:
	var c := CampaignCatalog.build({ "id": "x", "board": "tutorial",
		"stages": [ { "id": "s1", "file": "s1.json" } ] }, "res://x")
	assert_eq(c["stages"][0]["interlude"], "", "未指定は空＝印なし（連戦・独立）")

func test_build_interlude_three_values() -> void:
	var c := CampaignCatalog.build({ "id": "x", "board": "tutorial", "stages": [
		{ "id": "s1", "file": "s1.json" },
		{ "id": "s2", "file": "s2.json", "interlude": "damaged" },
		{ "id": "s3", "file": "s3.json", "interlude": "refill" },
		{ "id": "s4", "file": "s4.json", "interlude": "revive" } ] }, "res://x")
	assert_eq(c["stages"][1]["interlude"], "damaged", "連戦")
	assert_eq(c["stages"][2]["interlude"], "refill", "休息")
	assert_eq(c["stages"][3]["interlude"], "revive", "復帰")

func test_build_interlude_rejects_unknown() -> void:
	var c := CampaignCatalog.build({ "id": "x", "board": "tutorial",
		"stages": [ { "id": "s1", "file": "s1.json", "interlude": "rest" } ] }, "res://x")
	assert_eq(c["stages"][0]["interlude"], "", "未知の値は印なしに倒す（旧 rest は refill へ改名済み）")
	assert_push_warning("interlude")

func test_build_reads_synopsis() -> void:
	var c := CampaignCatalog.build({ "id": "x", "board": "tutorial",
		"stages": [ { "id": "s1", "file": "s1.json", "synopsis": "x.st1.synopsis" } ] }, "res://x")
	assert_eq(c["stages"][0]["synopsis"], "x.st1.synopsis", "あらすじの翻訳キーをそのまま持つ")

func test_build_warns_missing_synopsis() -> void:
	# 全ステージに書く決まり＝書き忘れは警告で拾う（既定値で黙って埋めない）。
	var c := CampaignCatalog.build({ "id": "x", "board": "tutorial",
		"stages": [ { "id": "s1", "file": "s1.json" } ] }, "res://x")
	assert_eq(c["stages"][0]["synopsis"], "", "無ければ空")
	assert_push_warning("synopsis")

func test_tutorial3_interlude() -> void:
	# 竜狩りは st2 以降の全話が名簿の駒に refill を書く＝全部の前が休息（doc/campaign/tutorial3-dragon-hunt.md）。
	var c := CampaignCatalog.load_file("res://data/stages/tutorial3-dragon-hunt/campaign.json")
	assert_eq(c["stages"][0]["interlude"], "", "1面の前に幕間は無い")
	for i in range(1, c["stages"].size()):
		assert_eq(c["stages"][i]["interlude"], "refill", "%s の前は休息" % c["stages"][i]["id"])

func test_all_roster_from_refs_resolve() -> void:
	# 実データ: roster_from の参照先 stage が同じ冒険譚に実在する（dangling だと仲間が黙って出てこない）。
	for c in CampaignCatalog.load_all():
		var ids := {}
		for s in c["stages"]:
			ids[s["id"]] = true
		for s in c["stages"]:
			var ref: String = s["roster_from"]
			if not ref.is_empty():
				assert_true(ids.has(ref), "%s/%s の roster_from '%s' が実在" % [c["id"], s["id"], ref])
