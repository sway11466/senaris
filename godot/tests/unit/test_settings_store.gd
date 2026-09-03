extends GutTest
## SettingsStore（設定＝user://settings.json）のテスト。仕様 → doc/tech/gamesystem.md §設定

const PATH := "user://test_settings.json"

func before_each() -> void:
	_remove()

func after_all() -> void:
	_remove()

func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func test_unset_locale_comes_from_environment() -> void:
	var store := SettingsStore.new(PATH)
	var expected := "ja" if OS.get_locale_language() == "ja" else "en"
	assert_eq(store.locale(), expected, "選ばれるまでは環境の言語で決まる")
	assert_false(FileAccess.file_exists(PATH), "選ぶまではファイルを作らない")

func test_chosen_locale_persists() -> void:
	SettingsStore.new(PATH).set_locale("en")
	assert_eq(SettingsStore.new(PATH).locale(), "en", "別インスタンスで読み直しても残る")
	SettingsStore.new(PATH).set_locale("ja")
	assert_eq(SettingsStore.new(PATH).locale(), "ja", "選び直しは上書きされる")

func test_unset_info_panel_is_open() -> void:
	var store := SettingsStore.new(PATH)
	assert_false(store.info_panel_minimized(), "選ばれるまでは開いている")
	assert_false(FileAccess.file_exists(PATH), "選ぶまではファイルを作らない")

func test_info_panel_minimized_persists() -> void:
	SettingsStore.new(PATH).set_info_panel_minimized(true)
	assert_true(SettingsStore.new(PATH).info_panel_minimized(), "畳んだ状態は別インスタンスで読み直しても残る")
	assert_eq(SettingsStore.new(PATH).locale(), "ja" if OS.get_locale_language() == "ja" else "en",
		"言語は選んでいないので環境のまま")
	SettingsStore.new(PATH).set_info_panel_minimized(false)
	assert_false(SettingsStore.new(PATH).info_panel_minimized(), "開き直しは上書きされる")

func test_unset_info_panel_position_is_absent() -> void:
	var store := SettingsStore.new(PATH)
	assert_false(store.has_info_panel_position(), "動かすまでは位置を持たない")
	assert_false(FileAccess.file_exists(PATH), "動かすまではファイルを作らない")

func test_info_panel_position_persists_and_clears() -> void:
	SettingsStore.new(PATH).set_info_panel_position(Vector2(120.5, 40))
	var store := SettingsStore.new(PATH)
	assert_true(store.has_info_panel_position(), "動かした位置は別インスタンスで読み直しても残る")
	assert_eq(store.info_panel_position(), Vector2(120.5, 40))
	store.clear_info_panel_position()
	assert_false(SettingsStore.new(PATH).has_info_panel_position(), "戻すと項目ごと消える")

func test_broken_info_panel_position_is_ignored() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": SettingsStore.VERSION, "info_panel_position": { "x": "a" } }))
	f.close()
	assert_false(SettingsStore.new(PATH).has_info_panel_position(), "数でない位置は無いものとして扱う")

func test_unknown_locale_is_rejected() -> void:
	var store := SettingsStore.new(PATH)
	store.set_locale("fr")
	assert_push_error("知らない言語")
	assert_false(FileAccess.file_exists(PATH), "知らない言語は書かない")

func test_garbage_file_falls_back_to_environment() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("これはJSONではない{{{")
	f = null
	var store := SettingsStore.new(PATH)  # クラッシュせず設定なし扱い
	assert_push_warning("設定ファイルが不正")
	var expected := "ja" if OS.get_locale_language() == "ja" else "en"
	assert_eq(store.locale(), expected)
	store.set_locale("en")
	assert_eq(SettingsStore.new(PATH).locale(), "en", "上書き保存で復旧する")

func test_wrong_version_falls_back_to_environment() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": 999, "locale": "en" }))
	f = null
	var store := SettingsStore.new(PATH)
	assert_push_warning("設定ファイルが不正")
	var expected := "ja" if OS.get_locale_language() == "ja" else "en"
	assert_eq(store.locale(), expected)

func test_unknown_locale_in_file_is_ignored() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": SettingsStore.VERSION, "locale": "fr" }))
	f = null
	var expected := "ja" if OS.get_locale_language() == "ja" else "en"
	assert_eq(SettingsStore.new(PATH).locale(), expected, "手編集で入った知らない言語は無視する")

func test_unset_volume_is_full() -> void:
	var store := SettingsStore.new(PATH)
	for bus in SettingsStore.VOLUME_BUSES:
		assert_eq(store.volume(bus), 100, "選ばれるまでは素材そのまま（100）: %s" % bus)
	assert_false(FileAccess.file_exists(PATH), "選ぶまではファイルを作らない")

func test_volume_persists_per_bus() -> void:
	SettingsStore.new(PATH).set_volume("music", 35)
	SettingsStore.new(PATH).set_volume("sfx", 0)
	var store := SettingsStore.new(PATH)
	assert_eq(store.volume("music"), 35, "別インスタンスで読み直しても残る")
	assert_eq(store.volume("sfx"), 0, "0（無音）も選んだ値として残る")
	assert_eq(store.volume("master"), 100, "選んでいない系統は素材そのまま")

func test_volume_out_of_range_is_rejected() -> void:
	var store := SettingsStore.new(PATH)
	store.set_volume("master", 101)
	assert_push_error("音量が範囲外")
	store.set_volume("master", -1)
	assert_push_error("音量が範囲外")
	store.set_volume("voice", 50)
	assert_push_error("知らない音量の系統")
	assert_false(FileAccess.file_exists(PATH), "範囲外・知らない系統は書かない")

func test_broken_volume_in_file_is_ignored() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": SettingsStore.VERSION,
		"volume_master": 200, "volume_music": 50.5, "volume_sfx": "loud" }))
	f = null
	var store := SettingsStore.new(PATH)
	assert_eq(store.volume("master"), 100, "範囲外は無いものとして扱う")
	assert_eq(store.volume("music"), 100, "整数でない値は無いものとして扱う")
	assert_eq(store.volume("sfx"), 100, "文字列は無いものとして扱う")

func test_whole_float_volume_in_file_is_read_as_int() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": SettingsStore.VERSION, "volume_music": 40.0 }))
	f = null
	assert_eq(SettingsStore.new(PATH).volume("music"), 40, "JSON の 40.0（float）は 40 として読む")

func test_unset_window_mode_is_windowed() -> void:
	var store := SettingsStore.new(PATH)
	assert_eq(store.window_mode(), "windowed", "選ばれるまではウィンドウ")
	assert_false(FileAccess.file_exists(PATH), "選ぶまではファイルを作らない")

func test_window_mode_persists() -> void:
	SettingsStore.new(PATH).set_window_mode("fullscreen")
	assert_eq(SettingsStore.new(PATH).window_mode(), "fullscreen", "別インスタンスで読み直しても残る")
	SettingsStore.new(PATH).set_window_mode("windowed")
	assert_eq(SettingsStore.new(PATH).window_mode(), "windowed", "選び直しは上書きされる")

func test_unknown_window_mode_is_rejected() -> void:
	var store := SettingsStore.new(PATH)
	store.set_window_mode("borderless")
	assert_push_error("知らない画面モード")
	assert_false(FileAccess.file_exists(PATH), "知らない画面モードは書かない")
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": SettingsStore.VERSION, "window_mode": "borderless" }))
	f = null
	assert_eq(SettingsStore.new(PATH).window_mode(), "windowed", "手編集で入った知らないモードは無視する")
