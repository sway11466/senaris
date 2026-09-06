extends SceneTree
## main.gd 分割の検証（使い捨て）: 中断セーブ／オートセーブ／ロード／タイトルの「冒険の続き」が
## SaveCoordinator 経由でも同じに通るか。debug 冒険譚の文脈でランクを持つステージを開き、
## オートセーブ→手動セーブ→盤を進めてロード→タイトルから続き、の順に見る。
## セーブ枠と名簿の実ファイルは控えて最後に戻す＝検証の値を残さない。
## 実行: godot --path . -s res://tests/manual/check_save_coordinator.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/tutorial1-goblin-raid/st1.json"
const LOG := "user://check_save_coordinator.txt"

var _lines := PackedStringArray()
var _backup := {}

func _initialize() -> void:
	_run()

func _say(s: String) -> void:
	_lines.append(s)

func _keep_paths() -> Array:
	var out: Array = ["user://roster.json"]
	for id in SaveSlots.slot_ids():
		out.append("user://%s%s.json" % [SaveSlots.PREFIX, id])
	return out

func _meta(slot: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string("user://%s%s.json" % [SaveSlots.PREFIX, slot])
	var data = JSON.parse_string(raw)
	if not (data is Dictionary):
		return {}
	return (data as Dictionary).get("meta", {})

func _close_talk(main: Node) -> void:
	if main._conversation.visible:
		main._conversation._close()

func _run() -> void:
	await process_frame
	for p in _keep_paths():
		_backup[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
	var main: Node = MAIN.instantiate()
	root.add_child(main)
	for f in 10:
		await process_frame
	main._title_pending = false
	main._title.visible = false
	main._select.close()
	main._context.campaign_id = "debug-victory"
	main._context.stage_id = "boss"
	main.load_stage(STAGE)
	for f in 10:
		await process_frame
	_close_talk(main)
	# オートセーブ＝ステージの頭（自ターン開始時点）で書かれている
	var auto := _meta(SaveSlots.AUTO)
	_say("autosave has_any=%s campaign=%s stage=%s turn=%s started_at=%s digest_len=%d" % [
		main._save.has_any(), auto.get("campaign_id"), auto.get("stage_id"), auto.get("turn_number"), auto.get("started_at"), String(auto.get("stage_digest", "")).length()])
	_say("autosave started_at matches context: %s" % [int(auto.get("started_at", -1)) == main._context.started_at])
	# 手動セーブ＝システムメニュー「セーブ」→枠 1
	main._hud.save_requested.emit()
	await process_frame
	var panel: SaveSlotPanel = main._save._slot_panel
	_say("save panel visible=%s heading=%s" % [panel.visible, panel._heading.text])
	panel._decide("1")
	await process_frame
	var m1 := _meta("1")
	_say("slot1 written=%s stage_title=%s panel_closed=%s" % [FileAccess.file_exists("user://save_1.json"), m1.get("stage_title"), not panel.visible])
	# 盤を進めてからロード＝自ターンの頭に戻る
	var st: BattleState = main._controller.state
	st.turn_number = 5
	main._context.started_at = 1
	main._hud.load_requested.emit()
	await process_frame
	_say("load panel visible=%s heading=%s" % [panel.visible, panel._heading.text])
	panel._decide("1")
	for f in 10:
		await process_frame
	_close_talk(main)
	_say("after load turn=%d (was 5) campaign=%s stage=%s started_at_restored=%s conv=%s" % [
		main._controller.state.turn_number, main._context.campaign_id, main._context.stage_id,
		main._context.started_at == int(m1.get("started_at", -1)), main._conversation.visible])
	# タイトルの「冒険の続き」＝オートセーブの枠から盤へ直行し、タイトルが畳まれる
	main._title.visible = true
	main._on_title_continue()
	await process_frame
	_say("continue panel visible=%s heading=%s" % [panel.visible, panel._heading.text])
	panel._decide(SaveSlots.AUTO)
	for f in 10:
		await process_frame
	_say("after continue title_visible=%s title_pending=%s turn=%d" % [main._title.visible, main._title_pending, main._controller.state.turn_number])
	# 戻す
	for p in _keep_paths():
		if _backup[p] == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_string(_backup[p])
			f.close()
	var same := true
	for p in _keep_paths():
		var now = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
		if now != _backup[p]:
			same = false
	_say("restored files_same=%s" % same)
	var log := FileAccess.open(LOG, FileAccess.WRITE)
	for l in _lines:
		log.store_line(l)
	log.close()
	quit(0)
