extends GutTest
## data/*/convert.gd の検証配線（build_* 純関数）の黒箱テスト。
## 契約: 問題が1件でもあれば json は null（＝壊れた生成物を書かせない）。正常時は期待形の json を返す。
## 「必須列の定義を1つ落としても既存テストが緑のまま」という穴を、必須列を1つずつ抜いて塞ぐ。

const Units = preload("res://data/units/convert.gd")
const Effects = preload("res://data/effects/convert.gd")
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
	return { "skin_id": sid, "name": "名", "side": side, "type_id": tid, "combat_lineup": "squad" }

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

# --- units: combat_lineup（戦闘演出での並べ方） ---

func test_combat_lineup_flows_into_json() -> void:
	var row := _valid_skin_row("kn_a", "knight", "ally")
	row["combat_lineup"] = "single"
	var r := Units.build_unit_skin([row], ["knight"])
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"]["knight"]["ally"][0]["combat_lineup"], "single")

func test_combat_lineup_invalid_value_blocks() -> void:
	# 打ち間違えを既定へ倒すと「squad と決めた」と区別できないので生成を止める。
	var row := _valid_skin_row("kn_a", "knight", "ally")
	row["combat_lineup"] = "solo"
	var r := Units.build_unit_skin([row], ["knight"])
	assert_null(r["json"], "combat_lineup が enum 外で json=null")

func test_retinue_without_retainers_blocks() -> void:
	var row := _valid_skin_row("boss", "knight", "enemy")
	row["combat_lineup"] = "retinue"
	var r := Units.build_unit_skin([row], ["knight"])
	assert_null(r["json"], "retinue なのに従者が無いと json=null")

func test_retainers_without_retinue_blocks() -> void:
	# squad/single に従者を書いても表示に出ない＝書いた意図が黙って捨てられる。
	var row := _valid_skin_row("boss", "knight", "enemy")
	row["retainers"] = "mob"
	var r := Units.build_unit_skin([row, _valid_skin_row("mob", "knight", "enemy")], ["knight"])
	assert_null(r["json"], "retinue 以外で retainers を書くと json=null")

# --- units: combat_effect（攻撃エフェクトの割り当て） ---

func test_combat_effect_flows_into_json() -> void:
	var row := _valid_skin_row("kn_a", "knight", "ally")
	row["combat_effect"] = "slash_m"
	var r := Units.build_unit_skin([row], ["knight"], ["slash_m"])
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"]["knight"]["ally"][0]["combat_effect"], "slash_m")

func test_combat_effect_empty_is_allowed() -> void:
	# 空欄＝既定のスパーク（未整備が画面で分かる運用）。必須にはしない。
	var r := Units.build_unit_skin([ _valid_skin_row("kn_a", "knight", "ally") ], ["knight"], ["slash_m"])
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"]["knight"]["ally"][0]["combat_effect"], "")

func test_combat_effect_dangling_ref_blocks() -> void:
	# 打ち間違えると黙ってスパークに落ちて気づけないので、生成を止める。
	var row := _valid_skin_row("kn_a", "knight", "ally")
	row["combat_effect"] = "slash_typo"
	var r := Units.build_unit_skin([row], ["knight"], ["slash_m"])
	assert_null(r["json"], "未定義の combat_effect で json=null")

# --- units: map_move_sfx（移動音のスキン上書き） ---

func test_map_move_sfx_flows_into_json() -> void:
	var row := _valid_skin_row("kn_a", "knight", "ally")
	row["map_move_sfx"] = "move_float"
	var r := Units.build_unit_skin([row], ["knight"])
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"]["knight"]["ally"][0]["map_move_sfx"], "move_float")

func test_map_move_sfx_empty_is_allowed() -> void:
	# 空欄＝移動タイプの既定を使う（上書きが要る駒だけ書く運用）。
	var r := Units.build_unit_skin([ _valid_skin_row("kn_a", "knight", "ally") ], ["knight"])
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"]["knight"]["ally"][0]["map_move_sfx"], "")

