extends SceneTree
## 検証用（使い捨て）: feature-125 の配線＝UI（main.tscn）から経験した会話の記録に
## 到達しているか。中身の正しさは tests/unit が見るので、ここは「呼べているか」だけ。
## 実行: godot --path . -s res://tests/manual/check_chronicle_story.gd（--headless 不可）
##
## 実セーブ（user://chronicle.json）を汚さないよう、開始時に退避し終了時に戻す。

const MAIN := preload("res://presentation/main/main.tscn")
const LOG := "res://tests/manual/out/chronicle_story.txt"
const REAL := "user://chronicle.json"
const BACKUP := "user://chronicle.json.checkbak"

const CAMPAIGN := "tutorial1-goblin-raid"
const STAGE := "goblin-raid-st1"
const STAGE_PATH := "res://data/stages/tutorial1-goblin-raid/goblin-raid-st1.json"

var _lines := PackedStringArray()

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_run()

func _say(s: String) -> void:
	_lines.append(s)
	DirAccess.make_dir_recursive_absolute("res://tests/manual/out")
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _stash() -> void:
	if FileAccess.file_exists(REAL):
		DirAccess.copy_absolute(REAL, BACKUP)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL))
		_say("実セーブを退避した（%s）" % BACKUP)
	else:
		_say("実セーブは無い（新規として走る）")

func _restore() -> void:
	if FileAccess.file_exists(BACKUP):
		DirAccess.copy_absolute(BACKUP, REAL)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP))
		_say("実セーブを戻した")
	elif FileAccess.file_exists(REAL):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REAL))
		_say("この確認で作ったファイルを消した")

func _run() -> void:
	await process_frame
	_stash()

	var main: Node = MAIN.instantiate()
	root.add_child(main)
	await _frames(12)
	main._title_pending = false
	_say("起動: main.tscn が立ち上がった")

	# ステージ選択と同じ経路で冒険譚のステージに入る。
	main._context.campaign_id = CAMPAIGN
	main._context.stage_id = STAGE
	main._context.stage_path = STAGE_PATH
	main._context.started_at = int(Time.get_unix_time_from_system()) - 60
	main.load_stage(STAGE_PATH)
	await _frames(20)

	var store: ChronicleStore = main._chronicle_store
	var after_start: Dictionary = store.story(CAMPAIGN, STAGE)
	_say("開始の記録: start=%d 通り（0 なら到達していない）" % after_start["start"].size())

	# 決着＝戦果の記録とクロニクルの書き出し。UI の入口をそのまま呼ぶ。
	main._on_battle_finished(BattleState.PLAYER_WIN)
	await _frames(20)

	var after_clear: Dictionary = store.story(CAMPAIGN, STAGE)
	_say("決着の記録: clear=%d 通り" % after_clear["clear"].size())

	# 盤を離れるときに書く＝ファイルに残っているか。
	var reloaded := ChronicleStore.new(REAL)
	var on_disk: Dictionary = reloaded.story(CAMPAIGN, STAGE)
	_say("ファイル: start=%d 通り clear=%d 通り events=%d 件" % [
		on_disk["start"].size(), on_disk["clear"].size(), on_disk["events"].size()])
	_say("駒の記録も生きているか: skins=%d recipes=%d" % [
		reloaded.skins().size(), reloaded.recipes().size()])

	_restore()
	quit()
