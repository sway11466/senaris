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
