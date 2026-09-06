extends SceneTree
## main.gd 分割の検証（使い捨て）: 会話の進行が StoryDirector 経由でも同じに通るか。
## (1) intro＝盤ロック・情報板隠し・ターン終了無効→閉じると戻る (2)「ストーリーを確認」の読み直し
## ＝割り込む前のターン終了の可否へ戻る (3) デバッグ「イベントを起こす」で会話が挟まる
## (4) 勝利→票→outro→次ステージへ進む。冒険譚の文脈で開くので進捗・名簿・オートセーブの実ファイルを
## 触る＝呼ぶ側（シェル）で控えて戻す。
## 実行: godot --path . -s res://tests/manual/check_story_director.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const CAMPAIGN := "tutorial1-goblin-raid"
const ST1 := "res://data/stages/tutorial1-goblin-raid/st1.json"
const ST4 := "res://data/stages/tutorial1-goblin-raid/st4.json"
const LOG := "user://check_story_director.txt"

var _lines := PackedStringArray()

func _initialize() -> void:
	_run()

func _say(s: String) -> void:
	_lines.append(s)

func _state(main: Node, tag: String) -> void:
	var panel: Control = main.get_node("Front/InfoPanel")
	_say("%s: conv=%s phase=%s turn_btn=%s covered=%s board_locked=%s" % [tag, main._conversation.visible, main._story._phase,
		main._hud.player_turn_enabled(), panel._covered, main.get_node("HexBoard")._frozen])

func _menu(main: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var menu: PopupMenu = main._hud._story_menu
	for i in menu.item_count:
		out.append(menu.get_item_text(i))
	return out

func _run() -> void:
	await process_frame
	var main: Node = MAIN.instantiate()
	root.add_child(main)
	for f in 10:
		await process_frame
	main._title_pending = false
	main._title.visible = false
	main._select.close()
	# (1) intro
	main._context.campaign_id = CAMPAIGN
	main._context.stage_id = "st1"
	main.load_stage(ST1)
	for f in 5:
		await process_frame
	_state(main, "intro open")
	main._conversation._close()
	for f in 5:
		await process_frame
	_state(main, "intro closed")
	_say("story menu after start: %s" % [_menu(main)])
	# (2) 読み直し＝ターン終了を切った状態から入っても、閉じたらその状態へ戻る
	main._hud.set_player_turn(false)
	main._hud.story_requested.emit("intro")
	for f in 5:
		await process_frame
	_state(main, "review open")
	main._conversation._close()
	for f in 5:
		await process_frame
	_state(main, "review closed (turn_btn should stay false)")
	main._hud.set_player_turn(true)
	# (3) イベントの会話（デバッグ項目＝未発生イベントを起こす）
	main._context.stage_id = "st4"
	main.load_stage(ST4)
	for f in 5:
		await process_frame
	if main._conversation.visible:
		main._conversation._close()
	for f in 5:
		await process_frame
	var labels: PackedStringArray = main._debug_event_labels()
	_say("debug events: %s" % [labels])
	var idx := -1
	for i in labels.size():
		if labels[i].contains("会話"):
			idx = i
			break
	if idx >= 0:
		main._on_debug_event_requested(idx)
		for f in 120:
			await process_frame
		_state(main, "event open")
		_say("story menu after event: %s" % [_menu(main)])
		_say("debug labels while talking (should be empty): %s" % [main._debug_event_labels()])
		main._conversation._close()
		for f in 5:
			await process_frame
		_state(main, "event closed")
	# (4) 勝利→票→outro→次ステージ
	main._context.stage_id = "st1"
	main.load_stage(ST1)
	for f in 5:
		await process_frame
	main._conversation._close()
	for f in 5:
		await process_frame
	main._controller.wipe_enemies()
	for f in 240:
		await process_frame
	_say("result visible=%s" % main._result.visible)
	main._result._dismiss()
	for f in 30:
		await process_frame
	_state(main, "outro open")
	_say("story menu after clear: %s" % [_menu(main)])
	main._conversation._close()
	for f in 30:
		await process_frame
	_say("after outro: stage=%s path=%s conv=%s select=%s" % [main._context.stage_id, main._context.stage_path.get_file(), main._conversation.visible, main._select.visible])
	var log := FileAccess.open(LOG, FileAccess.WRITE)
	for l in _lines:
		log.store_line(l)
	log.close()
	quit(0)
