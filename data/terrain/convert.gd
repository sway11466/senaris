extends SceneTree
## 地形表 CSV正本 → terrain.json（headless）。
## 列: id, char(ASCII), atk(地形攻), def(地形防), color(プレースホルダ色)。
## 移動コストは movement.csv 側（移動タイプ×地形の行列）。生成JSONは手で触らない。
##
## 実行: godot --headless --script res://data/terrain/convert.gd

const Csv = preload("res://data/csv_util.gd")

func _initialize() -> void:
	var rows := Csv.read_table("res://data/terrain/terrain.csv")
	Csv.write_json("res://data/terrain/terrain.json", { "terrains": rows })
	print("terrain.json: %d terrains" % rows.size())
	quit()
