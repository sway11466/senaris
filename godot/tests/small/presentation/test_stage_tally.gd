extends GutTest
## presentation/main/stage_tally.gd（戦果の集計と戦果票の行）のテスト。仕様 → doc/gdd/rank.md
## 盤（BattleState）は domain の駒で組み、開始兵力とランク閾値はステージJSONを読まずに直接控える
## ＝ステージのデータに依らず行の組み立てだけを見る。文言は ja で固定する。

var _prev_locale := ""
var _tally: StageTally
var _state: BattleState
var _context: StageContext

func before_each() -> void:
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	_state = BattleState.new(6, 6)
	for i in 3:
		_state.add_unit(Unit.new(i + 1, 0, Hex.offset_to_axial(i, 0), 2))
	for i in 2:
		_state.add_unit(Unit.new(i + 11, 1, Hex.offset_to_axial(i, 4), 2))
	_state.turn_number = 3
	_state.turn_limit = 10
	_context = StageContext.new()
	_context.campaign_id = "camp"
	_context.stage_id = "st2"
	_context.stage_path = "res://data/stages/camp/st2.json"
	_tally = StageTally.new()
	_tally._state = _state
	_tally._context = _context
	_tally._start_ally = 4  # 1体は既に失った体で
	_tally._rank_data = { "turn_s": 5, "turn_a": 8, "survival_s": 4, "survival_a": 2 }

func after_each() -> void:
	TranslationServer.set_locale(_prev_locale)

# --- rows ---

func test_win_rows_carry_goals() -> void:
	_tally._elapsed = 0
	var rows := _tally.rows(true)
	assert_eq(rows.size(), 3, "所要時間を測れていない回は3行")
	var turn: Dictionary = rows[0]
	assert_eq(turn["label"], "ターン")
	assert_eq(turn["value"], "3 / 10", "上限があれば n / N")
	assert_eq(turn["s"], "Sランク　5ターン未満")
	assert_true(turn["s_ok"], "3ターンは S 基準を満たす")
	assert_eq(turn["a"], "Aランク　8ターン未満")
	assert_true(turn["a_ok"], "S なら A も満たす")
	var alive: Dictionary = rows[1]
	assert_eq(alive["label"], "生存※", "兵器を数えない行には印")
	assert_eq(alive["value"], "3 / 4")
	assert_false(alive["s_ok"], "3体は S 基準（4体以上）に届かない")
	assert_true(alive["a_ok"], "A 基準（2体以上）は満たす")
	var defeated: Dictionary = rows[2]
	assert_eq(defeated["label"], "撃破※")
	assert_eq(defeated["value"], "0")

func test_defeated_counts_enemy_losses() -> void:
	_state.remove_unit(11)
	assert_eq(_tally.rows(false)[2]["value"], "1")

func test_lose_rows_have_no_goals() -> void:
	var rows := _tally.rows(false)
	assert_false(rows[0].has("s"), "敗北にランク基準は付かない")
	assert_false(rows[1].has("a"))

func test_no_turn_limit_shows_bare_turn() -> void:
	_state.turn_limit = 0
	assert_eq(_tally.rows(true)[0]["value"], "3")

func test_zero_threshold_leaves_goal_blank() -> void:
	_tally._rank_data = { "turn_s": 0, "turn_a": 8, "survival_s": 4, "survival_a": 0 }
	var rows := _tally.rows(true)
	assert_false(rows[0].has("s"), "閾値 0 の段は空欄")
	assert_true(rows[0].has("a"))
	assert_true(rows[1].has("s"))
	assert_false(rows[1].has("a"))

func test_no_rank_data_gives_no_goals_even_on_win() -> void:
	_tally._rank_data = {}
	var rows := _tally.rows(true)
	assert_false(rows[0].has("s"))
	assert_false(rows[1].has("s"))

# --- 所要時間の行 ---

