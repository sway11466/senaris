extends GutTest
## AchievementFile（実績ファイル＝user://achievements.json）のテスト。仕様 → doc/tech/platform.md 実績ファイル

const DIR := "user://test_achievement_file"
const PATH := "user://test_achievement_file/achievements.json"

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

func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_starts_empty_without_file() -> void:
	var vault := AchievementFile.new(PATH)
	assert_eq(vault.unlocked_ids().size(), 0)
	assert_false(vault.is_unlocked("tutorial1_clear"))
	assert_false(FileAccess.file_exists(PATH), "解除するまではファイルを作らない")

func test_unlock_persists_in_order() -> void:
	var vault := AchievementFile.new(PATH)
	vault.unlock("tutorial1_clear")
	vault.unlock("tutorial1_rank_a")
	var reread := AchievementFile.new(PATH)
	assert_true(reread.is_unlocked("tutorial1_clear"), "別インスタンスで読み直しても残る")
	assert_eq(reread.unlocked_ids(), PackedStringArray(["tutorial1_clear", "tutorial1_rank_a"]), "解除した順に並ぶ")

func test_unlock_twice_is_harmless() -> void:
	var vault := AchievementFile.new(PATH)
	vault.unlock("tutorial1_clear")
	vault.unlock("tutorial1_clear")
	assert_eq(AchievementFile.new(PATH).unlocked_ids(), PackedStringArray(["tutorial1_clear"]), "重ねて呼んでも1つ")

func test_file_format() -> void:
	AchievementFile.new(PATH).unlock("tutorial1_clear")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(data["version"]), AchievementFile.VERSION)
	assert_eq(data["unlocked"], ["tutorial1_clear"])

func test_unlocked_ids_is_a_copy() -> void:
	var vault := AchievementFile.new(PATH)
	vault.unlock("tutorial1_clear")
	var ids := vault.unlocked_ids()
	ids.append("forged")
	assert_false(vault.is_unlocked("forged"), "返した一覧をいじっても保管庫は変わらない")

func test_broken_file_starts_empty() -> void:
	_write("{ not json")
	var vault := AchievementFile.new(PATH)
	assert_eq(vault.unlocked_ids().size(), 0, "壊れたファイルは解除なしで起動")
	assert_false(FileAccess.file_exists(PATH), "壊れたファイルは退避されて元の場所から消える")

func test_junk_entries_are_dropped() -> void:
	_write(JSON.stringify({ "version": AchievementFile.VERSION, "unlocked": ["a", 3, "a", null, "b"] }))
	assert_eq(AchievementFile.new(PATH).unlocked_ids(), PackedStringArray(["a", "b"]), "文字列でないもの・重複は捨てる")
