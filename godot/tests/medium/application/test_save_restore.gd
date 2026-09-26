extends GutTest
## SaveRestore（中断セーブからの盤の組み立て）のテスト。仕様 → doc/tech/gamesystem.md §中断セーブが持つもの
## 現行版のセーブを書いて読み、ステージJSONの上に差分を被せた盤が中断時の盤と同じになることを見る。

const DIR := "user://test_save_restore"
const STAGE_PATH := "user://test_save_restore/stage.json"
const SAVE_PATH := "user://test_save_restore/save.json"

## 自軍2・敵1・自軍拠点1。地形は相棒のファイル（<ステージ>.terrain.json）に持つ。
const STAGE := {
	"turn_limit": 12,
	"player": [ { "units": [
		{ "type": "fighter", "col": 0, "row": 0 },
		{ "type": "fighter", "col": 1, "row": 0 },
	] } ],
	"enemy": [ { "order": 1, "ai": "charge", "units": [ { "type": "fighter", "col": 5, "row": 3 } ] } ],
	"bases": [ { "col": 0, "row": 2, "team": "player" } ],
}
const STAGE_TERRAIN := { "terrain": ["......", "......", "......", "......"] }

func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(STAGE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(STAGE))
	f.close()
	var t := FileAccess.open(StageLoader.terrain_path(STAGE_PATH), FileAccess.WRITE)
	t.store_string(JSON.stringify(STAGE_TERRAIN))
	t.close()

func after_all() -> void:
	_clean()

func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

## 盤を進めて（移動・損耗・ターン経過）現行版で保存し、再開と同じ経路（読込→版の変換→復元）で組み直す。
func _save_and_restore(s: BattleState) -> BattleState:
	SaveStore.new(SAVE_PATH).save(s.to_save_diff(), { "stage_path": STAGE_PATH })
	var data := SaveMigration.migrate(SaveStore.new(SAVE_PATH).load())
	assert_false(data.is_empty(), "前提: 現行版のセーブが読める")
	return SaveRestore.restore(String(data["meta"]["stage_path"]), data["state"])

func test_current_version_save_restores_the_board() -> void:
	var s := StageLoader.load_file(STAGE_PATH)
	var moved_to := Hex.offset_to_axial(0, 1)
	assert_true(s.move_unit(1, moved_to), "前提: 自軍の駒が動ける")
	s.unit_by_handle(2).troops = 3
	s.end_turn()  # 敵ターン
	s.end_turn()  # 自軍ターン 2
	var got := _save_and_restore(s)
	assert_not_null(got, "復元できる")
	assert_eq(got.turn_number, 2, "ターン数を復元")
	assert_eq(got.current_team, 0, "手番の陣営を復元")
	assert_eq(got.units().size(), 3, "駒の顔ぶれはセーブから")
	assert_eq(got.unit_by_handle(1).pos, moved_to, "駒の位置を復元")
	assert_eq(got.unit_by_handle(2).troops, 3, "損耗を復元")
	assert_eq(got.turn_limit, 12, "ターン上限はステージJSONから")
	assert_eq(got.base_at(Hex.offset_to_axial(0, 2)).team, 0, "拠点の帰属を復元")

func test_restore_keeps_units_in_base() -> void:
	# 拠点に入った駒は盤上には居ない＝控えとして戻る。
	var s := StageLoader.load_file(STAGE_PATH)
	var base_hex := Hex.offset_to_axial(0, 2)
	assert_true(s.move_unit(1, base_hex), "前提: 拠点まで動ける")
	assert_true(s.enter_base(1), "前提: 拠点に入れる")
	var got := _save_and_restore(s)
	assert_null(got.unit_by_handle(1), "盤上には居ない")
	assert_eq(got.base_at(base_hex).garrison.size(), 1, "拠点の控えとして戻る")
	assert_eq((got.base_at(base_hex).garrison[0] as Unit).handle, 1)

func test_restore_returns_null_when_stage_is_missing() -> void:
	var s := StageLoader.load_file(STAGE_PATH)
	var got := SaveRestore.restore("user://test_save_restore/no_such_stage.json", s.to_save_diff())
	assert_null(got, "ステージを読めなければ組まない")
	assert_push_error("SaveRestore: ステージを読めない")
