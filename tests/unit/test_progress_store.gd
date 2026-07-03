extends GutTest
## ProgressStore（進捗セーブ＝クリア記録）のテスト。仕様 → doc/gdd/stage_select.md

const PATH := "user://test_progress.json"

func before_each() -> void:
	_remove()

func after_all() -> void:
	_remove()

func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func test_fresh_store_has_nothing() -> void:
	var store := ProgressStore.new(PATH)
	assert_false(store.is_cleared("tutorial", "st1"))

func test_mark_cleared_persists() -> void:
	ProgressStore.new(PATH).mark_cleared("tutorial", "st1")
	var reloaded := ProgressStore.new(PATH)  # 別インスタンスで読み直し＝ファイルに書けている
	assert_true(reloaded.is_cleared("tutorial", "st1"))
	assert_false(reloaded.is_cleared("tutorial", "st2"))
	assert_false(reloaded.is_cleared("other", "st1"), "冒険譚IDで区別する")

func test_garbage_file_falls_back_to_fresh() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("これはJSONではない{{{")
	f = null
	var store := ProgressStore.new(PATH)  # クラッシュせず新規扱い
	assert_false(store.is_cleared("tutorial", "st1"))
	store.mark_cleared("tutorial", "st1")
	assert_true(ProgressStore.new(PATH).is_cleared("tutorial", "st1"), "上書き保存で復旧する")

func test_wrong_version_falls_back_to_fresh() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": 999, "cleared": { "tutorial": { "st1": true } } }))
	f = null
	assert_false(ProgressStore.new(PATH).is_cleared("tutorial", "st1"), "未知バージョンは読まない")
