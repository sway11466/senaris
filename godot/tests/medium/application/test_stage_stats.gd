extends GutTest
## StageStats（チュートリアルの Stats）と、StageOutcome からの発火のテスト。仕様 → doc/tech/platform.md Stats の中身

const DIR := "user://test_stage_stats"
const PROGRESS_PATH := "user://test_stage_stats/progress.json"

## 刻まれた Stats を控えるだけの部品。
class RecordingStats extends StatsSink:
	var added: Array = []
	func add(stat_id: String, amount: int = 1) -> void:
		added.append([stat_id, amount])

func _campaigns(board: String = "tutorial") -> Array:
	return [{
		"id": "tc", "debug": false, "board": board, "achievement": "TC",
		"stages": [
			{"id": "st1", "title": "tc.st1", "unlock": [], "path": ""},
			{"id": "st2", "title": "tc.st2", "unlock": [], "path": ""},
		],
		"emblem": {}, "victory_paths": [],
	}]

func _progress(campaigns: Array) -> CampaignProgress:
	return CampaignProgress.new(campaigns, ProgressStore.new(PROGRESS_PATH))

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

func test_ids_use_key_and_stage_order() -> void:
	var sink := RecordingStats.new()
	var stats := StageStats.new(_progress(_campaigns()), sink)
	stats.started("tc", "st2")
	stats.cleared("tc", "st2")
	assert_eq(sink.added, [["TC_ST2_START", 1], ["TC_ST2_CLEAR", 1]])

func test_non_tutorial_is_not_counted() -> void:
	var sink := RecordingStats.new()
	var stats := StageStats.new(_progress(_campaigns("bounties")), sink)
	stats.started("tc", "st1")
	stats.cleared("tc", "st1")
	assert_eq(sink.added.size(), 0, "チュートリアル以外は数えない")

func test_unknown_stage_is_not_counted() -> void:
	var sink := RecordingStats.new()
	StageStats.new(_progress(_campaigns()), sink).started("tc", "ghost")
	assert_eq(sink.added.size(), 0)

func test_stage_outcome_fires_stats_and_achievements() -> void:
	var progress := _progress(_campaigns())
	var sink := RecordingStats.new()
	var vault := AchievementFile.new(DIR.path_join("achievements.json"))
	var outcome := StageOutcome.new(progress, RosterStore.new(DIR.path_join("roster.json")),
			ChronicleService.new(ChronicleStore.new(DIR.path_join("chronicle.json"))),
			AchievementJudge.new(progress, vault), StageStats.new(progress, sink))
	var state := BattleState.new(8, 8)
	state.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	for sid in ["st1", "st2"]:
		outcome.stage_started("tc", sid, [])
		outcome.battle_finished("tc", sid, BattleState.PLAYER_WIN, state,
				int(Time.get_unix_time_from_system()) - 10, "", [])
	assert_eq(sink.added, [["TC_ST1_START", 1], ["TC_ST1_CLEAR", 1], ["TC_ST2_START", 1], ["TC_ST2_CLEAR", 1]])
	assert_true(vault.is_unlocked("TC_CLEAR"), "最終話のクリアで踏破が立つ")
