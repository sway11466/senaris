extends RefCounted
## CSV(2行ヘッダ) → 辞書配列 の共通読み取り＋JSON書き出し。CSV→JSON変換ツールが使う。
## class_name は付けない（変換ツールは preload で参照）。
## 1行目=英語キー, 2行目=日本語ラベル(読み飛ばす), 3行目以降=データ。値は int/bool/string 推論。

## CSV(2行ヘッダ)を読み、1行目キーの辞書配列を返す。全カラ行・不足行はスキップ。
static func read_table(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CSV を開けない: %s" % path)
		return []
	var headers := f.get_csv_line()
	f.get_csv_line()  # 2行目=日本語ラベル(人間用)を読み飛ばす
	var rows := []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < headers.size() or _is_blank(line):
			continue
		var row := {}
		for i in headers.size():
			row[headers[i]] = typed(line[i])
		rows.append(row)
	f.close()
	return rows

static func _is_blank(line: PackedStringArray) -> bool:
	for c in line:
		if c.strip_edges() != "":
			return false
	return true

## 文字列を int / float / bool / string に推論（int 優先＝"8"は8、"1.0"は1.0）。
static func typed(s: String) -> Variant:
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)
	return s

static func write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("JSON を書けない: %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t") + "\n")
	f.close()
	print("  wrote %s" % path)
