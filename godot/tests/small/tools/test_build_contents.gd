extends GutTest
## BuildContents（tools/build/build_contents.gd）のテスト。
## 収録リストの項目の読み方と、冒険譚を途中まで収録するときの切り方（マニフェスト・ステージのファイル・
## クロニクル）が、除外フィルタ側と書き出しプラグイン側で同じ答えになることを守る。
## 仕様 → doc/tech/build.md 冒険譚の途中まで収録する

const MANIFEST := {
	"id": "camp",
	"title": "camp.title",
	"stages": [
		{ "id": "st1", "file": "camp-st1.json" },
		{ "id": "st2", "file": "camp-st2.json", "unlock": [ { "type": "cleared", "stage": "st1" } ], "roster_from": "st1" },
		{ "id": "st3", "file": "camp-st3.json", "unlock": [ { "type": "cleared", "stage": "st2" } ], "roster_from": "st2" },
		{ "id": "st4", "file": "camp-st4.json", "unlock": [ { "type": "cleared", "stage": "st3" } ], "roster_from": "st3" },
	],
}

const CHRONICLE := {
	"lore": [
		{ "id": "stage", "unlock": [] },
		{ "id": "enemy", "unlock": [ { "type": "cleared", "stage": "st2" } ] },
		{ "id": "origin", "unlock": [ { "type": "cleared", "stage": "st4" } ] },
		{ "id": "other", "unlock": [ { "type": "campaign_cleared", "campaign": "x" } ] },
	],
	"story": [
		{ "stage": "st1" },
		{ "stage": "st2", "events": ["a"] },
		{ "stage": "st3" },
		{ "stage": "st4" },
	],
}


# --- parse_entries（収録リストの項目） ---

func test_parse_entries_accepts_string_and_dict() -> void:
	var entries := BuildContents.parse_entries(["tut1", { "id": "camp", "through": "st2" }])
	assert_eq(entries.size(), 2)
	assert_eq(entries[0], { "id": "tut1", "through": "" }, "文字列＝まるごと")
	assert_eq(entries[1], { "id": "camp", "through": "st2" }, "辞書＝範囲付き")
	assert_eq(BuildContents.ranges_of(entries), { "tut1": "", "camp": "st2" })

func test_parse_entries_dict_without_through_is_whole() -> void:
	var entries := BuildContents.parse_entries([{ "id": "camp" }])
	assert_eq(entries, [{ "id": "camp", "through": "" }])

func test_parse_entries_rejects_broken_items() -> void:
	# 形の崩れた項目は []＝呼び手がビルドを止める（黙って捨てると出荷から落ちるだけで気づけない）。
	assert_eq(BuildContents.parse_entries([{ "through": "st2" }]), [], "id の無い辞書")
	assert_push_error("id が無い")
	assert_eq(BuildContents.parse_entries([42]), [], "数値")
	assert_push_error("文字列か辞書")
	assert_eq(BuildContents.parse_entries(["camp", "camp"]), [], "同じ冒険譚が2回")
	assert_push_error("2回ある")
	assert_eq(BuildContents.parse_entries("camp"), [], "配列でない")
	assert_push_error("配列でない")

# --- kept_stages / cut_stage_files（範囲の切り方） ---

func test_kept_stages_is_prefix_through_the_named_stage() -> void:
	assert_eq(BuildContents.kept_stage_ids(MANIFEST, "st2"), ["st1", "st2"])
	assert_eq(BuildContents.kept_stage_ids(MANIFEST, "st4"), ["st1", "st2", "st3", "st4"], "最後を指せば全部")
	assert_eq(BuildContents.kept_stage_ids(MANIFEST, ""), ["st1", "st2", "st3", "st4"], "through 空＝まるごと")

func test_kept_stages_unknown_through_is_empty() -> void:
	assert_eq(BuildContents.kept_stages(MANIFEST, "st9"), [], "無いステージ＝[]（黙って全部入れない）")
	assert_push_error("through 'st9'")

func test_cut_stage_files_pairs_body_and_terrain() -> void:
	var cut := BuildContents.cut_stage_files(MANIFEST, "st2")
	assert_eq(Array(cut), ["camp-st3.json", "camp-st3.terrain.json", "camp-st4.json", "camp-st4.terrain.json"])
	assert_eq(BuildContents.cut_stage_files(MANIFEST, "").size(), 0, "まるごと＝落とすものなし")
	assert_eq(BuildContents.cut_stage_files(MANIFEST, "st4").size(), 0, "最後まで＝落とすものなし")

