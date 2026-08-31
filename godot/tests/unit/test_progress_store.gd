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
	assert_push_warning("進捗ファイルが不正")
	assert_false(store.is_cleared("tutorial", "st1"))
	store.mark_cleared("tutorial", "st1")
	assert_true(ProgressStore.new(PATH).is_cleared("tutorial", "st1"), "上書き保存で復旧する")

func test_wrong_version_falls_back_to_fresh() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": 999, "cleared": { "tutorial": { "st1": true } } }))
	f = null
	assert_false(ProgressStore.new(PATH).is_cleared("tutorial", "st1"), "未知バージョンは読まない")
	assert_push_warning("進捗ファイルが不正")

func test_missing_version_key_falls_back_to_fresh() -> void:
	# version キーそのものが無い（不一致とは別分岐＝get の既定値 0 で弾く）
	_write(JSON.stringify({ "cleared": { "tutorial": { "st1": true } } }))
	assert_false(ProgressStore.new(PATH).is_cleared("tutorial", "st1"), "version 欠損は新規扱い")
	assert_push_warning("進捗ファイルが不正")

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

# --- ランクの読み書き ---

func test_fresh_store_has_no_rank() -> void:
	assert_eq(ProgressStore.new(PATH).best_rank("tutorial", "st1"), "")

func test_mark_rank_persists() -> void:
	ProgressStore.new(PATH).mark_rank("tutorial", "st1", "A")
	assert_eq(ProgressStore.new(PATH).best_rank("tutorial", "st1"), "A")

func test_mark_rank_upgrades() -> void:
	var store := ProgressStore.new(PATH)
	store.mark_rank("tutorial", "st1", "B")
	store.mark_rank("tutorial", "st1", "A")
	assert_eq(ProgressStore.new(PATH).best_rank("tutorial", "st1"), "A")

func test_mark_rank_does_not_downgrade() -> void:
	var store := ProgressStore.new(PATH)
	store.mark_rank("tutorial", "st1", "S")
	store.mark_rank("tutorial", "st1", "B")
	assert_eq(ProgressStore.new(PATH).best_rank("tutorial", "st1"), "S")

func test_mark_rank_empty_is_ignored() -> void:
	var store := ProgressStore.new(PATH)
	store.mark_rank("tutorial", "st1", "")
	assert_eq(store.best_rank("tutorial", "st1"), "")

func test_ranks_survive_reload_with_cleared() -> void:
	var store := ProgressStore.new(PATH)
	store.mark_cleared("tutorial", "st1")
	store.mark_rank("tutorial", "st1", "S")
	var reloaded := ProgressStore.new(PATH)
	assert_true(reloaded.is_cleared("tutorial", "st1"), "クリア記録も残る")
	assert_eq(reloaded.best_rank("tutorial", "st1"), "S", "ランクも残る")

func test_invalid_rank_value_is_dropped() -> void:
	_write(JSON.stringify({ "version": ProgressStore.VERSION,
		"cleared": {}, "ranks": { "tutorial": { "st1": "X", "st2": "A" } } }))
	var store := ProgressStore.new(PATH)
	assert_eq(store.best_rank("tutorial", "st1"), "", "不正なランク値は読まない")
	assert_eq(store.best_rank("tutorial", "st2"), "A", "正常な値は残る")

func test_ranks_not_dict_is_ignored() -> void:
	_write(JSON.stringify({ "version": ProgressStore.VERSION,
		"cleared": {}, "ranks": "broken" }))
	var store := ProgressStore.new(PATH)
	assert_eq(store.best_rank("tutorial", "st1"), "")

func test_old_save_without_ranks_loads_fine() -> void:
	_write(JSON.stringify({ "version": ProgressStore.VERSION,
		"cleared": { "tutorial": { "st1": true } } }))
	var store := ProgressStore.new(PATH)
	assert_true(store.is_cleared("tutorial", "st1"), "クリア記録は読める")
	assert_eq(store.best_rank("tutorial", "st1"), "", "ランクは無し")

## 所要時間（doc/tech/gamesystem.md §所要時間）

func test_mark_time_keeps_shortest() -> void:
	var store := ProgressStore.new(PATH)
	store.mark_time("tutorial", "st1", 600)
	store.mark_time("tutorial", "st1", 900)
	assert_eq(ProgressStore.new(PATH).best_time("tutorial", "st1"), 600, "遅い回では上書きしない")
	store.mark_time("tutorial", "st1", 300)
	assert_eq(ProgressStore.new(PATH).best_time("tutorial", "st1"), 300, "短い回で更新する")

func test_mark_time_ignores_unmeasured() -> void:
	var store := ProgressStore.new(PATH)
	store.mark_time("tutorial", "st1", 0)
	assert_eq(store.best_time("tutorial", "st1"), 0, "測れていない回は記録しない")

func test_time_zero_or_negative_in_file_is_ignored() -> void:
	_write(JSON.stringify({ "version": ProgressStore.VERSION,
		"cleared": {}, "times": { "tutorial": { "st1": 0, "st2": -5, "st3": 120 } } }))
	var store := ProgressStore.new(PATH)
	assert_eq(store.best_time("tutorial", "st1"), 0, "0 は記録として読まない")
	assert_eq(store.best_time("tutorial", "st2"), 0, "負の値は読まない")
	assert_eq(store.best_time("tutorial", "st3"), 120)

func test_v1_file_is_migrated() -> void:
	_write(JSON.stringify({ "version": 1, "cleared": { "tutorial": { "st1": true } },
		"ranks": { "tutorial": { "st1": "A" } } }))
	var store := ProgressStore.new(PATH)
	assert_true(store.is_cleared("tutorial", "st1"), "旧版のクリア記録は消えない")
	assert_eq(store.best_rank("tutorial", "st1"), "A", "旧版のランクも残る")
	assert_eq(store.best_time("tutorial", "st1"), 0, "旧版は所要時間を持たない")
	store.mark_time("tutorial", "st1", 480)
	assert_eq(ProgressStore.new(PATH).best_time("tutorial", "st1"), 480, "以後のクリアから埋まる")

func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
