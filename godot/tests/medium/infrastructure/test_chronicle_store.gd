extends GutTest
## ChronicleStore のテスト。chronicle.json の読み書き・版・破損対策を検証する。
## 仕様 → doc/gdd/chronicle.md 記録の持ち方 / doc/tech/gamesystem.md §クロニクル

const DIR := "user://test_chronicle_store"
const PATH := "user://test_chronicle_store/chronicle.json"

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

# ---------------------------------------------------------------------------
# 基本：空のストア
# ---------------------------------------------------------------------------

func test_fresh_store_is_empty() -> void:
	var store := ChronicleStore.new(PATH)
	assert_eq(store.skins(), [], "初期状態はスキンなし")
	assert_eq(store.skills(), {}, "初期状態はスキルなし")

# ---------------------------------------------------------------------------
# record_skin
# ---------------------------------------------------------------------------

func test_record_skin_new_returns_true() -> void:
	var store := ChronicleStore.new(PATH)
	assert_true(store.record_skin("archer"), "新規スキンは true")
	assert_true(store.has_skin("archer"), "記録されている")

func test_record_skin_duplicate_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer")
	assert_false(store.record_skin("archer"), "既知スキンは false")

func test_record_skin_empty_id_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	assert_false(store.record_skin(""), "空 id は記録しない")

# ---------------------------------------------------------------------------
# record_skill
# ---------------------------------------------------------------------------

func test_record_skill_new_returns_true() -> void:
	var store := ChronicleStore.new(PATH)
	assert_true(store.record_skill("trinity_nova", "tc"), "新規スキルは true")
	assert_true(store.has_skill("trinity_nova"), "記録されている")

func test_record_skill_duplicate_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skill("trinity_nova", "tc")
	assert_false(store.record_skill("trinity_nova", "tc"), "既知スキルは false")

func test_record_skill_empty_id_returns_false() -> void:
	var store := ChronicleStore.new(PATH)
	assert_false(store.record_skill("", "tc"), "空 id は記録しない")

# ---------------------------------------------------------------------------
# save / reload（永続化の往復）
# ---------------------------------------------------------------------------

func test_save_and_reload() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer")
	store.record_skill("trinity_nova", "tc")
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	assert_true(reloaded.has_skin("archer"), "保存後に読み直せる")
	assert_true(reloaded.has_skill("trinity_nova"), "スキルも読み直せる")
	assert_eq(reloaded.skills()["trinity_nova"]["first"], "tc", "スキルの初出は保存されている")

func test_duplicate_skin_stays_single_entry() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer")
	store.record_skin("archer")  # 重複は無視される
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	assert_eq(reloaded.skins(), ["archer"], "同じスキンを何度記録しても1件")

func test_record_does_not_auto_save() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer")
	# save() を呼ばない
	var reloaded := ChronicleStore.new(PATH)
	assert_false(reloaded.has_skin("archer"), "save() を呼ぶまでファイルに書かない")

func test_save_without_changes_does_not_write() -> void:
	var store := ChronicleStore.new(PATH)
	store.save()  # 記録なしで save
	assert_false(FileAccess.file_exists(PATH), "変更がなければファイルを作らない")

func test_save_resets_dirty() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer")
	store.save()
	assert_true(FileAccess.file_exists(PATH), "1回目の save でファイルができる")
	# ファイルを消して、もう一度 save → dirty がリセットされていれば書かない
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	store.save()
	assert_false(FileAccess.file_exists(PATH), "save 後に dirty がリセットされている")

func test_multiple_skins_and_skills_persist() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer")
	store.record_skin("knight")
	store.record_skin("goblin")
	store.record_skill("trinity_nova", "tc")
	store.record_skill("grace", "tc2")
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	assert_true(reloaded.has_skin("archer"))
	assert_true(reloaded.has_skin("knight"))
	assert_true(reloaded.has_skin("goblin"))
	assert_true(reloaded.has_skill("trinity_nova"))
	assert_true(reloaded.has_skill("grace"))

# ---------------------------------------------------------------------------
# 破損・不正ファイル（ProgressStore / RosterStore と同流儀）
# ---------------------------------------------------------------------------

func test_garbage_file_falls_back_to_empty() -> void:
	_write("これはJSONではない{{{")
	var store := ChronicleStore.new(PATH)
	assert_push_warning("ファイルが不正")
	assert_eq(store.skins(), [], "壊れたファイルは空扱い")
	store.record_skin("archer")
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
			"skills": {} }))
	var store := ChronicleStore.new(PATH)
	assert_push_warning("ファイルが不正")
	assert_false(store.has_skin("archer"), "version 欠損は空扱い")

