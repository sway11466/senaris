extends SceneTree
## 使い捨て：④トリックショットの威力が formations.md ④の試算どおりか実測する。
## 起動: godot --headless --path . -s res://tests/manual/check_trick_shot_numbers.gd
## 出力: res://tests/manual/out/check_trick_shot_numbers.txt

const OUT := "res://tests/manual/out/check_trick_shot_numbers.txt"

func _initialize() -> void:
	var log: Array[String] = []
	for row in [
		{"archer": "archer", "atk": 30, "air": 30, "rng": 3, "def": 40, "fly": false, "memo": "ゴブリン級 防40（期待6）"},
		{"archer": "archer", "atk": 30, "air": 30, "rng": 3, "def": 70, "fly": false, "memo": "ナイト級 防70（期待3）"},
		{"archer": "hunter", "atk": 30, "air": 50, "rng": 4, "def": 50, "fly": true, "memo": "竜 防50・飛行 ハンター（期待6）"},
		{"archer": "elf", "atk": 30, "air": 60, "rng": 5, "def": 50, "fly": true, "memo": "竜 防50・飛行 エルフ（期待7）"},
	]:
		log.append("%s -> 損害 %d" % [row["memo"], _loss(row)])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(log) + "\n")
	f.close()
	quit()

func _loss(row: Dictionary) -> int:
	var s := BattleState.new(12, 8)
	var c := Hex.offset_to_axial(2, 3)
	var bow := Unit.new(1, 0, c, 4, 8, int(row["atk"]), 30, 1, String(row["archer"]))
	bow.atk_air = int(row["air"])
	bow.min_range = 1
	bow.attack_range = int(row["rng"])
	var foe_hex := c + Hex.direction(0) * 3
	var foe := Unit.new(9, 1, foe_hex, 3, 8, 10, int(row["def"]))
	if bool(row["fly"]):
		foe.move_type = "flight"
	var scout := Unit.new(2, 0, foe_hex + Hex.direction(0), 7, 8, 20, 20, 1, "thief")
	for u in [bow, foe, scout]:
		s.add_unit(u)
	for o in Formation.available_for(s, bow):
		if o.skill == "trick_shot":
			return FormationResolver.resolve(s, o, foe_hex).hits[0].loss
	return -1
