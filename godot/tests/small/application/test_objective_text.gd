extends GutTest
## ObjectiveText（勝敗条件を人の読む文に組む）のテスト。仕様 → doc/gdd/uiux.md ターン終了・システムメニュー
##
## 訳文は実行時の言語で変わるので、文字そのものは照合しない。「何行出るか」「どの順に出るか」
## 「名指した駒の名前が入っているか」を見る＝条件を足したときに紙から漏れれば落ちる。

func _state(data: Dictionary) -> BattleState:
	var base := { "cols": 8, "rows": 6, "turn_limit": 0 }
	for k in data:
		base[k] = data[k]
	return StageLoader.build(base)

func _lines(state: BattleState, key: String) -> PackedStringArray:
	return ObjectiveText.build(state, {}).get(key, PackedStringArray())

func test_wipe_and_total_loss_are_always_listed() -> void:
	# 条件を1つも書いていないステージでも、常に効く殲滅・全滅は出る。
	var s := _state({ "player": [ { "units": [{ "col": 1, "row": 1 }] } ] })
	assert_eq(_lines(s, "victory").size(), 1, "勝利＝殲滅の1行")
	assert_eq(_lines(s, "defeat").size(), 1, "敗北＝全滅の1行（turn_limit なし・本拠地なし）")

func test_turn_limit_is_listed_with_the_number() -> void:
	var s := _state({ "turn_limit": 30, "player": [ { "units": [{ "col": 1, "row": 1 }] } ] })
	var defeat := _lines(s, "defeat")
	assert_eq(defeat.size(), 2, "全滅＋ターン制限")
	assert_true(defeat[1].contains("30"), "ターン制限の行に上限の数が入る: %s" % defeat[1])

func test_own_hq_is_listed_even_without_a_defeat_condition() -> void:
	# 自軍本拠地の喪失は条件リストに書かれない常時のルール（Victory._own_hq_lost）。
	var s := _state({
		"player": [ { "units": [{ "col": 1, "row": 1 }] } ],
		"bases": [ { "col": 2, "row": 2, "team": "player", "hq": "player" } ],
	})
	assert_eq(_lines(s, "defeat").size(), 2, "本拠地の喪失＋全滅")

func test_stage_conditions_come_first() -> void:
	var s := _state({
		"player": [ { "units": [{ "col": 1, "row": 1 }] } ],
		"enemy": [ { "units": [{ "col": 5, "row": 5, "unit_id": "boss" }] } ],
		"victory": [ { "type": "defeat_unit", "unit_ids": ["boss"] } ],
	})
	var victory := _lines(s, "victory")
	assert_eq(victory.size(), 2, "ボス撃破＋殲滅")
	assert_ne(victory[0], victory[1], "同じ文が2行並ばない")
	assert_eq(victory[1], _lines(_state({ "player": [ { "units": [{ "col": 1, "row": 1 }] } ] }), "victory")[0],
		"後ろの行が常時の殲滅＝ステージの条件が先にくる")

func test_named_unit_appears_in_the_line() -> void:
	# 名指した駒は表示名で出す（スキン表が空なら type_id）。
	var s := _state({
		"player": [ { "units": [{ "col": 1, "row": 1 }] } ],
		"enemy": [ { "units": [{ "type": "dragon", "col": 5, "row": 5, "unit_id": "boss" }] } ],
		"victory": [ { "type": "defeat_unit", "unit_ids": ["boss"] } ],
	})
	assert_true(_lines(s, "victory")[0].contains("dragon"), "名指した駒の名前が文に入る")

func test_garrison_and_reinforcement_units_can_be_named() -> void:
	# 盤に出ていない駒（拠点の控え・未発生の増援）も名前で指せる＝登場前に開いても文が出る。
	var s := _state({
		"player": [ { "units": [{ "col": 1, "row": 1 }] } ],
		"bases": [ { "col": 2, "row": 2, "team": "enemy",
			"garrison": [{ "type": "wizard", "native": "enemy", "unit_id": "sleeper" }] } ],
		"victory": [ { "type": "defeat_unit", "unit_ids": ["sleeper"] } ],
	})
	assert_true(_lines(s, "victory")[0].contains("wizard"), "控えの駒も名前で出る")

func test_unknown_condition_type_is_not_listed() -> void:
	# 未知のタイプは Victory も不成立として扱う＝紙にも出さない（出すと満たせない条件が並ぶ）。
	var s := _state({
		"player": [ { "units": [{ "col": 1, "row": 1 }] } ],
		"victory": [ { "type": "reach_hex", "col": 3, "row": 3 } ],
	})
	assert_eq(_lines(s, "victory").size(), 1, "殲滅の1行だけ")

func test_multiple_targets_and_multiple_conditions() -> void:
	# 1件の中は AND（2体を1行に並べる）・条件どうしは OR（行が分かれる）。
	var s := _state({
		"player": [ { "units": [{ "col": 1, "row": 1 }] } ],
		"enemy": [ { "units": [
			{ "type": "dragon", "col": 5, "row": 5, "unit_id": "a" },
			{ "type": "wizard", "col": 6, "row": 5, "unit_id": "b" }] } ],
		"victory": [
			{ "type": "defeat_unit", "unit_ids": ["a", "b"] },
			{ "type": "capture_hq" } ],
	})
	var victory := _lines(s, "victory")
	assert_eq(victory.size(), 3, "AND1行＋本拠地占領＋殲滅")
	assert_true(victory[0].contains("dragon") and victory[0].contains("wizard"), "1行に2体が並ぶ: %s" % victory[0])
