extends GutTest
## data/csv_util.gd のテスト。検証の純関数（missing_required ほか）に加え、
## read_table（2行ヘッダ・空行/列不足スキップ）と typed（型推論）も固定する。

const Csv = preload("res://data/csv_util.gd")

## read_table 用の一時CSV置き場（テストごとに書いて after_each で消す）。
const TMP := "user://test_csv_util_tmp.csv"

func after_each() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

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

# --- typed（型推論） ---

func test_typed_int() -> void:
	assert_eq(Csv.typed("8"), 8)
	assert_typeof(Csv.typed("8"), TYPE_INT)

func test_typed_float() -> void:
	assert_eq(Csv.typed("1.0"), 1.0)
	assert_typeof(Csv.typed("1.0"), TYPE_FLOAT)

func test_typed_bool() -> void:
	assert_eq(Csv.typed("true"), true)
	assert_eq(Csv.typed("false"), false)
	assert_typeof(Csv.typed("true"), TYPE_BOOL)

func test_typed_string_passthrough() -> void:
	# `-`（該当なし）や "x"（進入不可）は文字列のまま。空文字も string。
	assert_eq(Csv.typed("-"), "-")
	assert_eq(Csv.typed("x"), "x")
	assert_eq(Csv.typed(""), "")
	assert_typeof(Csv.typed("-"), TYPE_STRING)

# --- read_table（一時CSVを書いて読む） ---

func _read(text: String) -> Array:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return Csv.read_table(TMP)

func test_read_table_first_row_keys_second_row_skipped() -> void:
	var rows := _read("id,atk\nＩＤ,攻撃\nknight,8\n")
	assert_eq(rows.size(), 1, "2行目(日本語ラベル)はデータ行にならない")
	assert_eq(rows[0].get("id"), "knight")
	assert_eq(rows[0].get("atk"), 8)

func test_read_table_types_values() -> void:
	var rows := _read("id,atk,speed,fly,memo\nID,攻,速,飛,備\nknight,8,1.5,true,-\n")
	assert_typeof(rows[0]["atk"], TYPE_INT)
	assert_eq(rows[0]["speed"], 1.5)
	assert_eq(rows[0]["fly"], true)
	assert_eq(rows[0]["memo"], "-")

func test_read_table_skips_blank_rows_silently() -> void:
	# 末尾改行・スペーサ行（空白やカンマだけ）は黙って飛ばす。
	var rows := _read("id,atk\nID,攻\n\nknight,8\n , \n\n")
	assert_eq(rows.size(), 1, "データ行は knight の1行だけ")

func test_read_table_skips_short_rows_and_keeps_rest() -> void:
	# 列不足の行はスキップし、必ず push_error で知らせる（旧実装の無言スキップへの退行防止）。他の行は生きる。
	var rows := _read("id,atk\nID,攻\nknight,8\nbroken\narcher,6\n")
	assert_eq(rows.size(), 2, "列不足の行だけ落ち、前後の行は残る")
	assert_eq(rows[1]["id"], "archer")
	assert_push_error("列不足")

func test_read_table_missing_file_returns_empty() -> void:
	assert_eq(Csv.read_table("user://no_such_file.csv").size(), 0, "開けないファイルは空配列")
	assert_push_error("開けない")
