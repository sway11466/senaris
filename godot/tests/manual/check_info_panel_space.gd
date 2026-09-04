extends SceneTree
## 検証用（使い捨て）: Space が情報板の畳む／開くに割り当たり、ターン終了は Enter だけになったことを実測する。
## (1) Space で情報板の畳み状態が往復する (2) Space ではターンが進まない (3) Enter でターンが進む
## (4) AIターン中でも Space が効く。ラベル「情報板（Space）」のスクショも撮る（ja / en）。
## 実行: godot --path . -s res://tests/manual/check_info_panel_space.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/debug-ai/standoff.json"
const OUT := "res://tests/manual/out/info_panel_space_%s.png"
const LOG := "res://tests/manual/out/info_panel_space.txt"

var _lines := PackedStringArray()

func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_run()

func _run() -> void:
	await process_frame
	var main: Node = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	var locale0 := TranslationServer.get_locale()
	main._title.visible = false
	main.load_stage(STAGE)
	for f in 12:
		await process_frame
	var board = main.get_node("HexBoard")
	var panel = main.get_node("Front/InfoPanel")
	var state: BattleState = board.state
	var min0: bool = panel.is_minimized()
	for loc in ["ja", "en"]:
		TranslationServer.set_locale(loc)
		main._refresh_labels()
		await process_frame
		await _shot(OUT % loc)
		_lines.append("[%s] info_btn.text=%s rect=%s  gear.rect=%s" % [loc, main._hud._info_btn.text,
			Rect2(main._hud._info_btn.global_position, main._hud._info_btn.size), Rect2(main._hud._gear.global_position, main._hud._gear.size)])
	TranslationServer.set_locale(locale0)

	# (1)(2) Space: 畳み状態が往復し、ターンは進まない
	var team0 := state.current_team
	var turn0 := state.turn_number
	_key(KEY_SPACE)
	await _frames(2)
	_lines.append("space#1: minimized %s -> %s (期待 反転)  team=%d turn=%d ai=%s (期待 変化なし %d/%d/false)" % [min0, panel.is_minimized(), state.current_team, state.turn_number, board.controller.is_ai_turn(), team0, turn0])
	_key(KEY_SPACE)
	await _frames(2)
	_lines.append("space#2: minimized=%s (期待 %s＝元に戻る)" % [panel.is_minimized(), min0])

	# (3) Enter: ターンが進む（AIターンに入る）
	_key(KEY_ENTER)
	await _frames(3)
	var ai_now: bool = board.controller.is_ai_turn()
	_lines.append("enter: team=%d ai=%s (期待 team!=%d / ai=true)" % [state.current_team, ai_now, team0])

	# (4) AIターン中の Space
	if ai_now:
		var m: bool = panel.is_minimized()
		_key(KEY_SPACE)
		await _frames(2)
		_lines.append("space during AI: minimized %s -> %s (期待 反転)" % [m, panel.is_minimized()])
		_key(KEY_SPACE)
		await _frames(2)
	_lines.append("final minimized=%s (期待 %s＝設定に検証の値を残さない)" % [panel.is_minimized(), min0])
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	quit(0)

func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(path)
