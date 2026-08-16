extends SceneTree
## 使い捨て：画面の明暗の共通基盤（ScreenLighting）の実測。
## ・幕が画面全体＋のりしろを覆うか ・重ね掛け（2者が dim →片方 undim で暗いまま）
## ・クリック吸収は block_input の者が居るときだけ ・カットインが dim/undim を呼ぶか
## 実行: godot --headless --path . --script res://tests/manual/measure_screen_lighting.gd

func _initialize() -> void:
	_run()

func _run() -> void:
	var screen := ScreenLighting.new()
	root.add_child(screen)
	var cutin := FormationCutin.new()
	root.add_child(cutin)
	await process_frame  # _ready はツリーの最初のフレームで走る＝それを待ってから測る
	var vp: Vector2 = root.get_visible_rect().size
	print("layer = ", screen.layer, "（40 が期待値）")
	print("scrim = ", Rect2(screen._scrim.position, screen._scrim.size),
		"（画面 ", vp, " ＋のりしろ ", ScreenLighting.BLEED, " が期待値）")
	print("色 = ", screen._scrim.color, "（a=0.5 が期待値）")
	# 重ね掛け：会話(block_input=true)と戦闘(false)が同時に掛かる → 片方明けても暗いまま
	var a := Node.new()
	var b := Node.new()
	screen.dim(a, true)
	screen.dim(b)
	print("2者dim: 幕が出ている=", screen._scrim.visible,
		" クリック吸収=", screen._scrim.mouse_filter == Control.MOUSE_FILTER_STOP)
	screen.undim(a)
	print("block者だけundim: まだ暗い=", not screen._owners.is_empty(),
		" クリック素通し=", screen._scrim.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	screen.undim(b)
	print("全員undim: 明ける=", screen._owners.is_empty())
	# カットイン：play で dim・close で undim（絵は実在レシピで引く）
	cutin.bind_screen(screen)
	var ok := cutin.play("holy_aria")
	print("cutin.play=", ok, " → dim掛かる=", not screen._owners.is_empty())
	cutin.dismiss()
	print("cutin.dismiss → 明ける=", screen._owners.is_empty())
	# 加護の光：幕より前（後に add した子が前面）
	screen.aura_play(AuraOverlay.HOLY_COLOR)
	print("aura: 出ている=", screen._aura.visible,
		" 幕より前=", screen._aura.get_index() > screen._scrim.get_index())
	a.free()
	b.free()
	quit()
