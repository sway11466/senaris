extends GutTest
## presentation/board/board_unit_renderer.gd の単体テスト。
## SceneTree に載せて _ready のメッシュ生成を走らせる。

var renderer: BoardUnitRenderer

func before_each() -> void:
	renderer = BoardUnitRenderer.new()
	add_child_autofree(renderer)
	await get_tree().process_frame

# --- 初期状態 ---

func test_ready_creates_meshes() -> void:
	assert_not_null(renderer._shadow_mesh, "影メッシュが生成される")
	assert_not_null(renderer._glow_mesh, "弱体グローメッシュが生成される")
	assert_not_null(renderer._glow_ring_mesh, "強化グローメッシュが生成される")
	assert_not_null(renderer._mark_mesh, "マーカーメッシュが生成される")
	assert_not_null(renderer._mark_edge_mesh, "マーカー縁取りメッシュが生成される")
	assert_not_null(renderer._disc_mesh, "プレースホルダ円盤が生成される")

func test_ready_creates_materials() -> void:
	assert_not_null(renderer._glow_mat, "強化グロー材質が生成される")
	assert_not_null(renderer._glow_mat_debuff, "弱体グロー材質が生成される")
	assert_not_null(renderer._mark_mat, "マーカー材質が生成される")
	assert_not_null(renderer._mark_mat_edge, "マーカー縁取り材質が生成される")

func test_initial_unit_nodes_empty() -> void:
	assert_eq(renderer._unit_nodes.size(), 0, "初期状態で駒ノードは空")

func test_initial_target_markers_empty() -> void:
	assert_eq(renderer._target_markers.size(), 0, "初期状態でマーカーは空")

# --- 定数 ---

func test_tile_matches_hex_board() -> void:
	assert_eq(BoardUnitRenderer.TILE, HexBoard3D.TILE, "TILE が HexBoard3D と一致")

func test_sprite_foot_z_positive() -> void:
	assert_true(BoardUnitRenderer.SPRITE_FOOT_Z > 0.0, "SPRITE_FOOT_Z は正の値")

# --- add_ring ---

func test_add_ring_creates_mesh_instance() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	renderer.add_ring(Vector3.ZERO, 0.7, 0.06, Color.RED, 0.05, root)
	assert_eq(root.get_child_count(), 1, "MeshInstance3D が1つ追加される")
	assert_is(root.get_child(0), MeshInstance3D)

func test_add_ring_caches_mesh() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	renderer.add_ring(Vector3.ZERO, 0.7, 0.06, Color.RED, 0.05, root)
	renderer.add_ring(Vector3.ZERO, 0.7, 0.06, Color.BLUE, 0.05, root)
	assert_eq(renderer._ring_mesh.size(), 1, "同じ半径と太さのメッシュは1つだけキャッシュ")

func test_add_ring_different_sizes_cached_separately() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	renderer.add_ring(Vector3.ZERO, 0.7, 0.06, Color.RED, 0.05, root)
	renderer.add_ring(Vector3.ZERO, 0.5, 0.04, Color.BLUE, 0.05, root)
	assert_eq(renderer._ring_mesh.size(), 2, "異なるサイズは別々にキャッシュ")

# --- add_count_label ---

func test_add_count_label_creates_label() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	renderer.add_count_label("+3", Vector3.ZERO, Color.WHITE, root)
	assert_eq(root.get_child_count(), 1, "Label3D が1つ追加される")
	assert_is(root.get_child(0), Label3D)
	var label := root.get_child(0) as Label3D
	assert_eq(label.text, "+3")

# --- get_unit_node / has_unit_node / forget_unit / remove_unit ---

func test_has_unit_node_false_when_empty() -> void:
	assert_false(renderer.has_unit_node(42), "存在しない id は false")

func test_get_unit_node_null_when_empty() -> void:
	assert_null(renderer.get_unit_node(42), "存在しない id は null")

## 駒ノードを1つ追跡に載せる（生成経路は state が要るので、追跡辞書へ直接置く）。
func _track_unit(uid: int) -> Node3D:
	var n := Node3D.new()
	renderer.add_child(n)
	renderer._unit_nodes[uid] = n
	return n

func test_forget_unit_drops_tracking_but_keeps_node() -> void:
	# forget＝追跡から外すだけ。ノードは呼び出し側が演出のあと片付ける（シーンには残る）。
	var n := _track_unit(7)
	var other := _track_unit(8)
	renderer.forget_unit(7)
	assert_false(renderer.has_unit_node(7), "追跡から外れる")
	assert_eq(n.get_parent(), renderer, "ノードはシーンに残る")
	assert_eq(renderer.get_unit_node(8), other, "他の駒はそのまま")
	n.free()

func test_remove_unit_drops_tracking_and_node() -> void:
	var n := _track_unit(7)
	var other := _track_unit(8)
	renderer.remove_unit(7)
	assert_false(renderer.has_unit_node(7), "追跡から外れる")
	assert_ne(n.get_parent(), renderer, "シーンから外れる")
	assert_eq(renderer.get_unit_node(8), other, "他の駒はそのまま")
	await get_tree().process_frame
	assert_false(is_instance_valid(n), "ノードは消される")

# --- clear_target_markers ---

func test_clear_target_markers_empties_list() -> void:
	var n := Node3D.new()
	add_child_autofree(n)
	renderer._target_markers.append(n)
	renderer.clear_target_markers()
	assert_eq(renderer._target_markers.size(), 0, "クリアで空になる")

# --- _mark_scale ---

func test_mark_scale_needs_camera() -> void:
	# BoardCamera を渡して _mark_scale が動くことを確認する。
	var cam := BoardCamera.new()
	add_child_autofree(cam)
	await get_tree().process_frame
	renderer._board_cam = cam
	var s := renderer._mark_scale()
	assert_true(s >= 1.0, "近い画角では等倍以上")

# --- sync_units without state ---

func test_sync_units_without_state_does_not_crash() -> void:
	renderer.sync_units()
	assert_eq(renderer._unit_nodes.size(), 0, "state 未設定なら何もしない")
