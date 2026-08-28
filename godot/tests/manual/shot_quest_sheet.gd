extends SceneTree
## 依頼書（出撃確認の紙）の顔ぶれが 560×400 の紙に収まるかを実測する使い捨てスクリプト。
## 起動: godot --path . -s res://tests/manual/shot_quest_sheet.gd
## 出力: tests/manual/out/quest_sheet_*.png

const SHOTS := [
	{ "name": "t1st1", "path": "res://data/stages/tutorial1-goblin-raid/st1.json", "roster": false },
	{ "name": "t2st7", "path": "res://data/stages/tutorial2-undead-rush/st7.json", "roster": false },
	{ "name": "t3st2", "path": "res://data/stages/tutorial3-dragon-hunt/st2.json", "roster": true },
]

var _sheet: QuestSheet
var _bg: ColorRect
var _index := -1
var _frames := 0

func _initialize() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.10, 0.07, 0.05)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_bg)
	_sheet = QuestSheet.new()
	root.add_child(_sheet)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 20 != 0:
		return false
	_index += 1
	if _index > 0:
		var img := root.get_texture().get_image()
		var out := ProjectSettings.globalize_path("res://tests/manual/out")
		DirAccess.make_dir_recursive_absolute(out)
		img.save_png("%s/quest_sheet_%s.png" % [out, SHOTS[_index - 1]["name"]])
		print("shot: ", SHOTS[_index - 1]["name"], "  sheet size=", _sheet.get_child(1).get_child(0).size)
	if _index >= SHOTS.size():
		return true
	var shot: Dictionary = SHOTS[_index]
	var brief := StageLoader.load_briefing(String(shot["path"]), _fake_roster(String(shot["path"])) if shot["roster"] else [])
	print(shot["name"], ": party=", (brief["party"] as Array).size(), " carryover=", brief["carryover"])
	_sheet.open(String(shot["name"]), brief["party"], brief["carryover"])
	return false

## 継承ステージ用のでっち上げ名簿。先頭の1体だけ兵力ゼロ＝沈めた絵を見るため。
func _fake_roster(path: String) -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Array = []
	for u in data.get("player", []):
		var actor := String(u.get("actor", ""))
		if actor == "":
			continue
		out.append({
			"type": String(u.get("type", u.get("skin", ""))),
			"skin": String(u.get("skin", u.get("type", ""))),
			"actor": actor, "level": 1,
			"troops": 0 if out.is_empty() else 8, "max_troops": 8,
		})
	return out
