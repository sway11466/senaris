extends GutTest
## UiLayout（盤エリアと右ボックスの寸法）。仕様 → doc/gdd/uiux.md 盤エリア

const VP := Vector2(1280.0, 720.0)

func after_each() -> void:
	# static＝他のテストへ持ち越さない
	UiLayout.set_panel_holds_right_box(true)
	UiLayout.set_panel_rect(UiLayout.RIGHT_BOX)

func test_board_area_avoids_the_panel_when_it_holds_the_right_box() -> void:
	UiLayout.set_panel_holds_right_box(true)
	var area := UiLayout.board_area(VP)
	assert_eq(area.position, Vector2.ZERO)
	assert_eq(area.size, Vector2(UiLayout.RIGHT_BOX_LEFT, 720.0), "板を除いた左側")

func test_board_area_is_the_whole_screen_when_the_panel_lets_go() -> void:
	UiLayout.set_panel_holds_right_box(false)  # 畳んでいる・動かしてある
	assert_eq(UiLayout.board_area(VP).size, VP, "板が塞いでいなければ画面全体")

func test_board_area_is_full_width_on_a_narrow_viewport() -> void:
	var narrow := Vector2(640.0, 480.0)
	UiLayout.set_panel_holds_right_box(true)
	assert_eq(UiLayout.board_area(narrow).size, narrow, "右ボックスより狭ければどちらでも全幅")

func test_end_turn_left_does_not_follow_the_board_area() -> void:
	UiLayout.set_panel_holds_right_box(true)
	var held := UiLayout.end_turn_left(VP, 140.0)
	UiLayout.set_panel_holds_right_box(false)
	assert_eq(UiLayout.end_turn_left(VP, 140.0), held, "畳んでも動かしても場所が変わらない")
	assert_eq(held, UiLayout.RIGHT_BOX_LEFT - 16.0 - 140.0, "右ボックスの既定の場所のすぐ左")

# --- カメラの可視域（板の裏は見えない＝板の無い側だけ使う）---

func test_camera_area_is_the_left_side_when_the_panel_is_at_its_default_place() -> void:
	UiLayout.set_panel_rect(UiLayout.RIGHT_BOX)
	var area := UiLayout.camera_area(VP)
	assert_eq(area.position, Vector2.ZERO)
	assert_eq(area.size, Vector2(UiLayout.RIGHT_BOX_LEFT, 720.0), "板を除いた左側")

func test_camera_area_avoids_a_panel_that_was_moved() -> void:
	# 動かしてあっても避ける（画面全体には戻さない）。左に空く帯のほうが広い置き方。
	UiLayout.set_panel_rect(Rect2(600.0, 200.0, 464.0, 608.0))
	var area := UiLayout.camera_area(VP)
	assert_eq(area.position, Vector2.ZERO)
	assert_eq(area.size.x, 600.0, "板の左に空く帯")

func test_camera_area_takes_the_wider_side() -> void:
	# 板を左端へ動かしたら、広いのは右側。
	UiLayout.set_panel_rect(Rect2(0.0, 96.0, 464.0, 608.0))
	var area := UiLayout.camera_area(VP)
	assert_eq(area.position.x, 464.0, "板の右端から始まる")
	assert_eq(area.size.x, VP.x - 464.0, "板の右に空く帯")

func test_camera_area_is_the_whole_screen_when_the_panel_is_minimized() -> void:
	UiLayout.set_panel_rect(Rect2())  # 畳んでいる＝何も塞いでいない
	assert_eq(UiLayout.camera_area(VP).size, VP, "板が無ければ画面全体")

func test_camera_area_is_the_whole_screen_when_the_panel_is_off_screen() -> void:
	UiLayout.set_panel_rect(Rect2(1400.0, 96.0, 464.0, 608.0))  # 画面の外へ出した
	var area := UiLayout.camera_area(VP)
	assert_eq(area.position, Vector2.ZERO)
	assert_eq(area.size, VP, "画面の外の板は塞いでいない")
