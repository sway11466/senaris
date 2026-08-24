extends Node3D
## marketing用スクリーンショット：ステージの盤を実機と同じ見た目で表示し、
## 駒を選択して移動範囲ハイライトが出た状態を高解像度PNGで保存する。
## セレクト・HUD・会話は挟まない（capture_board3d と同じ）。違いは選択状態を作れること。
## ロケールは英語固定（外に出す絵のため）。
##
## 実行（リポジトリ直下）:
##   godot --path godot res://tools/marketing/shot_stage.tscn -- <出力PNG> <ステージjsonのres://パス> [--select <col,row>] [--size <WxH>]
##
##   --select col,row … そのマスの駒を選択した状態で撮る（座標はステージJSONと同じ col/row）
##   --size WxH       … ウィンドウ＝出力の解像度（既定 2560x1440）

func _ready() -> void:
	var out := ""
	var stage_path := ""
	var select_cell := Vector2i(-1, -1)
	var has_select := false
	var size := Vector2i(2560, 1440)

	var uargs := OS.get_cmdline_user_args()
	var plain: Array[String] = []
	var i := 0
	while i < uargs.size():
		var a := uargs[i]
		if a == "--select" and i + 1 < uargs.size():
			var parts := uargs[i + 1].split(",")
			if parts.size() != 2:
				push_error("shot_stage: --select は col,row 形式: %s" % uargs[i + 1])
				get_tree().quit(1)
				return
			select_cell = Vector2i(int(parts[0]), int(parts[1]))
			has_select = true
			i += 2
		elif a == "--size" and i + 1 < uargs.size():
			var wh := uargs[i + 1].split("x")
			if wh.size() != 2:
				push_error("shot_stage: --size は WxH 形式: %s" % uargs[i + 1])
				get_tree().quit(1)
				return
			size = Vector2i(int(wh[0]), int(wh[1]))
			i += 2
		else:
			plain.append(a)
			i += 1
	if plain.size() < 2:
		push_error("shot_stage: 引数が足りない。<出力PNG> <ステージjsonのres://パス> が要る")
		get_tree().quit(1)
		return
	out = plain[0]
	stage_path = plain[1]

	TranslationServer.set_locale("en")
	get_window().size = size

	var skins := SkinCatalog.load_standard()
	var state := StageLoader.load_file(stage_path)
	if state == null:
		push_error("shot_stage: ステージを読めない: %s" % stage_path)
		get_tree().quit(1)
		return

	var controller := MatchController.new()
	controller.name = "MatchController"
	controller.setup(state)
	controller.ai_team = 1
	add_child(controller)

	var board: HexBoard3D = preload("res://presentation/board/hex_board_3d.gd").new()
	add_child(board)
	board.bind(state, controller, skins, StageLoader.load_terrain_skins(stage_path),
		StageLoader.load_margin_terrain(stage_path), StageLoader.load_board_height(stage_path, state.cols, state.rows),
		StageLoader.load_height_overrides(stage_path))

	if has_select:
		var hex := Hex.offset_to_axial(select_cell.x, select_cell.y)
		var unit := state.unit_at(hex)
		if unit == null:
			push_error("shot_stage: (%d,%d) に駒が居ない" % [select_cell.x, select_cell.y])
			get_tree().quit(1)
			return
		board._select(unit.id)

	# 盤全体を画面に収める。実機の fit_to_view は右の情報パネル（INFOPANEL_LEFT）を
	# 避けて左に寄せるが、このツールに HUD は無いので全画面を可視域にする。
	var b := board._board_bounds()
	var vp := get_viewport().get_visible_rect().size  # ストレッチ解像度（ウィンドウ実寸ではない）
	var margin := vp.y * 0.05
	var vis := Rect2(margin, margin, vp.x - margin * 2.0, vp.y - margin * 2.0)
	board._board_cam.fit_to_bounds(b.position, b.end, HexBoard3D.TILE, vis)

	# 地形テクスチャ・シェーダのウォームアップに数フレーム回す。
	for f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	print("SHOT_SAVED err=", err, " path=", out, " size=", img.get_size())
	get_tree().quit(0 if err == OK else 1)
