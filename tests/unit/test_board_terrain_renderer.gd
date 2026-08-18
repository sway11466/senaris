extends GutTest
## presentation/board/board_terrain_renderer.gd の単体テスト。
## SceneTree に載せて _ready のメッシュ生成を走らせる。

var renderer: BoardTerrainRenderer

func before_each() -> void:
	renderer = BoardTerrainRenderer.new()
	add_child_autofree(renderer)
	await get_tree().process_frame

# --- 初期状態 ---

func test_ready_creates_hex_mesh() -> void:
	assert_not_null(renderer._hex_mesh, "ヘックスメッシュが生成される")

func test_ready_creates_skirt_texture() -> void:
	assert_not_null(renderer._skirt_tex, "スカートテクスチャが生成される")

func test_initial_tile_nodes_empty() -> void:
	assert_eq(renderer._tile_nodes.size(), 0, "初期状態でタイルノードは空")

func test_initial_caches_empty() -> void:
	assert_eq(renderer._elev_cache.size(), 0, "標高キャッシュは空")
	assert_eq(renderer._terrain_tex.size(), 0, "テクスチャキャッシュは空")
	assert_eq(renderer._avg_color.size(), 0, "平均色キャッシュは空")

# --- 定数 ---

func test_tile_matches_hex_board() -> void:
	assert_eq(BoardTerrainRenderer.TILE, HexBoard3D.TILE, "TILE が HexBoard3D と一致")

func test_skirt_depth_positive() -> void:
	assert_true(BoardTerrainRenderer.SKIRT_DEPTH > 0.0, "SKIRT_DEPTH は正の値")

func test_skirt_darken_in_range() -> void:
	var d := BoardTerrainRenderer.SKIRT_DARKEN
	assert_true(d > 0.0 and d < 1.0, "SKIRT_DARKEN は 0〜1 の範囲")

func test_color_line_has_alpha() -> void:
	assert_true(BoardTerrainRenderer.COLOR_LINE.a > 0.0 and BoardTerrainRenderer.COLOR_LINE.a < 1.0,
		"COLOR_LINE は半透明")

# --- elev / unit_floor（state 未設定）---

func test_elev_without_state_returns_zero() -> void:
	assert_eq(renderer.elev(Vector2i.ZERO), 0.0, "state 未設定なら標高 0")

func test_unit_floor_without_state_returns_zero() -> void:
	assert_eq(renderer.unit_floor(Vector2i.ZERO), 0.0, "state 未設定なら足元 0")

func test_elev_levels_without_state() -> void:
	var levels := renderer.elev_levels()
	assert_eq(levels.size(), 1, "state 未設定でも 0.0 のみ")
	assert_eq(levels[0], 0.0)

func test_elev_caches_result() -> void:
	renderer.elev(Vector2i(3, 4))
	assert_true(renderer._elev_cache.has(Vector2i(3, 4)), "呼び出し後にキャッシュされる")

# --- build_tiles / refresh_base_tiles（state 未設定）---

func test_build_tiles_without_state_does_not_crash() -> void:
	renderer.build_tiles()
	assert_eq(renderer._tile_nodes.size(), 0, "state 未設定なら何もしない")

func test_refresh_base_tiles_without_state_does_not_crash() -> void:
	renderer.refresh_base_tiles()
	assert_true(true, "state 未設定でもクラッシュしない")

func test_build_tiles_clears_caches() -> void:
	renderer._elev_cache[Vector2i(1, 2)] = 0.5
	renderer._elev_levels_cache = [0.5, 0.0]
	renderer.build_tiles()
	assert_eq(renderer._elev_cache.size(), 0, "build_tiles で標高キャッシュが空になる")
	assert_eq(renderer._elev_levels_cache.size(), 0, "build_tiles で標高レベルキャッシュが空になる")
