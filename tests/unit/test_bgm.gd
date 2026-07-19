extends GutTest
## BGM のトラック解決（BgmCatalog）と場面→曲の決定（BgmDirector）のテスト。仕様 → doc/audio/bgm.md
## 再生そのもの（BgmPlayer＝presentation）は対象外＝ここは純ロジックだけ。

# --- BgmCatalog：規約 autowire とスロット読み取り ---

func test_path_of_resolves_by_convention() -> void:
	# メニュー曲は投入済み＝規約 assets/bgm/{track_id}.ogg で引ける。
	assert_eq(BgmCatalog.path_of("menu"), "res://assets/bgm/menu.ogg", "トラックID→パスは規約で解決")
	assert_true(BgmCatalog.exists("menu"), "置いてあれば exists")

func test_path_of_missing_track_is_empty() -> void:
	# 未配置は "" ＝呼び出し側が無音＋ログ1行にする（ゲームは止めない）。
	assert_eq(BgmCatalog.path_of("no_such_track"), "", "未配置は空文字")
	assert_false(BgmCatalog.exists("no_such_track"))
	assert_eq(BgmCatalog.path_of(""), "", "トラックID未指定も空文字")

func test_parse_slots_keeps_filled_slots_only() -> void:
	var got := BgmCatalog.parse_slots({ "main": "map_calm", "crisis": "map_crisis" })
	assert_eq(got, { "main": "map_calm", "crisis": "map_crisis" })
	assert_eq(BgmCatalog.parse_slots({ "main": "map_calm" }), { "main": "map_calm" }, "crisis 省略はキーごと落ちる")
	assert_eq(BgmCatalog.parse_slots({}), {}, "空の bgm 欄")

func test_parse_slots_ignores_malformed_values() -> void:
	# 外部データ（JSON）なので型違いが来うる。落とすだけで例外にしない。
	assert_eq(BgmCatalog.parse_slots({ "main": "", "crisis": 3 }), {}, "空文字・非文字列は落とす")
	assert_eq(BgmCatalog.parse_slots("map_calm"), {}, "辞書でない bgm 欄")
	assert_eq(BgmCatalog.parse_slots({ "other": "x" }), {}, "未知スロットは拾わない")

# --- BgmDirector：フォールバック連鎖と crisis ---

func test_stage_bgm_wins_over_campaign() -> void:
	var d := BgmDirector.new()
	d.begin_stage({ "main": "boss" }, { "main": "map_calm" })
	assert_eq(d.track_id(), "boss", "ステージ指定が冒険譚既定に優先")

func test_falls_back_to_campaign_then_global_default() -> void:
	var d := BgmDirector.new()
	d.begin_stage({}, { "main": "t1_journey" })
	assert_eq(d.track_id(), "t1_journey", "ステージ未指定→冒険譚既定")
	d.begin_stage({}, {})
	assert_eq(d.track_id(), BgmDirector.DEFAULT_STAGE_TRACK, "どちらも未指定→全体既定")

func test_crisis_switch_is_sticky() -> void:
	var d := BgmDirector.new()
	d.begin_stage({ "main": "map_calm", "crisis": "map_crisis" })
	assert_eq(d.track_id(), "map_calm", "開始は main")
	assert_false(d.in_crisis())
	d.enter_crisis()
	assert_true(d.in_crisis())
	assert_eq(d.track_id(), "map_crisis", "危機BGMへ")
	d.enter_crisis()
	assert_eq(d.track_id(), "map_crisis", "二度目の要求でも荒れない（永続）")

func test_crisis_without_slot_does_nothing() -> void:
	# crisis 未指定のステージは切替要求が来ても曲が変わらない（doc/audio/bgm.md）。
	var d := BgmDirector.new()
	d.begin_stage({ "main": "map_calm" })
	d.enter_crisis()
	assert_false(d.in_crisis(), "crisis スロットが空なら立たない")
	assert_eq(d.track_id(), "map_calm")

func test_begin_stage_resets_crisis() -> void:
	# 次のステージへ進んだら通常曲に戻る（危機はステージ内だけの状態）。
	var d := BgmDirector.new()
	d.begin_stage({ "main": "map_calm", "crisis": "map_crisis" })
	d.enter_crisis()
	d.begin_stage({ "main": "map_calm", "crisis": "map_crisis" })
	assert_false(d.in_crisis(), "ステージ開始でリセット")
	assert_eq(d.track_id(), "map_calm")

# --- ステージJSON / campaign.json との結線 ---

func test_stage_loader_parses_bgm() -> void:
	assert_eq(StageLoader.parse_bgm({ "bgm": { "main": "boss" } }), { "main": "boss" })
	assert_eq(StageLoader.parse_bgm({}), {}, "bgm 欄なしは空＝連鎖で埋まる")

func test_boot_underlay_uses_menu_track() -> void:
	# セレクトの下敷きはメニュー曲を指す＝起動時に曲が二重に切り替わらない。
	var bgm := StageLoader.load_bgm("res://data/stages/_boot/underlay.json")
	assert_eq(bgm.get("main", ""), BgmDirector.MENU_TRACK)

func test_campaign_manifest_exposes_bgm_slot() -> void:
	# 冒険譚に bgm 欄が無くても空辞書で通る（既定にフォールバックする）。
	var c := CampaignCatalog.load_file("res://data/stages/tutorial1-goblin-raid/campaign.json")
	assert_true(c.has("bgm"), "マニフェストは常に bgm キーを持つ")
	assert_eq(c["bgm"], {}, "未指定は空＝全体既定へ")