func test_kept_stage_files_pairs_body_and_terrain() -> void:
	var kept := BuildContents.kept_stage_files(MANIFEST, "st2")
	assert_eq(Array(kept), ["camp-st1.json", "camp-st1.terrain.json", "camp-st2.json", "camp-st2.terrain.json"])

# --- stub_manifest（campaign.json の差し替え） ---

func test_stub_manifest_keeps_count_and_hollows_cut_stages() -> void:
	var out := BuildContents.stub_manifest(MANIFEST, "st2")
	var stages: Array = out["stages"]
	assert_eq(stages.size(), 4, "話の数は製品版と同じ")
	assert_eq(stages[1], MANIFEST["stages"][1], "範囲内はそのまま")
	assert_eq(stages[2], { "id": "st3", BuildContents.FULL_ONLY_KEY: true }, "範囲外は id と full_only だけの殻")
	assert_eq(stages[3], { "id": "st4", BuildContents.FULL_ONLY_KEY: true })
	assert_eq(out["title"], "camp.title", "他の欄はそのまま")
	assert_eq((MANIFEST["stages"] as Array)[2].size(), 4, "元の辞書は書き換えない")

func test_stub_manifest_whole_is_untouched() -> void:
	assert_eq(BuildContents.stub_manifest(MANIFEST, ""), MANIFEST, "まるごと＝元のまま")

func test_stub_manifest_unknown_through_is_empty() -> void:
	assert_eq(BuildContents.stub_manifest(MANIFEST, "st9"), {})
	assert_push_error("through 'st9'")

func test_stubbed_manifest_loads_with_full_only_stages() -> void:
	# 差し替えた中身を CampaignCatalog が読むと、殻は full_only の話として並び、鎖（unlock・roster_from）は切れていない。
	var c := CampaignCatalog.build(BuildContents.stub_manifest(MANIFEST, "st2"), "res://x")
	assert_eq(c["stages"].size(), 4)
	assert_false(c["stages"][1]["full_only"])
	assert_eq(c["stages"][1]["roster_from"], "st1")
	assert_true(c["stages"][2]["full_only"])
	assert_eq(c["stages"][2]["title"], "", "殻は題名を持たない")
	assert_eq(c["stages"][2]["path"], "", "殻はファイルを持たない")

# --- trim_chronicle（data/chronicle/<id>.json の差し替え） ---

func test_trim_chronicle_drops_cut_story_and_dependent_lore() -> void:
	var out := BuildContents.trim_chronicle(CHRONICLE, ["st1", "st2"])
	var story_ids: Array = []
	for e in out["story"]:
		story_ids.append(e["stage"])
	assert_eq(story_ids, ["st1", "st2"], "範囲外の story を削る")
	var lore_ids: Array = []
	for e in out["lore"]:
		lore_ids.append(e["id"])
	assert_eq(lore_ids, ["stage", "enemy", "other"], "範囲外のステージを条件に持つ lore だけ削る（stage を指さない条件は触らない）")
	assert_eq((CHRONICLE["story"] as Array).size(), 4, "元の辞書は書き換えない")

func test_trim_chronicle_with_all_stages_is_untouched() -> void:
	assert_eq(BuildContents.trim_chronicle(CHRONICLE, ["st1", "st2", "st3", "st4"]), CHRONICLE)

# --- 実データ: 収録リストの項目が全部読め、範囲付きなら through が実在する ---

func test_contents_json_entries_resolve() -> void:
	var editions := BuildContents.load_editions("res://tools/build/contents.json")
	assert_false(editions.is_empty(), "contents.json が読める")
	for e in editions:
		var entries := BuildContents.parse_entries(editions[e])
		assert_false(entries.is_empty(), "版 '%s' の項目が読める" % e)
		for entry in entries:
			var manifest := BuildContents.load_json("res://data/stages/%s/campaign.json" % entry["id"])
			assert_false(manifest.is_empty(), "版 '%s' の冒険譚 '%s' のマニフェストがある" % [e, entry["id"]])
			if not String(entry["through"]).is_empty():
				assert_false(BuildContents.kept_stages(manifest, entry["through"]).is_empty(),
						"版 '%s' の冒険譚 '%s' の through '%s' が実在" % [e, entry["id"], entry["through"]])
