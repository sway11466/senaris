extends GutTest
## StageDigest（ステージ定義の印）のテスト。仕様 → doc/tech/gamesystem.md §ステージ更新の検出

func _stage() -> Dictionary:
	return {
		"name": "テスト平原",
		"cols": 6, "rows": 4, "turn_limit": 10, "haze": 0.35,
		"terrain": ["......", "..PP..", "......", "......"],
		"player": [{ "type": "archer", "col": 1, "row": 1 }],
		"bgm": { "main": "march" },
		"dialogue": { "intro": [{ "speaker": "a", "text": "b" }] },
		"backdrop": "sky1",
	}

func test_same_content_gives_the_same_digest() -> void:
	assert_eq(StageDigest.compute(_stage()), StageDigest.compute(_stage()), "同じ内容なら同じ印")
	assert_eq(StageDigest.compute(_stage()).length(), 64, "sha256 の16進文字列")

func test_key_order_does_not_matter() -> void:
	var reordered := {}
	var src := _stage()
	var keys := src.keys()
	keys.reverse()
	for k in keys:
		reordered[k] = src[k]
	assert_eq(StageDigest.compute(reordered), StageDigest.compute(_stage()), "書き並べ順では印が変わらない")

func test_json_roundtrip_does_not_change_the_digest() -> void:
	# 手元の dict（int）と JSON 往復後（float）で印が割れない＝ファイルから読んでも同じ印になる。
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(_stage()))
	assert_eq(StageDigest.compute(parsed), StageDigest.compute(_stage()))

func test_excluded_keys_do_not_change_the_digest() -> void:
	# 盤に効かないキー（name/dialogue/bgm/backdrop/haze）は印に入らない＝直しても通知は出ない。
	var base := StageDigest.compute(_stage())
	var edited := _stage()
	edited["name"] = "改題"
	edited["bgm"] = { "main": "requiem" }
	edited["backdrop"] = "cave1"
	edited["haze"] = 0.8
	edited["dialogue"] = {}
	assert_eq(StageDigest.compute(edited), base, "盤に効かないキーの変更で印は変わらない")

func test_board_affecting_change_changes_the_digest() -> void:
	var base := StageDigest.compute(_stage())
	var edited := _stage()
	edited["player"] = [{ "type": "archer", "col": 2, "row": 1 }]
	assert_ne(StageDigest.compute(edited), base, "盤に効く変更（駒の位置）で印が変わる")
	var added_key := _stage()
	added_key["height"] = { "row": [0, 0, 0, 1] }
	assert_ne(StageDigest.compute(added_key), base, "新しいキーは列挙にない限り印に入る＝通知側へ倒れる")

func test_unreadable_file_gives_no_digest() -> void:
	assert_eq(StageDigest.of_file("res://data/stages/no_such_stage.json"), "", "読めない＝印なし（不明として通知側へ）")
