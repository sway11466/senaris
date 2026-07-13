extends GutTest
## StageLoader（ステージJSON → BattleState）のテスト。

const TMP_PATH := "user://test_stage_tmp.json"

func after_each() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func _write_stage(text: String) -> void:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	f.store_string(text)

func test_build_reads_size_terrain_units() -> void:
	var data := {
		"cols": 6, "rows": 4,
		"terrain": [
			"......",
			"..PP..",
			"......",
			"......",
		],
		"player": [
			{ "col": 1, "row": 2, "move": 4, "troops": 7, "atk": 12, "def": 10, "level": 3 },
		],
		"enemy": [
			{ "ai": "charge", "units": [ { "col": 4, "row": 1 } ] },  # 省略値はデフォルト
		],
	}
	var s := StageLoader.build(data)
	assert_eq(s.cols, 6)
	assert_eq(s.rows, 4)
	# 地形: P が台地、それ以外は平地
	assert_eq(s.terrain_at(Hex.offset_to_axial(2, 1)), "plateau", "(2,1)は台地")
	assert_eq(s.terrain_at(Hex.offset_to_axial(3, 1)), "plateau", "(3,1)は台地")
	assert_eq(s.terrain_at(Hex.offset_to_axial(0, 0)), "plain", "未指定は平地")
	# ユニット
	assert_eq(s.units().size(), 2)

func test_build_unit_fields_and_defaults() -> void:
	var data := {
		"cols": 6, "rows": 4,
		"player": [
			{ "col": 1, "row": 2, "move": 4, "troops": 7, "atk": 12, "def": 10, "level": 3 },
		],
		"enemy": [
			{ "ai": "charge", "units": [ { "col": 4, "row": 1 } ] },
		],
	}
	var s := StageLoader.build(data)
	var u := s.unit_by_id(1)  # id 省略 → 出現順で1始まり
	assert_eq(u.team, 0)
	assert_eq(u.pos, Hex.offset_to_axial(1, 2))
	assert_eq(u.troops, 7)
	assert_eq(u.unit_attack, 12)
	assert_eq(u.level, 3)
	var u2 := s.unit_by_id(2)
	assert_eq(u2.troops, 8, "troops 省略は8")
	assert_eq(u2.unit_attack, 10, "atk 省略は10")
	assert_eq(u2.level, 1, "level 省略は1")

func test_build_resolves_type_from_catalog() -> void:
	var catalog := {
		"cleric": UnitType.from_dict({
			"id": "cleric", "atk_ground": 10, "defense": 4, "move": 3, "max_troops": 8,
		}),
	}
	var data := { "cols": 6, "rows": 4, "player": [
		{ "type": "cleric", "col": 1, "row": 1 },
	] }
	var s := StageLoader.build(data, catalog)
	var u := s.unit_by_id(1)
	assert_eq(u.type_id, "cleric", "type_id を保持")
	assert_eq(u.unit_attack, 10, "atk_ground → unit_attack")
	assert_eq(u.unit_defense, 4, "defense → unit_defense")
	assert_eq(u.troops, 8, "max_troops → troops")
	assert_eq(u.move, 3, "move は種別から")

func test_type_fields_can_be_overridden() -> void:
	var catalog := {
		"cleric": UnitType.from_dict({
			"id": "cleric", "atk_ground": 10, "defense": 4, "move": 3, "max_troops": 8,
		}),
	}
	var data := { "cols": 6, "rows": 4, "player": [
		{ "type": "cleric", "col": 1, "row": 1, "troops": 5, "level": 2 },
	] }
	var s := StageLoader.build(data, catalog)
	var u := s.unit_by_id(1)
	assert_eq(u.troops, 5, "troops を上書き")
	assert_eq(u.level, 2, "level を上書き")
	assert_eq(u.unit_attack, 10, "上書きしない項目は種別のまま")

func test_build_bases_with_garrison() -> void:
	var catalog := {
		"novice": UnitType.from_dict({
			"id": "novice", "atk_ground": 45, "defense": 30, "move": 5, "max_troops": 8,
		}),
		"cleric": UnitType.from_dict({
			"id": "cleric", "atk_ground": 10, "defense": 4, "move": 3, "max_troops": 8,
			"can_capture": true,
		}),
	}
	var data := {
		"cols": 8, "rows": 6,
		"player": [
			{ "type": "cleric", "col": 1, "row": 1 },
		],
		"bases": [
			{ "col": 4, "row": 3, "team": "enemy", "garrison": [ { "type": "novice", "count": 2 } ] },
		],
	}
	var s := StageLoader.build(data, catalog)
	# 占領フラグが種別から載る
	assert_true(s.unit_by_id(1).can_capture, "cleric は can_capture")
	# 拠点が組み上がる
	var b := s.base_at(Hex.offset_to_axial(4, 3))
	assert_not_null(b, "bases から拠点が立つ")
	assert_eq(b.team, 1, "初期所属は敵")
	assert_eq(b.garrison.size(), 2, "garrison は count ぶん展開される")
	assert_eq(b.garrison[0].unit_attack, 45, "garrison も種別ステータスを引く")
	assert_eq(b.garrison[0].troops, 8, "garrison 既定は満員")
	# garrison の id は盤上ユニットと衝突しない採番
	assert_ne(b.garrison[0].id, s.unit_by_id(1).id)

