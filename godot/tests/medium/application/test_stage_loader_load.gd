extends GutTest
## StageLoader の load_*（res:// パスのステージを読んで値を返す口）のテスト。ステージは本体と
## 相棒の地形ファイル（<ステージ>.terrain.json）の2枚をこの回だけのディレクトリへ書いて読ませる。
## parse 系は tests/small/application/test_stage_loader_parse.gd。

const DIR := "user://test_stage_loader_load"
const STAGE_PATH := "user://test_stage_loader_load/stage.json"
const MISSING_PATH := "user://test_stage_loader_load/no_such_stage.json"
const GRID := ["......", "......", "......", "......"]

func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

func after_all() -> void:
	_clean()

func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

func _write(stage: Dictionary, terrain: Dictionary = { "terrain": GRID }) -> void:
	var f := FileAccess.open(STAGE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(stage))
	f.close()
	var t := FileAccess.open(StageLoader.terrain_path(STAGE_PATH), FileAccess.WRITE)
	t.store_string(JSON.stringify(terrain))
	t.close()

# --- 靄（haze） ---

func test_load_haze_reads_the_stage() -> void:
	_write({ "turn_limit": 10, "haze": 0.35 })
	assert_almost_eq(StageLoader.load_haze(STAGE_PATH), 0.35, 0.0001)

func test_load_haze_missing_key_is_error() -> void:
	_write({ "turn_limit": 10 })
	assert_almost_eq(StageLoader.load_haze(STAGE_PATH), 0.0, 0.0001, "書き忘れは 0 に倒す")
	assert_push_error("haze（0〜1 の数値）は必須")

func test_load_haze_missing_file_is_zero() -> void:
	assert_almost_eq(StageLoader.load_haze(MISSING_PATH), 0.0, 0.0001, "読めないステージは 0")

# --- 評価ランクの閾値（rank）。詳細 → doc/gdd/rank.md ---

func test_load_rank_reads_thresholds() -> void:
	var rank := { "turn_s": 15, "turn_a": 22, "survival_s": 4, "survival_a": 2 }
	_write({ "turn_limit": 30, "rank": rank })
	var got := StageLoader.load_rank(STAGE_PATH)
	assert_eq(got.keys().size(), 4, "4キーとも返す")
	for k in rank:
		assert_eq(int(got[k]), int(rank[k]), k)

func test_load_rank_absent_is_empty() -> void:
	_write({ "turn_limit": 30 })
	assert_eq(StageLoader.load_rank(STAGE_PATH), {}, "rank が無いステージは評価しない＝空")

func test_load_rank_non_dictionary_is_empty() -> void:
	_write({ "turn_limit": 30, "rank": [15, 22, 4, 2] })
	assert_eq(StageLoader.load_rank(STAGE_PATH), {}, "辞書でなければ空")

func test_load_rank_missing_file_is_empty() -> void:
	assert_eq(StageLoader.load_rank(MISSING_PATH), {})

# --- 戦果の分母（開始時の自軍戦力）。詳細 → doc/gdd/rank.md 生存 ---

func test_count_start_allies_at_reads_the_stage() -> void:
	# 盤の自軍2＋自軍の増援1（未発火でも数える）。敵は数えない。
	_write({
		"turn_limit": 10,
		"player": [ { "units": [
			{ "type": "fighter", "col": 0, "row": 0 },
			{ "type": "fighter", "col": 1, "row": 0 },
		] } ],
		"enemy": [ { "order": 1, "ai": "charge", "units": [ { "type": "fighter", "col": 5, "row": 3 } ] } ],
		"events": [ { "id": "help", "turn": 5, "type": "turn", "entry": "fade",
			"player": [ { "units": [ { "type": "fighter", "col": 0, "row": 3 } ] } ] } ],
	})
	var s := StageLoader.load_file(STAGE_PATH)
	assert_eq(StageLoader.count_start_allies_at(STAGE_PATH, s), 3)
	s.remove_unit(1)
	assert_eq(StageLoader.count_start_allies_at(STAGE_PATH, s), 3, "盤の現況ではなくステージ定義から数える")

func test_count_start_allies_at_missing_file_is_zero() -> void:
	assert_eq(StageLoader.count_start_allies_at(MISSING_PATH, BattleState.new(4, 4)), 0)

# --- マスごとの高さ上書き（terrain_skins の elevation / floor）。詳細 → doc/gdd/terrain.md 盤の高さ ---

func test_load_height_overrides_reads_the_terrain_file() -> void:
	_write({ "turn_limit": 10 }, { "terrain": GRID, "terrain_skins": [
		{ "col": 2, "row": 1, "skin": "snow1", "elevation": 0.5, "floor": 0.25 },
		{ "col": 3, "row": 1, "skin": "snow1" },  # 上書きなし＝載らない
	] })
	var got := StageLoader.load_height_overrides(STAGE_PATH)
	assert_eq(got.size(), 1, "上書きを書いたマスだけ")
	assert_eq(got.get(Hex.offset_to_axial(2, 1)), { "elevation": 0.5, "floor": 0.25 })

func test_load_height_overrides_missing_file_is_empty() -> void:
	assert_eq(StageLoader.load_height_overrides(MISSING_PATH), {})

# --- 外周（margin）の地形。詳細 → doc/gdd/map.md ---

func test_load_margin_terrain_reads_only_the_rim() -> void:
	# 6×5 のグリッドに厚み1の外周＝盤は 4×3。外周のマスだけ（6*5 - 4*3 = 18）を返す。
	_write({ "turn_limit": 10 }, { "margin": 1, "terrain": ["......", "......", "......", "......", "......"] })
	var got := StageLoader.load_margin_terrain(STAGE_PATH)
	assert_eq(got.size(), 18, "外周のマスだけ")
	assert_true(got.has(Hex.offset_to_axial(-1, -1)), "盤の外の角も載る")
	assert_false(got.has(Hex.offset_to_axial(0, 0)), "盤の中は載らない")

func test_load_margin_terrain_without_margin_is_empty() -> void:
	_write({ "turn_limit": 10 })
	assert_eq(StageLoader.load_margin_terrain(STAGE_PATH), {}, "外周なし＝空")

func test_load_margin_terrain_missing_file_is_empty() -> void:
	assert_eq(StageLoader.load_margin_terrain(MISSING_PATH), {})
