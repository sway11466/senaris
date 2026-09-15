extends GutTest
## ChronicleStore のテスト。chronicle.json の読み書き・版・破損対策を検証する。
## 仕様 → doc/gdd/chronicle.md 記録の持ち方 / doc/tech/gamesystem.md §クロニクル

const PATH := "user://test_chronicle.json"

func before_each() -> void:
	_remove()

func after_all() -> void:
	_remove()

func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	# SaveFile.rotate の世代ファイルも消す
	var dir := DirAccess.open(PATH.get_base_dir())
	if dir == null:
		return
	var prefix := PATH.get_file().get_basename() + "."
	for file in dir.get_files():
		if file.begins_with(prefix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(
					PATH.get_base_dir().path_join(file)))

func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)

# ---------------------------------------------------------------------------
# 基本：空のストア
# ---------------------------------------------------------------------------

func test_fresh_store_is_empty() -> void:
	var store := ChronicleStore.new(PATH)
	assert_eq(store.skins(), {}, "初期状態はスキンなし")
	assert_eq(store.recipes(), {}, "初期状態はレシピなし")

# ---------------------------------------------------------------------------
# record_skin
# ---------------------------------------------------------------------------

func test_record_skin_new_returns_true() -> void:
	var store := ChronicleStore.new(PATH)
	assert_true(store.record_skin("archer", "tc"), "新規スキンは true")
	assert_true(store.has_skin("archer"), "記録されている")

func test_record_skin_duplicate_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer", "tc")
	assert_false(store.record_skin("archer", "tc"), "既知スキンは false")

func test_record_skin_empty_id_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	assert_false(store.record_skin("", "tc"), "空 id は記録しない")

# ---------------------------------------------------------------------------
# record_recipe
# ---------------------------------------------------------------------------

func test_record_recipe_new_returns_true() -> void:
	var store := ChronicleStore.new(PATH)
	assert_true(store.record_recipe("trinity_nova", "tc"), "新規レシピは true")
	assert_true(store.has_recipe("trinity_nova"), "記録されている")

func test_record_recipe_duplicate_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_recipe("trinity_nova", "tc")
	assert_false(store.record_recipe("trinity_nova", "tc"), "既知レシピは false")

func test_record_recipe_empty_id_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	assert_false(store.record_recipe("", "tc"), "空 id は記録しない")

# ---------------------------------------------------------------------------
# save / reload（永続化の往復）
# ---------------------------------------------------------------------------

func test_save_and_reload() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer", "tc")
	store.record_recipe("trinity_nova", "tc")
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	assert_true(reloaded.has_skin("archer"), "保存後に読み直せる")
	assert_true(reloaded.has_recipe("trinity_nova"), "レシピも読み直せる")
	assert_eq(reloaded.skins()["archer"]["first"], "tc", "初出の冒険譚が保存されている")
	assert_eq(reloaded.recipes()["trinity_nova"]["first"], "tc", "レシピの初出も保存されている")

func test_first_campaign_is_preserved() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer", "campaign1")
	store.record_skin("archer", "campaign2")  # 重複は無視される
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	assert_eq(reloaded.skins()["archer"]["first"], "campaign1",
			"初出の冒険譚は上書きされない")

func test_record_does_not_auto_save() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer", "tc")
	# save() を呼ばない
	var reloaded := ChronicleStore.new(PATH)
	assert_false(reloaded.has_skin("archer"), "save() を呼ぶまでファイルに書かない")

func test_save_without_changes_does_not_write() -> void:
	var store := ChronicleStore.new(PATH)
	store.save()  # 記録なしで save
	assert_false(FileAccess.file_exists(PATH), "変更がなければファイルを作らない")

func test_save_resets_dirty() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer", "tc")
	store.save()
	assert_true(FileAccess.file_exists(PATH), "1回目の save でファイルができる")
	# ファイルを消して、もう一度 save → dirty がリセットされていれば書かない
	_remove()
	store.save()
	assert_false(FileAccess.file_exists(PATH), "save 後に dirty がリセットされている")

func test_multiple_skins_and_recipes_persist() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer", "tc")
	store.record_skin("knight", "tc")
	store.record_skin("goblin", "tc2")
	store.record_recipe("trinity_nova", "tc")
	store.record_recipe("grace", "tc2")
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	assert_true(reloaded.has_skin("archer"))
	assert_true(reloaded.has_skin("knight"))
	assert_true(reloaded.has_skin("goblin"))
	assert_true(reloaded.has_recipe("trinity_nova"))
	assert_true(reloaded.has_recipe("grace"))
	assert_eq(reloaded.skins()["goblin"]["first"], "tc2",
			"冒険譚が異なるスキンもそれぞれ初出を持つ")

# ---------------------------------------------------------------------------
# 破損・不正ファイル（ProgressStore / RosterStore と同流儀）
# ---------------------------------------------------------------------------

func test_garbage_file_falls_back_to_empty() -> void:
	_write("これはJSONではない{{{")
	var store := ChronicleStore.new(PATH)
	assert_push_warning("ファイルが不正")
	assert_eq(store.skins(), {}, "壊れたファイルは空扱い")
	store.record_skin("archer", "tc")
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	assert_true(reloaded.has_skin("archer"), "上書き保存で復旧する")

func test_wrong_version_falls_back_to_empty() -> void:
	_write(JSON.stringify({ "version": 999,
			"skins": { "archer": { "first": "tc" } } }))
	var store := ChronicleStore.new(PATH)
	assert_push_warning("ファイルが不正")
	assert_false(store.has_skin("archer"), "未知バージョンは読まない")

func test_missing_version_falls_back_to_empty() -> void:
	_write(JSON.stringify({
			"skins": { "archer": { "first": "tc" } },
			"recipes": {} }))
	var store := ChronicleStore.new(PATH)
	assert_push_warning("ファイルが不正")
	assert_false(store.has_skin("archer"), "version 欠損は空扱い")

func test_skins_not_dict_loads_empty() -> void:
	_write(JSON.stringify({ "version": ChronicleStore.VERSION,
			"skins": "oops", "recipes": {} }))
	var store := ChronicleStore.new(PATH)
	assert_eq(store.skins(), {}, "skins が辞書でなければ空")

func test_recipes_not_dict_loads_empty() -> void:
	_write(JSON.stringify({ "version": ChronicleStore.VERSION,
			"skins": {}, "recipes": 42 }))
	var store := ChronicleStore.new(PATH)
	assert_eq(store.recipes(), {}, "recipes が辞書でなければ空")

func test_non_dict_entry_skipped() -> void:
	_write(JSON.stringify({ "version": ChronicleStore.VERSION,
			"skins": { "archer": { "first": "tc" }, "broken": "not a dict" },
			"recipes": {} }))
	var store := ChronicleStore.new(PATH)
	assert_true(store.has_skin("archer"), "正常なエントリは残る")
	assert_false(store.has_skin("broken"), "辞書でないエントリはスキップ")

# ---------------------------------------------------------------------------
# skins / recipes はコピーを返す
# ---------------------------------------------------------------------------

func test_skins_returns_copy() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer", "tc")
	var got := store.skins()
	got["archer"]["first"] = "tampered"
	assert_eq(store.skins()["archer"]["first"], "tc",
			"skins() の返り値を変えても内部状態は汚れない")

func test_recipes_returns_copy() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_recipe("trinity_nova", "tc")
	var got := store.recipes()
	got["trinity_nova"]["first"] = "tampered"
	assert_eq(store.recipes()["trinity_nova"]["first"], "tc",
			"recipes() の返り値を変えても内部状態は汚れない")
