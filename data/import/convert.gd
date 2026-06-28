extends SceneTree
## CSV正本 → コード用JSON の変換ツール（headless で実行）。
## 正本 data/import/*.csv（人間が表計算で編集）→ 生成物 data/units/*.json（コードが読む）。
## 生成JSONは手で触らない。CSVを直し、これを再実行する。
##
## 実行: godot --headless --script res://data/import/convert.gd

func _initialize() -> void:
	_convert_unit_type()
	_convert_aliases()
	# 今後: _convert_movement() を足す
	quit()

func _convert_unit_type() -> void:
	var rows := _read_csv("res://data/import/unit_type.csv")
	_write_json("res://data/units/unit_type.json", { "types": rows })
	print("unit_type.json: %d types" % rows.size())

## エイリアス表（1行=1別名: type_id, side, name）→ スキン表 skins.json。
## 同じ (type_id, side) の行は出現順にエイリアス配列へ。description/images は空（後で拡張）。
func _convert_aliases() -> void:
	var rows := _read_csv("res://data/import/aliases.csv")
	var skins := {}
	for r in rows:
		var tid := String(r["type_id"])
		var side := String(r["side"])
		if not skins.has(tid):
			skins[tid] = { "ally": [], "enemy": [] }
		skins[tid][side].append({ "name": String(r["name"]), "description": "", "images": {} })
	_write_json("res://data/units/skins.json", { "skins": skins })
	print("skins.json: %d types" % skins.size())

## CSV を読み、ヘッダをキーにした辞書の配列を返す。値は型推論（int/bool/string）。
func _read_csv(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CSV を開けない: %s" % path)
		return []
	var headers := f.get_csv_line()
	var rows := []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < headers.size() or (line.size() == 1 and line[0] == ""):
			continue  # 空行・不足行はスキップ
		var row := {}
		for i in headers.size():
			row[headers[i]] = _typed(line[i])
		rows.append(row)
	f.close()
	return rows

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
