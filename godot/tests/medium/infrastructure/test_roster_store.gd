extends GutTest
## RosterStore（名簿＝継承の控え）のテスト。仕様 → doc/gdd/campaigns.md 名簿 / doc/tech/gamesystem.md セーブ
## 控えは冒険譚ID×ステージID。版1（冒険譚に1冊）は変換で捨てる（doc/gdd/campaigns.md 名簿）。

const DIR := "user://test_roster_store"
const PATH := "user://test_roster_store/roster.json"

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

func _archer(troops: int = 8) -> Dictionary:
	return { "type": "archer", "level": 1, "troops": troops, "max_troops": 8 }

func test_fresh_store_has_nothing() -> void:
	var store := RosterStore.new(PATH)
	assert_eq(store.load_roster("tutorial3", "st1"), [], "無ければ空配列")

func test_save_persists_across_instances() -> void:
	var snap := [
		{ "type": "archer", "skin": "archer", "level": 3, "troops": 6, "max_troops": 8 },
		{ "type": "knight", "skin": "knight", "level": 1, "troops": 8, "max_troops": 8 },
	]
	RosterStore.new(PATH).save_roster("tutorial3", "st1", snap)
	var reloaded := RosterStore.new(PATH)  # 別インスタンスで読み直し＝ファイルに書けている
	var loaded := reloaded.load_roster("tutorial3", "st1")
	assert_false(loaded.is_empty(), "tutorial3/st1 に控えがある")
	assert_eq(loaded.size(), 2)
	# JSON 経由で数値は float 化するが、実パイプラインは Unit.from_dict が int に戻す＝そこで一致する
	assert_eq(Unit.from_dict(loaded[0]).to_dict(), snap[0])
	assert_eq(Unit.from_dict(loaded[1]).to_dict(), snap[1])
	assert_push_warning_count(2, "type 未解決の復元＝既定性能で復元する警告（catalog 解決は呼び出し側）")
	assert_eq(reloaded.load_roster("other", "st1"), [], "冒険譚IDで区別する")
	assert_eq(reloaded.load_roster("tutorial3", "st2"), [], "ステージIDで区別する")

func test_snapshots_per_stage_are_independent() -> void:
	# ステージごとの控え＝片方を書き直しても他方は変わらない（doc/gdd/campaigns.md 名簿）。
	var store := RosterStore.new(PATH)
	store.save_roster("tutorial3", "st1", [_archer(5)])
	store.save_roster("tutorial3", "st2", [_archer(3)])
	store.save_roster("tutorial3", "st1", [_archer(7)])
	var reloaded := RosterStore.new(PATH)
	assert_eq(reloaded.load_roster("tutorial3", "st1")[0]["troops"], 7, "st1 は書き直した値")
	assert_eq(reloaded.load_roster("tutorial3", "st2")[0]["troops"], 3, "st2 は据え置き")

func test_roundtrips_unit_snapshots() -> void:
	# 実際の Unit.to_dict() を保存→読み出しできる。
	var u1 := Unit.new(1, 0, Vector2i(0, 0), 4, 6, 8, 5, 3, "archer")
	u1.skin_id = "archer_red"
	var u2 := Unit.new(2, 0, Vector2i(0, 0), 3, 8, 12, 8, 1, "knight")
	RosterStore.new(PATH).save_roster("tutorial3", "st1", [u1.to_dict(), u2.to_dict()])
	var loaded := RosterStore.new(PATH).load_roster("tutorial3", "st1")
	assert_eq(loaded.size(), 2)
	# JSON 経由の float 化を Unit.from_dict が吸収して元の snapshot に戻る。
	assert_eq(Unit.from_dict(loaded[0]).to_dict(), u1.to_dict())
	assert_eq(Unit.from_dict(loaded[1]).to_dict(), u2.to_dict())
	assert_push_warning_count(2, "type 未解決の復元＝既定性能で復元する警告（catalog 解決は呼び出し側）")

func test_clear_removes_only_that_stage() -> void:
	var store := RosterStore.new(PATH)
	store.save_roster("tutorial3", "st1", [_archer()])
	store.save_roster("tutorial3", "st2", [_archer()])
	store.clear_roster("tutorial3", "st1")
	assert_eq(store.load_roster("tutorial3", "st1"), [], "破棄で消える")
	assert_false(store.load_roster("tutorial3", "st2").is_empty(), "他のステージの控えは残る")
	var reloaded := RosterStore.new(PATH)
	assert_eq(reloaded.load_roster("tutorial3", "st1"), [], "破棄が保存されている")
	assert_false(reloaded.load_roster("tutorial3", "st2").is_empty())

