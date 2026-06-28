extends SceneTree
## CSV正本 → コード用JSON の変換ツール（headless）。ユニットデータ一式は data/units/ に同居。
## CSVは2行ヘッダ: 1行目=キー(英語), 2行目=日本語ラベル(人間用・変換時は読み飛ばす), 3行目以降=データ。
## 生成JSONは手で触らない。CSVを直してこれを再実行する。
##
## 実行: godot --headless --script res://data/units/convert.gd

func _initialize() -> void:
	_convert_unit_type()
	_convert_aliases()
	quit()

## ユニット性能表 → unit_type.json（{ "types": [...] }）。
func _convert_unit_type() -> void:
	var rows := _read_csv("res://data/units/unit_type.csv")
	_write_json("res://data/units/unit_type.json", { "types": rows })
	print("unit_type.json: %d types" % rows.size())

## エイリアス表（1行=1別名: type_id, side, name）→ スキン表 skins.json。
## 同じ (type_id, side) の行は出現順にエイリアス配列へ。description/images は空（後で拡張）。
func _convert_aliases() -> void:
	var rows := _read_csv("res://data/units/aliases.csv")
	var skins := {}
	for r in rows:
		var tid := String(r["type_id"])
		var side := String(r["side"])
		if not skins.has(tid):
			skins[tid] = { "ally": [], "enemy": [] }
		skins[tid][side].append({ "name": String(r["name"]), "description": "", "images": {} })
	_write_json("res://data/units/skins.json", { "skins": skins })
	print("skins.json: %d types" % skins.size())

## CSV(2行ヘッダ)を読み、1行目キーの辞書配列を返す。2行目(日本語ラベル)は読み飛ばす。
## 値は型推論（int/bool/string）。
func _read_csv(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CSV を開けない: %s" % path)
		return []
	var headers := f.get_csv_line()
	f.get_csv_line()  # 2行目=日本語ラベル(人間用)。コードは使わないので読み飛ばす
	var rows := []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < headers.size() or _is_blank(line):
			continue  # 不足行・全カラ行はスキップ
		var row := {}
		for i in headers.size():
			row[headers[i]] = _typed(line[i])
		rows.append(row)
	f.close()
	return rows

## 全カラムが空白の行か（末尾の空行・カンマだけの行を弾く）。
func _is_blank(line: PackedStringArray) -> bool:
	for c in line:
		if c.strip_edges() != "":
			return false
	return true

## 文字列を int / bool / string に推論。
func _typed(s: String) -> Variant:
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_int():
		return int(s)
	return s

func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("JSON を書けない: %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t") + "\n")
	f.close()
	print("  wrote %s" % path)
