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
	assert_eq(SfxCatalog.sfx_of("menu_locked"), "ui_denied")
	assert_eq(SfxCatalog.sfx_of("map_hover"), "ui_hover")
	assert_eq(SfxCatalog.sfx_of("map_talk"), "ui_hover", "文字送りはホバーと同じ極短クリック")

func test_sfx_of_unbound_event_is_empty() -> void:
	# 対応表に無い発火点＝まだ音を割り当てていない。空文字を返して無音で進む。
	assert_eq(SfxCatalog.sfx_of("no_such_event"), "", "未知の発火点は空文字")
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

# --- 移動音：移動タイプ → 素材 → 型 ---

func test_move_bind_collapses_move_types() -> void:
	# 移動タイプは地形コストの都合で分かれているが、音としては足音（重）へ集約する。
	assert_eq(SfxCatalog.move_sfx_of("foot"), "move_ground")
	assert_eq(SfxCatalog.move_sfx_of("forest_stride"), "move_ground", "森歩きも同じ足音")
	assert_eq(SfxCatalog.move_sfx_of("light_foot"), "move_light_foot")
	assert_eq(SfxCatalog.move_sfx_of("flight"), "move_flight")

func test_move_sfx_of_unknown_type_is_silent() -> void:
	assert_eq(SfxCatalog.move_sfx_of("stationary"), "", "動かない駒は無音")
	assert_eq(SfxCatalog.move_sfx_of("no_such_type"), "", "未知の移動タイプも無音")

func test_move_bind_targets_exist_in_move_sfx() -> void:
	# MOVE_SFX が移動音の素材IDの正本（unit_skin.csv の検証もここを見る）。
	# 既定の指し先が載っていないと、その駒だけ型が引けなくなる。
	for move_type: String in SfxCatalog.MOVE_BIND:
		var sfx_id := SfxCatalog.move_sfx_of(move_type)
		assert_true(SfxCatalog.MOVE_SFX.has(sfx_id), "%s の既定 '%s' が MOVE_SFX に在る" % [move_type, sfx_id])

func test_move_sfx_entries_are_well_formed() -> void:
	# 型は3つのどれか。周期は2マス以上空ける（1なら刻むと同じ）。止める型はフェード秒を持つ。
	for sfx_id: String in SfxCatalog.MOVE_SFX:
		var kind := SfxCatalog.move_kind_of(sfx_id)
		assert_true(kind in SfxCatalog.MOVE_KINDS, "%s の型 '%s' は既知" % [sfx_id, kind])
		if kind == SfxCatalog.MOVE_BEAT:
			assert_gt(SfxCatalog.move_every_of(sfx_id), 1, "%s は2マス以上ごと" % sfx_id)
		if kind != SfxCatalog.MOVE_STEP:
			assert_gt(SfxCatalog.move_fade_of(sfx_id), 0.0, "%s は到着で止めるのでフェードを持つ" % sfx_id)
		else:
			assert_eq(SfxCatalog.move_fade_of(sfx_id), 0.0, "%s は刻む型＝止めない" % sfx_id)

func test_move_footsteps_are_step() -> void:
	# 足音は1マス踏むごと。
	assert_eq(SfxCatalog.move_kind_of("move_ground"), SfxCatalog.MOVE_STEP)
	assert_eq(SfxCatalog.move_kind_of("move_light_foot"), SfxCatalog.MOVE_STEP)

func test_move_drift_is_sustain() -> void:
	# 漂う屍は動いている間だけ続く音（ループ）。
	assert_eq(SfxCatalog.move_kind_of("move_drift"), SfxCatalog.MOVE_SUSTAIN)

func test_move_kind_unknown_falls_back_to_step() -> void:
	# 未登録は刻む型＝既定の鳴り方へ倒す（鳴らない方向には倒さない）。
	assert_eq(SfxCatalog.move_kind_of("no_such_sfx"), SfxCatalog.MOVE_STEP)
	assert_eq(SfxCatalog.move_every_of("no_such_sfx"), 1)
	assert_eq(SfxCatalog.move_fade_of("no_such_sfx"), 0.0)

func test_every_bound_event_has_its_asset() -> void:
	# 素材が未用意の発火点は対応表に載せない、という決まりを守れているか（doc/audio/sfx.md）。
	# 載せてしまうと「配線したのに鳴らない」が黙って起きる。素材が無いなら載せず、
	# 置いた時点で鳴り出すのが規約 autowire の狙い。
	for event_id: String in SfxCatalog.BIND:
		assert_true(SfxCatalog.exists(event_id), "対応表に載せた発火点は素材が在る: %s" % event_id)