func test_load_returns_copy_not_internal() -> void:
	# load_roster の返り値を書き換えても内部状態は汚れない（deep copy）。
	var store := RosterStore.new(PATH)
	store.save_roster("tutorial3", "st1", [_archer()])
	var got := store.load_roster("tutorial3", "st1")
	got[0]["troops"] = 1
	assert_eq(store.load_roster("tutorial3", "st1")[0]["troops"], 8, "返り値の変更は内部に波及しない")

func test_garbage_file_falls_back_to_empty() -> void:
	_write("これはJSONではない{{{")
	var store := RosterStore.new(PATH)  # クラッシュせず空扱い
	assert_push_warning("名簿が不正")
	assert_eq(store.load_roster("tutorial3", "st1"), [], "壊れたファイルは空扱い")
	store.save_roster("tutorial3", "st1", [_archer()])
	assert_false(RosterStore.new(PATH).load_roster("tutorial3", "st1").is_empty(), "上書き保存で復旧する")

func test_wrong_version_falls_back_to_empty() -> void:
	_write(JSON.stringify({ "version": 999, "rosters": { "tutorial3": { "st1": [{ "type": "archer" }] } } }))
	assert_eq(RosterStore.new(PATH).load_roster("tutorial3", "st1"), [], "未知バージョンは読まない")
	assert_push_warning("名簿が不正")

func test_missing_version_falls_back_to_empty() -> void:
	_write(JSON.stringify({ "rosters": { "tutorial3": { "st1": [{ "type": "archer" }] } } }))
	assert_eq(RosterStore.new(PATH).load_roster("tutorial3", "st1"), [], "version 欠損は空扱い")
	assert_push_warning("名簿が不正")

func test_v1_single_roster_is_discarded() -> void:
	# 版1（冒険譚に1冊）は変換で捨てる＝どのステージのクリア後かが分からない（doc/gdd/campaigns.md 名簿）。
	# 読めないファイルではないので警告も退避も無い。
	_write(JSON.stringify({ "version": 1, "rosters": { "tutorial3": [_archer(4)] } }))
	var store := RosterStore.new(PATH)
	assert_eq(store.load_roster("tutorial3", "st1"), [], "1冊の名簿はどのステージにも付かない")
	assert_push_warning_count(0, "版1は変換で読む＝不正扱いしない")
	store.save_roster("tutorial3", "st1", [_archer()])
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw["version"]), RosterStore.VERSION, "保存すると現行版で書き直される")

func test_rosters_not_dict_loads_empty() -> void:
	_write(JSON.stringify({ "version": RosterStore.VERSION, "rosters": "oops" }))
	assert_eq(RosterStore.new(PATH).load_roster("tutorial3", "st1"), [])

func test_non_dict_campaign_entry_skipped_others_survive() -> void:
	_write(JSON.stringify({ "version": RosterStore.VERSION, "rosters": {
		"broken": "not a dict",
		"tutorial3": { "st1": [_archer()] },
	} }))
	var store := RosterStore.new(PATH)
	assert_eq(store.load_roster("broken", "st1"), [], "辞書でない冒険譚エントリはスキップ")
	assert_false(store.load_roster("tutorial3", "st1").is_empty(), "正常なエントリは残る")

func test_non_array_stage_entry_skipped_others_survive() -> void:
	_write(JSON.stringify({ "version": RosterStore.VERSION, "rosters": {
		"tutorial3": { "st1": "not an array", "st2": [_archer()] },
	} }))
	var store := RosterStore.new(PATH)
	assert_eq(store.load_roster("tutorial3", "st1"), [], "配列でないステージエントリはスキップ")
	assert_false(store.load_roster("tutorial3", "st2").is_empty(), "正常なエントリは残る")

func test_non_dict_elements_are_filtered() -> void:
	_write(JSON.stringify({ "version": RosterStore.VERSION, "rosters": {
		"tutorial3": { "st1": [_archer(), "junk", 42] },
	} }))
	var loaded := RosterStore.new(PATH).load_roster("tutorial3", "st1")
	assert_eq(loaded.size(), 1, "dict でない要素は落とす")
	assert_eq(loaded[0]["type"], "archer")
