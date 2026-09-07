extends SceneTree
## 使い捨ての実機確認：会話の場面の区切り（scene 行）。チュートリアル３ st3 の戦闘前会話を
## 開いて「次へ」を送り、ローグ側へ切り替わる区切りと、冒険者側へ戻る区切りを撮る。
## 起動: godot --path . -s res://tests/manual/shot_talk_scene.gd
## 出力: user://talk_scene_1.png / user://talk_scene_2.png / user://shot_talk_scene.txt（板の矩形）

const STAGE := "res://data/stages/tutorial3-dragon-hunt/st3.json"
const OUT := "user://shot_talk_scene.txt"

var _main: Node = null
var _talk: Control = null
var _lines: PackedStringArray = []
var _frames := 0
var _done := false

func _initialize() -> void:
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		30: _open()
		120: _advance(7)   # hunter, vanguard, sfx, wizard, thief, [scene], rogue, rogue_axe
		160: _shoot("user://talk_scene_1.png")
		170: _advance(6)   # rogue x3, [scene], hunter, vanguard
		210: _shoot("user://talk_scene_2.png")
		220: _finish()
	if _done:
		FileAccess.open(OUT, FileAccess.WRITE).store_string("\n".join(_lines))
		return true
	return _frames > 600

func _open() -> void:
	_talk = _main._conversation
	_main._select.close()
	if _main._title != null and _main._title.visible:
		_main._title_pending = false
		_main._title.close()
	_main._on_stage_chosen("tutorial3-dragon-hunt", "st3", STAGE)

func _advance(n: int) -> void:
	for i in n:
		_talk._on_next()

func _shoot(path: String) -> void:
	_say("%s rect=%s visible=%s rows=%d" % [path, str(_talk.get_global_rect()), str(_talk.visible), _talk._messages.get_child_count()])
	root.get_texture().get_image().save_png(path)

func _finish() -> void:
	_done = true

func _say(line: String) -> void:
	_lines.append(line)
