class_name DialogueCsvStore
## dialogue.csv（i18n 正本・keys,ja,en）の読み書き（マップエディタ用）。
## 行単位で扱い、対象キーの行だけ置換／挿入する＝他の行・並び・引用符の書き方には触らない。
## 挿入位置は同じステージ接頭辞（キーの先頭2セグメント）のブロック末尾＝手書きの「ステージごとの並び」を保つ。

const PATH := "res://data/i18n/dialogue.csv"

## 全行を key -> { "ja", "en" } で読む。ファイルが無ければ空。
static func load_map() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var out := {}
	f.get_csv_line()  # ヘッダ（keys,ja,en）
	while not f.eof_reached():
		var cols := f.get_csv_line()
		if cols.size() >= 3 and cols[0] != "":
			out[cols[0]] = { "ja": cols[1], "en": cols[2] }
	f.close()
	return out

## キーの行を置換／挿入したテキストを返す（純関数＝テスト対象）。
static func upsert(text: String, key: String, ja: String, en: String) -> String:
	var line := "%s,%s,%s" % [key, _field(ja), _field(en)]
	var lines := text.split("\n")
	var prefix := _stage_prefix(key)
	var insert_at := -1
	for i in lines.size():
		var k := _key_of(lines[i])
		if k == key:
			lines[i] = line
			return "\n".join(lines)
		if prefix != "" and k.begins_with(prefix):
			insert_at = i + 1
	if insert_at == -1:
		insert_at = lines.size()  # 同じブロックが無い＝末尾（終端の空行の手前）へ
		while insert_at > 0 and lines[insert_at - 1].strip_edges() == "":
			insert_at -= 1
	lines.insert(insert_at, line)
	return "\n".join(lines)

## ファイルへ upsert を適用する。成功で true。
static func upsert_file(key: String, ja: String, en: String) -> bool:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var w := FileAccess.open(PATH, FileAccess.WRITE)
	if w == null:
		return false
	w.store_string(upsert(text, key, ja, en))
	w.close()
	return true

## キーの先頭2セグメント（"t2.st7." 等）。3セグメント未満は ""＝ブロックを持たない。
static func _stage_prefix(key: String) -> String:
	var parts := key.split(".")
	return "" if parts.size() < 3 else parts[0] + "." + parts[1] + "."

## 行のキー（先頭フィールド）。キーは英数字とドットだけ＝引用符付きにはならない前提。
static func _key_of(line: String) -> String:
	var comma := line.find(",")
	return "" if comma <= 0 else line.substr(0, comma)

## CSV の1フィールド。カンマ・引用符・改行を含む値は引用符で包む（中の引用符は二重化）。
static func _field(v: String) -> String:
	if v.find(",") == -1 and v.find("\"") == -1 and v.find("\n") == -1:
		return v
	return "\"%s\"" % v.replace("\"", "\"\"")
