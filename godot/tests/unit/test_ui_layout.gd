extends GutTest
## UiLayout（盤エリアと右ボックスの寸法）。仕様 → doc/gdd/uiux.md 盤エリア

const VP := Vector2(1280.0, 720.0)

func after_each() -> void:
	UiLayout.set_panel_holds_right_box(true)  # static＝他のテストへ持ち越さない

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
