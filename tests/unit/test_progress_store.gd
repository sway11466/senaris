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

func test_missing_version_key_falls_back_to_fresh() -> void:
	# version キーそのものが無い（不一致とは別分岐＝get の既定値 0 で弾く）
	_write(JSON.stringify({ "cleared": { "tutorial": { "st1": true } } }))
	assert_false(ProgressStore.new(PATH).is_cleared("tutorial", "st1"), "version 欠損は新規扱い")

func test_cleared_not_dict_loads_empty() -> void:
	_write(JSON.stringify({ "version": ProgressStore.VERSION, "cleared": "oops" }))
	var store := ProgressStore.new(PATH)  # クラッシュせず空で読む
	assert_false(store.is_cleared("tutorial", "st1"))

func test_cleared_key_missing_loads_empty() -> void:
	_write(JSON.stringify({ "version": ProgressStore.VERSION }))
	var store := ProgressStore.new(PATH)  # クラッシュせず空で読む
	assert_false(store.is_cleared("tutorial", "st1"))

func test_non_dict_campaign_entry_is_skipped() -> void:
	# 冒険譚エントリが dict でない → その冒険譚だけスキップし、他は生きる
	_write(JSON.stringify({ "version": ProgressStore.VERSION,
		"cleared": { "tutorial": "broken", "other": { "st1": true } } }))
	var store := ProgressStore.new(PATH)
	assert_false(store.is_cleared("tutorial", "st1"), "壊れたエントリは読まない")
	assert_true(store.is_cleared("other", "st1"), "正常なエントリは残る")

func test_non_true_stage_values_are_dropped() -> void:
	# true 以外のステージ値（false・文字列・数値）はクリア扱いにせず、実行時エラーにもならない
	_write(JSON.stringify({ "version": ProgressStore.VERSION,
		"cleared": { "tutorial": { "st1": false, "st2": "yes", "st3": 1 } } }))
	var store := ProgressStore.new(PATH)
	assert_false(store.is_cleared("tutorial", "st1"))
	assert_false(store.is_cleared("tutorial", "st2"), "文字列はクリア扱いしない")
	assert_false(store.is_cleared("tutorial", "st3"), "数値はクリア扱いしない")
	assert_false(store._cleared.has("tutorial"), "全滅した冒険譚の空エントリは積まない")

func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
