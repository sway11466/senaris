extends GutTest
## AchievementJudge（冒険譚の実績を進捗から判定する）のテスト。仕様 → doc/tech/platform.md 実績の中身

const DIR := "user://test_achievement_judge"
const PROGRESS_PATH := "user://test_achievement_judge/progress.json"
const VAULT_PATH := "user://test_achievement_judge/achievements.json"

func _campaigns(achievement: String = "TC", debug: bool = false) -> Array:
	return [{
		"id": "tc", "debug": debug, "board": "tutorial", "achievement": achievement,
		"stages": [
			{"id": "st1", "title": "tc.st1", "unlock": [], "path": ""},
			{"id": "st2", "title": "tc.st2", "unlock": [], "path": ""},
		],
		"emblem": {}, "victory_paths": [],
	}]

func _setup(campaigns: Array) -> Array:
	var progress := CampaignProgress.new(campaigns, ProgressStore.new(PROGRESS_PATH))
	var vault := AchievementFile.new(VAULT_PATH)
	return [progress, vault, AchievementJudge.new(progress, vault)]

func _clear(progress: CampaignProgress, stage_id: String, rank: String) -> void:
	progress.record_clear("tc", stage_id)
	progress.record_rank("tc", stage_id, rank)

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

func test_nothing_until_every_stage_is_cleared() -> void:
	var s := _setup(_campaigns())
	_clear(s[0], "st1", "S")
	s[2].judge("tc")
	assert_eq(s[1].unlocked_ids().size(), 0, "1話だけでは何も立たない")

func test_all_cleared_with_b_gives_clear_only() -> void:
	var s := _setup(_campaigns())
	_clear(s[0], "st1", "S")
	_clear(s[0], "st2", "B")
	s[2].judge("tc")
	assert_eq(s[1].unlocked_ids(), PackedStringArray(["TC_CLEAR"]))

func test_all_a_or_above_gives_rank_a() -> void:
	var s := _setup(_campaigns())
	_clear(s[0], "st1", "S")
	_clear(s[0], "st2", "A")
	s[2].judge("tc")
	assert_eq(s[1].unlocked_ids(), PackedStringArray(["TC_CLEAR", "TC_RANK_A"]))

func test_all_s_gives_every_tier() -> void:
	var s := _setup(_campaigns())
	_clear(s[0], "st1", "S")
	_clear(s[0], "st2", "S")
	s[2].judge("tc")
	assert_eq(s[1].unlocked_ids(), PackedStringArray(["TC_CLEAR", "TC_RANK_A", "TC_RANK_S"]),
		"最上位を満たせば下の2段も同時に立つ")

func test_judge_all_picks_up_earlier_progress() -> void:
	var s := _setup(_campaigns())
	_clear(s[0], "st1", "A")
	_clear(s[0], "st2", "A")
	s[2].judge_all()
	assert_true(s[1].is_unlocked("TC_RANK_A"), "起動時の判定で、仕組みより前の進捗も拾う")

func test_campaign_without_key_has_no_achievements() -> void:
	var s := _setup(_campaigns(""))
	_clear(s[0], "st1", "S")
	_clear(s[0], "st2", "S")
	s[2].judge_all()
	assert_eq(s[1].unlocked_ids().size(), 0, "achievement を書かない冒険譚には実績が無い")
