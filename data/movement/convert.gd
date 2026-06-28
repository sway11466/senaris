extends SceneTree
## 移動タイプ×地形コスト表 CSV正本 → movement.json（headless）。
## CSVは「行=移動タイプ／列=地形コスト」の完全表（差分なし）。x=進入不可。
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
##
## 実行: godot --headless --script res://data/movement/convert.gd

const Csv = preload("res://data/csv_util.gd")

func _initialize() -> void:
	_convert_movement()
	quit()

## movement.csv → { "movement_types": { move_type: { 地形: コスト } } }。
func _convert_movement() -> void:
	var rows := Csv.read_table("res://data/movement/movement.csv")
	var types := {}
	for r in rows:
		var id := String(r["move_type"])
		var costs := {}
		for key in r:
			if key != "move_type" and key != "name":  # 識別列は地形コストではない
				costs[key] = r[key]  # int か "x"
		types[id] = costs
	Csv.write_json("res://data/movement/movement.json", { "movement_types": types })
	print("movement.json: %d move types" % types.size())
