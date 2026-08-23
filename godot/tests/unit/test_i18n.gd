extends GutTest
## 会話テキストの翻訳（Godot 標準の翻訳CSV → TranslationServer/tr()）が疎通しているか。
## 正本 data/i18n/dialogue.csv（keys, ja, en）→ .translation を project.godot に登録済み。

func test_dialogue_translation_ja() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	assert_eq(TranslationServer.translate("talk.intro.1"), "敵は1体だ。落ち着いて仕留めろ。", "日本語が引ける")
	assert_eq(TranslationServer.translate("char.cap.name"), "隊長", "話者名キーも引ける")
	TranslationServer.set_locale(prev)

func test_dialogue_translation_en() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_eq(TranslationServer.translate("char.cap.name"), "Captain", "英語ロケールで英語が引ける")
	TranslationServer.set_locale(prev)

## UI 文言（ui.csv）が project.godot の locale/translations 経由で引けること。
## .translation の中身は test_i18n_translation.gd が見る。ここが見るのは登録の有無＝
## CSV を新設して project.godot への追記を忘れると、画面にキー文字列がそのまま出る事故を検知する。
func test_ui_translation_registered() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	assert_eq(TranslationServer.translate("ui.title.quit"), "おわる", "日本語ロケールで UI 文言が引ける")
	TranslationServer.set_locale("en")
	assert_eq(TranslationServer.translate("ui.title.quit"), "Quit", "英語ロケールで UI 文言が引ける")
	TranslationServer.set_locale(prev)

func test_missing_key_returns_key() -> void:
	assert_eq(TranslationServer.translate("no.such.key"), "no.such.key", "未定義キーはキーをそのまま返す（i18n未整備でも壊れない）")
