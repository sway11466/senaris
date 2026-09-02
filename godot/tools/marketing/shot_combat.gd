extends Node3D
## marketing用スクリーンショット：戦闘演出を1回再生し、演出中を一定間隔で連写してPNG保存する。
## 盤の上に実機と同じ結線（ScreenLighting＋CombatScene）で演出を重ねる。撮れた連番から良い瞬間を選ぶ。
## ロケールは英語固定（外に出す絵のため）。
##
## 実行（リポジトリ直下）:
##   godot --path godot res://tools/marketing/shot_combat.tscn -- <出力フォルダ> <ステージjsonのres://パス> --attacker <col,row> --target <col,row> [--size <WxH>] [--count <枚数>] [--interval <秒>]
##
##   --attacker / --target … ステージJSONと同じ col/row。隣接（または射程内）で攻撃可能であること
##   --size WxH            … ウィンドウ＝出力の解像度（既定 2560x1440）
##   --count / --interval  … 連写の枚数と間隔（既定 24枚 × 0.12秒 ≒ 演出全体をカバー）

func _ready() -> void:
	var uargs := OS.get_cmdline_user_args()
	var plain: Array[String] = []
	var atk_cell := Vector2i(-1, -1)
	var tgt_cell := Vector2i(-1, -1)
	var size := Vector2i(2560, 1440)
	var count := 24
	var interval := 0.12
	var i := 0
	while i < uargs.size():
		var a := uargs[i]
		if a in ["--attacker", "--target", "--size", "--count", "--interval"] and i + 1 < uargs.size():
			var v := uargs[i + 1]
			match a:
				"--attacker", "--target":
					var parts := v.split(",")
					if parts.size() != 2:
						push_error("shot_combat: %s は col,row 形式: %s" % [a, v])
						get_tree().quit(1)
						return
					var cell := Vector2i(int(parts[0]), int(parts[1]))
					if a == "--attacker":
						atk_cell = cell
					else:
						tgt_cell = cell
				"--size":
					var wh := v.split("x")
					size = Vector2i(int(wh[0]), int(wh[1]))
				"--count":
					count = int(v)
				"--interval":
					interval = float(v)
			i += 2
		else:
			plain.append(a)
			i += 1
	if plain.size() < 2 or atk_cell.x < 0 or tgt_cell.x < 0:
		push_error("shot_combat: <出力フォルダ> <ステージjson> --attacker col,row --target col,row が要る")
		get_tree().quit(1)
		return
	var out_dir := plain[0]
	var stage_path := plain[1]

	TranslationServer.set_locale("en")
	get_window().size = size
	DirAccess.make_dir_recursive_absolute(out_dir)

	var skins := SkinCatalog.load_standard()
	var state := StageLoader.load_file(stage_path)
	if state == null:
		push_error("shot_combat: ステージを読めない: %s" % stage_path)
		get_tree().quit(1)
		return

	var controller := MatchController.new()
	controller.name = "MatchController"
	controller.setup(state)
	controller.ai_team = 1
	add_child(controller)

	var board: HexBoard3D = preload("res://presentation/board/hex_board_3d.gd").new()
	add_child(board)
	var terrain_skins := StageLoader.load_terrain_skins(stage_path)
	board.bind(state, controller, skins, terrain_skins,
		StageLoader.load_margin_terrain(stage_path), StageLoader.load_board_height(stage_path, state.cols, state.rows),
		StageLoader.load_height_overrides(stage_path))
	board.set_process(false)  # ホバーの写り込み防止（shot_stage と同じ）

	# 盤全体を収める（背景に写る側）。可視矩形はストレッチ解像度基準。
	var b := board._board_bounds()
	var vp := get_viewport().get_visible_rect().size
	var margin := vp.y * 0.05
	board._board_cam.fit_to_bounds(b.position, b.end, HexBoard3D.TILE, Rect2(margin, margin, vp.x - margin * 2.0, vp.y - margin * 2.0))

	# 実機と同じ結線で演出を重ねる（main.gd の _install_screen / load_stage と同じ順）。
	var screen := ScreenLighting.new()
	screen.name = "ScreenLighting"
	add_child(screen)
	var combat := CombatScene.new()
	combat.bind(skins)
	combat.bind_screen(screen)
	combat.bind_terrain_skins(terrain_skins)
	combat.bind_state(state)
	combat.bind_backdrop(StageLoader.load_backdrop(stage_path))
	combat.bind_haze(StageLoader.load_haze(stage_path))
	add_child(combat)
	controller.combat_resolved.connect(combat.play)

	# 右の情報パネル（実機と同じ位置・幅＝main.tscn の Front/InfoPanel と同値）。
	# 戦闘レポートが並ぶ＝画面としての完成形で撮れる。
	var front := CanvasLayer.new()
	front.layer = 45
	add_child(front)
	var info: UnitInfoPanel = preload("res://presentation/ui/unit_info_panel.gd").new()
	info.offset_left = 800.0
	info.offset_top = 96.0
	info.offset_right = 1264.0
	info.offset_bottom = 704.0
	front.add_child(info)
	info.bind(state, skins)
	info.bind_terrain_skins(terrain_skins)
	info.bind_ai_presets(AiCatalog.load_default())
	controller.combat_resolved.connect(info.show_combat)

	var atk := state.unit_at(Hex.offset_to_axial(atk_cell.x, atk_cell.y))
	var tgt := state.unit_at(Hex.offset_to_axial(tgt_cell.x, tgt_cell.y))
	if atk == null or tgt == null:
		push_error("shot_combat: 指定マスに駒が居ない")
		get_tree().quit(1)
		return

	for f in 6:  # ウォームアップ
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	if not controller.execute_attack(AttackCommand.new(atk.id, tgt.id)):
		push_error("shot_combat: 攻撃が通らない（隣接/射程/行動済みを確認）")
		get_tree().quit(1)
		return

	# 撮影中はメモリに溜め、演出が終わってからまとめて書き出す（save_png が重く、撮影間隔を壊すため）。
	var frames: Array[Image] = []
	for shot in count:
		await get_tree().create_timer(interval).timeout
		await RenderingServer.frame_post_draw
		frames.append(get_viewport().get_texture().get_image())
	for shot in frames.size():
		frames[shot].save_png("%s/combat_%02d.png" % [out_dir, shot])
	print("SHOT_BURST_SAVED dir=", out_dir, " count=", frames.size())
	get_tree().quit(0)
