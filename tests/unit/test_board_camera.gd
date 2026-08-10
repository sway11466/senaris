extends GutTest
## presentation/board/board_camera.gd の単体テスト。
## Camera3D が get_viewport を使うため add_child_autofree で SceneTree に載せる。

var cam: BoardCamera

func before_each() -> void:
	cam = BoardCamera.new()
	add_child_autofree(cam)
	# _ready で Camera3D が生成されるので、1フレーム待つ。
	await get_tree().process_frame

# --- 初期状態 ---

func test_camera_created() -> void:
	assert_not_null(cam.camera, "Camera3D が生成される")
	assert_is(cam.camera, Camera3D)

func test_initial_target_is_zero() -> void:
	assert_eq(cam.target, Vector3.ZERO)

func test_initial_dist() -> void:
	assert_eq(cam.dist, 20.0)

func test_cam_up_not_zero() -> void:
	assert_true(cam.cam_up.length() > 0.9, "cam_up は単位ベクトル相当")

# --- update_rig ---

func test_update_rig_positions_camera() -> void:
	cam.target = Vector3(5.0, 0.0, 3.0)
	cam.dist = 10.0
	cam.update_rig()
	# カメラは target より後ろ上に居る。
	assert_true(cam.camera.position.y > cam.target.y, "カメラは注視点より高い")
	assert_true(cam.camera.position.z > cam.target.z, "カメラは注視点より手前")

# --- pan_by ---

func test_pan_by_changes_target() -> void:
	var before := cam.target
	cam.pan_by(Vector2(100, 0))
	assert_ne(cam.target, before, "パンで target が動く")

func test_pan_by_horizontal() -> void:
	var before_x := cam.target.x
	cam.pan_by(Vector2(50, 0))
	assert_true(cam.target.x < before_x, "右ドラッグで target.x が減る")

# --- zoom_at_point ---

func test_zoom_in_decreases_dist() -> void:
	var before := cam.dist
	cam.zoom_at_point(BoardCamera.ZOOM_STEP, Vector2(400, 300))
	assert_true(cam.dist < before, "ズームインで dist が減る")

func test_zoom_out_increases_dist() -> void:
	var before := cam.dist
	cam.zoom_at_point(1.0 / BoardCamera.ZOOM_STEP, Vector2(400, 300))
	assert_true(cam.dist > before, "ズームアウトで dist が増える")

func test_zoom_clamped_min() -> void:
	cam.dist = BoardCamera.MIN_DIST
	cam.update_rig()
	cam.zoom_at_point(BoardCamera.ZOOM_STEP * 100.0, Vector2(400, 300))
	assert_true(cam.dist >= BoardCamera.MIN_DIST, "MIN_DIST を下回らない")

func test_zoom_clamped_max() -> void:
	cam.dist = BoardCamera.MAX_DIST
	cam.update_rig()
	cam.zoom_at_point(1.0 / (BoardCamera.ZOOM_STEP * 100.0), Vector2(400, 300))
	assert_true(cam.dist <= BoardCamera.MAX_DIST, "MAX_DIST を上回らない")

# --- world_per_pixel ---

func test_world_per_pixel_positive() -> void:
	var wpp := cam.world_per_pixel()
	assert_true(wpp > 0.0, "正の値")

func test_world_per_pixel_scales_with_dist() -> void:
	var wpp1 := cam.world_per_pixel()
	cam.dist = 40.0
	cam.update_rig()
	var wpp2 := cam.world_per_pixel()
	assert_true(wpp2 > wpp1, "距離が遠いほど大きい")

# --- shake ---

func test_shake_does_not_crash() -> void:
	cam.shake()
	# Tween で動くだけ。例外が出なければOK。
	assert_true(true)

# --- constants ---

func test_fov_matches() -> void:
	assert_eq(cam.camera.fov, BoardCamera.FOV, "FOV が設定されている")
