extends GutTest
## 会話板を掴める場所（doc/gdd/uiux.md 移動）。板は1枚＝情報板と同じく、ボタン以外の
## どこを押して引きずっても板が動く。吹き出し・顔・ト書きが押下を吸ってはいけない。
##
## Godot の Control は mouse_filter の既定が STOP＝明示的に PASS/IGNORE を入れていない子は
## 押下を吸い、その矩形の上では板を掴めなくなる（ScrollContainer・PanelContainer が該当）。

var panel: ConversationPanel

func before_each() -> void:
	panel = ConversationPanel.new()
	panel.bind({})
	add_child_autofree(panel)
	await get_tree().process_frame  # _ready で中身が組まれる
	panel.start([
		{ "speaker": "x.a", "skin": "fighter", "text": "x.1" },
		{ "text": "x.sfx" },
		{ "speaker": "x.b", "skin": "archer", "text": "x.2" },
	], "ui.talk.start_battle", "ui.talk.skip")
	panel._reveal_next()
	panel._reveal_next()
	await get_tree().process_frame

## 押下を吸う子（mouse_filter == STOP）を集める。
func _stoppers(node: Node, found: Array) -> Array:
	for c in node.get_children():
		if c is Control and (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			found.append(c)
		_stoppers(c, found)
	return found

func test_only_buttons_swallow_presses() -> void:
	for c in _stoppers(panel, []):
		var src := c.get_script() as Script
		var who: String = src.resource_path.get_file() if src != null else c.get_class()
		assert_is(c, Button, "板の上で押下を吸ってよいのはスキップ・次へだけ（%s）" % who)

func test_the_walk_actually_sees_the_buttons() -> void:
	# 上のテストが空振り（子を1つも辿れていない）で通るのを防ぐ見張り。
	assert_gt(_stoppers(panel, []).size(), 0, "スキップ・次への Button は見つかる")

func test_lines_are_on_the_board() -> void:
	# 吹き出しが実際に組まれてから走査していることの見張り（start が空振りなら上の検査は意味を持たない）。
	assert_gt(panel._messages.get_child_count(), 0, "吹き出しの行が板に載っている")
