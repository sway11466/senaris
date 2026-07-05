extends SceneTree
## 地形表 CSV正本 → terrain.json（headless）。
## 列: id, char(ASCII), atk(地形攻), def(地形防), color(プレースホルダ色)。
## 移動コストは movement.csv 側（移動タイプ×地形の行列）。生成JSONは手で触らない。
##
## 実行: godot --headless --path . --script res://data/terrain/convert.gd

const Csv = preload("res://data/csv_util.gd")

## 非空で必ず要る列（image/memo は任意）。
const REQUIRED := ["id", "name", "char", "atk", "def"]

func _initialize() -> void:
	var rows := Csv.read_table("res://data/terrain/terrain.csv")
	var problems := Csv.missing_required(rows, REQUIRED, "id")
	for v in Csv.duplicates(rows, "id"):
		problems.append("id が重複: '%s'（後勝ち上書きになる）" % v)
	for v in Csv.duplicates(rows, "char"):
		problems.append("char が重複: '%s'（マップ文字→地形の衝突）" % v)
	if problems.is_empty():
		Csv.write_json("res://data/terrain/terrain.json", { "terrains": rows })
		print("terrain.json: %d terrains" % rows.size())
	else:
		for p in problems:
			push_error("terrain.csv: %s" % p)
		push_error("terrain.csv: 検証エラー %d 件。terrain.json は更新しない（CSVを直して再実行）" % problems.size())
	quit()
