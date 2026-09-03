extends SceneTree
## feature-96 検証用（使い捨て）: 戦闘のとどめ（スロー＋寄り）→ 白フラッシュ → 戦果票（白から現れる）
## の受け渡しを通しで動かし、節目でスクショと実測を採る。見るのは (1) 一斉射中に窓の中身が寄るか
## (2) finished 後も窓が白待ちで残るか (3) 白の下で票が敷かれ、白が引くと票が出ているか。
## 実行: godot --path . -s res://tests/manual/shot_finish_combat.gd（--headless 不可）

const OUT := "res://tests/manual/out"

var _scene: CombatScene
var _flash: FinishFlash
var _banner: ResultBanner
var _screen: ScreenLighting
var _log: Array = []

func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()  # 盤の代わりの下地
	bg.color = Color(0.22, 0.30, 0.20)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_screen = ScreenLighting.new()
	root.add_child(_screen)
	_scene = CombatScene.new()
	_scene.bind({})
	_scene.bind_screen(_screen)
	root.add_child(_scene)
	_banner = ResultBanner.new()
	root.add_child(_banner)
	_flash = FinishFlash.new()
	root.add_child(_flash)
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var detail := {
		"attacker": { "team": 0, "type_id": "fighter", "troops_before": 5, "troops_after": 5,
			"terrain": "plain", "pos": Vector2i(0, 0) },
		"defender": { "team": 1, "type_id": "fighter", "troops_before": 3, "troops_after": 0,
			"terrain": "plain", "pos": Vector2i(1, 0) },
		"to_attacker": null,
	}
	_scene.arm_finisher()  # main._on_combat_resolved と同じ順（勝ち確定 → arm → play）
	_scene.play(detail)
	await create_timer(1.35).timeout  # LEAD_IN(0.95) 明け＝とどめの一斉射の直後
	_note("volley: inner.scale=%s (期待 1.16 へ寄る)" % _scene._inner.scale)
	_shot("finish_1_volley.png")
	await _scene.finished
	_note("finished: scene.visible=%s (期待 true＝フェード無しで白待ち)" % _scene.visible)
	_shot("finish_2_hold.png")
	await _flash.rise()
	_shot("finish_3_white.png")
	_scene.close_under_flash()
	_banner.play("森の追撃", "S", true, [
		{ "label": "ターン", "value": "12 / 30" },
		{ "label": "生存", "value": "5 / 5" },
	], "ランク", "", true)
	_flash.fall()
	_note("under white: scene.visible=%s banner.visible=%s (期待 false / true)" % [_scene.visible, _banner.visible])
	await create_timer(0.30).timeout
	_shot("finish_4_reveal.png")  # 白が引く途中＝票が透けて出てくる
	await create_timer(0.60).timeout
	_shot("finish_5_stamp.png")   # 白が引き切り、印が落ちた後
	var f := FileAccess.open(OUT.path_join("finish_log.txt"), FileAccess.WRITE)
	for line in _log:
		f.store_line(String(line))
	f.close()
	quit()

func _note(s: String) -> void:
	_log.append(s)

func _shot(fname: String) -> void:
	root.get_texture().get_image().save_png(OUT.path_join(fname))
	_note("shot: %s" % fname)
