extends GutTest
## data/csv_util.gd の検証ロジック（missing_required）のテスト。
## read_table のファイルIOは対象外（純関数の検証だけを見る）。

const Csv = preload("res://data/csv_util.gd")

func test_all_required_present_passes() -> void:
	var rows := [ { "label": "a", "engage": "charge", "sight": "-", "retreat": 0 } ]
	assert_eq(Csv.missing_required(rows, ["engage", "sight", "retreat"], "label").size(), 0, "全必須列そろい＝違反0")

func test_dash_and_zero_are_non_empty() -> void:
	# `-`（該当なし の明示値）と 数値0 は「非空」扱い＝違反にしない。
	var rows := [ { "label": "a", "sight": "-", "retreat": 0 } ]
	assert_eq(Csv.missing_required(rows, ["sight", "retreat"], "label").size(), 0, "`-` と 0 は埋まっている")

func test_missing_column_counts() -> void:
	var rows := [ { "label": "a", "engage": "charge" } ]  # sight が欠落
	assert_eq(Csv.missing_required(rows, ["engage", "sight"], "label").size(), 1, "欠落列を1件数える")

func test_empty_string_cell_counts() -> void:
	var rows := [ { "label": "a", "advance": "" } ]  # 空セル
	assert_eq(Csv.missing_required(rows, ["advance"], "label").size(), 1, "空文字セルを違反にする")

func test_whitespace_only_cell_counts() -> void:
	var rows := [ { "label": "a", "advance": "   " } ]  # 空白のみ
	assert_eq(Csv.missing_required(rows, ["advance"], "label").size(), 1, "空白のみも空扱い")

func test_counts_across_multiple_rows() -> void:
	var rows := [
		{ "label": "a", "engage": "charge", "sight": "-" },
		{ "label": "b", "engage": "", "sight": "-" },   # engage 空
		{ "label": "c", "sight": "-" },                 # engage 欠落
	]
	assert_eq(Csv.missing_required(rows, ["engage", "sight"], "label").size(), 2, "行をまたいで違反を合算")

func test_problem_message_names_label_and_column() -> void:
	# メッセージが「どの行(label)のどの列か」を含む（診断性の担保）。
	var rows := [ { "label": "boss", "advance": "" } ]
	var problems := Csv.missing_required(rows, ["advance"], "label")
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "boss")
	assert_string_contains(problems[0], "advance")

# --- duplicates ---

func test_duplicates_none() -> void:
	var rows := [ { "id": "a" }, { "id": "b" }, { "id": "c" } ]
	assert_eq(Csv.duplicates(rows, "id").size(), 0, "重複なし")

func test_duplicates_reports_each_value_once() -> void:
	var rows := [ { "id": "a" }, { "id": "b" }, { "id": "a" }, { "id": "a" } ]
	var dups := Csv.duplicates(rows, "id")
	assert_eq(dups.size(), 1, "重複値は1回だけ返す")
	assert_eq(str(dups[0]), "a")

func test_duplicates_ignores_empty() -> void:
	var rows := [ { "id": "" }, { "id": "" } ]
	assert_eq(Csv.duplicates(rows, "id").size(), 0, "空セルは重複扱いしない")

# --- invalid_values（enum / 参照整合） ---

func test_invalid_values_enum() -> void:
	var rows := [ { "label": "a", "side": "ally" }, { "label": "b", "side": "neutral" } ]
	var problems := Csv.invalid_values(rows, "side", ["ally", "enemy"], "label")
	assert_eq(problems.size(), 1, "許容外(neutral)を1件")
	assert_string_contains(problems[0], "b")
	assert_string_contains(problems[0], "neutral")

func test_invalid_values_ignores_empty() -> void:
	# 空セルは missing_required の担当＝ここでは無視。
	var rows := [ { "label": "a", "side": "" } ]
	assert_eq(Csv.invalid_values(rows, "side", ["ally", "enemy"], "label").size(), 0)

func test_invalid_values_as_reference_check() -> void:
	# 参照整合: type_id が既知idの集合に無ければ未定義参照。
	var types := [ { "id": "cleric" }, { "id": "archer" } ]
	var known := Csv.value_set(types, "id")
	var skins := [ { "skin_id": "goblin", "type_id": "cleric" }, { "skin_id": "x", "type_id": "typo" } ]
	var problems := Csv.invalid_values(skins, "type_id", known, "skin_id")
	assert_eq(problems.size(), 1, "typo の参照を1件")
	assert_string_contains(problems[0], "typo")

func test_value_set_dedupes_and_skips_empty() -> void:
	var rows := [ { "id": "a" }, { "id": "a" }, { "id": "" }, { "id": "b" } ]
	var s := Csv.value_set(rows, "id")
	assert_eq(s.size(), 2, "a,b の2種（重複・空を除く）")
	assert_true("a" in s and "b" in s)
