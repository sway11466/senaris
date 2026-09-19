extends SceneTree
## 使い捨て：クロニクルの「紙を先に出して絵をあとから載せる」を確かめる。
## 起動: godot --path . -s res://tests/manual/check_chronicle_async.gd
## 出力: res://tests/manual/out/chronicle_async.txt ＋ chronicle_skeleton.png（絵が届く前）・chronicle_filled.png

var _main: Node = null
var _frame := 0
var _phase := 0
var _at := 15
var _log := ""
var _open_frame := 0
var _shot_done := false

func _initialize() -> void:
	var packed: PackedScene = load("res://presentation/main/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < _at:
		return false
	var screen = _main._chronicle_screen
	match _phase:
		0:
			if _main._title != null:
				_main._title.visible = false
			_main._select.visible = false
			_phase = 1
			_at = _frame + 5
		1:
			_open("1st open")
			_phase = 2
		2:
			# 絵が全部載るまで毎フレーム数える
			var c := _count(screen._chapters[0])
			if not _shot_done and c[1] < c[0] and _frame - _open_frame >= 20:  # 暗幕のフェードが済んでから
				_shot("chronicle_skeleton")
				_shot_done = true
			if c[1] >= c[0] or _frame - _open_frame > 600:
				_log += "1st open: faces %d/%d after %d frames\n" % [c[1], c[0], _frame - _open_frame]
				_phase = 3
				_at = _frame + 20
		3:
			_shot("chronicle_filled")
			screen.visible = false
			_open("2nd open")
			var c := _count(screen._chapters[0])
			_log += "2nd open: faces %d/%d immediately\n" % [c[1], c[0]]
			_phase = 4
			_at = _frame + 5
		4:
			var t0 := Time.get_ticks_usec()
			screen._select_chapter(1)  # 陣形スキル章
			_log += "formations chapter: switch = %.1f ms\n" % ((Time.get_ticks_usec() - t0) / 1000.0)
			_open_frame = _frame
			_phase = 5
		5:
			var c := _count(screen._chapters[1])
			if c[1] >= c[0] or _frame - _open_frame > 600:
				_log += "formations chapter: faces %d/%d after %d frames\n" % [c[1], c[0], _frame - _open_frame]
				_phase = 6
				_at = _frame + 10
		6:
			_shot("chronicle_formations")
			var t0 := Time.get_ticks_usec()
			screen._select_chapter(0)
			_log += "back to units: switch = %.1f ms\n" % ((Time.get_ticks_usec() - t0) / 1000.0)
			var c := _count(screen._chapters[0])
			_log += "back to units: faces %d/%d immediately\n" % [c[1], c[0]]
			var f := FileAccess.open("res://tests/manual/out/chronicle_async.txt", FileAccess.WRITE)
			f.store_string(_log)
			f.close()
			return true
	return false

func _open(tag: String) -> void:
	var t0 := Time.get_ticks_usec()
	_main._chronicle_screen.open(_main._chronicle_store, _main._progress, _main._skins)
	_log += "%s: open() = %.1f ms\n" % [tag, (Time.get_ticks_usec() - t0) / 1000.0]
	_open_frame = _frame

## [紙の数, 絵が載った紙の数]
func _count(chapter) -> Array:
	var total := 0
	var filled := 0
	for grid in chapter._content_box.get_children():
		if not (grid is HFlowContainer) or grid.is_queued_for_deletion():
			continue
		for card in grid.get_children():
			total += 1
			if card.get_child_count() > 0 and card.get_child(0).get_child_count() > 0:
				filled += 1
	return [total, filled]

func _shot(tag: String) -> void:
	root.get_texture().get_image().save_png("res://tests/manual/out/%s.png" % tag)
