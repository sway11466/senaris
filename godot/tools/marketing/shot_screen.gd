extends Node
## marketing用スクリーンショット：実機の画面まるごとを撮る（盤＋HUD＋情報パネル＋ターン板＋ロゴ）。
## 盤だけを撮る shot_stage と違い、main.tscn をそのまま起動し、タイトル画面だけ伏せて撮影する。
## ＝紹介画像の「遊んでいるあいだ何を見ているか」を、実機と1ピクセルも変えずに渡すための道具。
## ロケールは英語固定（外に出す絵のため）。
##
## 実行（リポジトリ直下）:
##   godot --path godot res://tools/marketing/shot_screen.tscn -- <出力PNG> <ステージjsonのres://パス> [--select <col,row>] [--size <WxH>]
##
##   --select col,row … そのマスの駒を選択した状態で撮る（情報パネルにその駒が出る）
##   --frame c1,r1,c2,r2 … 盤全体ではなく、この2マスが作る矩形に画角を寄せる（縦長の盤を横長の画に収める）
##   --attack c1,r1,c2,r2 … 攻撃を1回通し、演出中を連写する（<出力PNG> は出力フォルダとして扱う）
##   --formation <recipe> --leader c,r --target c,r … 陣形スキルを1回発動し、カットインごと連写する（同上）
##   --talk N … 会話パートを N 行ぶん進めた状態で撮る（intro を持つステージで使う）
##   --select-screen … 盤ではなく酒場の冒険譚選択（依頼ボード）を開いた状態で撮る
##   --fresh … 進捗を空の別ファイルに差し替えて撮る（「討伐済」の焼き印が絵に重ならない）
##   --count / --interval … 連写の枚数と間隔（既定 24枚 × 0.12秒）
##   --size WxH       … ウィンドウ＝出力の解像度（既定 1920x1080）

const MAIN := preload("res://presentation/main/main.tscn")


