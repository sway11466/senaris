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

func test_parse_dialogue_absent_is_empty() -> void:
	var d := StageLoader.parse_dialogue({ "cols": 6 })
	assert_true(d["intro"].is_empty() and d["outro"].is_empty(), "dialogue 無しは空の intro/outro")

func test_load_dialogue_talk_stage() -> void:
	var d := StageLoader.load_dialogue("res://data/stages/debug/talk.json")
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