func test_skins_not_array_loads_empty() -> void:
	_write(JSON.stringify({ "version": ChronicleStore.VERSION,
			"skins": "oops", "skills": {} }))
	var store := ChronicleStore.new(PATH)
	assert_eq(store.skins(), [], "skins が並びでなければ空")

func test_skills_not_dict_loads_empty() -> void:
	_write(JSON.stringify({ "version": ChronicleStore.VERSION,
			"skins": {}, "skills": 42 }))
	var store := ChronicleStore.new(PATH)
	assert_eq(store.skills(), {}, "skills が辞書でなければ空")

func test_non_string_skin_entry_skipped() -> void:
	_write(JSON.stringify({ "version": ChronicleStore.VERSION,
			"skins": ["archer", 42], "skills": {} }))
	var store := ChronicleStore.new(PATH)
	assert_eq(store.skins(), ["archer"], "文字列でない要素はスキップ")

func test_non_dict_skill_entry_skipped() -> void:
	_write(JSON.stringify({ "version": ChronicleStore.VERSION, "skins": [],
			"skills": { "trinity_nova": { "first": "tc" }, "broken": "not a dict" } }))
	var store := ChronicleStore.new(PATH)
	assert_true(store.has_skill("trinity_nova"), "正常なエントリは残る")
	assert_false(store.has_skill("broken"), "辞書でないエントリはスキップ")

# ---------------------------------------------------------------------------
# 版と移行（v1＝スキンにも初出を持っていた版）
# ---------------------------------------------------------------------------

func test_v1_file_loads_and_drops_skin_first() -> void:
	_write(JSON.stringify({ "version": 1,
			"skins": { "archer": { "first": "tc" }, "knight": { "first": "tc2" } },
			"skills": { "trinity_nova": { "first": "tc" } } }))
	var store := ChronicleStore.new(PATH)
	assert_true(store.has_skin("archer"), "v1 のスキンは読める")
	assert_true(store.has_skin("knight"), "v1 のスキンは読める")
	assert_eq(store.skills()["trinity_nova"]["first"], "tc", "スキルの初出は残る")

func test_v1_file_is_rewritten_without_skin_first() -> void:
	_write(JSON.stringify({ "version": 1,
			"skins": { "archer": { "first": "tc" } }, "skills": {} }))
	var store := ChronicleStore.new(PATH)
	store.record_skin("knight")  # 変更が無いと書き出さないので1件足す
	store.save()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int((raw as Dictionary)["version"]), ChronicleStore.VERSION, "版が上がっている")
	assert_eq((raw as Dictionary)["skins"], ["archer", "knight"],
			"スキンは id の並びだけになり、初出の冒険譚は消えている")

# ---------------------------------------------------------------------------
# skins / skills はコピーを返す
# ---------------------------------------------------------------------------

func test_skins_returns_copy() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skin("archer")
	var got := store.skins()
	got.append("tampered")
	assert_eq(store.skins(), ["archer"],
			"skins() の返り値を変えても内部状態は汚れない")

func test_skills_returns_copy() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_skill("trinity_nova", "tc")
	var got := store.skills()
	got["trinity_nova"]["first"] = "tampered"
	assert_eq(store.skills()["trinity_nova"]["first"], "tc",
			"skills() の返り値を変えても内部状態は汚れない")

# ---------------------------------------------------------------------------
# 経験した会話：顔ぶれを足す
# ---------------------------------------------------------------------------

func test_story_roster_accumulates_patterns() -> void:
	var store := ChronicleStore.new(PATH)
	assert_true(store.record_story_roster("tc", "st1", "start", ["cap", "elf"]),
			"初めての顔ぶれは記録される")
	assert_true(store.record_story_roster("tc", "st1", "start", ["cap"]),
			"別の顔ぶれの回も足される")
	var got := store.story("tc", "st1")
	assert_eq(got["start"].size(), 2, "2通りの顔ぶれを経験した")

func test_story_roster_folds_same_pattern() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_story_roster("tc", "st1", "start", ["cap", "elf"])
	assert_false(store.record_story_roster("tc", "st1", "start", ["elf", "cap"]),
			"並び順が違っても同じ顔ぶれは畳む")
	assert_eq(store.story("tc", "st1")["start"].size(), 1)

