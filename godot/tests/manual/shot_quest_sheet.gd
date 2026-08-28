extends SceneTree
## 依頼書（出撃確認の紙）の顔ぶれが 560×400 の紙に収まるかを実測する使い捨てスクリプト。
## 起動: godot --path . -s res://tests/manual/shot_quest_sheet.gd
## 出力: tests/manual/out/quest_sheet_*.png

const SHOTS := [
	{ "name": "t1st1", "path": "res://data/stages/tutorial1-goblin-raid/st1.json", "roster": false, "lost": 0 },
	{ "name": "t2st7", "path": "res://data/stages/tutorial2-undead-rush/st7.json", "roster": false, "lost": 0 },
	{ "name": "t3st2", "path": "res://data/stages/tutorial3-dragon-hunt/st2.json", "roster": true, "lost": 0 },
	# 3群（出撃できる生存者・このマップ限り・兵力ゼロ）が同時に出る紙。
	{ "name": "t3st2_lost", "path": "res://data/stages/tutorial3-dragon-hunt/st2.json", "roster": true, "lost": 3 },
	# 兵力ゼロで出撃できない駒（沈めた絵）の見え方を見るため、名簿の先頭4体を離脱者にする。
	{ "name": "t3st5_lost", "path": "res://data/stages/tutorial3-dragon-hunt/st5.json", "roster": true, "lost": 4 },
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
		var name := String(SHOTS[_index - 1]["name"])
		img.save_png("%s/quest_sheet_%s.png" % [out, name])
		_save_zoom(img, "%s/quest_sheet_%s_zoom.png" % [out, name])
		print("shot: ", name, "  sheet size=", _sheet.get_child(1).get_child(0).size)
	if _index >= SHOTS.size():
		return true
	var shot: Dictionary = SHOTS[_index]
	var brief := StageLoader.load_briefing(String(shot["path"]),
		_fake_roster(String(shot["path"]), int(shot["lost"])) if shot["roster"] else [])
	print(shot["name"], ": party=", (brief["party"] as Array).size(), " carryover=", brief["carryover"])
	_sheet.open(String(shot["name"]), brief["party"], brief["carryover"])
	return false

## 継承ステージ用のでっち上げ名簿。先頭 lost 体を兵力ゼロにする＝沈めた絵を見るため。
func _fake_roster(path: String, lost: int) -> Array:
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
			"troops": 0 if out.size() < lost else 8, "max_troops": 8,
		})
	return out

## 顔ぶれの並びだけを3倍に拡大して保存する（沈めた絵の見え方を確かめるため）。
func _save_zoom(img: Image, path: String) -> void:
	# 幕 > 中央 > 紙 > 余白 > 中身 の4番目が顔ぶれの箱（quest_sheet.gd の組み立て順）。
	var box: Control = _sheet.get_child(1).get_child(0).get_child(0).get_child(0).get_child(3)
	var r := box.get_global_rect().grow(6.0)
	var crop := img.get_region(Rect2i(r.position, r.size))
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(path)
