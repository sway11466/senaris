extends GutTest
## SaveFile（保存ファイルの版の判定と退避）のテスト。仕様 → doc/tech/gamesystem.md §版と移行・§バックアップ

const DIR := "user://test_save_file"
const PATH := "user://test_save_file/save.json"

func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

func after_all() -> void:
	_clean()

func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)

func _files() -> PackedStringArray:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return PackedStringArray()
	var out := dir.get_files()
	out.sort()
	return out

## 名前に part を含むファイル（退避の印で数える）。
func _matching(part: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in _files():
		if file.contains(part):
			out.append(file)
	return out

func test_missing_file_is_not_set_aside() -> void:
	var result := SaveFile.read(PATH, 1)
	assert_eq(int(result["status"]), SaveFile.MISSING)
	assert_eq(_files().size(), 0, "無いファイルは退避しない")

func test_matching_version_reads_data() -> void:
	_write(PATH, '{ "version": 1, "cleared": {} }')
	var result := SaveFile.read(PATH, 1)
	assert_eq(int(result["status"]), SaveFile.VALID)
	assert_true((result["data"] as Dictionary).has("cleared"), "中身をそのまま返す")
	assert_eq(_files().size(), 1, "読めたファイルは退避しない")

func test_broken_json_is_set_aside_as_broken() -> void:
	_write(PATH, "{ これは JSON ではない")
	var result := SaveFile.read(PATH, 1)
	assert_eq(int(result["status"]), SaveFile.UNREADABLE)
	assert_false(FileAccess.file_exists(PATH), "元の場所からは消える")
	assert_eq(_matching("broken-").size(), 1, "broken の印で退避する")

func test_old_version_is_set_aside_with_its_version() -> void:
	_write(PATH, '{ "version": 1 }')
	var result := SaveFile.read(PATH, 2)
	assert_eq(int(result["status"]), SaveFile.MISMATCHED)
	assert_eq(_matching("v1-").size(), 1, "版番号を名前に入れて退避する")

func test_newer_version_is_treated_like_an_unreadable_file() -> void:
	_write(PATH, '{ "version": 9 }')
	var result := SaveFile.read(PATH, 2)
	assert_eq(int(result["status"]), SaveFile.MISMATCHED, "現行より新しい版も読まない")
	assert_eq(_matching("v9-").size(), 1)

# --- 変換を持つ旧版（oldest）の受け入れ。仕様 → doc/tech/gamesystem.md §版と移行 ---

func test_supported_old_version_reads_data_without_set_aside() -> void:
	_write(PATH, '{ "version": 2, "cleared": {} }')
	var result := SaveFile.read(PATH, 3, 2)
	assert_eq(int(result["status"]), SaveFile.VALID, "変換を持つ旧版は VALID として中身を返す")
	assert_eq(int((result["data"] as Dictionary)["version"]), 2, "版はファイルの中身に残っている")
	assert_true(FileAccess.file_exists(PATH), "退避せず元の場所に残す＝版が違うだけのファイルを捨てない")

func test_version_below_oldest_is_set_aside() -> void:
	_write(PATH, '{ "version": 1 }')
	var result := SaveFile.read(PATH, 3, 2)
	assert_eq(int(result["status"]), SaveFile.MISMATCHED, "変換を持たない版は読まない")
	assert_eq(_matching("v1-").size(), 1, "版番号を名前に入れて退避する")

func test_newer_version_is_set_aside_even_with_oldest() -> void:
	_write(PATH, '{ "version": 9 }')
	var result := SaveFile.read(PATH, 3, 2)
	assert_eq(int(result["status"]), SaveFile.MISMATCHED, "現行より新しい版は oldest 指定でも読まない")
	assert_eq(_matching("v9-").size(), 1)

func test_reading_twice_does_not_stack_backups() -> void:
	_write(PATH, "壊れている")
	SaveFile.read(PATH, 1)
	SaveFile.read(PATH, 1)
	assert_eq(_matching("broken-").size(), 1, "退避すると元の場所から消えるので重ならない")

func test_rotate_keeps_the_current_file() -> void:
	_write(PATH, '{ "version": 1 }')
	SaveFile.rotate(PATH)
	assert_true(FileAccess.file_exists(PATH), "現物は残す（このあと上書きするため）")
	assert_eq(_files().size(), 2, "世代が1つ増える")

func test_rotate_on_missing_file_does_nothing() -> void:
	SaveFile.rotate(PATH)
	assert_eq(_files().size(), 0)

func test_rotate_trims_to_five_generations() -> void:
	_write(PATH, '{ "version": 1 }')
	for i in range(5):
		_write(DIR.path_join("save.2026010%d-000000.json" % (i + 1)), "古い世代")
	SaveFile.rotate(PATH)
	assert_false(FileAccess.file_exists(DIR.path_join("save.20260101-000000.json")), "一番古い世代が消える")
	assert_true(FileAccess.file_exists(DIR.path_join("save.20260105-000000.json")), "新しい世代は残る")
	assert_eq(_files().size(), 6, "現物1つ＋世代5つ")

func test_set_aside_files_are_not_trimmed() -> void:
	_write(PATH, '{ "version": 1 }')
	_write(DIR.path_join("save.broken-20260101-000000.json"), "壊れていたもの")
	for i in range(5):
		_write(DIR.path_join("save.2026010%d-000000.json" % (i + 1)), "古い世代")
	SaveFile.rotate(PATH)
	assert_true(FileAccess.file_exists(DIR.path_join("save.broken-20260101-000000.json")),
		"印つきの退避は世代の勘定に入らない＝自動で消さない")

func test_store_sets_aside_before_falling_back() -> void:
	# 各ストアが SaveFile を通していることの確認（進捗ストアで代表させる）
	_write(PATH, '{ "version": 99, "cleared": { "tutorial1": { "st1": true } } }')
	var store := ProgressStore.new(PATH)
	assert_false(store.is_cleared("tutorial1", "st1"), "版が違うので読まない")
	assert_eq(_matching("v99-").size(), 1, "捨てる前に退避する")
