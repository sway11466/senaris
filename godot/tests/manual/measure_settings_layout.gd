extends SceneTree
## 使い捨て検証: 設定画面を日英で開き、項目名・選択子の位置と大きさを測って言語差を出す。
## 実行: godot --path . -s res://tests/manual/measure_settings_layout.gd（--headless 不可）

const LOG := "res://tests/manual/out/settings_layout.txt"
const SHOT_JA := "res://tests/manual/out/settings_layout_ja.png"
const SHOT_EN := "res://tests/manual/out/settings_layout_en.png"

var _lines := PackedStringArray()
var _rects := {}

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_run()

func _run() -> void:
	await process_frame
	var locale0 := TranslationServer.get_locale()
	var screen := SettingsScreen.new()
	root.add_child(screen)
	await process_frame
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		screen.refresh_labels()
		screen.open(locale, {"master": 100, "music": 100, "sfx": 100}, "windowed", "hide")
		for f in 8:
			await process_frame
		_measure(locale, screen)
		await _shot(SHOT_JA if locale == "ja" else SHOT_EN)
	_diff()
	TranslationServer.set_locale(locale0)
	var log := FileAccess.open(LOG, FileAccess.WRITE)
	for l in _lines:
		log.store_line(l)
	log.close()
	quit(0)

func _measure(locale: String, screen: SettingsScreen) -> void:
	var got := {}
	for key in screen._labels:
		got["label:" + String(key)] = (screen._labels[key] as Control).get_global_rect()
	for row_id in screen._choice_frames:
		for id in screen._choice_frames[row_id]:
			got["frame:%s/%s" % [row_id, id]] = (screen._choice_frames[row_id][id] as Control).get_global_rect()
	for bus in screen._sliders:
		got["slider:" + String(bus)] = (screen._sliders[bus] as Control).get_global_rect()
		got["spin:" + String(bus)] = (screen._spins[bus] as Control).get_global_rect()
	_rects[locale] = got
	_lines.append("--- %s ---" % locale)
	for k in got:
		var r: Rect2 = got[k]
		_lines.append("  %-42s x=%.0f y=%.0f w=%.0f h=%.0f" % [k, r.position.x, r.position.y, r.size.x, r.size.y])

func _diff() -> void:
	_lines.append("--- ja vs en ---")
	var moved := 0
	for k in _rects["ja"]:
		var a: Rect2 = _rects["ja"][k]
		var b: Rect2 = _rects["en"][k]
		if a != b:
			moved += 1
			_lines.append("  MOVED %-40s dx=%.0f dy=%.0f dw=%.0f dh=%.0f" % [k, b.position.x - a.position.x, b.position.y - a.position.y, b.size.x - a.size.x, b.size.y - a.size.y])
	_lines.append("moved=%d / %d" % [moved, _rects["ja"].size()])

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	_lines.append("shot %s save=%d" % [path, err])
