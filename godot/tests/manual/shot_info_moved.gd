extends SceneTree
## feature-98 検証用（使い捨て）: 情報板を掴んで動かし、設定への保存と「位置を戻す」を確かめる。
## main.tscn を起動し、板の木の地（ボタンの無い所）を合成マウスイベントで押して引きずって離す。
## 撮ったあと「情報板の位置を戻す」を通す＝設定ファイルに動かした位置を残さない。
## 実行: godot --path . -s res://tests/manual/shot_info_moved.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/debug-mapops/event.json"
const OUT := "res://tests/manual/out/info_moved.png"
const LOG := "res://tests/manual/out/info_moved.txt"

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var main: Node = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	TranslationServer.set_locale("en")
	main._refresh_labels()
	main._title.visible = false
	main.load_stage(STAGE)
	for f in 12:
		await process_frame
	var unit: Variant = main._controller.state.unit_at(Hex.offset_to_axial(1, 3))
	if unit != null:
		main.get_node("HexBoard")._select(unit.id)
	main.get_node("HexBoard").set_process(false)
	await process_frame
	var info: Control = main.get_node("Front/InfoPanel")
	var before: Vector2 = info.position
	# 板の木の地＝中身の空きの所（1280×720 の論理座標。板は x=800..1264 / y=96..704）
	_button(Vector2(1000, 600), true)
	await process_frame
	_motion(Vector2(850, 500))
	await process_frame
	_motion(Vector2(700, 400))
	await process_frame
	var during: Vector2 = info.position
	_button(Vector2(700, 400), false)
	await process_frame
	var after: Vector2 = info.position
	var store := SettingsStore.new()  # user://settings.json を読み直す
	var saved_has: bool = store.has_info_panel_position()
	var saved: Vector2 = store.info_panel_position()
	for f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT)
	main._on_info_panel_reset_requested()
	await process_frame
	var reset_pos: Vector2 = info.position
	var cleared: bool = not SettingsStore.new().has_info_panel_position()
	var log := FileAccess.open(LOG, FileAccess.WRITE)
	log.store_line("save=%d before=%s during=%s after=%s saved_has=%s saved=%s reset=%s cleared=%s" % [
		err, before, during, after, saved_has, saved, reset_pos, cleared])
	log.close()
	quit(0 if err == OK else 1)

func _button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(ev)

func _motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev)
