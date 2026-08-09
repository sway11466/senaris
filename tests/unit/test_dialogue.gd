extends GutTest
## 会話：StageLoader.parse_dialogue/load_dialogue（データ）と ConversationPanel（表示ロジック）。
## テキスト自体の翻訳は test_i18n.gd。

func test_parse_dialogue_reads_intro_outro() -> void:
	var d := StageLoader.parse_dialogue({
		"dialogue": {
			"intro": [ { "speaker": "a", "skin": "fighter", "text": "k1" } ],
			"outro": [ { "speaker": "b", "skin": "novice", "text": "k2" } ],
		}
	})
	assert_eq(d["intro"].size(), 1)
	assert_eq(d["outro"].size(), 1)
	assert_eq(String(d["intro"][0]["text"]), "k1", "行はそのまま渡す（キーは表示時に tr()）")

## intro/outro 以外のキーも読む＝イベント（events の "dialogue"）が名指しする戦闘中の台本。
func test_parse_dialogue_reads_event_scripts() -> void:
	var d := StageLoader.parse_dialogue({
		"dialogue": {
			"intro": [ { "speaker": "a", "skin": "fighter", "text": "k1" } ],
			"arrive": [ { "speaker": "b", "skin": "paladin", "text": "k2" } ],
		}
	})
	assert_eq(d["arrive"].size(), 1, "イベントの台本も台本キーで引ける")
	assert_eq(String(d["arrive"][0]["text"]), "k2")
	assert_true(d["outro"].is_empty(), "書かれていない前後の台本は空のまま")

## ステージのイベントが名指しする台本が、そのステージに在ること（キーの打ち間違い検出）。
func test_stage_event_dialogue_keys_exist() -> void:
	for path in _stage_paths("res://data/stages"):
		var text := FileAccess.get_file_as_string(path)
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var events: Variant = (data as Dictionary).get("events", [])
		if typeof(events) != TYPE_ARRAY:
			continue
		var scripts := StageLoader.parse_dialogue(data)
		for e in events:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var key := String((e as Dictionary).get("dialogue", ""))
			if key.is_empty():
				continue
			assert_true(scripts.has(key) and not (scripts[key] as Array).is_empty(),
				"%s: イベントの台本 '%s' が dialogue ブロックに在ること" % [path, key])

## data/stages 以下のステージJSONを全部集める（再帰）。
func _stage_paths(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for d in dir.get_directories():
		out.append_array(_stage_paths(dir_path.path_join(d)))
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(dir_path.path_join(f))
	return out

func test_parse_dialogue_absent_is_empty() -> void:
	var d := StageLoader.parse_dialogue({ "cols": 6 })
	assert_true(d["intro"].is_empty() and d["outro"].is_empty(), "dialogue 無しは空の intro/outro")

func test_load_dialogue_talk_stage() -> void:
	var d := StageLoader.load_dialogue("res://data/stages/debug-misc/talk.json")
	assert_eq(d["intro"].size(), 4, "talk.json の intro は4行")
	assert_eq(d["outro"].size(), 2, "talk.json の outro は2行")

func test_conversation_panel_reveals_then_closes() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	watch_signals(panel)
	var lines := [
		{ "speaker": "char.cap.name", "skin": "fighter", "text": "talk.intro.1" },
		{ "speaker": "char.rookie.name", "skin": "novice", "text": "talk.intro.2" },
	]
	panel.start(lines, "戦闘開始")
	assert_eq(panel._messages.get_child_count(), 1, "開始で1行目を表示")
	assert_true(panel.visible, "会話中は表示")
	panel._on_next()
	assert_eq(panel._messages.get_child_count(), 2, "次へで2行目を追加")
	panel._on_next()  # 最後まで読んだ後の「次へ」＝終了
	assert_signal_emitted(panel, "closed", "最後まで読むと closed")
	assert_false(panel.visible, "終了で非表示")

func test_conversation_panel_skip_closes_immediately() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	watch_signals(panel)
	panel.start([ { "speaker": "char.cap.name", "skin": "fighter", "text": "talk.intro.1" } ], "戦闘開始")
	panel._on_skip()
	assert_signal_emitted(panel, "closed", "スキップで即 closed")
	assert_false(panel.visible)

func test_conversation_panel_empty_closes() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	watch_signals(panel)
	panel.start([], "戦闘開始")
	assert_signal_emitted(panel, "closed", "空の会話は即 closed（フローを止めない）")
