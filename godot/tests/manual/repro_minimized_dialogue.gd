extends SceneTree
## 使い捨ての実機検証：情報板を畳んだまま会話つきステージを開き、
## (1) 会話が出ない (2) 吹き出しが出る (3)「ストーリーを確認」の目次が埋まる、を測る。
## 結果は user://repro_minimized_dialogue.txt に書く（headless の print は出ないため）。
## 起動: godot --path . -s res://tests/manual/repro_minimized_dialogue.gd

const STAGE := "res://data/stages/tutorial1-goblin-raid/st4.json"
const OUT := "user://repro_minimized_dialogue.txt"

var _main: Node = null
var _lines: PackedStringArray = []
var _frames := 0
var _done := false

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_run()
	if _done:
		var f := FileAccess.open(OUT, FileAccess.WRITE)
		f.store_string("\n".join(_lines))
		return true
	return _frames > 600  # 保険＝進まなくてもハングさせない

func _run() -> void:
	var panel: Control = _main.get_node("Front/InfoPanel")
	var hud: Node = _main._hud
	_main._select.close()
	# 実機の設定ファイル（user://settings.json）を触るので、測り終えたら元の値へ戻す。
	var was_minimized: bool = _main._settings_store.info_panel_minimized()
	var was_mode: String = _main._settings_store.dialogue_when_minimized()
	panel.set_minimized(true)
	_main._settings_store.set_dialogue_when_minimized("hide")
	_main._current_campaign_id = "tutorial1-goblin-raid"
	_main._current_stage_id = "st4"
	_main.load_stage(STAGE)
	_say("intro を持つステージか: %s" % str(not _main._dialogue["intro"].is_empty()))
	_say("会話パネルが出ていない: %s" % str(not _main._conversation.visible))
	_say("情報板が畳まれたまま: %s" % str(panel.is_minimized() and not panel.visible))
	_say("吹き出しが出た: %s" % str(hud._badge.visible))
	_say("イベントの見出しを読めた: %s" % str(_main._event_talks))
	_say("目次: %s" % str(_menu_labels(hud)))
	# 会話を出す設定に切り替えて開き直すと、いつもどおり会話が出る。
	_main._settings_store.set_dialogue_when_minimized("show")
	_main.load_stage(STAGE)
	_say("show に変えると会話が出る: %s" % str(_main._conversation.visible))
	_main._settings_store.set_dialogue_when_minimized(was_mode)
	panel.set_minimized(was_minimized)
	_done = true

func _menu_labels(hud: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var menu: PopupMenu = hud._story_menu
	for i in menu.item_count:
		out.append(menu.get_item_text(i))
	return out

func _say(line: String) -> void:
	_lines.append(line)
