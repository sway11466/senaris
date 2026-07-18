extends GutTest
## SaveStore（中断セーブ＝1枠）のテスト。仕様 → doc/tech/gamesystem.md

const PATH := "user://test_save.json"

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

func test_fresh_has_no_save() -> void:
	var store := SaveStore.new(PATH)
	assert_false(store.has_save())
	assert_eq(store.load(), {}, "無ければ空 dict")

func test_save_and_load_persists() -> void:
	var state := { "cols": 8, "rows": 6, "units": [] }
	SaveStore.new(PATH).save(state, { "campaign_id": "tutorial3", "stage_id": "st2" })
	var reloaded := SaveStore.new(PATH)  # 別インスタンスで読み直し
	assert_true(reloaded.has_save())
	var got := reloaded.load()
	assert_eq(int(got["state"]["cols"]), 8, "盤状態を保つ")
	assert_eq(String(got["meta"]["campaign_id"]), "tutorial3", "メタを保つ")
	assert_eq(String(got["meta"]["stage_id"]), "st2")

func test_roundtrips_real_battle_state() -> void:
	# 実 BattleState を to_dict→保存→読出→from_dict で復元できる（中断→再開の経路）。
	var cat := { "knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 8 }) }
	var s := StageLoader.build({ "cols": 6, "rows": 4, "turn_limit": 10,
		"player": [{ "type": "knight", "col": 1, "row": 1 }] }, cat)
	s.current_team = 1
	s.turn_number = 4
	s.unit_by_id(1).troops = 3
	SaveStore.new(PATH).save(s.to_dict(), { "stage_path": "res://data/stages/x.json" })

	var got := SaveStore.new(PATH).load()
	var s2 := BattleState.from_dict(got["state"], cat)
	assert_eq(s2.current_team, 1, "手番を復元")
	assert_eq(s2.turn_number, 4)
	assert_eq(s2.unit_by_id(1).troops, 3, "損耗を復元")
	assert_eq(String(got["meta"]["stage_path"]), "res://data/stages/x.json", "再開に使うステージパス")

func test_save_overwrites_single_slot() -> void:
	var store := SaveStore.new(PATH)
	store.save({ "cols": 4 }, { "stage_id": "a" })
	store.save({ "cols": 9 }, { "stage_id": "b" })
	var got := SaveStore.new(PATH).load()
	assert_eq(int(got["state"]["cols"]), 9, "1枠＝後の保存で上書き")
	assert_eq(String(got["meta"]["stage_id"]), "b")

func test_clear_removes_save() -> void:
	var store := SaveStore.new(PATH)
	store.save({ "cols": 4 }, {})
	store.clear()
	assert_false(store.has_save(), "破棄で消える")
	assert_false(SaveStore.new(PATH).has_save(), "破棄が永続")

func test_garbage_file_falls_back_to_none() -> void:
	_write("これはJSONではない{{{")
	var store := SaveStore.new(PATH)  # クラッシュせず「セーブ無し」
	assert_false(store.has_save())
	store.save({ "cols": 4 }, {})
	assert_true(SaveStore.new(PATH).has_save(), "上書き保存で復旧")

func test_wrong_version_falls_back_to_none() -> void:
	_write(JSON.stringify({ "version": 999, "meta": {}, "state": { "cols": 4 } }))
	assert_false(SaveStore.new(PATH).has_save(), "未知バージョンは読まない")

func test_missing_version_falls_back_to_none() -> void:
	_write(JSON.stringify({ "meta": {}, "state": { "cols": 4 } }))
	assert_false(SaveStore.new(PATH).has_save(), "version 欠損は無効")

func test_missing_state_is_invalid() -> void:
	_write(JSON.stringify({ "version": SaveStore.VERSION, "meta": { "stage_id": "a" } }))
	assert_false(SaveStore.new(PATH).has_save(), "state が無ければセーブとして無効")

func test_empty_state_is_invalid() -> void:
	_write(JSON.stringify({ "version": SaveStore.VERSION, "meta": {}, "state": {} }))
	assert_false(SaveStore.new(PATH).has_save(), "空の state は無効")