func test_story_roster_start_and_clear_are_separate() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_story_roster("tc", "st1", "start", ["cap"])
	store.record_story_roster("tc", "st1", "clear", ["cap", "elf"])
	var got := store.story("tc", "st1")
	assert_eq(got["start"], [["cap"]], "開始時の顔ぶれ")
	assert_eq(got["clear"], [["cap", "elf"]], "クリア後の顔ぶれ＝この回で仲間になった駒を含む")

func test_story_roster_rejects_unknown_phase() -> void:
	var store := ChronicleStore.new(PATH)
	assert_false(store.record_story_roster("tc", "st1", "middle", ["cap"]),
			"start / clear 以外は記録しない")
	assert_false(store.record_story_roster("", "st1", "start", ["cap"]),
			"冒険譚の外は記録しない")
	assert_false(store.record_story_roster("tc", "", "start", ["cap"]),
			"ステージ不明は記録しない")

func test_story_roster_empty_is_a_pattern() -> void:
	var store := ChronicleStore.new(PATH)
	assert_true(store.record_story_roster("tc", "st1", "start", []),
			"誰も居ない回も1つの顔ぶれ＝「居なかった」を表す")
	store.record_story_roster("tc", "st1", "start", ["cap"])
	assert_eq(store.story("tc", "st1")["start"].size(), 2,
			"居なかった回と居た回の両方が残る")

# ---------------------------------------------------------------------------
# 経験した会話：イベントを足す
# ---------------------------------------------------------------------------

func test_story_events_accumulate() -> void:
	var store := ChronicleStore.new(PATH)
	assert_true(store.record_story_event("tc", "st1", "town-freed"))
	assert_false(store.record_story_event("tc", "st1", "town-freed"), "同じイベントは1つ")
	assert_true(store.record_story_event("tc", "st1", "town-lost"),
			"どちらか一方しか起きないイベントも、両方を経験すれば両方残る")
	assert_eq(store.story("tc", "st1")["events"], ["town-freed", "town-lost"])

func test_story_event_ignores_empty() -> void:
	var store := ChronicleStore.new(PATH)
	assert_false(store.record_story_event("tc", "st1", ""), "空のイベント id は記録しない")

# ---------------------------------------------------------------------------
# 経験した会話：保存と読み直し
# ---------------------------------------------------------------------------

func test_story_survives_save_and_load() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_story_roster("tc", "st1", "start", ["cap", "elf"])
	store.record_story_roster("tc", "st1", "start", ["cap"])
	store.record_story_roster("tc", "st1", "clear", ["cap"])
	store.record_story_event("tc", "st1", "town-freed")
	store.save()
	var reloaded := ChronicleStore.new(PATH)
	var got := reloaded.story("tc", "st1")
	assert_eq(got["start"].size(), 2, "顔ぶれ2通りが残る")
	assert_eq(got["clear"], [["cap"]])
	assert_eq(got["events"], ["town-freed"])

func test_story_missing_returns_empty_shape() -> void:
	var store := ChronicleStore.new(PATH)
	var got := store.story("tc", "st1")
	assert_eq(got["start"], [], "記録が無ければ空の形")
	assert_eq(got["clear"], [])
	assert_eq(got["events"], [])

func test_story_returns_copy() -> void:
	var store := ChronicleStore.new(PATH)
	store.record_story_event("tc", "st1", "town-freed")
	var got := store.story("tc", "st1")
	got["events"].append("tampered")
	assert_eq(store.story("tc", "st1")["events"], ["town-freed"],
			"story() の返り値を変えても内部状態は汚れない")

func test_story_broken_shape_is_skipped() -> void:
	_write('{"version": 1, "stories": {"tc": {"st1": {"start": "garbage", "events": ["ok", 7]}}}}')
	var store := ChronicleStore.new(PATH)
	var got := store.story("tc", "st1")
	assert_eq(got["start"], [], "読めない枝は捨てる")
	assert_eq(got["events"], ["ok"], "文字列でない要素は捨てる")

func test_old_file_without_stories_loads() -> void:
	_write('{"version": 1, "skins": {"archer": {"first": "tc"}}}')
	var store := ChronicleStore.new(PATH)
	assert_true(store.has_skin("archer"), "stories を持たない旧ファイルもそのまま読める")
	assert_eq(store.story("tc", "st1")["start"], [])

