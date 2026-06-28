extends SceneTree
## CSV正本 → コード用JSON の変換（headless）。ユニットデータ一式は data/units/ に同居。
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
##
## 実行: godot --headless --script res://data/units/convert.gd

const Csv = preload("res://data/csv_util.gd")

func _initialize() -> void:
	_convert_unit_type()
	_convert_unit_skin()
	quit()

## ユニット性能表 → unit_type.json（{ "types": [...] }）。
func _convert_unit_type() -> void:
	var rows := Csv.read_table("res://data/units/unit_type.csv")
	Csv.write_json("res://data/units/unit_type.json", { "types": rows })
	print("unit_type.json: %d types" % rows.size())

## スキン表（1行=1別名: type_id, side, name）→ unit_skin.json。
## 同じ (type_id, side) の行は出現順にエイリアス配列へ。description/images は空（後で拡張）。
func _convert_unit_skin() -> void:
	var rows := Csv.read_table("res://data/units/unit_skin.csv")
	var skins := {}
	for r in rows:
		var tid := String(r["type_id"])
		var side := String(r["side"])
		if not skins.has(tid):
			skins[tid] = { "ally": [], "enemy": [] }
		skins[tid][side].append({ "name": String(r["name"]), "description": "", "images": {} })
	Csv.write_json("res://data/units/unit_skin.json", { "skins": skins })
	print("unit_skin.json: %d types" % skins.size())
