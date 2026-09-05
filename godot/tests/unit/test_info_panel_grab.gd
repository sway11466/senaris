extends GutTest
## 情報板を掴める場所（doc/gdd/uiux.md 移動）。
## 「タブ・ページャーの上は押下として効き、それ以外はどこを押して引きずっても板が動く」を守る。
##
## Godot の Control は mouse_filter の既定が STOP＝明示的に IGNORE を入れていない子は押下を吸い、
## その矩形の上では板を掴めなくなる。板いっぱいに広がるレポートで一度これを踏んでいる。

var panel: UnitInfoPanel

func before_each() -> void:
	panel = UnitInfoPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame  # _ready で中身が組まれる

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
		assert_is(c, Button, "板の上で押下を吸ってよいのはタブ・ページャーだけ（%s）" % who)

func test_the_walk_actually_sees_the_tabs() -> void:
	# 上のテストが空振り（子を1つも辿れていない）で通るのを防ぐ見張り。
	assert_gt(_stoppers(panel, []).size(), 0, "タブ・ページャーの Button は見つかる")
