extends GutTest
## data/*/convert.gd の検証配線（build_* 純関数）の黒箱テスト。
## 契約: 問題が1件でもあれば json は null（＝壊れた生成物を書かせない）。正常時は期待形の json を返す。
## 「必須列の定義を1つ落としても既存テストが緑のまま」という穴を、必須列を1つずつ抜いて塞ぐ。

const Units = preload("res://data/units/convert.gd")
const Ai = preload("res://data/ai/convert.gd")
const Terrain = preload("res://data/terrain/convert.gd")
const Movement = preload("res://data/movement/convert.gd")

# --- units: build_unit_type ---

func _valid_type_row() -> Dictionary:
	return {
		"id": "knight", "atk_ground": 8, "atk_air": 0, "pierce": 0, "defense": 5,
		"move": 3, "move_type": "walk", "range": 1, "move_after_attack": false,
		"can_capture": true, "max_troops": 10, "capacity": 0,
	}

func test_unit_type_valid_builds_json() -> void:
	var rows := [ _valid_type_row() ]
	var r := Units.build_unit_type(rows, ["walk"])
	assert_eq(r["problems"].size(), 0, "正常＝違反0")
	assert_not_null(r["json"], "正常時は json を返す")
	assert_eq(r["json"]["types"], rows, "json は { types: rows }")

func test_unit_type_each_required_column_pins_json_null() -> void:
	# TYPE_REQUIRED を1列ずつ落とすと必ず json=null。列定義の欠落を退行防止で固定。
	for col in Units.TYPE_REQUIRED:
		var row := _valid_type_row()
		row.erase(col)
		var r := Units.build_unit_type([row], ["walk"])
		assert_gt(r["problems"].size(), 0, "'%s' 欠落で違反" % col)
		assert_null(r["json"], "'%s' 欠落で json=null（書かない）" % col)

func test_unit_type_unknown_move_type_blocks() -> void:
	var row := _valid_type_row()
	row["move_type"] = "swim"  # movement に無い移動タイプ
	var r := Units.build_unit_type([row], ["walk"])
	assert_null(r["json"], "未定義 move_type 参照で json=null")

func test_unit_type_duplicate_id_blocks() -> void:
	var r := Units.build_unit_type([ _valid_type_row(), _valid_type_row() ], ["walk"])
	assert_null(r["json"], "id 重複で json=null")

# --- units: build_unit_skin ---

func _valid_skin_row(sid: String, tid: String, side: String) -> Dictionary:
	return { "skin_id": sid, "name": "名", "side": side, "type_id": tid }

func test_unit_skin_valid_builds_json() -> void:
	var rows := [
		_valid_skin_row("kn_a", "knight", "ally"),
		_valid_skin_row("kn_e", "knight", "enemy"),
	]
	var r := Units.build_unit_skin(rows, ["knight"])
	assert_eq(r["problems"].size(), 0)
	assert_not_null(r["json"])
	assert_true(r["json"]["skins"].has("knight"), "type_id でグループ化")
	assert_eq(r["json"]["skins"]["knight"]["ally"].size(), 1)
	assert_eq(r["json"]["skins"]["knight"]["enemy"].size(), 1)

func test_unit_skin_category_flows_into_json() -> void:
	# category は参考データとして JSON に乗る（任意列＝無ければ空文字）。ロジックでは使わない前提。
	var with_cat := _valid_skin_row("kn_a", "knight", "ally")
	with_cat["category"] = "基準"
	var r := Units.build_unit_skin([with_cat, _valid_skin_row("kn_e", "knight", "enemy")], ["knight"])
	assert_eq(r["json"]["skins"]["knight"]["ally"][0]["category"], "基準")
	assert_eq(r["json"]["skins"]["knight"]["enemy"][0]["category"], "", "category 無し＝空文字")


func test_unit_skin_each_required_column_pins_json_null() -> void:
	for col in Units.SKIN_REQUIRED:
		var row := _valid_skin_row("kn_a", "knight", "ally")
		row.erase(col)
		var r := Units.build_unit_skin([row], ["knight"])
		assert_null(r["json"], "'%s' 欠落で json=null" % col)

func test_unit_skin_invalid_side_blocks() -> void:
	var r := Units.build_unit_skin([ _valid_skin_row("x", "knight", "neutral") ], ["knight"])
	assert_null(r["json"], "side が enum 外で json=null")

func test_unit_skin_dangling_type_ref_blocks() -> void:
	var r := Units.build_unit_skin([ _valid_skin_row("x", "ghost", "ally") ], ["knight"])
	assert_null(r["json"], "type_id 参照切れで json=null")

func test_unit_skin_duplicate_skin_id_blocks() -> void:
	var rows := [ _valid_skin_row("dup", "knight", "ally"), _valid_skin_row("dup", "knight", "enemy") ]
	var r := Units.build_unit_skin(rows, ["knight"])
	assert_null(r["json"], "skin_id 重複で json=null")

# --- ai: build_presets ---

func _valid_ai_row(label: String) -> Dictionary:
	return {
		"label": label, "engage": "charge", "sight": "-", "retreat": "-",
		"attack": "-", "target": "weak", "advance": "-",
	}

func test_ai_valid_builds_json() -> void:
	var r := Ai.build_presets([ _valid_ai_row("raid") ])
	assert_eq(r["problems"].size(), 0)
	assert_not_null(r["json"])
	assert_true(r["json"]["presets"].has("raid"))
	assert_false(r["json"]["presets"]["raid"].has("label"), "label は軸に含めない")
	assert_eq(r["json"]["presets"]["raid"]["engage"], "charge")

