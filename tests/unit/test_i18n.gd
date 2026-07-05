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

func test_missing_key_returns_key() -> void:
	assert_eq(TranslationServer.translate("no.such.key"), "no.such.key", "未定義キーはキーをそのまま返す（i18n未整備でも壊れない）")
