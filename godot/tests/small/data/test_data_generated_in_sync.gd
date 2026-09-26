extends GutTest
## 生成JSON が正本CSV と食い違っていないか（ドリフト検出）。
## 各 data/*/convert.gd の build_* 純関数に、同梱の正本CSV（res://）を読ませてメモリ上で JSON を作り、
## コミット済みの生成JSON と突き合わせる。「CSV を直したが convert を回し忘れた」をここで落とす。
## ファイルは書かない（生成物の更新は convert を実行して行う）。
## 比べるのは中身＝両方を JSON 文字列に通して読み直してから比べる（数値は読み直すと float になり、
## 書き出し側の int と揃わないため。インデント・改行の違いも見ない）。

const Csv = preload("res://data/csv_util.gd")
const Units = preload("res://data/units/convert.gd")
const Effects = preload("res://data/effects/convert.gd")
const Ai = preload("res://data/ai/convert.gd")
const Terrain = preload("res://data/terrain/convert.gd")
const Movement = preload("res://data/movement/convert.gd")


## build_* の結果とコミット済み JSON を比べる。検証エラーがあれば convert は書かない＝その時点で食い違い。
func _assert_in_sync(result: Dictionary, json_path: String) -> void:
	assert_eq(result["problems"], [], "%s の正本CSV に検証エラーがある（convert が書かない状態）" % json_path)
	if result["json"] == null:
		return
	var committed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	assert_not_null(committed, "%s が読めること" % json_path)
	var built: Variant = JSON.parse_string(JSON.stringify(result["json"]))
	# 大きな表なので差分全体は出さず、どの生成物が古いかだけを言う。
	assert_true(JSON.stringify(built) == JSON.stringify(committed),
		"%s が正本CSV と食い違う（CSV を直したら convert を実行して再生成する）" % json_path)


func test_ai_json_in_sync() -> void:
	var rows := Csv.read_table("res://data/ai/ai.csv")
	_assert_in_sync(Ai.build_presets(rows), "res://data/ai/ai.json")


func test_combat_effect_json_in_sync() -> void:
	var rows := Csv.read_table("res://data/effects/combat_effect.csv")
	_assert_in_sync(Effects.build(rows), "res://data/effects/combat_effect.json")


func test_movement_json_in_sync() -> void:
	var rows := Csv.read_table("res://data/movement/movement.csv")
	var terrain_ids := Csv.value_set(Csv.read_table("res://data/terrain/terrain_type.csv"), "id")
	_assert_in_sync(Movement.build(rows, terrain_ids), "res://data/movement/movement.json")


func test_terrain_type_json_in_sync() -> void:
	var rows := Csv.read_table("res://data/terrain/terrain_type.csv")
	_assert_in_sync(Terrain.build_type(rows), "res://data/terrain/terrain_type.json")


func test_terrain_skin_json_in_sync() -> void:
	var type_rows := Csv.read_table("res://data/terrain/terrain_type.csv")
	var skin_rows := Csv.read_table("res://data/terrain/terrain_skin.csv")
	_assert_in_sync(Terrain.build_skin(skin_rows, type_rows), "res://data/terrain/terrain_skin.json")


func test_unit_type_json_in_sync() -> void:
	var rows := Csv.read_table("res://data/units/unit_type.csv")
	var move_types := Csv.value_set(Csv.read_table("res://data/movement/movement.csv"), "move_type")
	_assert_in_sync(Units.build_unit_type(rows, move_types), "res://data/units/unit_type.json")


func test_unit_skin_json_in_sync() -> void:
	var type_rows := Csv.read_table("res://data/units/unit_type.csv")
	var skin_rows := Csv.read_table("res://data/units/unit_skin.csv")
	var type_ids := Csv.value_set(type_rows, "id")
	var effect_ids := Csv.value_set(Csv.read_table("res://data/effects/combat_effect.csv"), "effect_id")
	_assert_in_sync(Units.build_unit_skin(skin_rows, type_ids, effect_ids), "res://data/units/unit_skin.json")
	# convert は分類の検証（category_problems）が通らないときも書かない。
	assert_eq(Units.category_problems(skin_rows, type_rows), [], "unit_skin.csv の分類に検証エラーがある")
