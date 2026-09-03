extends SceneTree
## feature-47 検証用（使い捨て）: 盤の上に設定画面を開いた実機画面を撮り、音量がバスに当たることを測る。
## main.tscn を起動し、ステージを読み、HUD のシステムメニューと同じ経路（settings_requested）で開く。
## 撮ったあと音量・画面モードを元に戻す＝設定ファイルに検証の値を残さない。
## 実行: godot --path . -s res://tests/manual/shot_settings.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/debug-ai/guard.json"
const OUT_JA := "res://tests/manual/out/settings_board_ja.png"
const OUT_EN := "res://tests/manual/out/settings_board_en.png"
const LOG := "res://tests/manual/out/settings_board.txt"

var _lines := PackedStringArray()

func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_run()

func _run() -> void:
	await process_frame
	var main: Node = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	var store: SettingsStore = main._settings_store
	# 設定ファイルは中身ごと控えて最後に書き戻す＝検証で触った値（選んでいない項目）を残さない。
	var had_file := FileAccess.file_exists(SettingsStore.DEFAULT_PATH)
	var raw0 := FileAccess.get_file_as_string(SettingsStore.DEFAULT_PATH) if had_file else ""
	var locale0 := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	main._refresh_labels()
	main._title.visible = false
	main.load_stage(STAGE)
	for f in 12:
		await process_frame
	main.get_node("HexBoard").set_process(false)

	# 盤の上に開く（HUD のシステムメニュー「設定」と同じ signal）。
	main._hud.settings_requested.emit()
	for f in 20:
		await process_frame
	var settings: SettingsScreen = main._settings
	_lines.append("visible=%s layer=%d" % [settings.visible, settings.layer])
	await _shot(OUT_JA)

	# つまみを動かす＝バスに当たるか（引きずり中は保存しない・離すと保存）。
	var slider: HSlider = settings._sliders["music"]
	slider.drag_started.emit()
	slider.value = 40
	var music_idx := AudioServer.get_bus_index("Music")
	_lines.append("drag music=40 -> bus_db=%.2f saved=%d" % [AudioServer.get_bus_volume_db(music_idx), store.volume("music")])
	slider.drag_ended.emit(true)
	_lines.append("release music=40 -> saved=%d" % store.volume("music"))
	var spin: SpinBox = settings._spins["sfx"]
	spin.value = 0
	var sfx_idx := AudioServer.get_bus_index("SFX")
	_lines.append("spin sfx=0 -> mute=%s saved=%d slider=%d" % [AudioServer.is_bus_mute(sfx_idx), store.volume("sfx"), int(settings._sliders["sfx"].value)])
	spin.value = 100
	_lines.append("spin sfx=100 -> mute=%s db=%.2f saved=%d" % [AudioServer.is_bus_mute(sfx_idx), AudioServer.get_bus_volume_db(sfx_idx), store.volume("sfx")])

	# 盤の上で言語を変える＝生き続ける画面の文言が追う。いまと違う方へ切り替える。
	settings._locale = TranslationServer.get_locale()  # 画面は設定ファイルの言語で開く＝いま表示している言語に揃えてから切り替える
	var other := "en" if settings._locale == "ja" else "ja"
	settings._on_language(other)
	for f in 6:
		await process_frame
	_lines.append("switched to %s: locale=%s hud_menu=%s conv_skip=%s settings_label=%s" % [other, TranslationServer.get_locale(), main._hud._gear.text, main._conversation._skip_btn.text, settings._labels["ui.settings.volume_master"].text])
	await _shot(OUT_EN)

	# 戻す。言語は表示だけ戻し、ファイルは控えた中身をそのまま書き戻す（無かったなら消す）。
	TranslationServer.set_locale(locale0)
	for bus in SettingsStore.VOLUME_BUSES:
		main._apply_volume(bus, 100)
	if had_file:
		var f := FileAccess.open(SettingsStore.DEFAULT_PATH, FileAccess.WRITE)
		f.store_string(raw0)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsStore.DEFAULT_PATH))
	_lines.append("restored file_same=%s" % [FileAccess.get_file_as_string(SettingsStore.DEFAULT_PATH) == raw0])
	settings.close()
	for f in 20:
		await process_frame
	_lines.append("closed visible=%s title_visible=%s" % [settings.visible, main._title.visible])
	var log := FileAccess.open(LOG, FileAccess.WRITE)
	for l in _lines:
		log.store_line(l)
	log.close()
	quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	_lines.append("shot %s save=%d size=%s" % [path, err, img.get_size()])
