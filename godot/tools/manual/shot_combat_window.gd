extends Node3D
## マニュアル用スクリーンショット：戦闘演出の窓だけを切り出して PNG に保存する（連写）。
## 実機と同じ結線（盤＋暗幕＋CombatScene）で1回戦わせ、演出中を一定間隔で撮り、窓の矩形で
## 切り抜く。盤と暗幕は窓の角の丸みの外側にだけ残る。良い瞬間は撮れた連番から選ぶ。
## 窓の作り → doc/tech/combat_scene.md
##
## 右の情報パネルは出さない（マニュアルには別に撮った情報板を貼る＝同じ物を二度写さない）。
## 窓に出る文字は損害の数字だけなので、情報板（shot_info_panel）と違って言語ごとには撮らない。
##
## 実行（リポジトリ直下）:
##   godot --path godot res://tools/manual/shot_combat_window.tscn -- <出力フォルダ> <ステージjsonのres://パス> --attacker <col,row> --target <col,row> [--size <WxH>] [--count <枚数>] [--interval <秒>]
##
##   --attacker / --target … ステージJSONと同じ col/row。隣接（または射程内）であること
##   --size WxH            … ウィンドウの解像度（既定 2560x1440）。窓の切り抜きもこの倍率で大きくなる
##   --count / --interval  … 連写の枚数と間隔（既定 24枚 × 0.12秒 ≒ 演出全体）

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
						_die("%s は col,row 形式: %s" % [a, v])
						return
					var cell := Vector2i(int(parts[0]), int(parts[1]))
					if a == "--attacker":
						atk_cell = cell
					else:
						tgt_cell = cell
				"--size":
					var wh := v.split("x")
					if wh.size() != 2:
						_die("--size は WxH 形式: %s" % v)
						return
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
		_die("<出力フォルダ> <ステージjson> --attacker col,row --target col,row が要る")
		return
	var out_dir := plain[0]
	var stage_path := plain[1]

	get_window().size = size
	DirAccess.make_dir_recursive_absolute(out_dir)

	var skins := SkinCatalog.load_standard()
	var state := StageLoader.load_file(stage_path)
	if state == null:
		_die("ステージを読めない: %s" % stage_path)
		return

	var controller := MatchController.new()
	controller.name = "MatchController"
	controller.setup(state)
	controller.ai_team = 1
	add_child(controller)

	# 盤は窓の下に敷かれるだけだが、実機と同じ結線で組む（暗幕の下に盤が居る前提の画）。
	var board: HexBoard3D = preload("res://presentation/board/hex_board_3d.gd").new()
	add_child(board)
	var terrain_skins := StageLoader.load_terrain_skins(stage_path)
	board.bind(state, controller, skins, terrain_skins,
		StageLoader.load_margin_terrain(stage_path), StageLoader.load_height_overrides(stage_path))
	board.set_process(false)  # ホバーの写り込み防止（shot_stage と同じ）
	var b := board._board_bounds()
	var vp := get_viewport().get_visible_rect().size
	var margin := vp.y * 0.05
	board._board_cam.fit_to_bounds(b.position, b.end, HexBoard3D.TILE,
		Rect2(margin, margin, vp.x - margin * 2.0, vp.y - margin * 2.0))

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

	var atk := state.unit_at(Hex.offset_to_axial(atk_cell.x, atk_cell.y))
	var tgt := state.unit_at(Hex.offset_to_axial(tgt_cell.x, tgt_cell.y))
	if atk == null or tgt == null:
		_die("指定マスに駒が居ない")
		return

	for f in 6:  # ウォームアップ
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	if not controller.execute_attack(AttackCommand.new(atk.handle, tgt.handle)):
		_die("攻撃が通らない（隣接/射程/行動済みを確認）")
		return

	# 撮影中はメモリに溜め、演出が終わってからまとめて書き出す（save_png が重く、間隔を壊すため）。
	# 窓の矩形はストレッチ解像度（1280x720）の座標なので、実解像度との比を掛けて切り抜く。
	var frames: Array[Image] = []
	for shot in count:
		await get_tree().create_timer(interval).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		frames.append(img.get_region(_window_region(combat, img)))
	for shot in frames.size():
		frames[shot].save_png("%s/combat_%02d.png" % [out_dir, shot])
	print("SHOT_BURST_SAVED dir=", out_dir, " count=", frames.size(),
		" size=", frames[0].get_size() if not frames.is_empty() else Vector2i.ZERO)
	get_tree().quit(0)

## 撮った画像の中で窓が占める矩形。窓（_panel）は演出が開くときに置かれるので毎回引き直す。
func _window_region(combat: CombatScene, img: Image) -> Rect2i:
	var view := get_viewport().get_visible_rect().size
	var rect: Rect2 = combat._panel.get_global_rect()
	var s := Vector2(img.get_size()) / view
	var pos := (rect.position * s).floor()
	var end := (rect.end * s).ceil()
	return Rect2i(Vector2i(pos), Vector2i(end - pos))

func _die(msg: String) -> void:
	push_error("shot_combat_window: " + msg)
	get_tree().quit(1)
