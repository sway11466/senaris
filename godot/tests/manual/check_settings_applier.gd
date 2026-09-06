extends SceneTree
## main.gd 分割の検証（使い捨て）: 設定の適用が SettingsApplier 経由でも同じに効くか。
## 起動時の復元（言語・音量バス・画面モード）と、設定画面のシグナルで値が動いたときの適用を測る。
## 設定ファイルは中身ごと控えて最後に書き戻す＝検証で触った値を残さない。
## 実行: godot --path . -s res://tests/manual/check_settings_applier.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const LOG := "user://check_settings_applier.txt"

var _lines := PackedStringArray()

func _initialize() -> void:
	_run()

func _say(s: String) -> void:
	_lines.append(s)

func _run() -> void:
	await process_frame
	var had_file := FileAccess.file_exists(SettingsStore.DEFAULT_PATH)
	var raw0 := FileAccess.get_file_as_string(SettingsStore.DEFAULT_PATH) if had_file else ""
	var main: Node = MAIN.instantiate()
	root.add_child(main)
	for f in 10:
		await process_frame
	var store: SettingsStore = main._settings_store
	# 起動時の復元
	_say("boot locale store=%s applied=%s" % [store.locale(), TranslationServer.get_locale()])
	for bus in SettingsStore.VOLUME_BUSES:
		var idx := AudioServer.get_bus_index(String(SettingsApplier.VOLUME_BUS_NAMES[bus]))
		_say("boot volume %s store=%d bus_linear=%.2f mute=%s" % [bus, store.volume(bus), AudioServer.get_bus_volume_linear(idx), AudioServer.is_bus_mute(idx)])
	_say("boot window store=%s applied=%d (0=windowed 3=fullscreen)" % [store.window_mode(), DisplayServer.window_get_mode()])
	# 設定画面のシグナル＝つまみを引きずる（保存しない）→離す（保存する）
	var settings: SettingsScreen = main._settings
	var music_idx := AudioServer.get_bus_index("Music")
	settings.volume_changed.emit("music", 40)
	_say("drag music=40 -> bus_linear=%.2f saved=%d" % [AudioServer.get_bus_volume_linear(music_idx), store.volume("music")])
	settings.volume_settled.emit("music", 40)
	_say("release music=40 -> saved=%d" % store.volume("music"))
	settings.volume_changed.emit("sfx", 0)
	var sfx_idx := AudioServer.get_bus_index("SFX")
	_say("sfx=0 -> mute=%s" % AudioServer.is_bus_mute(sfx_idx))
	settings.volume_changed.emit("sfx", 100)
	_say("sfx=100 -> mute=%s linear=%.2f" % [AudioServer.is_bus_mute(sfx_idx), AudioServer.get_bus_volume_linear(sfx_idx)])
	# 言語＝適用・保存・生きている画面の貼り直し
	var before := TranslationServer.get_locale()
	var other := "en" if before == "ja" else "ja"
	var gear_before: String = main._hud._gear.text
	settings.locale_chosen.emit(other)
	for f in 3:
		await process_frame
	_say("locale %s -> applied=%s saved=%s hud_gear %s -> %s" % [other, TranslationServer.get_locale(), store.locale(), gear_before, main._hud._gear.text])
	settings.locale_chosen.emit(before)
	# 画面モード＝適用・保存（同じ値を選び直す＝見た目は変えない）
	settings.window_mode_chosen.emit(store.window_mode())
	_say("window re-chosen -> applied=%d saved=%s" % [DisplayServer.window_get_mode(), store.window_mode()])
	# 戻す
	for bus in SettingsStore.VOLUME_BUSES:
		SettingsApplier.apply_volume(bus, 100)
	if had_file:
		var f := FileAccess.open(SettingsStore.DEFAULT_PATH, FileAccess.WRITE)
		f.store_string(raw0)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsStore.DEFAULT_PATH))
	_say("restored file_same=%s" % [FileAccess.get_file_as_string(SettingsStore.DEFAULT_PATH) == raw0])
	var log := FileAccess.open(LOG, FileAccess.WRITE)
	for l in _lines:
		log.store_line(l)
	log.close()
	quit(0)