func test_time_row_with_new_best() -> void:
	_tally._elapsed = 754
	_tally._best_time = 900
	var rows := _tally.rows(true)
	assert_eq(rows.size(), 4, "測れていれば所要時間の行が付く")
	var t: Dictionary = rows[3]
	assert_eq(t["label"], "所要時間")
	assert_eq(t["value"], "12:34")
	assert_eq(t["sub"], "最速 12:34", "更新した回はこの回の時間がベスト")
	assert_true(t["sub_ok"])

func test_time_row_keeps_old_best() -> void:
	_tally._elapsed = 754
	_tally._best_time = 600
	var t: Dictionary = _tally.rows(true)[3]
	assert_eq(t["sub"], "最速 10:00", "更新していなければ前のベストを出す")
	assert_false(t["sub_ok"])

func test_first_clear_is_a_best() -> void:
	_tally._elapsed = 754
	_tally._best_time = 0
	var t: Dictionary = _tally.rows(true)[3]
	assert_eq(t["sub"], "最速 12:34")
	assert_true(t["sub_ok"])

func test_lose_time_row_has_no_best() -> void:
	_tally._elapsed = 754
	_tally._best_time = 600
	var t: Dictionary = _tally.rows(false)[3]
	assert_eq(t["value"], "12:34")
	assert_false(t.has("sub"), "負けた回は記録に触らない＝比べる相手を出さない")

func test_outside_campaign_time_row_has_no_best() -> void:
	_context.campaign_id = ""
	_tally._elapsed = 754
	var t: Dictionary = _tally.rows(true)[3]
	assert_false(t.has("sub"), "冒険譚の外は記録が無い")

# --- format_duration ---

func test_format_under_an_hour() -> void:
	assert_eq(_tally.format_duration(0), "0:00")
	assert_eq(_tally.format_duration(59), "0:59")
	assert_eq(_tally.format_duration(754), "12:34")

func test_format_hours() -> void:
	assert_eq(_tally.format_duration(3600), "1:00:00")
	assert_eq(_tally.format_duration(3754), "1:02:34")

func test_format_days_drops_seconds() -> void:
	assert_eq(_tally.format_duration(3 * 86400 + 2 * 3600 + 15 * 60 + 40), "3日 2:15")

func test_format_negative_is_zero() -> void:
	assert_eq(_tally.format_duration(-5), "0:00")

# --- finish ---

func test_finish_win_returns_rank_and_elapsed() -> void:
	_context.started_at = int(Time.get_unix_time_from_system()) - 100
	var rank := _tally.finish(BattleState.PLAYER_WIN, 0)
	assert_eq(rank, "A", "ターン S・生存 A ＝ 低い方の A")
	assert_between(_tally.elapsed(), 100, 102, "開始時刻からの秒数")

func test_finish_lose_has_no_rank() -> void:
	_context.started_at = int(Time.get_unix_time_from_system()) - 100
	assert_eq(_tally.finish(BattleState.PLAYER_LOSS, 0), "")
	assert_gt(_tally.elapsed(), 0, "所要時間は負けても測る")

func test_finish_without_start_time_is_unmeasured() -> void:
	_context.started_at = 0
	_tally.finish(BattleState.PLAYER_WIN, 0)
	assert_eq(_tally.elapsed(), 0)

func test_finish_clock_rewind_is_zero() -> void:
	_context.started_at = int(Time.get_unix_time_from_system()) + 1000
	_tally.finish(BattleState.PLAYER_WIN, 0)
	assert_eq(_tally.elapsed(), 0, "時計が巻き戻っても負の時間にしない")

func test_finish_without_rank_data_is_blank() -> void:
	_tally._rank_data = {}
	assert_eq(_tally.finish(BattleState.PLAYER_WIN, 0), "")

# --- title ---

func test_title_from_campaign_manifest() -> void:
	var campaign := { "stages": [ { "id": "st1", "title": "x" }, { "id": "st2", "title": "ui.result.turns" } ] }
	assert_eq(_tally.title(campaign), "ターン", "マニフェストの翻訳キーを解決する")

func test_title_falls_back_to_file_name() -> void:
	assert_eq(_tally.title({}), "st2", "載っていなければステージJSONのファイル名")