func test_map_move_sfx_unknown_id_blocks() -> void:
	# 綴りを間違えると黙って無音になるので、生成を止める。
	var row := _valid_skin_row("kn_a", "knight", "ally")
	row["map_move_sfx"] = "move_flght"
	var r := Units.build_unit_skin([row], ["knight"])
	assert_null(r["json"], "SfxCatalog.MOVE_SFX に無い素材IDで json=null")

# --- effects: build（攻撃エフェクト表） ---

func _valid_effect_row(eid: String, kind: String) -> Dictionary:
	return { "effect_id": eid, "name": "名", "kind": kind, "scale": 1.0 }

func test_effects_valid_builds_json() -> void:
	var rows := [ _valid_effect_row("slash_s", "impact"), _valid_effect_row("arrow", "projectile") ]
	var r := Effects.build(rows)
	assert_eq(r["problems"].size(), 0, "正常＝違反0")
	assert_eq(r["json"]["effects"], rows, "json は { effects: rows }")

func test_effects_each_required_column_pins_json_null() -> void:
	for col in Effects.REQUIRED:
		var row := _valid_effect_row("slash_s", "impact")
		row.erase(col)
		var r := Effects.build([row])
		assert_null(r["json"], "'%s' 欠落で json=null" % col)

func test_effects_invalid_kind_blocks() -> void:
	var r := Effects.build([ _valid_effect_row("slash_s", "burst") ])
	assert_null(r["json"], "kind が enum 外で json=null")

func test_effects_non_numeric_scale_blocks() -> void:
	# 文字列が混じると float() で 0 に化けてエフェクトが消えるので、生成を止める。
	var row := _valid_effect_row("slash_s", "impact")
	row["scale"] = "おおきめ"
	var r := Effects.build([row])
	assert_null(r["json"], "scale が数値でないと json=null")

func test_effects_zero_scale_blocks() -> void:
	var row := _valid_effect_row("slash_s", "impact")
	row["scale"] = 0
	var r := Effects.build([row])
	assert_null(r["json"], "scale=0（見えない）で json=null")

func test_effects_duplicate_id_blocks() -> void:
	var rows := [ _valid_effect_row("slash_s", "impact"), _valid_effect_row("slash_s", "projectile") ]
	var r := Effects.build(rows)
	assert_null(r["json"], "effect_id 重複で json=null")

# --- units: retainers（戦闘演出でボスの脇に並べる従者スキン） ---

func _skin_rows_with_retainers(value: String) -> Array:
	var boss := _valid_skin_row("boss", "knight", "enemy")
	boss["combat_lineup"] = "retinue"
	boss["retainers"] = value
	return [boss, _valid_skin_row("mob", "knight", "enemy")]

func test_retainers_split_into_array() -> void:
	var r := Units.build_unit_skin(_skin_rows_with_retainers("mob|boss|mob"), ["knight"])
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"]["knight"]["enemy"][0]["retainers"], ["mob", "boss", "mob"])

func test_retainers_empty_cell_is_empty_array() -> void:
	# 空欄＝従者なし＝全部本人の絵。列を書いていない既存行もここに落ちる。
	var r := Units.build_unit_skin([ _valid_skin_row("solo", "knight", "ally") ], ["knight"])
	assert_eq(r["json"]["skins"]["knight"]["ally"][0]["retainers"], [])

func test_retainers_trims_and_drops_blanks() -> void:
	var r := Units.build_unit_skin(_skin_rows_with_retainers(" mob | | mob "), ["knight"])
	assert_eq(r["json"]["skins"]["knight"]["enemy"][0]["retainers"], ["mob", "mob"])

func test_retainers_dangling_skin_ref_blocks() -> void:
	# 打ち間違えると「黙って絵が出ない」ので、生成を止めて気づかせる。
	var r := Units.build_unit_skin(_skin_rows_with_retainers("mob|typo"), ["knight"])
	assert_null(r["json"], "未定義 skin_id を指す retainers で json=null")

