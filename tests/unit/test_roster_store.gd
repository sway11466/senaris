extends GutTest
## RosterStore（戦力スナップショット＝継承 carryover）のテスト。仕様 → doc/gdd/map.md / doc/tech/gamesystem.md

const PATH := "user://test_roster.json"

func before_each() -> void:
	_remove()

func after_all() -> void:
	_remove()

func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)

func test_fresh_store_has_nothing() -> void:
	var store := RosterStore.new(PATH)
	assert_false(store.has_roster("tutorial3"))
	assert_eq(store.load_roster("tutorial3"), [], "無ければ空配列")

func test_save_persists_across_instances() -> void:
	var snap := [
		{ "type": "archer", "skin": "archer", "level": 3, "troops": 6, "max_troops": 8 },
		{ "type": "knight", "skin": "knight", "level": 1, "troops": 8, "max_troops": 8 },
	]
	RosterStore.new(PATH).save_roster("tutorial3", snap)
	var reloaded := RosterStore.new(PATH)  # 別インスタンスで読み直し＝ファイルに書けている
	assert_true(reloaded.has_roster("tutorial3"))
	var loaded := reloaded.load_roster("tutorial3")
	assert_eq(loaded.size(), 2)
	# JSON 経由で数値は float 化するが、実パイプラインは Unit.from_dict が int に戻す＝そこで一致する
	assert_eq(Unit.from_dict(loaded[0]).to_dict(), snap[0])
	assert_eq(Unit.from_dict(loaded[1]).to_dict(), snap[1])
	assert_false(reloaded.has_roster("other"), "冒険譚IDで区別する")

func test_roundtrips_unit_snapshots() -> void:
	# 実際の Unit.to_dict() を保存→読み出しできる（Phase 2d で使う経路）。
	var u1 := Unit.new(1, 0, Vector2i(0, 0), 4, 6, 8, 5, 3, "archer")
	u1.skin_id = "archer_red"
	var u2 := Unit.new(2, 0, Vector2i(0, 0), 3, 8, 12, 8, 1, "knight")
	RosterStore.new(PATH).save_roster("tutorial3", [u1.to_dict(), u2.to_dict()])
	var loaded := RosterStore.new(PATH).load_roster("tutorial3")
	assert_eq(loaded.size(), 2)
	# JSON 経由の float 化を Unit.from_dict が吸収して元の snapshot に戻る（Phase 2d で使う経路）。
	assert_eq(Unit.from_dict(loaded[0]).to_dict(), u1.to_dict())
	assert_eq(Unit.from_dict(loaded[1]).to_dict(), u2.to_dict())

func test_clear_removes_snapshot() -> void:
	var store := RosterStore.new(PATH)
	store.save_roster("tutorial3", [{ "type": "archer", "level": 1, "troops": 8, "max_troops": 8 }])
	store.clear_roster("tutorial3")
	assert_false(store.has_roster("tutorial3"), "破棄で消える")
	assert_false(RosterStore.new(PATH).has_roster("tutorial3"), "破棄が保存されている")

func test_load_returns_copy_not_internal() -> void:
	# load_roster の返り値を書き換えても内部状態は汚れない（deep copy）。
	var store := RosterStore.new(PATH)
	store.save_roster("tutorial3", [{ "type": "archer", "level": 1, "troops": 8, "max_troops": 8 }])
	var got := store.load_roster("tutorial3")
	got[0]["troops"] = 1
	assert_eq(store.load_roster("tutorial3")[0]["troops"], 8, "返り値の変更は内部に波及しない")

func test_garbage_file_falls_back_to_empty() -> void:
	_write("これはJSONではない{{{")
	var store := RosterStore.new(PATH)  # クラッシュせず空扱い
	assert_false(store.has_roster("tutorial3"))
	store.save_roster("tutorial3", [{ "type": "archer", "level": 1, "troops": 8, "max_troops": 8 }])
	assert_true(RosterStore.new(PATH).has_roster("tutorial3"), "上書き保存で復旧する")

func test_wrong_version_falls_back_to_empty() -> void:
	_write(JSON.stringify({ "version": 999, "rosters": { "tutorial3": [{ "type": "archer" }] } }))
	assert_false(RosterStore.new(PATH).has_roster("tutorial3"), "未知バージョンは読まない")

func test_missing_version_falls_back_to_empty() -> void:
	_write(JSON.stringify({ "rosters": { "tutorial3": [{ "type": "archer" }] } }))
	assert_false(RosterStore.new(PATH).has_roster("tutorial3"), "version 欠損は空扱い")

func test_rosters_not_dict_loads_empty() -> void:
	_write(JSON.stringify({ "version": RosterStore.VERSION, "rosters": "oops" }))
	assert_false(RosterStore.new(PATH).has_roster("tutorial3"))

func test_non_array_entry_skipped_others_survive() -> void:
	_write(JSON.stringify({ "version": RosterStore.VERSION, "rosters": {
		"broken": "not an array",
		"tutorial3": [{ "type": "archer", "level": 1, "troops": 8, "max_troops": 8 }],
	} }))
	var store := RosterStore.new(PATH)
	assert_false(store.has_roster("broken"), "配列でないエントリはスキップ")
	assert_true(store.has_roster("tutorial3"), "正常なエントリは残る")

func test_non_dict_elements_are_filtered() -> void:
	_write(JSON.stringify({ "version": RosterStore.VERSION, "rosters": {
		"tutorial3": [{ "type": "archer", "level": 1, "troops": 8, "max_troops": 8 }, "junk", 42],
	} }))
	var loaded := RosterStore.new(PATH).load_roster("tutorial3")
	assert_eq(loaded.size(), 1, "dict でない要素は落とす")
	assert_eq(loaded[0]["type"], "archer")
