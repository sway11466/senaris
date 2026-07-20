extends GutTest
## 効果音の発火点→素材→ファイル解決（SfxCatalog）のテスト。仕様 → doc/audio/sfx.md
## 再生そのもの（SfxPlayer＝presentation）は対象外＝ここは純ロジックだけ。

# --- 対応表：発火点 → 素材 ---

func test_bind_shares_base_sounds_across_screens() -> void:
	# 基本音は画面をまたいで同じ素材を指す（多対1）。ここが崩れると操作音の一貫性が壊れる。
	assert_eq(SfxCatalog.sfx_of("menu_campaign"), "ui_confirm")
	assert_eq(SfxCatalog.sfx_of("map_select"), "ui_confirm", "確定はメニューでも盤でも同じ素材")
	assert_eq(SfxCatalog.sfx_of("menu_back"), "ui_cancel")
	assert_eq(SfxCatalog.sfx_of("map_cancel"), "ui_cancel", "キャンセルも共用")

func test_sfx_of_unbound_event_is_empty() -> void:
	# 対応表に無い発火点＝まだ音を割り当てていない。空文字を返して無音で進む。
	assert_eq(SfxCatalog.sfx_of("map_capture"), "", "未割当の発火点は空文字")
	assert_eq(SfxCatalog.sfx_of("no_such_event"), "", "未知の発火点も空文字")
	assert_eq(SfxCatalog.sfx_of(""), "", "発火点未指定も空文字")

# --- 規約 autowire：素材 → ファイル ---

func test_path_of_resolves_by_convention() -> void:
	# 基本音の確定・キャンセルは投入済み＝規約 assets/sfx/{sfx_id}.ogg で引ける。
	assert_eq(SfxCatalog.path_of("ui_confirm"), "res://assets/sfx/ui_confirm.ogg", "素材ID→パスは規約で解決")
	assert_eq(SfxCatalog.path_of("ui_cancel"), "res://assets/sfx/ui_cancel.ogg")

func test_path_of_missing_sfx_is_empty() -> void:
	# 未配置は "" ＝呼び出し側が無音＋ログ1行にする（ゲームは止めない）。
	assert_eq(SfxCatalog.path_of("no_such_sfx"), "", "未配置は空文字")
	assert_eq(SfxCatalog.path_of(""), "", "素材ID未指定も空文字")

func test_path_of_event_chains_bind_and_autowire() -> void:
	# 対応表と autowire を一度に通す（呼び出し側が使う入口）。
	assert_eq(SfxCatalog.path_of_event("map_select"), "res://assets/sfx/ui_confirm.ogg")
	assert_true(SfxCatalog.exists("menu_back"), "素材が置いてあれば exists")

func test_bound_event_without_asset_is_silent() -> void:
	# 対応表には在るが素材が未配置＝解決は空。ui_denied はまだ作っていない。
	assert_eq(SfxCatalog.sfx_of("map_denied"), "ui_denied", "対応表には載っている")
	assert_eq(SfxCatalog.path_of_event("map_denied"), "", "素材が無ければ無音で進む")
	assert_false(SfxCatalog.exists("map_denied"))
