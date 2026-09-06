extends SceneTree
## main.gd 分割の検証（使い捨て）: 勝利の決着で戦果票に載る行（ランク基準・所要時間）と印が
## StageTally 経由でも組めるか。ランクを持つステージを debug 冒険譚の文脈で開いて敵を殲滅する
## ＝進捗（progress.json）には記録されない。名簿とオートセーブは控えて最後に戻す。
## 実行: godot --path . -s res://tests/manual/check_stage_tally.gd（--headless 不可）

const MAIN := preload("res://presentation/main/main.tscn")
const STAGE := "res://data/stages/tutorial1-goblin-raid/st1.json"
const LOG := "user://check_stage_tally.txt"
const KEEP := ["user://roster.json", "user://save_auto.json"]

var _lines := PackedStringArray()
var _backup := {}

func _initialize() -> void:
	_run()

func _say(s: String) -> void:
	_lines.append(s)

func _labels(node: Node, out: Array) -> Array:
	for c in node.get_children():
		if c is Label and c.visible and not (c as Label).text.is_empty():
			out.append((c as Label).text)
		_labels(c, out)
	return out

func _run() -> void:
	await process_frame
	for p in KEEP:
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
	var st: BattleState = main._controller.state
	_say("stage loaded start_ally=%d rank_data=%s started_at>0=%s" % [main._tally._start_ally, main._tally._rank_data, main._context.started_at > 0])
	main._context.started_at -= 754  # 12:34 経った体にする
	st.turn_number = 3
	main._controller.wipe_enemies()  # 殲滅＝勝利の決着
	for f in 240:
		await process_frame
	_say("result visible=%s title=%s" % [main._result.visible, main._tally.title(main._campaign())])
	_say("rank=%s elapsed=%d" % [main._tally._evaluate_rank(), main._tally.elapsed()])
	for r in main._tally.rows(true):
		_say("row %s" % JSON.stringify(r))
	_say("banner labels=%s" % JSON.stringify(_labels(main._result, [])))
	main._result._dismiss()
	for f in 30:
		await process_frame
	_say("after dismiss: conversation=%s phase=%s" % [main._conversation.visible, main._story._phase])
	for p in KEEP:
		if _backup[p] == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_string(_backup[p])
			f.close()
	var log := FileAccess.open(LOG, FileAccess.WRITE)
	for l in _lines:
		log.store_line(l)
	log.close()
	quit(0)