func test_team_names_resolve_to_internal_ints() -> void:
	# 駒の陣営はセクション（player/enemy）で決まり内部 int(0/1) に。拠点/native は可読表記→int(-1/0)。
	var data := {
		"cols": 6, "rows": 6,
		"player": [
			{ "col": 1, "row": 1 },
		],
		"enemy": [
			{ "ai": "charge", "units": [ { "col": 4, "row": 4 } ] },
		],
		"bases": [
			{ "col": 2, "row": 2, "team": "neutral",
				"garrison": [ { "count": 1, "native": "player" } ] },
		],
	}
	var s := StageLoader.build(data)
	assert_eq(s.unit_by_id(1).team, 0, "player セクション → 0")
	assert_eq(s.unit_by_id(2).team, 1, "enemy セクション → 1")
	var b := s.base_at(Hex.offset_to_axial(2, 2))
	assert_eq(b.team, -1, "neutral → -1")
	assert_eq(b.native_team, -1, "拠点 native も初期所属の中立")
	assert_eq(b.garrison[0].native_team, 0, "garrison native=player → 0（中立拠点でも寝返らない）")

func test_load_boot_underlay() -> void:
	# 起動時の下敷き（セレクトの裏に出る空盤）。ユニット0・地形のみで実読み込みできる。
	var s := StageLoader.load_file("res://data/stages/_boot/underlay.json")
	assert_not_null(s, "_boot/underlay.json が読める")
	assert_eq(s.cols, 12)
	assert_eq(s.rows, 8)
	assert_eq(s.units().size(), 0, "下敷きは空盤（駒なし）")
	assert_eq(s.terrain_at(Hex.offset_to_axial(5, 4)), "plateau", "台地の見本")
	assert_eq(s.terrain_at(Hex.offset_to_axial(6, 4)), "plateau")

func test_all_campaign_stages_load() -> void:
	# 全冒険譚の全ステージJSONが新スキーマで実読み込みでき、駒が1体以上載る（一括移行の取りこぼし検出）。
	for c in CampaignCatalog.load_all():
		for entry in c["stages"]:
			var s := StageLoader.load_file(entry["path"])
			assert_not_null(s, "読み込める: %s" % entry["path"])
			if s != null:
				assert_true(s.units().size() >= 1, "駒が載る: %s" % entry["path"])

func test_skin_field_resolves_type_and_keeps_skin_id() -> void:
	var catalog := {
		"cleric": UnitType.from_dict({
			"id": "cleric", "atk_ground": 10, "defense": 4, "move": 3, "max_troops": 8,
		}),
	}
	var skin_catalog := SkinCatalog.build({ "skins": {
		"cleric": {
			"ally": [ { "skin_id": "cleric", "type_id": "cleric", "name": "クレリック" } ],
			"enemy": [ { "skin_id": "goblin", "type_id": "cleric", "name": "ゴブリン" } ],
		},
	} })
	var data := { "cols": 6, "rows": 4, "enemy": [
		{ "ai": "charge", "units": [ { "skin": "goblin", "col": 1, "row": 1 } ] },
	] }
	var s := StageLoader.build(data, catalog, skin_catalog)
	var u := s.unit_by_id(1)
	assert_eq(u.skin_id, "goblin", "skin_id を保持")
	assert_eq(u.type_id, "cleric", "skin から type を逆引き")
	assert_eq(u.unit_attack, 10, "逆引きした type の stats を引く")

func test_load_file_missing_returns_null() -> void:
	assert_null(StageLoader.load_file("user://no_such_stage.json"))
	assert_push_error("読み込めない")

func test_load_file_empty_returns_null() -> void:
	_write_stage("")
	assert_null(StageLoader.load_file(TMP_PATH))
	assert_push_error("読み込めない")

func test_load_file_non_dict_json_returns_null() -> void:
	_write_stage("[1, 2, 3]")  # 正しいJSONだが dict でない
	assert_null(StageLoader.load_file(TMP_PATH))
	assert_push_error("JSON が不正")

