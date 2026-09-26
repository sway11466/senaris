extends GutTest
## StageLoader の parse 系（ステージ辞書 → 値。ファイルを読まない）と検査のテスト。
## ファイルを読む load_* は tests/medium/application/test_stage_loader_load.gd。

# --- 靄（haze）。必須＝書き忘れはデータのバグ。詳細 → doc/tech/combat_scene.md ---

func test_parse_haze_reads_number() -> void:
	assert_almost_eq(StageLoader.parse_haze({ "haze": 0.35 }, "x.json"), 0.35, 0.0001, "小数をそのまま")
	assert_almost_eq(StageLoader.parse_haze({ "haze": 1 }, "x.json"), 1.0, 0.0001, "整数でも読む（JSON の 1）")

func test_parse_haze_clamps_to_unit_range() -> void:
	assert_almost_eq(StageLoader.parse_haze({ "haze": 1.5 }, "x.json"), 1.0, 0.0001, "1 を超えたら 1")
	assert_almost_eq(StageLoader.parse_haze({ "haze": -0.2 }, "x.json"), 0.0, 0.0001, "負は 0")

func test_parse_haze_missing_is_error() -> void:
	assert_almost_eq(StageLoader.parse_haze({}, "x.json"), 0.0, 0.0001, "書いていなければ 0 に倒す")
	assert_push_error("haze（0〜1 の数値）は必須")

func test_parse_haze_non_number_is_error() -> void:
	assert_almost_eq(StageLoader.parse_haze({ "haze": "0.5" }, "x.json"), 0.0, 0.0001, "文字列は数値として読まない")
	assert_push_error("haze（0〜1 の数値）は必須")

# --- 依頼書（出撃前の紙）。詳細 → doc/gdd/stage_select.md 依頼書 ---

func test_parse_briefing_bundles_party_and_carryover() -> void:
	var data := { "player": [ { "units": [
		{ "col": 1, "row": 1, "actor": "c.hero", "supply": "join" },
		{ "col": 2, "row": 1 },
	] } ] }
	var got := StageLoader.parse_briefing(data)
	assert_eq(got["party"], StageLoader.preview_player_units(data), "顔ぶれは preview_player_units と同じ")
	assert_eq((got["party"] as Array).size(), 2)
	assert_true(bool(got["carryover"]), "actor を持つ駒が居る＝継承のステージ")

func test_parse_briefing_independent_stage() -> void:
	var got := StageLoader.parse_briefing({ "player": [ { "units": [ { "col": 1, "row": 1 } ] } ] })
	assert_false(bool(got["carryover"]), "actor が無い＝独立のステージ")

func test_parse_briefing_empty_stage() -> void:
	var got := StageLoader.parse_briefing({})
	assert_eq(got["party"], [], "駒が無ければ空")
	assert_false(bool(got["carryover"]))

# --- 駒の名前（unit_id）の検査。詳細 → doc/gdd/map.md 駒を指す名前 ---

func test_check_unit_ids_clean_data_is_silent() -> void:
	var data := {
		"player": [ { "units": [ { "col": 0, "row": 0, "unit_id": "hero" } ] } ],
		"enemy": [ { "units": [ { "col": 3, "row": 3, "unit_id": "boss" } ] } ],
		"victory": [ { "type": "defeat_unit", "unit_ids": ["boss"] } ],
		"defeat": [ { "type": "lose_unit", "unit_ids": ["hero"] } ],
	}
	StageLoader.check_unit_ids(data, "x.json")
	assert_push_error_count(0, "問題が無ければ何も出さない")

func test_check_unit_ids_reports_each_problem_with_path() -> void:
	var data := {
		"player": [ { "units": [ { "col": 0, "row": 0, "unit_id": "hero" } ] } ],
		"enemy": [ { "units": [
			{ "col": 3, "row": 3, "unit_id": "hero" },  # 重複
		] } ],
		"victory": [ { "type": "defeat_unit", "unit_ids": ["ghost"] } ],  # 盤に無い
	}
	StageLoader.check_unit_ids(data, "res://x/stage.json")
	# 重複と不在をそれぞれ1行ずつ、どのステージかをパスで添える（宣言の無い push_error は GUT が落とす＝数もこれで決まる）。
	assert_push_error("'hero' がステージ内で重複（＝データのバグ）: res://x/stage.json")
	assert_push_error("'ghost' の駒が盤に無い（＝データのバグ）: res://x/stage.json")
