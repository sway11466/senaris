extends SceneTree
## feature-98 検証用（使い捨て）: 情報板を畳んだ状態の実機画面を撮る。
## main.tscn を起動し、ステージを読み、駒を選んでから HUD の「情報板」相当（toggle_minimized）で畳む。
## 撮ったあと開き直す＝設定ファイルに畳んだ状態を残さない。
## 実行: godot --path . -s res://tests/manual/shot_info_minimized.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/debug-mapops/event.json"
const OUT := "res://tests/manual/out/info_minimized.png"

func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
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
	var board: Node = main.get_node("HexBoard")
	board.set_process(false)
	var info: Node = main.get_node("Front/InfoPanel")
	info.toggle_minimized()  # 畳む（HUD の「情報板」ボタンと同じ経路）
	for f in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT)
	var minimized_now: bool = info.is_minimized()
	var hidden_now: bool = not info.visible
	info.toggle_minimized()  # 開き直す＝設定を元に戻す
	await process_frame
	var reopened: bool = info.visible and not info.is_minimized()
	var log := FileAccess.open("res://tests/manual/out/info_minimized.txt", FileAccess.WRITE)
	log.store_line("save=%d minimized=%s hidden=%s reopened=%s size=%s" % [err, minimized_now, hidden_now, reopened, img.get_size()])
	log.close()
	quit(0 if err == OK else 1)
