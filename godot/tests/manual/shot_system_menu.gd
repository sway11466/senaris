extends SceneTree
## 検証用（使い捨て）: システムメニューがマウスの位置ではなく「メニュー」ボタンの真上に開くことを実測する。
## 盤を出し、マウスを画面中央へ置いたまま盤の最上位 Esc と同じ経路（system_menu_requested）で開き、
## メニューの矩形とボタンの矩形を記録してスクショを撮る。ja / en の両方。
## 実行: godot --path . -s res://tests/manual/shot_system_menu.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/debug-ai/standoff.json"
const OUT := "res://tests/manual/out/system_menu_%s.png"
const LOG := "res://tests/manual/out/system_menu.txt"

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
	main.get_node("HexBoard").set_process(false)
	for loc in ["ja", "en"]:
		TranslationServer.set_locale(loc)
		main._refresh_labels()
		await process_frame
		root.warp_mouse(Vector2(960, 540))  # マウスは画面中央＝メニューがここに出たら不合格
		await process_frame
		main.get_node("HexBoard").system_menu_requested.emit()  # 盤の最上位 Esc と同じ経路
		for f in 6:
			await process_frame
		var hud: Hud = main._hud
		var menu: PopupMenu = hud._menu
		var gear: Button = hud._gear
		_lines.append("[%s] gear.text=%s gear.rect=%s" % [loc, gear.text, Rect2(gear.global_position, gear.size)])
		_lines.append("[%s] menu.visible=%s menu.rect=%s mouse=%s" % [loc, menu.visible, Rect2(Vector2(menu.position), Vector2(menu.size)), root.get_mouse_position()])
		_lines.append("[%s] menu.bottom - gear.top = %d (期待 0)  menu.left - gear.left = %d (期待 0)" % [loc, menu.position.y + menu.size.y - int(gear.global_position.y), menu.position.x - int(gear.global_position.x)])
		await _shot(OUT % loc)
		menu.hide()
		await process_frame
	TranslationServer.set_locale(locale0)
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	quit(0)

func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(path)
