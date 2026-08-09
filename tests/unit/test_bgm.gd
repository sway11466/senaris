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
	assert_eq(BgmCatalog.parse_slots({ "main": "map_calm" }), { "main": "map_calm" })
	assert_eq(BgmCatalog.parse_slots({}), {}, "空の bgm 欄")

func test_parse_slots_ignores_malformed_values() -> void:
	# 外部データ（JSON）なので型違いが来うる。落とすだけで例外にしない。
	assert_eq(BgmCatalog.parse_slots({ "main": "" }), {}, "空文字は落とす")
	assert_eq(BgmCatalog.parse_slots({ "main": 3 }), {}, "非文字列は落とす")
	assert_eq(BgmCatalog.parse_slots("map_calm"), {}, "辞書でない bgm 欄")
	assert_eq(BgmCatalog.parse_slots({ "other": "x" }), {}, "未知スロットは拾わない")

# --- BgmDirector：フォールバック ---

func test_stage_bgm_decides_the_track() -> void:
	var d := BgmDirector.new()
	d.begin_stage({ "main": "boss" })
	assert_eq(d.track_id(), "boss", "ステージ指定がそのまま鳴る曲になる")

func test_falls_back_to_global_default() -> void:
	var d := BgmDirector.new()
	d.begin_stage({})
	assert_eq(d.track_id(), BgmDirector.DEFAULT_STAGE_TRACK, "ステージ未指定→全体既定")

func test_begin_stage_replaces_the_track() -> void:
	# ステージを跨いでも前のステージの曲を引きずらない。
	var d := BgmDirector.new()
	d.begin_stage({ "main": "boss" })
	d.begin_stage({ "main": "map_calm" })
	assert_eq(d.track_id(), "map_calm", "後から始めたステージの曲になる")

# --- ステージJSON との結線 ---

func test_stage_loader_parses_bgm() -> void:
	assert_eq(StageLoader.parse_bgm({ "bgm": { "main": "boss" } }), { "main": "boss" })
	assert_eq(StageLoader.parse_bgm({}), {}, "bgm 欄なしは空＝全体既定へ落ちる")

func test_boot_underlay_uses_menu_track() -> void:
	# セレクトの下敷きはメニュー曲を指す＝起動時に曲が二重に切り替わらない。
	var bgm := StageLoader.load_bgm("res://data/stages/_boot/underlay.json")
	assert_eq(bgm.get("main", ""), BgmDirector.MENU_TRACK)

func test_campaign_stages_all_declare_bgm() -> void:
	# 曲は冒険譚単位でなくステージJSONに書く＝本編ステージに書き漏らしが無いことを守る。
	for dir_name in ["tutorial1-goblin-raid", "tutorial2-undead-rush"]:
		var c := CampaignCatalog.load_file("res://data/stages/%s/campaign.json" % dir_name)
		for s in c["stages"]:
			var bgm := StageLoader.load_bgm(String(s["path"]))
			assert_ne(String(bgm.get("main", "")), "",
				"%s/%s に bgm main が要る（無いと全体既定＝無音）" % [dir_name, s["id"]])
