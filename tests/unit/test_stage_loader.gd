extends GutTest
## StageLoader（ステージJSON → BattleState）のテスト。

func test_build_reads_size_terrain_units() -> void:
	var data := {
		"cols": 6, "rows": 4,
		"terrain": [
			"......",
			"..PP..",
			"......",
			"......",
		],
		"units": [
			{ "team": 0, "col": 1, "row": 2, "move": 4, "troops": 7, "atk": 12, "def": 10, "level": 3 },
			{ "team": 1, "col": 4, "row": 1 },  # 省略値はデフォルト
		],
	}
	var s := StageLoader.build(data)
	assert_eq(s.cols, 6)
	assert_eq(s.rows, 4)
	# 地形: P が台地、それ以外は平地
	assert_eq(s.terrain_at(Hex.offset_to_axial(2, 1)), Terrain.PLATEAU, "(2,1)は台地")
	assert_eq(s.terrain_at(Hex.offset_to_axial(3, 1)), Terrain.PLATEAU, "(3,1)は台地")
	assert_eq(s.terrain_at(Hex.offset_to_axial(0, 0)), Terrain.PLAINS, "未指定は平地")
	# ユニット
	assert_eq(s.units().size(), 2)

func test_build_unit_fields_and_defaults() -> void:
	var data := {
		"cols": 6, "rows": 4,
		"units": [
			{ "team": 0, "col": 1, "row": 2, "move": 4, "troops": 7, "atk": 12, "def": 10, "level": 3 },
			{ "team": 1, "col": 4, "row": 1 },
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

func test_load_demo_file() -> void:
	var s := StageLoader.load_file("res://data/stages/demo/demo.json")
	assert_not_null(s, "demo.json が読める")
	assert_eq(s.cols, 12)
	assert_eq(s.rows, 8)
	assert_eq(s.units().size(), 4, "デモは4体")
	assert_eq(s.terrain_at(Hex.offset_to_axial(5, 4)), Terrain.PLATEAU, "中央に台地")
	assert_eq(s.terrain_at(Hex.offset_to_axial(6, 4)), Terrain.PLATEAU)
