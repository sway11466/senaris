extends SceneTree
## 使い捨ての実機確認：敵のユニットスキル（ドレッドタッチ）を実機と同じ手番で撮れるかを見る。
## 手順＝AIを外す（ai_brain=null）→ end_turn で敵の手番へ渡す → ゴーストで発動 → 1枚撮る。
## 実行: godot --path godot -s res://tests/manual/check_enemy_skill_shot.gd
## 経過は下の LOG に1行ずつ書き足す（print は出ない＝途中で止まっても読める）。

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/debug-photo/devlog4-2.json"
const DIR := "C:/Users/tappe/AppData/Local/Temp/claude/C--Users-tappe-OneDrive-project-senaris/151f57df-e2c7-4c95-98d1-b281fcb4577a/scratchpad"
const LOG := DIR + "/enemy_skill_check.txt"
const PNG := DIR + "/enemy_skill_check.png"


func _initialize() -> void:
	_log("start")
	_run()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var main := MAIN.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_log("main added")
	TranslationServer.set_locale("en")
	main._refresh_labels()
	main._title.visible = false
	main.load_stage(STAGE)
	for f in 12:
		await process_frame
	_log("stage loaded")

	var ctl: Variant = main._controller
	_log("before: current_team=%d ai_team=%d is_ai_turn=%s" % [ctl.state.current_team, ctl.ai_team, str(ctl.is_ai_turn())])

	# AI を外してからターンを渡す＝敵の手番になっても思考が走らない（盤が動かない）。
	ctl.ai_brain = null
	ctl.end_turn()
	for f in 12:
		await process_frame
	_log("after end_turn: current_team=%d is_ai_turn=%s" % [ctl.state.current_team, str(ctl.is_ai_turn())])

	var ghost: Variant = ctl.state.unit_at(Hex.offset_to_axial(4, 4))
	if ghost == null:
		_log("NG: (4,4) に駒が居ない")
		quit(1)
		return
	_log("caster: team=%d skin=%s" % [ghost.team, str(ghost.skin_id)])

	var picked: FormationOption = null
	for o in Formation.available_for(ctl.state, ghost):
		_log("available: %s" % o.recipe)
		if o.recipe == "dread_touch":
			picked = o
	if picked == null:
		_log("NG: dread_touch が候補に出ない")
		quit(1)
		return

	var ok: bool = ctl.execute_formation(FormationCommand.new(picked, Hex.offset_to_axial(5, 4)))
	_log("execute_formation = %s" % str(ok))
	for f in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	_log("save_png err=%d" % img.save_png(PNG))
	quit(0 if ok else 1)


func _log(line: String) -> void:
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string(line + "\n")
	f.close()
