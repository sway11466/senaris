extends GutTest
## 会話板（ConversationPanel）の表示ロジック＝1行ずつ出す・効果音の行・スキップ・終了。
## 会話データの解析は tests/medium/application/test_dialogue.gd。

func test_conversation_panel_reveals_then_closes() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	watch_signals(panel)
	var lines := [
		{ "speaker": "char.cap.name", "skin": "fighter", "text": "talk.intro.1" },
		{ "speaker": "char.rookie.name", "skin": "novice", "text": "talk.intro.2" },
	]
	panel.start(lines, "戦闘開始", "ui.talk.skip")
	assert_eq(panel._messages.get_child_count(), 1, "開始で1行目を表示")
	assert_true(panel.visible, "会話中は表示")
	panel._on_next()
	assert_eq(panel._messages.get_child_count(), 2, "次へで2行目を追加")
	panel._on_next()  # 最後まで読んだ後の「次へ」＝終了
	assert_signal_emitted(panel, "closed", "最後まで読むと closed")
	assert_false(panel.visible, "終了で非表示")

## 効果音の行（話者なし）＝1行として表示され、前後の話者の左右交互を崩さない。
func test_conversation_panel_sound_line_is_shown_without_speaker() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	var lines := [
		{ "speaker": "char.cap.name", "skin": "fighter", "text": "talk.intro.1" },
		{ "text": "talk.intro.sfx", "sfx": "slash_m" },
		{ "speaker": "char.rookie.name", "skin": "novice", "text": "talk.intro.2" },
	]
	panel.start(lines, "戦闘開始", "ui.talk.skip")
	panel._on_next()
	assert_eq(panel._messages.get_child_count(), 2, "効果音の行も1行として表示される")
	assert_eq(panel._speakers, 1, "効果音の行は左右交互の順番を消費しない")
	panel._on_next()
	assert_eq(panel._speakers, 2, "続く話者は2人目＝右側（挟んでも左右が入れ替わらない）")

## 表示するものが無い行（音だけ）は「次へ」を消費せず、続けて次の行まで進める。
func test_conversation_panel_sound_only_line_advances() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	var lines := [
		{ "sfx": "slash_m" },
		{ "speaker": "char.cap.name", "skin": "fighter", "text": "talk.intro.1" },
	]
	panel.start(lines, "戦闘開始", "ui.talk.skip")
	assert_eq(panel._messages.get_child_count(), 1, "音だけの行は表示を持たず、次の行まで進む")
	assert_eq(panel._shown, 2, "2行とも消費済み")

func test_conversation_panel_skip_closes_immediately() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	watch_signals(panel)
	panel.start([ { "speaker": "char.cap.name", "skin": "fighter", "text": "talk.intro.1" } ], "戦闘開始", "ui.talk.skip")
	panel._on_skip()
	assert_signal_emitted(panel, "closed", "スキップで即 closed")
	assert_false(panel.visible)

func test_conversation_panel_empty_closes() -> void:
	var panel = preload("res://presentation/ui/conversation_panel.gd").new()
	add_child_autofree(panel)
	panel.bind({})
	watch_signals(panel)
	panel.start([], "戦闘開始", "ui.talk.skip")
	assert_signal_emitted(panel, "closed", "空の会話は即 closed（フローを止めない）")
