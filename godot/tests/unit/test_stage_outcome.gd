extends GutTest
## application/stage_outcome.gd のテスト。
## 決着時の記録が正しい順序で書かれること、冒険譚の外では書かないこと、
## 敗北では名簿を更新しないことを検証する。

const PROGRESS_PATH := "user://test_outcome_progress.json"
const ROSTER_PATH := "user://test_outcome_roster.json"

## テスト用の最小限の冒険譚マニフェスト。
func _campaign() -> Array:
	return [{
		"id": "tc",
		"debug": false,
		"stages": [
			{"id": "st1", "title": "tc.st1", "unlock": [], "path": ""},
			{"id": "st2", "title": "tc.st2", "unlock": [{"type": "cleared", "stage": "st1"}], "path": ""},
		],
		"emblem": {},
		"victory_paths": [],
	}]

## テスト用のデバッグ冒険譚。
func _debug_campaign() -> Array:
	return [{
		"id": "dbg",
		"debug": true,
		"stages": [{"id": "d1", "title": "dbg.d1", "unlock": [], "path": ""}],
		"emblem": {},
		"victory_paths": [],
	}]

func _progress(campaigns: Array = []) -> CampaignProgress:
	if campaigns.is_empty():
		campaigns = _campaign()
	return CampaignProgress.new(campaigns, ProgressStore.new(PROGRESS_PATH))

func _roster_store() -> RosterStore:
	return RosterStore.new(ROSTER_PATH)

func _outcome(progress: CampaignProgress = null, roster: RosterStore = null) -> StageOutcome:
	if progress == null:
		progress = _progress()
	if roster == null:
		roster = _roster_store()
	return StageOutcome.new(progress, roster)

## 最小限の BattleState（自軍1・敵1）。勝利判定に使う。
func _state() -> BattleState:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))  # 自軍
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3))  # 敵軍
	return s

func after_each() -> void:
	# テスト用の一時ファイルを消す。
	for path in [PROGRESS_PATH, ROSTER_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		# ProgressStore のバックアップ（.bak）も消す。
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)

# ---------------------------------------------------------------------------
# stage_started
# ---------------------------------------------------------------------------

func test_stage_started_records_story() -> void:
	var p := _progress()
	var o := _outcome(p)
	o.stage_started("tc", "st1", [{"actor": "knight"}])
	var story := p.story("tc", "st1")
	assert_true(story.has("start"), "story に start がある")
	assert_true(story["start"].has("knight"), "開始時の actor が記録されている")

func test_stage_started_outside_campaign_does_nothing() -> void:
	var p := _progress()
	var o := _outcome(p)
	o.stage_started("", "", [{"actor": "knight"}])  # 冒険譚の外
	assert_true(p.story("", "").is_empty(), "冒険譚の外では記録しない")

# ---------------------------------------------------------------------------
# event_fired
# ---------------------------------------------------------------------------

func test_event_fired_records_event() -> void:
	var p := _progress()
	var o := _outcome(p)
	o.stage_started("tc", "st1", [])  # まず start を作る
	o.event_fired("tc", "st1", "ev1")
	var story := p.story("tc", "st1")
	assert_true(story["events"].has("ev1"), "イベントが記録されている")

func test_event_fired_empty_id_does_nothing() -> void:
	var p := _progress()
	var o := _outcome(p)
	o.stage_started("tc", "st1", [])
	o.event_fired("tc", "st1", "")  # 空の id
	var story := p.story("tc", "st1")
	assert_eq(story["events"].size(), 0, "空 id では記録しない")

# ---------------------------------------------------------------------------
# battle_finished — 敗北
# ---------------------------------------------------------------------------

func test_defeat_does_not_record() -> void:
	var p := _progress()
	var o := _outcome(p)
	var result := o.battle_finished("tc", "st1", BattleState.PLAYER_LOSE,
			_state(), int(Time.get_unix_time_from_system()) - 60, "", [])
	assert_false(p.stage_state("tc", "st1") == "cleared", "敗北ではクリアしない")
	assert_true(result["updated_roster"].is_empty(), "敗北では名簿を更新しない")

# ---------------------------------------------------------------------------
# battle_finished — 勝利（冒険譚内）
# ---------------------------------------------------------------------------

func test_win_records_clear() -> void:
	var p := _progress()
	var o := _outcome(p)
	o.stage_started("tc", "st1", [])
	o.battle_finished("tc", "st1", BattleState.PLAYER_WIN,
			_state(), int(Time.get_unix_time_from_system()) - 30, "", [])
	assert_eq(p.stage_state("tc", "st1"), "cleared", "勝利でクリア記録がつく")

func test_win_records_time() -> void:
	var p := _progress()
	var o := _outcome(p)
	var result := o.battle_finished("tc", "st1", BattleState.PLAYER_WIN,
			_state(), int(Time.get_unix_time_from_system()) - 45, "", [])
	assert_true(int(result["elapsed"]) > 0, "所要時間が計算される")
	assert_true(p.best_time("tc", "st1") > 0, "所要時間が記録される")

func test_win_records_story_clear() -> void:
	var p := _progress()
	var o := _outcome(p)
	o.stage_started("tc", "st1", [{"actor": "knight"}])
	o.battle_finished("tc", "st1", BattleState.PLAYER_WIN,
			_state(), int(Time.get_unix_time_from_system()) - 10, "", [])
	var story := p.story("tc", "st1")
	assert_true(story.has("clear"), "勝利で clear が記録される")

func test_win_unlocks_next_stage() -> void:
	var p := _progress()
	var o := _outcome(p)
	assert_eq(p.stage_state("tc", "st2"), "locked", "st2 は未解放")
	o.battle_finished("tc", "st1", BattleState.PLAYER_WIN,
			_state(), int(Time.get_unix_time_from_system()) - 10, "", [])
	assert_eq(p.stage_state("tc", "st2"), "unlocked", "st1 クリアで st2 が解放")

func test_result_has_best_time_zero_on_first_clear() -> void:
	var p := _progress()
	var o := _outcome(p)
	var result := o.battle_finished("tc", "st1", BattleState.PLAYER_WIN,
			_state(), int(Time.get_unix_time_from_system()) - 10, "", [])
	assert_eq(int(result["best_time"]), 0, "初回クリアの前のベストは 0")

# ---------------------------------------------------------------------------
# battle_finished — 冒険譚の外
# ---------------------------------------------------------------------------

func test_win_outside_campaign_does_not_record() -> void:
	var p := _progress()
	var o := _outcome(p)
	var result := o.battle_finished("", "", BattleState.PLAYER_WIN,
			_state(), int(Time.get_unix_time_from_system()) - 10, "", [])
	# ランクと所要時間は計算される（表示用）が、記録はされない。
	assert_true(result["updated_roster"].is_empty(), "冒険譚の外では名簿を更新しない")

# ---------------------------------------------------------------------------
# _compute_elapsed
# ---------------------------------------------------------------------------

func test_elapsed_zero_when_no_start() -> void:
	assert_eq(StageOutcome._compute_elapsed(0), 0, "開始時刻なしは 0")
	assert_eq(StageOutcome._compute_elapsed(-1), 0, "負の開始時刻も 0")

func test_elapsed_positive_for_past_start() -> void:
	var started := int(Time.get_unix_time_from_system()) - 120
	var elapsed := StageOutcome._compute_elapsed(started)
	assert_true(elapsed >= 119 and elapsed <= 121, "120秒前の開始で ≈120 秒")
