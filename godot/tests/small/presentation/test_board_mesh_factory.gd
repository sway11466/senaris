extends GutTest
## presentation/board/board_mesh_factory.gd の単体テスト。
## メッシュ生成は純関数（引数だけで完結）なので、返り値の型・surface 数・頂点数を検証する。

# --- hex_mesh / hexring_mesh ---

func test_hex_mesh_returns_array_mesh() -> void:
	var m := BoardMeshFactory.make_hex_mesh(1.0)
	assert_not_null(m, "null でない")
	assert_is(m, ArrayMesh, "ArrayMesh が返る")

func test_hex_mesh_has_one_surface() -> void:
	var m := BoardMeshFactory.make_hex_mesh(1.0)
	assert_eq(m.get_surface_count(), 1, "surface は1つ")

func test_hexring_mesh_has_one_surface() -> void:
	var m := BoardMeshFactory.make_hexring_mesh(1.0)
	assert_eq(m.get_surface_count(), 1)

func test_hexring_mesh_vertex_count() -> void:
	# 6辺 × 2三角 × 3頂点 = 36
	var m := BoardMeshFactory.make_hexring_mesh(1.0)
	var arr := m.surface_get_arrays(0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 36, "6辺×6頂点=36")

# --- disc_mesh ---

func test_disc_mesh_has_one_surface() -> void:
	var m := BoardMeshFactory.make_disc_mesh(0.5, 0.5)
	assert_eq(m.get_surface_count(), 1)

func test_disc_mesh_vertex_count() -> void:
	# 24分割の扇。24三角 × 3頂点 = 72
	var m := BoardMeshFactory.make_disc_mesh(0.5, 0.5)
	var arr := m.surface_get_arrays(0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 72, "24三角×3頂点=72")

# --- ring_mesh ---

func test_ring_mesh_has_one_surface() -> void:
	var m := BoardMeshFactory.make_ring_mesh(0.7, 0.06)
	assert_eq(m.get_surface_count(), 1)

func test_ring_mesh_vertex_count() -> void:
	# 32分割の帯。32セグメント × 2三角 × 3頂点 = 192
	var m := BoardMeshFactory.make_ring_mesh(0.7, 0.06)
	var arr := m.surface_get_arrays(0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 192, "32セグメント×6頂点=192")

# --- glow_mesh / glow_ring_mesh ---

func test_glow_mesh_has_one_surface() -> void:
	var m := BoardMeshFactory.make_glow_mesh(0.5, 0.5)
	assert_eq(m.get_surface_count(), 1)

func test_glow_mesh_vertex_count() -> void:
	# 32分割の扇。32三角 × 3頂点 = 96
	var m := BoardMeshFactory.make_glow_mesh(0.5, 0.5)
	var arr := m.surface_get_arrays(0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 96, "32三角×3頂点=96")

func test_glow_ring_mesh_has_one_surface() -> void:
	var m := BoardMeshFactory.make_glow_ring_mesh(0.4, 0.8, 0.5)
	assert_eq(m.get_surface_count(), 1)

func test_glow_ring_mesh_vertex_count() -> void:
	# 32分割 × 2段の帯。32 × 2段 × 2三角 × 3頂点 = 384
	var m := BoardMeshFactory.make_glow_ring_mesh(0.4, 0.8, 0.5)
	var arr := m.surface_get_arrays(0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 384, "32×2段×6頂点=384")

# --- tri ---

func test_tri_points_returns_three_vertices() -> void:
	var pts := BoardMeshFactory.tri_points(0.42, 0.38)
	assert_eq(pts.size(), 3)

func test_tri_points_tip_at_origin() -> void:
	var pts := BoardMeshFactory.tri_points(0.42, 0.38)
	# 先端（下向き三角の下端）は原点
	assert_almost_eq(pts[1], Vector2.ZERO, Vector2(0.001, 0.001))

func test_outset_tri_larger_than_original() -> void:
	var pts := BoardMeshFactory.tri_points(0.42, 0.38)
	var out := BoardMeshFactory.outset_tri(pts, 0.05)
	# 押し出した三角のほうが面積が大きい
	var area_orig := absf((pts[1] - pts[0]).cross(pts[2] - pts[0])) * 0.5
	var area_out := absf((out[1] - out[0]).cross(out[2] - out[0])) * 0.5
	assert_gt(area_out, area_orig, "押し出した三角のほうが大きい")

func test_make_tri_mesh_has_one_surface() -> void:
	var pts := BoardMeshFactory.tri_points(0.42, 0.38)
	var m := BoardMeshFactory.make_tri_mesh(pts)
	assert_eq(m.get_surface_count(), 1)

func test_make_tri_mesh_vertex_count() -> void:
	var pts := BoardMeshFactory.tri_points(0.42, 0.38)
	var m := BoardMeshFactory.make_tri_mesh(pts)
	var arr := m.surface_get_arrays(0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 3, "三角は3頂点")

# --- material ---

func test_glow_material_additive() -> void:
	var m := BoardMeshFactory.make_glow_material(Color.WHITE, true)
	assert_eq(m.blend_mode, BaseMaterial3D.BLEND_MODE_ADD, "加算合成")

func test_glow_material_mix() -> void:
	var m := BoardMeshFactory.make_glow_material(Color.WHITE, false)
	assert_eq(m.blend_mode, BaseMaterial3D.BLEND_MODE_MIX, "通常合成")

func test_mark_material_no_depth() -> void:
	var m := BoardMeshFactory.make_mark_material(Color.RED, 4)
	assert_true(m.no_depth_test, "深度判定なし")
	assert_eq(m.render_priority, 4)

func test_overlay_material_cached() -> void:
	var a := BoardMeshFactory.overlay_material(Color.RED)
	var b := BoardMeshFactory.overlay_material(Color.RED)
	assert_same(a, b, "同じ色は同じインスタンス")

func test_overlay_material_different_color() -> void:
	var a := BoardMeshFactory.overlay_material(Color.RED)
	var b := BoardMeshFactory.overlay_material(Color.BLUE)
	assert_ne(a, b, "違う色は別インスタンス")

func test_bill_material_cached() -> void:
	var a := BoardMeshFactory.bill_material(Color.GREEN)
	var b := BoardMeshFactory.bill_material(Color.GREEN)
	assert_same(a, b, "同じ色は同じインスタンス")

func test_bill_material_billboard() -> void:
	var m := BoardMeshFactory.bill_material(Color.GREEN)
	assert_eq(m.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED)

# --- skirt_texture ---

func test_skirt_texture_returns_image_texture() -> void:
	var t := BoardMeshFactory.make_skirt_texture()
	assert_not_null(t)
	assert_is(t, ImageTexture)

func test_skirt_texture_size() -> void:
	var t := BoardMeshFactory.make_skirt_texture()
	assert_eq(t.get_width(), 256)
	assert_eq(t.get_height(), 256)
