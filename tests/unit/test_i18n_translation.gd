extends GutTest
## dialogue.csv（i18n 正本）と、そこから Godot が生成する .translation の整合を固定する。
## 目的: csv を編集したのに .translation を再インポート＆コミットし忘れる「翻訳コミット漏れ」を検知する。
##   csv の全 key について、各言語の .translation が期待テキストを返すことを確認する。
## 限界: get_message ベースの内容照合なので「csv に無い古いエントリが .translation に残っている」
##   （＝再生成漏れで肥大した stale）は検知できない。byte 完全一致まで固めたい場合は
##   `godot --headless --import` 後の `git diff --exit-code -- data/i18n/*.translation` を併用する。

## i18n 正本（CSV）と、そこから生成する .translation の対応。CSV を増やしたらここに足す。
const SOURCES := [
	{ "csv": "res://data/i18n/dialogue.csv", "tr": {
		"ja": "res://data/i18n/dialogue.ja.translation",
		"en": "res://data/i18n/dialogue.en.translation",
	} },
	{ "csv": "res://data/i18n/campaigns.csv", "tr": {
		"ja": "res://data/i18n/campaigns.ja.translation",
		"en": "res://data/i18n/campaigns.en.translation",
	} },
]

## CSV を [{ "keys": ..., "ja": ..., "en": ... }, ...] に読む。
## 前提: 1メッセージ＝1行（フィールド内の改行・\n エスケープは使っていない）。
func _read_csv_rows(csv_path: String) -> Array:
	var f := FileAccess.open(csv_path, FileAccess.READ)
	assert_not_null(f, "CSV を開けること: %s" % csv_path)
	if f == null:
		return []
	var header := f.get_csv_line()  # ["keys", "ja", "en"]
	var rows: Array = []
	while not f.eof_reached():
		var cols := f.get_csv_line()
		if cols.size() == 1 and cols[0] == "":
			continue  # 末尾の空行
		assert_eq(cols.size(), header.size(), "列数がヘッダと一致すること（行: %s）" % str(cols))
		if cols.size() != header.size():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = cols[i]
		rows.append(row)
	f.close()
	return rows

func test_csv_has_rows() -> void:
	for src in SOURCES:
		assert_gt(_read_csv_rows(src["csv"]).size(), 0, "%s に少なくとも1行あること" % src["csv"])

func test_translations_load() -> void:
	for src in SOURCES:
		for lang in src["tr"]:
			var tr: Translation = load(src["tr"][lang])
			assert_not_null(tr, "%s の .translation を読めること: %s" % [lang, src["tr"][lang]])

## 正本の全 key が、各言語の .translation で期待テキストに解決すること。
## key が欠けていれば get_message は key をそのまま返す（＝期待値と不一致）ので、
## 再生成漏れ・キー欠落・訳文の食い違いをまとめて検知できる。
func test_every_csv_key_resolves_in_each_translation() -> void:
	for src in SOURCES:
		var rows := _read_csv_rows(src["csv"])
		for lang in src["tr"]:
			var tr: Translation = load(src["tr"][lang])
			assert_not_null(tr, "%s の .translation を読めること" % lang)
			if tr == null:
				continue
			for row in rows:
				var key: String = row["keys"]
				var expected: String = row[lang]
				var got := String(tr.get_message(key))
				assert_eq(got, expected, "[%s] %s の訳文が csv と一致すること" % [lang, key])