func test_ai_each_required_axis_pins_json_null() -> void:
	for axis in Ai.REQUIRED_AXES:
		var row := _valid_ai_row("raid")
		row.erase(axis)
		var r := Ai.build_presets([row])
		assert_null(r["json"], "軸 '%s' 欠落で json=null" % axis)

func test_ai_empty_label_blocks() -> void:
	var r := Ai.build_presets([ _valid_ai_row("") ])
	assert_null(r["json"], "label 空で json=null")

# --- terrain: build_type ---

func test_terrain_type_valid_builds_json() -> void:
	var rows := [
		{ "id": "plain", "char": ".", "atk": 0, "def": 0 },
		{ "id": "forest", "char": "F", "atk": 0, "def": 2 },
	]
	var r := Terrain.build_type(rows)
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["terrains"], rows)

func test_terrain_type_each_required_column_pins_json_null() -> void:
	for col in Terrain.TYPE_REQUIRED:
		var row := { "id": "plain", "char": ".", "atk": 0, "def": 0 }
		row.erase(col)
		var r := Terrain.build_type([row])
		assert_null(r["json"], "'%s' 欠落で json=null" % col)

func test_terrain_type_duplicate_char_blocks() -> void:
	var rows := [
		{ "id": "plain", "char": ".", "atk": 0, "def": 0 },
		{ "id": "road", "char": ".", "atk": 0, "def": 0 },  # char 衝突
	]
	assert_null(Terrain.build_type(rows)["json"], "char 重複で json=null")

# --- terrain: build_skin ---

func _valid_terrain_skin(sid: String, tid: String) -> Dictionary:
	return { "skin_id": sid, "terrain_type": tid, "name": "名", "orientable": false }

func test_terrain_skin_valid_builds_json() -> void:
	var rows := [ _valid_terrain_skin("plain_a", "plain"), _valid_terrain_skin("forest_a", "forest") ]
	var r := Terrain.build_skin(rows, ["plain", "forest"])
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"], rows)

func test_terrain_skin_each_required_column_pins_json_null() -> void:
	for col in Terrain.SKIN_REQUIRED:
		var rows := [ _valid_terrain_skin("plain_a", "plain"), _valid_terrain_skin("forest_a", "forest") ]
		rows[0].erase(col)
		var r := Terrain.build_skin(rows, ["plain", "forest"])
		assert_null(r["json"], "'%s' 欠落で json=null" % col)

func test_terrain_skin_uncovered_type_blocks() -> void:
	# forest のスキンが1枚も無い＝描画フォールバック先が無い。
	var r := Terrain.build_skin([ _valid_terrain_skin("plain_a", "plain") ], ["plain", "forest"])
	assert_null(r["json"], "type 未カバーで json=null")

func test_terrain_skin_non_bool_orientable_blocks() -> void:
	var rows := [ _valid_terrain_skin("plain_a", "plain"), _valid_terrain_skin("forest_a", "forest") ]
	rows[0]["orientable"] = "maybe"  # bool 以外の誤記
	var r := Terrain.build_skin(rows, ["plain", "forest"])
	assert_null(r["json"], "orientable が非bool で json=null")

# --- movement: build ---

func _valid_move_rows() -> Array:
	return [
		{ "move_type": "walk", "name": "歩行", "plain": 1, "forest": 2 },
		{ "move_type": "fly", "name": "飛行", "plain": 1, "forest": 1 },
	]

func test_movement_valid_builds_json() -> void:
	var r := Movement.build(_valid_move_rows(), ["plain", "forest"])
	assert_eq(r["problems"].size(), 0)
	assert_not_null(r["json"])
	assert_eq(r["json"]["movement_types"]["walk"], { "plain": 1, "forest": 2 }, "コストは地形キーだけの純辞書")
	assert_eq(r["json"]["move_type_names"]["fly"], "飛行", "表示名は別辞書")

func test_movement_each_required_column_pins_json_null() -> void:
	for col in Movement.REQUIRED:
		var rows := _valid_move_rows()
		rows[0].erase(col)
		var r := Movement.build(rows, ["plain", "forest"])
		assert_null(r["json"], "'%s' 欠落で json=null" % col)

func test_movement_missing_terrain_column_blocks() -> void:
	# terrain に mountain があるのにコスト列が無い＝黙ってコスト1になる罠。
	var r := Movement.build(_valid_move_rows(), ["plain", "forest", "mountain"])
	assert_null(r["json"], "地形の列欠落（不完全表）で json=null")

func test_movement_extra_terrain_column_blocks() -> void:
	var rows := _valid_move_rows()
	for row in rows:
		row["swamp"] = 3  # terrain に無い地形の列
	var r := Movement.build(rows, ["plain", "forest"])
	assert_null(r["json"], "terrain に無い列で json=null")

func test_movement_bad_cost_value_blocks() -> void:
	var rows := _valid_move_rows()
	rows[0]["forest"] = "y"  # int でも "x" でもない誤記
	var r := Movement.build(rows, ["plain", "forest"])
	assert_null(r["json"], "不正コスト値で json=null")

func test_movement_duplicate_move_type_blocks() -> void:
	var rows := [
		{ "move_type": "walk", "name": "歩行", "plain": 1, "forest": 2 },
		{ "move_type": "walk", "name": "歩行2", "plain": 1, "forest": 1 },
	]
	assert_null(Movement.build(rows, ["plain", "forest"])["json"], "move_type 重複で json=null")
