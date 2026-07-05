extends RefCounted
## CSV(2行ヘッダ) → 辞書配列 の共通読み取り＋JSON書き出し。CSV→JSON変換ツールが使う。
## class_name は付けない（変換ツールは preload で参照）。
## 1行目=英語キー, 2行目=日本語ラベル(読み飛ばす), 3行目以降=データ。値は int/bool/string 推論。
## 検証の基本方針は doc/tech/architecture.md「CSV→データ生成のバリデーション」を参照。

## CSV(2行ヘッダ)を読み、1行目キーの辞書配列を返す。空行はスキップ、列不足行は警告してスキップ。
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
		if _is_blank(line):
			continue  # 空行（末尾改行・区切りのスペーサ行）は黙って飛ばす
		if line.size() < headers.size():
			# 内容のある行が列不足＝データ欠損のバグ。黙って消さず知らせる（旧実装は無言スキップだった）。
			push_error("CSV %s: 列不足の行をスキップ（%d/%d列）: %s" % [path, line.size(), headers.size(), ", ".join(line)])
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

## 必須列がすべて非空か検証し、違反メッセージの配列を返す（空＝全部OK）。純関数＝副作用なし・テスト容易。
## push_error は呼び出し側（生成ツール）が行い、>0 件なら JSON を書かず中止すること（壊れた生成物を残さない）。
## 数値セル(int/float/bool)は非空扱い。空判定は文字列セルにだけ効かせる（"-" 等の明示値は非空）。
## label_key を渡すと、メッセージの行識別にその列値を使う（未指定は行番号）。
static func missing_required(rows: Array, required: Array, label_key: String = "") -> Array:
	var problems: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var who := str(r.get(label_key, i)) if label_key != "" else str(i)
		for col in required:
			var v: Variant = r.get(col)
			if v == null or (typeof(v) == TYPE_STRING and v.strip_edges().is_empty()):
				problems.append("行[%s] の必須列 '%s' が空/欠落" % [who, col])
	return problems

## key 列の値が重複している行を検出し、重複値の配列を返す（各重複値は1回だけ・空セルは無視）。純関数。
## id / char / skin_id など「一意であるべき列」の後勝ち上書きを事前に炙り出す。
static func duplicates(rows: Array, key: String) -> Array:
	var seen := {}
	var dups := {}
	for r in rows:
		var v := str(r.get(key, "")).strip_edges()
		if v.is_empty():
			continue
		if seen.has(v):
			dups[v] = true
		seen[v] = true
	return dups.keys()

## col 列の値が allowed（許容集合）に無い行を、問題メッセージ配列で返す。純関数。
## 空セルは missing_required の担当なので無視する。enum（side 等）にも参照整合（type_id→id 集合）にも使える。
static func invalid_values(rows: Array, col: String, allowed: Array, label_key: String = "") -> Array:
	var ok := {}
	for a in allowed:
		ok[str(a)] = true
	var problems: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var v := str(r.get(col, "")).strip_edges()
		if v.is_empty():
			continue
		if not ok.has(v):
			var who := str(r.get(label_key, i)) if label_key != "" else str(i)
			problems.append("行[%s] の '%s' が不正値/未定義参照 '%s'" % [who, col, v])
	return problems

## rows から key 列の値集合を作る（参照整合の「許容集合」を作るのに使う）。
static func value_set(rows: Array, key: String) -> Array:
	var out := {}
	for r in rows:
		var v := str(r.get(key, "")).strip_edges()
		if not v.is_empty():
			out[v] = true
	return out.keys()

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