func test_load_file_missing_turn_limit_errors_but_builds() -> void:
	# turn_limit 欠損はデータのバグとして push_error するが、build は続行して state を返す（現仕様）
	_write_stage(JSON.stringify({ "cols": 4, "rows": 3, "player": [ { "col": 0, "row": 0 } ] }))
	var s := StageLoader.load_file(TMP_PATH)
	assert_push_error("turn_limit")
	assert_not_null(s, "エラーは出すが読み込みは成立する")
	assert_eq(s.turn_limit, 0, "欠損は 0（無制限）のまま")
	assert_eq(s.units().size(), 1)

func test_load_file_non_positive_turn_limit_errors_but_builds() -> void:
	_write_stage(JSON.stringify({ "cols": 4, "rows": 3, "turn_limit": 0,
		"player": [ { "col": 0, "row": 0 } ] }))
	var s := StageLoader.load_file(TMP_PATH)
	assert_push_error("turn_limit")
	assert_not_null(s, "0 以下でもエラーを出しつつ state を返す")
	assert_eq(s.turn_limit, 0)

func test_unknown_type_warns_and_falls_back_to_defaults() -> void:
	var data := { "cols": 4, "rows": 3, "player": [ { "type": "nope", "col": 1, "row": 1 } ] }
	var s := StageLoader.build(data)  # catalog に無い種別＝クラッシュせず素の値
	assert_push_warning("未知のユニット種別")
	var u := s.unit_by_id(1)
	assert_eq(u.type_id, "nope", "type_id は書かれたまま保持")
	assert_eq(u.move, 3, "素の既定 move")
	assert_eq(u.troops, 8, "素の既定 troops")
	assert_eq(u.unit_attack, 10, "素の既定 atk")
	assert_eq(u.unit_defense, 10, "素の既定 def")
	assert_eq(u.attack_range, 1, "素の既定 range")

func test_type_wires_all_combat_fields_from_catalog() -> void:
	var catalog := {
		"wyvern": UnitType.from_dict({
			"id": "wyvern", "atk_ground": 30, "atk_air": 25, "pierce": 0.5,
			"defense": 20, "move": 6, "move_type": "flight", "range": 2,
			"move_after_attack": true, "max_troops": 8, "capacity": 4,
		}),
	}
	var data := { "cols": 6, "rows": 4, "player": [
		{ "type": "wyvern", "col": 1, "row": 1 },
	] }
	var u := StageLoader.build(data, catalog).unit_by_id(1)
	assert_eq(u.move_type, "flight", "move_type が種別から載る")
	assert_eq(u.attack_range, 2, "attack_range が種別から載る")
	assert_eq(u.move_after_attack, true, "move_after_attack が種別から載る")
	assert_eq(u.atk_air, 25, "atk_air が種別から載る")
	assert_eq(u.pierce, 0.5, "pierce が種別から載る")
	assert_eq(u.capacity, 4, "capacity が種別から載る")

func test_type_combat_fields_can_be_overridden_per_unit() -> void:
	var catalog := {
		"wyvern": UnitType.from_dict({
			"id": "wyvern", "atk_ground": 30, "atk_air": 25, "pierce": 0.5,
			"defense": 20, "move": 6, "move_type": "flight", "range": 2,
			"move_after_attack": true, "max_troops": 8, "capacity": 4,
		}),
	}
	var data := { "cols": 6, "rows": 4, "player": [
		{ "type": "wyvern", "col": 1, "row": 1, "move_type": "ground", "range": 1,
			"move_after_attack": false, "atk_air": 0, "pierce": 0.0, "capacity": 0 },
	] }
	var u := StageLoader.build(data, catalog).unit_by_id(1)
	assert_eq(u.move_type, "ground", "move_type を個別キーで上書き")
	assert_eq(u.attack_range, 1, "range を上書き")
	assert_eq(u.move_after_attack, false, "move_after_attack を上書き")
	assert_eq(u.atk_air, 0, "atk_air を上書き")
	assert_eq(u.pierce, 0.0, "pierce を上書き")
	assert_eq(u.capacity, 0, "capacity を上書き")

func test_type_field_sets_skin_id_to_same_name() -> void:
	var catalog := {
		"fighter": UnitType.from_dict({
			"id": "fighter", "atk_ground": 50, "defense": 40, "move": 6, "max_troops": 8,
		}),
	}
	var data := { "cols": 6, "rows": 4, "player": [
		{ "type": "fighter", "col": 1, "row": 1 },
	] }
	var s := StageLoader.build(data, catalog)
	var u := s.unit_by_id(1)
	assert_eq(u.skin_id, "fighter", "type 指定 → 同名 skin_id")
	assert_eq(u.type_id, "fighter", "type_id はそのまま")