func test_retainers_over_max_blocks() -> void:
	var many := []
	for i in Units.RETAINER_MAX + 1:
		many.append("mob")
	var r := Units.build_unit_skin(_skin_rows_with_retainers("|".join(many)), ["knight"])
	assert_null(r["json"], "隊列に入り切らない数の retainers で json=null")

func test_retainers_at_max_is_allowed() -> void:
	var many := []
	for i in Units.RETAINER_MAX:
		many.append("mob")
	var r := Units.build_unit_skin(_skin_rows_with_retainers("|".join(many)), ["knight"])
	assert_eq(r["problems"].size(), 0, "上限ちょうどは通る")

# --- ai: build_presets ---

func _valid_ai_row(ai: String) -> Dictionary:
	return { "ai": ai, "name": "拠点攻略", "sight": "-", "stack": "-", "retreat": "-" }

func test_ai_valid_builds_json() -> void:
	var r := Ai.build_presets([ _valid_ai_row("raid") ])
	assert_eq(r["problems"].size(), 0)
	assert_not_null(r["json"])
	assert_true(r["json"]["presets"].has("raid"))
	assert_false(r["json"]["presets"]["raid"].has("ai"), "主キー ai はパラメーターに含めない")
	assert_eq(r["json"]["presets"]["raid"]["name"], "拠点攻略")

func test_ai_each_required_axis_pins_json_null() -> void:
	for axis in Ai.REQUIRED_AXES:
		var row := _valid_ai_row("raid")
		row.erase(axis)
		var r := Ai.build_presets([row])
		assert_null(r["json"], "列 '%s' 欠落で json=null" % axis)

func test_ai_empty_label_blocks() -> void:
	var r := Ai.build_presets([ _valid_ai_row("") ])
	assert_null(r["json"], "ai 空で json=null")

# --- terrain: build_type ---

func _valid_terrain_type(id: String, ch: String, layer := "footing") -> Dictionary:
	return { "id": id, "name": "名", "layer": layer, "char": ch, "atk": 0, "def": 0, "sight_cost": 1 }

## build_skin に渡す地形タイプ表（足場2つ）。
func _terrain_types() -> Array:
	return [ _valid_terrain_type("plain", "."), _valid_terrain_type("forest", "F") ]

func test_terrain_type_valid_builds_json() -> void:
	var rows := [
		_valid_terrain_type("plain", "."),
		_valid_terrain_type("forest", "F"),
		_valid_terrain_type("rock", "C", "object"),
	]
	rows[2]["sight_cost"] = "x"  # x＝完全遮蔽も有効
	var r := Terrain.build_type(rows)
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["terrains"], rows)

func test_terrain_type_each_required_column_pins_json_null() -> void:
	for col in Terrain.TYPE_REQUIRED:
		var row := _valid_terrain_type("plain", ".")
		row.erase(col)
		var r := Terrain.build_type([row])
		assert_null(r["json"], "'%s' 欠落で json=null" % col)

func test_terrain_type_duplicate_char_blocks() -> void:
	var rows := [ _valid_terrain_type("plain", "."), _valid_terrain_type("road", ".") ]  # char 衝突
	assert_null(Terrain.build_type(rows)["json"], "char 重複で json=null")

func test_terrain_type_unknown_layer_blocks() -> void:
	# layer は footing / object だけ。未知の語が黙って足場扱いになると描き方を取り違える。
	var row := _valid_terrain_type("plain", ".")
	row["layer"] = "prop"
	assert_null(Terrain.build_type([row])["json"], "layer が未知の値で json=null")

func test_terrain_type_invalid_sight_cost_blocks() -> void:
	# sight_cost は 0以上の整数か 'x' だけ許す（負数・小数・他文字列は弾く）。
	for bad in [-1, 1.5, "y", "opaque"]:
		var row := _valid_terrain_type("plain", ".")
		row["sight_cost"] = bad
		assert_null(Terrain.build_type([row])["json"], "sight_cost=%s で json=null" % str(bad))
	# 0 と 'x' は有効
	var zero := _valid_terrain_type("a", "a")
	zero["sight_cost"] = 0
	assert_eq(Terrain.build_type([zero])["problems"].size(), 0, "0 は有効")
	var opaque := _valid_terrain_type("b", "b")
	opaque["sight_cost"] = "x"
	assert_eq(Terrain.build_type([opaque])["problems"].size(), 0, "'x' は有効")

