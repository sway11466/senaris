extends GutTest
## 会話の分岐（行単位の when）。仕様 → doc/campaign/authoring.md（会話の分岐）
## 出欠は名簿だけを見る＝兵力ゼロの離脱者も喋る／未加入は喋らない。

func _stage() -> Dictionary:
	return { "dialogue": { "intro": [
		{ "speaker": "char.van.name", "skin": "knight", "text": "t3.st5.van.01" },
		{ "speaker": "char.elf.name", "skin": "elf", "text": "t3.st5.elf.01", "when": "joined:t3.elf" },
		{ "speaker": "char.van.name", "skin": "knight", "text": "t3.st5.van.02", "when": "!joined:t3.elf" },
	], "outro": [] } }

func _texts(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		out.append(String((l as Dictionary).get("text", "")))
	return out

func test_no_roster_keeps_only_unconditional_and_negated_lines() -> void:
	var d := StageLoader.parse_dialogue(_stage())
	assert_eq(_texts(d["intro"]), ["t3.st5.van.01", "t3.st5.van.02"], "名簿なし＝未加入として扱う")

func test_joined_actor_shows_their_line() -> void:
	var roster: Array = [{ "type": "elf", "troops": 8, "actor": "t3.elf" }]
	var d := StageLoader.parse_dialogue(_stage(), roster)
	assert_eq(_texts(d["intro"]), ["t3.st5.van.01", "t3.st5.elf.01"], "在籍していれば喋り、否定の行は落ちる")

func test_zero_troops_member_still_speaks() -> void:
	# 兵力ゼロは戦線離脱であって死亡ではない＝会話には出る。
	var roster: Array = [{ "type": "elf", "troops": 0, "actor": "t3.elf" }]
	var d := StageLoader.parse_dialogue(_stage(), roster)
	assert_true("t3.st5.elf.01" in _texts(d["intro"]), "離脱者も会話に出る")

func test_other_actor_does_not_satisfy_condition() -> void:
	var roster: Array = [{ "type": "knight", "troops": 8, "actor": "t3.van" }]
	var d := StageLoader.parse_dialogue(_stage(), roster)
	assert_eq(_texts(d["intro"]), ["t3.st5.van.01", "t3.st5.van.02"], "別人の在籍では条件を満たさない")

func test_unknown_condition_keeps_the_line() -> void:
	# 未知の表記で行が消えると台本が欠ける＝前方互換のため残す（警告つき）。
	var data := { "dialogue": { "intro": [
		{ "speaker": "s", "skin": "k", "text": "keep.me", "when": "cleared:st1" },
	] } }
	var d := StageLoader.parse_dialogue(data)
	assert_eq(_texts(d["intro"]), ["keep.me"], "未知の条件は行を落とさない")

func test_blank_condition_is_always_true() -> void:
	var data := { "dialogue": { "intro": [
		{ "speaker": "s", "skin": "k", "text": "keep.me", "when": "" },
	] } }
	var d := StageLoader.parse_dialogue(data)
	assert_eq(_texts(d["intro"]), ["keep.me"], "空の条件は常に真")
