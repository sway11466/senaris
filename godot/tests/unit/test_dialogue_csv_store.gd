extends GutTest
## DialogueCsvStore（マップエディタからの dialogue.csv 読み書き）のテスト。
## upsert はテキスト入出力の純関数＝ファイルを使わずに置換・挿入位置・引用符を固定する。

const HEAD := "keys,ja,en"

func _text(rows: Array) -> String:
	return HEAD + "\n" + "\n".join(PackedStringArray(rows)) + ("\n" if not rows.is_empty() else "")

func test_upsert_replaces_existing_line() -> void:
	var t := _text(["undead-rush.st7.arrive.label,旧,old", "undead-rush.st7.arrive.1,こんにちは,hello"])
	var out := DialogueCsvStore.upsert(t, "undead-rush.st7.arrive.label", "新しい文", "new text")
	assert_string_contains(out, "undead-rush.st7.arrive.label,新しい文,new text")
	assert_false(out.contains("旧"), "旧行は置換されて消える")
	assert_string_contains(out, "undead-rush.st7.arrive.1,こんにちは,hello")

func test_upsert_inserts_after_same_stage_block() -> void:
	var t := _text(["undead-rush.st7.intro.1,a,b", "undead-rush.st7.intro.2,c,d", "dragon-hunt.st1.intro.1,e,f"])
	var out := DialogueCsvStore.upsert(t, "undead-rush.st7.event.label", "や", "en")
	var lines := out.split("\n")
	assert_eq(lines[3], "undead-rush.st7.event.label,や,en", "同じステージ（undead-rush.st7.）ブロックの末尾に入る")
	assert_eq(lines[4], "dragon-hunt.st1.intro.1,e,f", "他ステージの行は後ろへずれるだけ")

func test_upsert_appends_at_end_without_block() -> void:
	var t := _text(["undead-rush.st7.intro.1,a,b"])
	var out := DialogueCsvStore.upsert(t, "c9.st1.x.label", "j", "e")
	var lines := out.split("\n")
	assert_eq(lines[2], "c9.st1.x.label,j,e", "該当ブロックが無ければ末尾へ")
	assert_eq(lines[3], "", "終端の空行（改行終わり）は保たれる")

func test_upsert_quotes_comma_and_quote() -> void:
	var t := _text(["undead-rush.st7.intro.1,a,b"])
	var out := DialogueCsvStore.upsert(t, "undead-rush.st7.x.label", "や,あ", "he said \"hi\"")
	assert_string_contains(out, "undead-rush.st7.x.label,\"や,あ\",\"he said \"\"hi\"\"\"")

func test_upsert_keeps_other_lines_untouched() -> void:
	var quoted := "undead-rush.st7.note.1,\"引用,あり\",\"with, comma\""
	var t := _text([quoted, "undead-rush.st7.intro.1,a,b"])
	var out := DialogueCsvStore.upsert(t, "undead-rush.st7.intro.1", "A", "B")
	assert_string_contains(out, quoted)