# --- terrain: TerrainType.sight_cost（実データ）---

func test_terrain_sight_cost_from_real_data() -> void:
	assert_eq(TerrainType.sight_cost("plain"), 1, "開地=1")
	assert_eq(TerrainType.sight_cost("forest"), 2, "森=2（減衰）")
	assert_eq(TerrainType.sight_cost("bedrock"), 2, "岩地=2")
	assert_eq(TerrainType.sight_cost("wall"), TerrainType.SIGHT_OPAQUE, "壁=完全遮蔽")
	assert_eq(TerrainType.sight_cost("nonexistent"), TerrainType.SIGHT_DEFAULT, "未定義=既定1")
	var table := TerrainType.sight_cost_table()
	assert_eq(int(table.get("forest", 0)), 2, "注入テーブルにも反映")

# --- terrain: build_skin ---

func _valid_terrain_skin(sid: String, tid: String) -> Dictionary:
	return { "skin_id": sid, "terrain_type": tid, "name": "名", "orientable": "none",
		"elevation": 0, "floor": 0, "ignore_board_height": "false" }

func test_terrain_skin_valid_builds_json() -> void:
	var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
	var r := Terrain.build_skin(rows, _terrain_types())
	assert_eq(r["problems"].size(), 0)
	assert_eq(r["json"]["skins"], rows)

func test_terrain_skin_each_required_column_pins_json_null() -> void:
	for col in Terrain.SKIN_REQUIRED:
		var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
		rows[0].erase(col)
		var r := Terrain.build_skin(rows, _terrain_types())
		assert_null(r["json"], "'%s' 欠落で json=null" % col)

func test_terrain_skin_amount_must_be_number() -> void:
	# 見た目の量が文字列だと float() で 0 に化けて黙って平らになる＝生成前に弾く。
	for col in ["elevation", "floor"]:
		var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
		rows[0][col] = "０.18"  # 全角＝数値に推論されず文字列のまま入る打ち間違い
		var r := Terrain.build_skin(rows, _terrain_types())
		assert_null(r["json"], "'%s' が数値でなければ json=null" % col)

func test_terrain_skin_negative_amount_is_valid() -> void:
	# 負の高さは水面（盤の高さを無視して沈む足場）で使う＝弾かない。
	var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
	rows[0]["elevation"] = -0.18
	rows[0]["floor"] = 0
	assert_eq(Terrain.build_skin(rows, _terrain_types())["problems"].size(), 0, "負の高さは有効")

func test_terrain_skin_ignore_board_height_must_be_bool_word() -> void:
	# 盤の高さを無視するかは全行に true/false を明示する（空を既定に倒さない）。
	var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
	rows[0]["ignore_board_height"] = "yes"
	assert_null(Terrain.build_skin(rows, _terrain_types())["json"], "未知の語は弾く")
	rows[0].erase("ignore_board_height")
	assert_null(Terrain.build_skin(rows, _terrain_types())["json"], "空/欠落も弾く")

func test_terrain_footing_without_same_name_skin_blocks() -> void:
	# 足場は型IDと同名のスキンで引く（ステージが指定しないセル）。同名が無いと引けない。
	var r := Terrain.build_skin([ _valid_terrain_skin("plain", "plain") ], _terrain_types())
	assert_null(r["json"], "足場 forest に同名スキンが無く json=null")

