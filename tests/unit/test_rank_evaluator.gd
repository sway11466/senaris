extends GutTest
## RankEvaluator（評価ランクの判定）のテスト。仕様 → doc/gdd/rank.md

## 典型的な閾値（turn_limit=30 の 50%/75% 基準、自軍8体の 50%/25% 基準）。
var _rank := { "turn_s": 15, "turn_a": 22, "survival_s": 4, "survival_a": 2 }

# --- evaluate: 両指標の低い方が最終ランク ---

func test_both_s_gives_s() -> void:
	assert_eq(RankEvaluator.evaluate(10, 8, 8, _rank), "S")

func test_turn_s_survival_a_gives_a() -> void:
	assert_eq(RankEvaluator.evaluate(10, 3, 8, _rank), "A")

func test_turn_a_survival_s_gives_a() -> void:
	assert_eq(RankEvaluator.evaluate(18, 5, 8, _rank), "A")

func test_both_a_gives_a() -> void:
	assert_eq(RankEvaluator.evaluate(18, 3, 8, _rank), "A")

func test_turn_s_survival_b_gives_b() -> void:
	assert_eq(RankEvaluator.evaluate(10, 1, 8, _rank), "B")

func test_turn_b_survival_s_gives_b() -> void:
	assert_eq(RankEvaluator.evaluate(25, 8, 8, _rank), "B")

func test_both_b_gives_b() -> void:
	assert_eq(RankEvaluator.evaluate(25, 1, 8, _rank), "B")

# --- 境界値 ---

func test_turn_at_boundary_s() -> void:
	# turn_s=15 のとき 14 は S、15 は A（未満なので）
	assert_eq(RankEvaluator.evaluate(14, 8, 8, _rank), "S")
	assert_eq(RankEvaluator.evaluate(15, 8, 8, _rank), "A")

func test_turn_at_boundary_a() -> void:
	# turn_a=22 のとき 21 は A、22 は B
	assert_eq(RankEvaluator.evaluate(21, 8, 8, _rank), "A")
	assert_eq(RankEvaluator.evaluate(22, 8, 8, _rank), "B")

func test_survival_at_boundary_s() -> void:
	# survival_s=4 のとき 4 は S、3 は A（以上なので）
	assert_eq(RankEvaluator.evaluate(10, 4, 8, _rank), "S")
	assert_eq(RankEvaluator.evaluate(10, 3, 8, _rank), "A")

func test_survival_at_boundary_a() -> void:
	# survival_a=2 のとき 2 は A、1 は B
	assert_eq(RankEvaluator.evaluate(10, 2, 8, _rank), "A")
	assert_eq(RankEvaluator.evaluate(10, 1, 8, _rank), "B")

# --- rank_data が空＝ランクなし ---

func test_empty_rank_data_returns_empty() -> void:
	assert_eq(RankEvaluator.evaluate(10, 8, 8, {}), "")

# --- start_allies が 0（異常系） ---

func test_zero_start_allies() -> void:
	assert_eq(RankEvaluator.evaluate(10, 0, 0, _rank), "B")

# --- is_better ---

func test_s_is_better_than_a() -> void:
	assert_true(RankEvaluator.is_better("S", "A"))

func test_a_is_better_than_b() -> void:
	assert_true(RankEvaluator.is_better("A", "B"))

func test_s_is_better_than_b() -> void:
	assert_true(RankEvaluator.is_better("S", "B"))

func test_same_rank_is_not_better() -> void:
	assert_false(RankEvaluator.is_better("A", "A"))

func test_b_is_not_better_than_a() -> void:
	assert_false(RankEvaluator.is_better("B", "A"))

# --- worse ---

func test_worse_returns_lower() -> void:
	assert_eq(RankEvaluator.worse("S", "A"), "A")
	assert_eq(RankEvaluator.worse("A", "S"), "A")
	assert_eq(RankEvaluator.worse("S", "B"), "B")
	assert_eq(RankEvaluator.worse("A", "A"), "A")
