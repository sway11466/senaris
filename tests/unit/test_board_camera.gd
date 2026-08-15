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

# --- focus_dest（AIターンの追従の行き先）---

## 追従の可視域（HUD を避けた矩形の代用）。
func _vis() -> Rect2:
	var vp := cam.get_viewport().get_visible_rect().size
	return Rect2(16.0, 64.0, vp.x - 32.0, vp.y - 96.0)

## dest へ動かしたとき world_pos が可視域に入るか。
func _visible_after(world_pos: Vector3, dest: Vector3) -> bool:
	cam.target = dest
	cam.update_rig()
	if cam.camera.is_position_behind(world_pos):
		return false
	return _vis().has_point(cam.camera.unproject_position(world_pos))

func test_focus_dest_ignores_unit_in_safe_area() -> void:
	# 注視点の真上＝画面中央。安全域の内側なので動かさない（デッドゾーン）。
	assert_eq(cam.focus_dest(Vector3.ZERO, _vis()), cam.target, "見えている主体は追わない")

func test_focus_dest_pulls_in_far_unit() -> void:
	# 画面の上（奥）へ大きく外れた主体。1回のパンで可視域に入る。
	var p := Vector3(0.0, 0.0, -40.0)
	assert_true(_visible_after(p, cam.focus_dest(p, _vis())), "奥に外れた主体が可視域に入る")

func test_focus_dest_near_unit_does_not_overshoot() -> void:
	# 画面の下（手前）へ外れた主体。px 差分の線形近似だとここで数十倍に飛んで盤の外に出た。
	var p := Vector3(0.0, 0.0, 25.0)
	var dest := cam.focus_dest(p, _vis())
	assert_almost_eq(dest.z, p.z, cam.dist, "手前の主体でも行き過ぎない")
	assert_true(_visible_after(p, dest), "手前に外れた主体が可視域に入る")

func test_focus_dest_recovers_unit_behind_camera() -> void:
	# カメラの背後（＝一度通り越した状態）からも引き戻せる。
	var p := Vector3(0.0, 0.0, 40.0)
	assert_true(cam.camera.is_position_behind(p), "前提：この点は背後にある")
	assert_true(_visible_after(p, cam.focus_dest(p, _vis())), "背後の主体も可視域に戻す")

func test_focus_dest_keeps_only_out_of_range_axis() -> void:
	# 横にだけ外れた主体は、縦の見え方（画面上のy）を保ったまま寄せる。
	var p := Vector3(30.0, 0.0, 0.0)
	var before := cam.camera.unproject_position(p).y
	cam.target = cam.focus_dest(p, _vis())
	cam.update_rig()
	assert_almost_eq(cam.camera.unproject_position(p).y, before, 8.0, "縦の見え方は変えない")

func test_focus_dest_clamped_to_board_bounds() -> void:
	# 盤の外へは出さない（保険）。
	cam.set_focus_bounds(Vector2(-10.0, -10.0), Vector2(10.0, 10.0), 2.0)
	var dest := cam.focus_dest(Vector3(0.0, 0.0, 200.0), _vis())
	assert_almost_eq(dest.z, 12.0, 0.001, "盤の範囲＋余白で止まる")

# --- shake ---

func test_shake_does_not_crash() -> void:
	cam.shake()
	# Tween で動くだけ。例外が出なければOK。
	assert_true(true)

# --- constants ---

func test_fov_matches() -> void:
	assert_eq(cam.camera.fov, BoardCamera.FOV, "FOV が設定されている")