func test_terrain_object_without_map_ground_blocks() -> void:
	# オブジェクトは足場の上に置く＝下に敷く足場を書かないと、描く側が既定を決めることになる。
	var types := _terrain_types()
	types.append(_valid_terrain_type("fence", "+", "object"))
	var rows := [
		_valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest"),
		_object_terrain_skin("plain_fence", "fence"),
	]
	rows[2].erase("map_ground")
	assert_null(Terrain.build_skin(rows, types)["json"], "object で map_ground 空なら json=null")
	rows[2]["map_ground"] = "plain"
	assert_eq(Terrain.build_skin(rows, types)["problems"].size(), 0, "足場を書けば通る")

## オブジェクトのスキン行（足場・描画倍率・足元の奥行きを埋めた、最小の有効な行）。
func _object_terrain_skin(sid: String, tid: String) -> Dictionary:
	var r := _valid_terrain_skin(sid, tid)
	r["map_ground"] = "plain"
	r["map_scale"] = 1.0
	r["object_foot_z"] = 0.2
	return r

func test_terrain_object_without_map_scale_blocks() -> void:
	# 描画倍率は絵の書き出しだけが読む列。空のまま書き出すと等倍の巨大な立ち絵が盤に出るので、
	# ゲームが読まない列でもここで弾く（空を1.0に倒さない）。
	var types := _terrain_types()
	types.append(_valid_terrain_type("fort", "O", "object"))
	var rows := [
		_valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest"),
		_object_terrain_skin("plain_fort", "fort"),
	]
	rows[2].erase("map_scale")
	assert_null(Terrain.build_skin(rows, types)["json"], "倍率が空で json=null")
	rows[2]["map_scale"] = 0
	assert_null(Terrain.build_skin(rows, types)["json"], "0倍で json=null")
	rows[2]["map_scale"] = 1.13
	assert_eq(Terrain.build_skin(rows, types)["problems"].size(), 0, "正の数なら通る")

func test_terrain_footing_with_object_column_blocks() -> void:
	# 足場に書いても効かない列。埋まっていると読む側があるように見えるので、空を要求する。
	for col in ["map_scale", "object_foot_z"]:
		var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
		rows[0][col] = 1.0
		var r := Terrain.build_skin(rows, _terrain_types())
		assert_null(r["json"], "足場に %s があれば json=null" % col)

func test_terrain_object_foot_z_required_except_connected() -> void:
	# 立ち絵は足元の奥行きが要る。柵は板で立てる＝この列を使わないので、逆に空でなければ弾く。
	var types := _terrain_types()
	types.append(_valid_terrain_type("fort", "O", "object"))
	types.append(_valid_terrain_type("fence", "+", "object"))
	var rows := [
		_valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest"),
		_object_terrain_skin("plain_fort", "fort"), _object_terrain_skin("plain_fence", "fence"),
	]
	rows[3]["connect"] = "line"
	assert_null(Terrain.build_skin(rows, types)["json"], "柵に足元の奥行きがあれば json=null")
	rows[3]["object_foot_z"] = ""
	assert_eq(Terrain.build_skin(rows, types)["problems"].size(), 0, "柵は空で通る")
	rows[2].erase("object_foot_z")
	assert_null(Terrain.build_skin(rows, types)["json"], "立ち絵で空なら json=null")

func test_terrain_skin_unknown_orientable_blocks() -> void:
	var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
	rows[0]["orientable"] = "maybe"  # ORIENTS に無い誤記
	var r := Terrain.build_skin(rows, _terrain_types())
	assert_null(r["json"], "orientable が未知の値で json=null")

func test_terrain_skin_legacy_bool_orientable_blocks() -> void:
	# 旧データの true/false は「回してよいか」しか言えず、flip（左右反転だけ）と区別できない。
	# 黙って full に化けると、立てて描いた墓標が回って倒れる＝生成前に弾く。
	for legacy in [true, false]:
		var rows := [ _valid_terrain_skin("plain", "plain"), _valid_terrain_skin("forest", "forest") ]
		rows[0]["orientable"] = legacy
		var r := Terrain.build_skin(rows, _terrain_types())
		assert_null(r["json"], "orientable が旧 bool(%s) で json=null" % legacy)

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
