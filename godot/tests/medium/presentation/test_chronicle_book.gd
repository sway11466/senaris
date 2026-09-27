extends GutTest
## presentation/chronicle/chronicle_book.gd のテスト。仕様 → doc/gdd/chronicle.md 本文の持ち方
## 物語の本文は書き手がページを区切る＝全言語で1ページ（挿絵を引いた残り）に収まっているかを見る。
## 文字の折り返しはフォントで決まるので、実物のページを組んで SceneTree に載せて測る。

const CHRONICLE_DIR := "res://data/chronicle"
const CSV_PATH := "res://data/i18n/chronicle.csv"
const LOCALES := ["ja", "en"]

var _locale_before := ""

func before_all() -> void:
	_locale_before = TranslationServer.get_locale()

func after_all() -> void:
	TranslationServer.set_locale(_locale_before)

func _campaign_ids() -> Array:
	var ids: Array = []
	for f in DirAccess.get_files_at(CHRONICLE_DIR):
		if f.ends_with(".json"):
			ids.append(f.get_basename())
	return ids

## ページを組んで載せ、本文の高さ（折り返した後）を返す。本文が無ければ 0。
func _body_height(campaign_id: String, page: int) -> float:
	var node := ChronicleBook.build_page(campaign_id, page)
	add_child_autofree(node)
	await get_tree().process_frame
	for c in node.find_children("*", "Label", true, false):
		if c.has_meta("book_body"):
			return (c as Label).get_minimum_size().y
	return 0.0

func _image_of(campaign_id: String, page: int) -> Texture2D:
	var path := ChronicleBook.image_path(campaign_id, page)
	return null if path.is_empty() else load(path) as Texture2D

func test_every_page_fits_in_each_locale() -> void:
	var checked := 0
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for cid in _campaign_ids():
			var id := String(cid)
			for p in range(1, ChronicleBook.page_count(id) + 1):
				var h := await _body_height(id, p)
				var limit := ChronicleBook.body_height_limit(_image_of(id, p))
				assert_true(h <= limit, "%s p%d (%s) が1ページに収まる: %.0f / %.0f" % [id, p, locale, h, limit])
				checked += 1
	gut.p("見たページ: %d" % checked)
	pass_test("全ページを見た")

## 測り方が効いているか＝ページの場所より長い本文は収まらないと判定される。
func test_overlong_text_is_detected() -> void:
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(ChronicleBook.TEXT_WIDTH, 0)
	body.add_theme_font_size_override("font_size", ChronicleBook.FONT_SIZE)
	body.text = "あ".repeat(2000)
	add_child_autofree(body)
	await get_tree().process_frame
	assert_gt(body.get_minimum_size().y, ChronicleBook.TEXT_HEIGHT, "長すぎる本文ははみ出す")

## ページは連番＝本文も挿絵も無いページの先に続きのキーがあると読めない（書き漏れ）。
func test_book_keys_are_reachable() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert_not_null(f, "chronicle.csv が開ける")
	if f == null:
		return
	while not f.eof_reached():
		var row := f.get_csv_line()
		var key := String(row[0]).trim_prefix("﻿")
		if not key.begins_with("book."):
			continue
		var parts := key.split(".")
		assert_eq(parts.size(), 3, "%s は book.<冒険譚>.<ページ>" % key)
		if parts.size() != 3:
			continue
		assert_true(parts[1] in _campaign_ids(), "%s の冒険譚にマニフェストがある" % key)
		assert_true(int(parts[2]) <= ChronicleBook.page_count(parts[1]), "%s が連番の中にある" % key)
