extends SceneTree
## AI思考プリセット CSV正本 → ai.json（headless）。詳細 → doc/gdd/ai.md
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
##
## 実行: godot --headless --script res://data/ai/convert.gd

const Csv = preload("res://data/csv_util.gd")

func _initialize() -> void:
	_convert_ai()
	quit()

## ai.csv → { "presets": { label: {engage, sight, retreat, attack, target, advance} } }。
func _convert_ai() -> void:
	var rows := Csv.read_table("res://data/ai/ai.csv")
	var presets := {}
	for r in rows:
		var label := String(r["label"])
		var p := {}
		for key in r:
			if key != "label":
				p[key] = r[key]
		presets[label] = p
	Csv.write_json("res://data/ai/ai.json", { "presets": presets })
	print("ai.json: %d presets" % presets.size())
