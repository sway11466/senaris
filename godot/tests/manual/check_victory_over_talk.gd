extends SceneTree
## 使い捨ての実機検証: 情報板を畳み「会話のみ表示する」にした状態で、
## (A) focus 付きイベントの会話中にカメラの寄せ先が会話板の裏に来ないか（tutorial1 st4 の町解放）
## (B) 完走の outro で勝利イラストが会話板を覆わないか（tutorial1 st7＝最終ステージ）
## を main と同じ呼び順で再現して実測し、絵も撮る。
## 起動: godot --path . -s res://tests/manual/check_victory_over_talk.gd（--headless 不可＝スクショを撮る）
## 結果: res://tests/manual/out/victory_over_talk.txt

const ST4 := "res://data/stages/tutorial1-goblin-raid/goblin-raid-st4.json"
const ST7 := "res://data/stages/tutorial1-goblin-raid/goblin-raid-st7.json"
const OUT := "res://tests/manual/out"
const LOG := OUT + "/victory_over_talk.txt"

var _main: Node = null
var _lines := PackedStringArray()
var _was_minimized := false
var _was_mode := ""

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)
	_run()

func _log(s: String) -> void:
	_lines.append(s)
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()

func _wait(frames: int) -> void:
	for i in frames:
		await process_frame

func _run() -> void:
	await _wait(30)
	var panel: Control = _main.get_node("Front/InfoPanel")
	_was_minimized = panel.is_minimized()
	_was_mode = _main._settings_store.dialogue_when_minimized()
	_main._select.close()
	if _main._title != null and _main._title.visible:
		_main._title_pending = false
		_main._title.close()
	panel.set_minimized(true)
	_main._settings_store.set_dialogue_when_minimized("show")
	_main._context.campaign_id = "tutorial1-goblin-raid"
	_log("viewport=%s" % str(root.get_visible_rect().size))

	await _check_event_focus()
	await _check_victory_outro()

	# 触った設定は戻す（実機の user://settings.json を共有しているため）。
	_main._settings_store.set_dialogue_when_minimized(_was_mode)
	panel.set_minimized(_was_minimized)
	_log("done")
	quit()

## (A) イベント会話のカメラ寄せ。会話板が出る前に寄せるので、寄せ先の可視域に会話板が入っているかを見る。
func _check_event_focus() -> void:
	_log("=== (A) event focus: st4 ===")
	_main._context.stage_id = "goblin-raid-st4"
	_main.load_stage(ST4)
	await _wait(20)
	await _skip_talk("intro")
	var board: Node = _main.get_node("HexBoard")
	var cam = board._board_cam
	_log("会話板 visible=%s / 盤エリア=%s / カメラ可視域=%s"
		% [_main._conversation.visible, _area(), board._vis_rect()])
	# 右ボックス（x=800..1264）の裏に映っているヘックスを探す
	var hex := Vector2i.MAX
	var state = board.state
	for col in state.cols:
		for row in state.rows:
			var h := Vector2i(col, row)
			var sp: Vector2 = cam.camera.unproject_position(board._hex_world(h))
			if sp.x > 900.0 and sp.x < 1200.0 and sp.y > 200.0 and sp.y < 600.0:
				hex = h
				break
		if hex != Vector2i.MAX:
			break
	if hex == Vector2i.MAX:
		_log("右ボックスの裏に映るヘックスが無い（盤が右まで広がっていない）")
		return
	var w: Vector3 = board._hex_world(hex)
	_log("hex=%s screen(before)=%s" % [hex, cam.camera.unproject_position(w)])
	_main._story.on_event_fired({ "id": "town-freed", "on": "capture", "dialogue": "free", "focus": true, "hex": hex })
	await _wait(90)  # 寄せの Tween と会話の開始を待つ
	var sp_after: Vector2 = cam.camera.unproject_position(w)
	var talk_rect := Rect2(_main._conversation.position, _main._conversation.size)
	_log("会話中: 会話板 visible=%s rect=%s / 盤エリア=%s / カメラ可視域=%s"
		% [_main._conversation.visible, talk_rect, _area(), board._vis_rect()])
	_log("hex screen(after focus)=%s → 会話板の裏か: %s" % [sp_after, talk_rect.has_point(sp_after)])
	_shot("victory_over_talk_A_event.png")
	await _skip_talk("event")

## (B) 完走の outro。main._on_battle_finished と同じ順＝会話板を出してから絵を敷く。
func _check_victory_outro() -> void:
	_log("=== (B) victory over outro: st7 ===")
	_main._context.stage_id = "goblin-raid-st7"
	_main.load_stage(ST7)
	await _wait(20)
	await _skip_talk("intro")
	_log("outro 前: 会話板 visible=%s / 盤エリア=%s" % [_main._conversation.visible, _area()])
	_log("_should_show_victory=%s path=%s" % [_main._should_show_victory(), _main._victory_path()])
	var outro: Array = _main._story.outro_lines()
	# --- main と同じ順（会話板→絵） ---
	var show_victory: bool = _main._should_show_victory()
	_main._story.start_outro(outro, "ui.talk.close")
	if show_victory:
		_main._victory_overlay = true
		_main._victory_screen.play_over_board(_main._victory_path())
	# ---
	await _wait(40)  # フェードイン 0.4 秒を待つ
	var vs = _main._victory_screen
	var pic_rect: Rect2 = vs._pic.get_global_rect()
	var root_rect: Rect2 = Rect2(vs._root.position, vs._root.size)
	var talk_rect := Rect2(_main._conversation.position, _main._conversation.size)
	_log("会話中: 会話板 visible=%s rect=%s / 盤エリア=%s" % [_main._conversation.visible, talk_rect, _area()])
	_log("勝利イラスト: visible=%s 表示域=%s 絵=%s" % [vs.visible, root_rect, pic_rect])
	var inter := pic_rect.intersection(talk_rect)
	_log("絵と会話板の重なり=%s → 覆っている: %s" % [inter, inter.size.x > 0.0 and inter.size.y > 0.0])
	_shot("victory_over_talk_B_outro.png")
	await _skip_talk("outro")

func _skip_talk(label: String) -> void:
	if _main._conversation.visible:
		_log("%s の会話をスキップ" % label)
		_main._conversation._on_skip()
	else:
		_log("%s の会話は出ていない" % label)
	await _wait(5)

func _area() -> Rect2:
	return UiLayout.board_area(root.get_visible_rect().size)

func _shot(fname: String) -> void:
	root.get_texture().get_image().save_png(OUT.path_join(fname))
	_log("shot: %s" % fname)
