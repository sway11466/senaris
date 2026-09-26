extends GutTest
## 会話：StageLoader.parse_dialogue/load_dialogue（データ）。表示ロジック（ConversationPanel）は
## tests/medium/presentation/test_conversation_panel.gd。テキスト自体の翻訳は test_i18n.gd。

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
		if f.ends_with(".json") and not f.ends_with(StageLoader.TERRAIN_SUFFIX):
			out.append(dir_path.path_join(f))
	return out

func test_parse_dialogue_absent_is_empty() -> void:
	var d := StageLoader.parse_dialogue({ "cols": 6 })
	assert_true(d["intro"].is_empty() and d["outro"].is_empty(), "dialogue 無しは空の intro/outro")

func test_load_dialogue_talk_stage() -> void:
	var d := StageLoader.load_dialogue("res://data/stages/debug-misc/talk.json")
	assert_eq(d["intro"].size(), 4, "talk.json の intro は4行")
	assert_eq(d["outro"].size(), 2, "talk.json の outro は2行")

## 「ストーリーを確認」の目次＝会話つきイベントの索引（doc/gdd/uiux.md ターン終了・システムメニュー）。
func test_parse_event_talks_indexes_events_with_dialogue() -> void:
	var talks := StageLoader.parse_event_talks({
		"name": "goblin-raid-st4",
		"events": [
			{ "id": "town-freed", "type": "capture", "dialogue": "free" },
			{ "id": "airship", "type": "turn" },
		]
	})
	assert_eq(talks.size(), 1, "会話を持たないイベントは目次に出さない")
	assert_eq(String(talks["town-freed"]["dialogue"]), "free", "読み直す台本のキーを引ける")
	assert_eq(String(talks["town-freed"]["name"]), "event.goblin-raid-st4.town-freed.name",
		"見出しはステージ id とイベント id からの規約キー（JSON には書かない）")

func test_parse_event_talks_skips_events_without_id() -> void:
	var talks := StageLoader.parse_event_talks({
		"name": "goblin-raid-st4",
		"events": [ { "type": "capture", "dialogue": "free" } ]
	})
	assert_eq(talks, {}, "id が無ければ記録と突き合わせられない（欠落は _apply_events が知らせる）")

func test_parse_event_talks_needs_the_stage_id() -> void:
	var talks := StageLoader.parse_event_talks({
		"events": [ { "id": "town-freed", "type": "capture", "dialogue": "free" } ]
	})
	assert_push_error("ステージの name")
	assert_eq(talks, {}, "ステージ id が無ければ規約キーを組めない")
