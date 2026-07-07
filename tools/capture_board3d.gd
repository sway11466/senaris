extends Node3D
## 【使い捨て】HexBoard3D（本物の3D盤）をステージ単体で表示して PNG 保存する検証ツール。
## セレクト画面・HUD・会話を挟まず、盤の見た目だけを素早く確認するため。
## 実行: godot --path . res://tools/capture_board3d.tscn -- <出力PNG> [ステージjsonのres://パス]
## リポジトリの本流には残さない前提（実験ブランチのプローブ）。

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var out := "board3d.png"
	var path := "res://data/stages/debug/debug.json"
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		out = uargs[0]
	if uargs.size() > 1:
		path = uargs[1]

	var skins := SkinCatalog.load_standard()
	var state := StageLoader.load_file(path)
	if state == null:
		push_error("capture3d: ステージを読めない: %s" % path)
		get_tree().quit(1)
		return

	var controller := MatchController.new()
	controller.name = "MatchController"
	controller.setup(state)
	controller.ai_team = 1
	add_child(controller)

	var board: HexBoard3D = preload("res://presentation/board/hex_board_3d.gd").new()
	add_child(board)
	board.bind(state, controller, skins, StageLoader.load_terrain_skins(path))

	# 地形テクスチャ・シェーダのウォームアップに数フレーム回す。
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	print("CAPTURE_SAVED err=", img.save_png(out), " path=", out)

	# picking の往復チェック: 各ヘックス中心 → スクリーン → レイ∩平面 → 同じヘックスに戻るか。
	var bad := 0
	var total := 0
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var p := Hex.to_pixel(hex, HexBoard3D.TILE)
			var screen := board._cam.unproject_position(Vector3(p.x, 0.0, p.y))
			var pt := board._plane_point_at(screen)
			total += 1
			if not pt.is_finite() or Hex.from_pixel(Vector2(pt.x, pt.z), HexBoard3D.TILE) != hex:
				bad += 1
	print("PICK_CHECK bad=", bad, "/", total)
	get_tree().quit(0)
