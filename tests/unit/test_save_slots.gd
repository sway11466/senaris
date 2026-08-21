extends GutTest
## SaveSlots（中断セーブ5枠＋オートセーブ1枠）のテスト。仕様 → doc/tech/gamesystem.md
## 1枠ぶんの永続化・破損耐性は test_save_store.gd が見る。ここは枠の集合・並び・独立性を見る。

const DIR := "user://test_slots/"

func before_each() -> void:
	_wipe()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

func after_all() -> void:
	_wipe()

func _wipe() -> void:
	var abs := ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(f))
	DirAccess.remove_absolute(abs)

func test_slot_ids_are_auto_then_five() -> void:
	assert_eq(SaveSlots.slot_ids(), ["auto", "1", "2", "3", "4", "5"], "一覧の並び＝オートが先頭")
	assert_eq(SaveSlots.manual_slot_ids(), ["1", "2", "3", "4", "5"], "保存先に選べるのは中断5枠だけ")
	assert_true(SaveSlots.is_auto("auto"))
	assert_false(SaveSlots.is_auto("1"))

func test_fresh_has_nothing() -> void:
	var slots := SaveSlots.new(DIR)
	assert_false(slots.has_any(), "1枠も無ければ「冒険の続き」は出せない")
	for e in slots.list():
		assert_false(e["used"], "空き枠も一覧に並ぶ（used=false）")
	assert_eq(slots.list().size(), 6, "空でも6行")

func test_slots_are_independent_files() -> void:
	var slots := SaveSlots.new(DIR)
	slots.save_slot("1", { "cols": 4 }, { "stage_id": "a" })
	slots.save_slot("3", { "cols": 9 }, { "stage_id": "b" })
	var reloaded := SaveSlots.new(DIR)  # 別インスタンスで読み直し＝枠ごとに別ファイル
	assert_eq(int(reloaded.load_slot("1")["state"]["cols"]), 4)
	assert_eq(int(reloaded.load_slot("3")["state"]["cols"]), 9)
	assert_false(reloaded.has("2"), "書いていない枠は空のまま")
	assert_true(reloaded.has_any())

func test_auto_is_separate_from_manual() -> void:
	var slots := SaveSlots.new(DIR)
	slots.save_slot(SaveSlots.AUTO, { "cols": 7 }, { "stage_id": "auto" })
	slots.save_slot("1", { "cols": 4 }, { "stage_id": "manual" })
	slots.save_slot(SaveSlots.AUTO, { "cols": 8 }, { "stage_id": "auto2" })  # 自動は上書き
	assert_eq(int(slots.load_slot(SaveSlots.AUTO)["state"]["cols"]), 8, "オートは上書きされる")
	assert_eq(int(slots.load_slot("1")["state"]["cols"]), 4, "オートの上書きは中断枠に触らない")

func test_list_reports_meta_and_order() -> void:
	var slots := SaveSlots.new(DIR)
	slots.save_slot("2", { "cols": 4 }, { "stage_id": "st2", "turn_number": 3 })
	var rows := slots.list()
	assert_eq(rows[0]["slot"], SaveSlots.AUTO)
	assert_true(rows[0]["auto"], "先頭行はオートセーブ")
	assert_false(rows[0]["used"])
	assert_eq(rows[2]["slot"], "2", "3行目＝中断2枠目")
	assert_true(rows[2]["used"])
	assert_eq(int(rows[2]["meta"]["turn_number"]), 3, "一覧の表示材料はメタから取れる")

func test_clear_removes_only_that_slot() -> void:
	var slots := SaveSlots.new(DIR)
	slots.save_slot("1", { "cols": 4 }, {})
	slots.save_slot("2", { "cols": 5 }, {})
	slots.clear_slot("1")
	assert_false(slots.has("1"), "消した枠は空きに戻る")
	assert_true(slots.has("2"), "隣の枠は残る")
	assert_false(SaveSlots.new(DIR).has("1"), "破棄が永続")

func test_unknown_slot_is_rejected() -> void:
	var slots := SaveSlots.new(DIR)
	slots.save_slot("9", { "cols": 4 }, {})
	assert_push_error("知らない枠")
	assert_false(slots.has("9"))
	assert_eq(slots.load_slot("9"), {}, "知らない枠は空扱い")
