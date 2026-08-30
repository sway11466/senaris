extends GutTest
## ゲーム内マニュアルの構造（ManualToc）と本文（data/i18n/manual.csv）の整合を固定する。
## 仕様 → doc/gdd/manual.md
##
## 構造はコード・本文はCSVと持ち場が分かれているので、片方だけ直すとズレる。
## 章を足したのに文を書き忘れれば画面にキー文字列が出るし、文を消して構造に残せば同じ。
## 両方向（構造→CSV／CSV→構造）を突き合わせて、どちらの取りこぼしも落とす。

const CSV_PATH := "res://data/i18n/manual.csv"

## CSV を [{ "keys": ..., "ja": ..., "en": ... }, ...] に読む。
## 前提: 1メッセージ＝1行（フィールド内の改行は使わない。doc/tech/i18n.md UI 文言）。
func _rows() -> Array:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert_not_null(f, "CSV を開けること: %s" % CSV_PATH)
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

func _csv_keys() -> Array:
	var keys: Array = []
	for row in _rows():
		keys.append(String(row["keys"]))
	return keys

func test_structure_has_chapters() -> void:
	assert_gt(ManualToc.CHAPTERS.size(), 0, "章が1つ以上あること")

## 章idと節idは重複しない。重なると同じ翻訳キーを2箇所が指す。
func test_ids_are_unique() -> void:
	var seen_chapters := {}
	for chapter in ManualToc.CHAPTERS:
		var chapter_id := String(chapter["id"])
		assert_false(seen_chapters.has(chapter_id), "章idが重複しないこと: %s" % chapter_id)
		seen_chapters[chapter_id] = true
		var seen_sections := {}
		for section in chapter["sections"]:
			var section_id := String(section["id"])
			assert_false(seen_sections.has(section_id), "節idが章の中で重複しないこと: %s.%s" % [chapter_id, section_id])
			seen_sections[section_id] = true

## 章は必ず節を1つ以上持つ。0だと目次から開いても本文が無い。
func test_every_chapter_has_a_section() -> void:
	for chapter in ManualToc.CHAPTERS:
		assert_gt(chapter["sections"].size(), 0, "%s に節があること" % String(chapter["id"]))

## 構造が参照するキーが CSV に揃っていること（書き忘れ＝画面にキー文字列が出る）。
func test_every_structure_key_exists_in_csv() -> void:
	var have := {}
	for key in _csv_keys():
		have[key] = true
	for key in ManualToc.all_keys():
		assert_true(have.has(key), "構造が参照するキーが manual.csv にあること: %s" % key)

## CSV 側に、構造から参照されないキーが残っていないこと（節を消したときの取り残し）。
func test_no_orphan_keys_in_csv() -> void:
	var used := {}
	for key in ManualToc.all_keys():
		used[key] = true
	for key in _csv_keys():
		assert_true(used.has(key), "manual.csv のキーが構造から参照されていること: %s" % key)

func test_no_duplicate_keys_in_csv() -> void:
	var seen := {}
	for key in _csv_keys():
		assert_false(seen.has(key), "manual.csv のキーが重複しないこと: %s" % key)
		seen[key] = true

## ja/en とも空欄でないこと。空だと訳が抜けたまま出荷される。
func test_both_languages_are_filled() -> void:
	for row in _rows():
		var key := String(row["keys"])
		assert_false(String(row["ja"]).strip_edges().is_empty(), "ja が埋まっていること: %s" % key)
		assert_false(String(row["en"]).strip_edges().is_empty(), "en が埋まっていること: %s" % key)

## 画面の枠（見出し・戻る・章の一覧へ戻る行）は ui.csv 側にある。
func test_screen_chrome_keys_resolve() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	for key in ["ui.manual.title", "ui.manual.back", "ui.manual.chapters"]:
		assert_ne(TranslationServer.translate(key), key, "画面の文言が引けること: %s" % key)
	TranslationServer.set_locale(prev)

## 本文が翻訳として登録されていること（project.godot への追記忘れを検知する）。
func test_manual_translation_registered() -> void:
	var prev := TranslationServer.get_locale()
	for locale in ["ja", "en"]:
		TranslationServer.set_locale(locale)
		var key := ManualToc.chapter_title_key("ai")
		assert_ne(TranslationServer.translate(key), key, "[%s] 本文が引けること: %s" % [locale, key])
	TranslationServer.set_locale(prev)