func _ready() -> void:
	var plain: Array[String] = []
	var select_cell := Vector2i(-1, -1)
	var has_select := false
	var frame := PackedInt32Array()
	var attack := PackedInt32Array()
	var recipe := ""
	var talk := -1
	var select_screen := false
	var fresh := false
	var leader_cell := Vector2i(-1, -1)
	var target_cell := Vector2i(-1, -1)
	var count := 24
	var interval := 0.12
	var size := Vector2i(1920, 1080)

	var uargs := OS.get_cmdline_user_args()
	var i := 0
	while i < uargs.size():
		var a := uargs[i]
		if a == "--select" and i + 1 < uargs.size():
			var parts := uargs[i + 1].split(",")
			if parts.size() != 2:
				push_error("shot_screen: --select は col,row 形式: %s" % uargs[i + 1])
				get_tree().quit(1)
				return
			select_cell = Vector2i(int(parts[0]), int(parts[1]))
			has_select = true
			i += 2
		elif a == "--frame" and i + 1 < uargs.size():
			var f := uargs[i + 1].split(",")
			if f.size() != 4:
				push_error("shot_screen: --frame は c1,r1,c2,r2 形式: %s" % uargs[i + 1])
				get_tree().quit(1)
				return
			frame = PackedInt32Array([int(f[0]), int(f[1]), int(f[2]), int(f[3])])
			i += 2
		elif a == "--attack" and i + 1 < uargs.size():
			var t := uargs[i + 1].split(",")
			if t.size() != 4:
				push_error("shot_screen: --attack は c1,r1,c2,r2 形式: %s" % uargs[i + 1])
				get_tree().quit(1)
				return
			attack = PackedInt32Array([int(t[0]), int(t[1]), int(t[2]), int(t[3])])
			i += 2
		elif a == "--fresh":
			fresh = true
			i += 1
		elif a == "--select-screen":
			select_screen = true
			i += 1
		elif a == "--talk" and i + 1 < uargs.size():
			talk = int(uargs[i + 1])
			i += 2
		elif a == "--formation" and i + 1 < uargs.size():
			recipe = uargs[i + 1]
			i += 2
		elif a in ["--leader", "--target"] and i + 1 < uargs.size():
			var c := uargs[i + 1].split(",")
			if c.size() != 2:
				push_error("shot_screen: %s は col,row 形式: %s" % [a, uargs[i + 1]])
				get_tree().quit(1)
				return
			if a == "--leader":
				leader_cell = Vector2i(int(c[0]), int(c[1]))
			else:
				target_cell = Vector2i(int(c[0]), int(c[1]))
			i += 2
		elif a == "--count" and i + 1 < uargs.size():
			count = int(uargs[i + 1])
			i += 2
		elif a == "--interval" and i + 1 < uargs.size():
			interval = float(uargs[i + 1])
			i += 2
		elif a == "--size" and i + 1 < uargs.size():
			var wh := uargs[i + 1].split("x")
			if wh.size() != 2:
				push_error("shot_screen: --size は WxH 形式: %s" % uargs[i + 1])
				get_tree().quit(1)
				return
			size = Vector2i(int(wh[0]), int(wh[1]))
			i += 2
		else:
			plain.append(a)
			i += 1

	if plain.size() < 2:
		push_error("shot_screen: 引数が足りない。<出力PNG> <ステージjsonのres://パス> が要る")
		get_tree().quit(1)
		return
	var out := plain[0]
	var stage_path := plain[1]

	get_window().size = size

	var main := MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame

	# 言語は設定ファイルではなく英語で焼く。文言は _ready で組まれているので張り替えを頼む。
	TranslationServer.set_locale("en")
	main._refresh_labels()

	main._title.visible = false  # 酒場の扉。伏せるだけ＝_refresh_labels が参照するので消さない
	if select_screen:
		if fresh:
			# 手元の進捗を触らずに未クリア状態を作る＝別パスの空ストアへ差し替える。
			var store := ProgressStore.new("user://shot_fresh_progress.json")
			main._progress = CampaignProgress.new(CampaignCatalog.load_all(), store)
			main._select.setup(main._progress)
		# 盤は _ready が読んだ下敷きのまま。実機と同じく扉をくぐった後の画面を開く。
		main._select.open()
		for f in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var sel_img := get_viewport().get_texture().get_image()
		var sel_err := sel_img.save_png(out)
		print("SHOT_SAVED err=", sel_err, " path=", out, " size=", sel_img.get_size())
		get_tree().quit(0 if sel_err == OK else 1)
		return
	main.load_stage(stage_path)
	for f in 12:
		await get_tree().process_frame

	if has_select:
		var hex := Hex.offset_to_axial(select_cell.x, select_cell.y)
		var unit: Variant = main._controller.state.unit_at(hex)
		if unit == null:
			push_error("shot_screen: (%d,%d) に駒が居ない" % [select_cell.x, select_cell.y])
			get_tree().quit(1)
			return
		main.get_node("HexBoard")._select(unit.id)

	var board: Node = main.get_node("HexBoard")
	if frame.size() == 4:
		# 盤全体ではなく、指定した矩形に画角を寄せる。縦長の盤をそのまま撮ると駒が小さくなるため。
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for col in range(mini(frame[0], frame[2]), maxi(frame[0], frame[2]) + 1):
			for row in range(mini(frame[1], frame[3]), maxi(frame[1], frame[3]) + 1):
				var px: Vector2 = Hex.to_pixel(Hex.offset_to_axial(col, row), HexBoard3D.TILE)
				mn = mn.min(px)
				mx = mx.max(px)
		board._board_cam.fit_to_bounds(mn, mx, HexBoard3D.TILE, board._vis_rect())
	board.set_process(false)  # 盤の _process はホバー更新のみ＝止めて水色のホバーhexを写り込ませない

	for f in 12:  # 地形テクスチャ・シェーダのウォームアップとパネルの整列
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	if talk >= 0:
		# intro は load_stage が自動で始める。行送りは実機と同じ「次へ」を叩く。
		for n in talk:
			main._conversation._on_next()
			await get_tree().process_frame
		for f in 8:
			await get_tree().process_frame

	if recipe != "":
		var fs: Variant = main._controller.state
		var lead: Variant = fs.unit_at(Hex.offset_to_axial(leader_cell.x, leader_cell.y))
		if lead == null:
			push_error("shot_screen: --leader の指定マスに駒が居ない")
			get_tree().quit(1)
			return
		var picked := {}
		for o in Formation.available_for(fs, lead):
			if String(o["recipe"]) == recipe:
				picked = o
				break
		if picked.is_empty():
			push_error("shot_screen: %s が発動できない（レシピの並びと射程を確認）" % recipe)
			get_tree().quit(1)
			return
		DirAccess.make_dir_recursive_absolute(out)
		if not main._controller.execute_formation(FormationCommand.new(picked, Hex.offset_to_axial(target_cell.x, target_cell.y))):
			push_error("shot_screen: 陣形スキルが通らない")
			get_tree().quit(1)
			return
		var fframes: Array[Image] = []
		for shot in count:
			await get_tree().create_timer(interval).timeout
			await RenderingServer.frame_post_draw
			fframes.append(get_viewport().get_texture().get_image())
		for shot in fframes.size():
			fframes[shot].save_png("%s/formation_%02d.png" % [out, shot])
		print("SHOT_SAVED frames=", fframes.size(), " dir=", out)
		get_tree().quit(0)
		return

	if attack.size() == 4:
		var st: Variant = main._controller.state
		var atk: Variant = st.unit_at(Hex.offset_to_axial(attack[0], attack[1]))
		var tgt: Variant = st.unit_at(Hex.offset_to_axial(attack[2], attack[3]))
		if atk == null or tgt == null:
			push_error("shot_screen: --attack の指定マスに駒が居ない")
			get_tree().quit(1)
			return
		DirAccess.make_dir_recursive_absolute(out)
		if not main._controller.execute_attack(AttackCommand.new(atk.id, tgt.id)):
			push_error("shot_screen: 攻撃が通らない（隣接/射程/行動済みを確認）")
			get_tree().quit(1)
			return
		# 撮影中はメモリに溜め、演出が終わってから書き出す（save_png が重く撮影間隔を壊すため）
		var frames: Array[Image] = []
		for shot in count:
			await get_tree().create_timer(interval).timeout
			await RenderingServer.frame_post_draw
			frames.append(get_viewport().get_texture().get_image())
		for shot in frames.size():
			frames[shot].save_png("%s/combat_%02d.png" % [out, shot])
		print("SHOT_SAVED frames=", frames.size(), " dir=", out)
		get_tree().quit(0)
		return

	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	print("SHOT_SAVED err=", err, " path=", out, " size=", img.get_size())
	get_tree().quit(0 if err == OK else 1)
