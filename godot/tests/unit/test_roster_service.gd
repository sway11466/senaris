extends GutTest
## 名簿（パーティ）の更新規則。仕様 → doc/gdd/map.md（名簿）
## 兵力ゼロ＝離脱で在籍は続く／未加入は載らない／捕虜でも加入、を固定する。

func _catalog() -> Dictionary:
	return {
		"elf": UnitType.from_dict({ "id": "elf", "atk_ground": 6, "defense": 5, "move": 5, "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 8 }),
		"cleric": UnitType.from_dict({ "id": "cleric", "atk_ground": 4, "defense": 4, "move": 4, "max_troops": 8, "can_capture": true }),
		"recruit": UnitType.from_dict({ "id": "recruit", "atk_ground": 5, "defense": 5, "move": 3, "max_troops": 8 }),
	}

func _actors(roster: Array) -> Array:
	var out: Array = []
	for e in roster:
		out.append(String((e as Dictionary).get("actor", "")))
	return out

func _entry(roster: Array, actor: String) -> Dictionary:
	for e in roster:
		if String((e as Dictionary).get("actor", "")) == actor:
			return e
	return {}

func test_named_member_lost_stays_enrolled_with_zero_troops() -> void:
	# 名前つきの仲間は撃破されても名簿に残る（troops 0＝戦線離脱）。
	var previous: Array = [
		{ "type": "knight", "skin": "knight", "level": 3, "troops": 6, "max_troops": 8, "actor": "t3.van" },
		{ "type": "elf", "skin": "elf", "level": 1, "troops": 8, "max_troops": 8, "actor": "t3.elf" },
	]
	# 2人とも出撃した盤で、エルフだけを失って決着した。
	var s := StageLoader.build({ "cols": 8, "rows": 4, "player": [
		{ "type": "knight", "col": 1, "row": 1, "actor": "t3.van", "supply": "join", "troops": 2, "level": 3 },
		{ "type": "elf", "col": 2, "row": 1, "actor": "t3.elf", "supply": "join" },
	] }, _catalog())
	assert_true(s.remove_unit(s.unit_at(Hex.offset_to_axial(2, 1)).id), "エルフを失う")
	var updated := RosterService.update_after_clear(previous, s)
	assert_eq(_actors(updated), ["t3.van", "t3.elf"], "名簿の並び順を保つ")
	assert_eq(int(_entry(updated, "t3.van")["troops"]), 2, "生存者は現在値で更新")
	assert_eq(int(_entry(updated, "t3.elf")["troops"]), 0, "失った仲間は troops 0 で在籍")
	assert_eq(int(_entry(updated, "t3.elf")["level"]), 1, "離脱者の素性は前の名簿のまま")

func test_member_not_sortied_is_left_untouched() -> void:
	# 出番の無かった在籍者は名簿を書き換えない（別の隊として待機している＝失ってはいない）。
	# これが無いと、隊を分けて戦う冒険譚で待機中の隊が全滅扱いになる。詳細 → doc/gdd/map.md 名簿の更新
	var previous: Array = [
		{ "type": "knight", "skin": "knight", "level": 3, "troops": 6, "max_troops": 8, "actor": "t3.van" },
		{ "type": "elf", "skin": "elf", "level": 2, "troops": 5, "max_troops": 8, "actor": "t3.elf" },
	]
	# この盤に出したのはヴァンガードだけ（エルフは配置していない）。
	var s := StageLoader.build({ "cols": 8, "rows": 4, "player": [
		{ "type": "knight", "col": 1, "row": 1, "actor": "t3.van", "supply": "join", "troops": 2, "level": 3 },
	] }, _catalog())
	var updated := RosterService.update_after_clear(previous, s)
	assert_eq(_actors(updated), ["t3.van", "t3.elf"], "名簿の並び順を保つ")
	assert_eq(int(_entry(updated, "t3.van")["troops"]), 2, "出た者は現在値で更新")
	assert_eq(int(_entry(updated, "t3.elf")["troops"]), 5, "出番の無かった者は据え置き")
	assert_eq(int(_entry(updated, "t3.elf")["level"]), 2, "素性も前の名簿のまま")

func test_garrison_member_counts_as_sortied() -> void:
	# 拠点の控えに居るだけで出撃しなかった者も「この盤に出た」＝更新対象。
	# 盤から消えていれば離脱として数える（控えごと拠点を失った場合）。
	var s := StageLoader.build({ "cols": 8, "rows": 4,
		"player": [{ "type": "knight", "col": 1, "row": 1, "actor": "t3.van", "supply": "join" }],
		"bases": [{ "col": 4, "row": 1, "team": "player",
			"garrison": [{ "type": "elf", "actor": "t3.elf" }] }] }, _catalog())
	assert_true(s.has_sortied("t3.elf"), "控えも投入済みとして数える")

func test_anonymous_units_are_not_enrolled() -> void:
	# 名前のない雑兵は同一性を持たない＝名簿に載らない（持ち越さず各ステージが配給する）。
	var s := StageLoader.build({ "cols": 8, "rows": 4, "player": [
		{ "type": "recruit", "col": 1, "row": 1 },
		{ "type": "knight", "col": 2, "row": 1, "actor": "t3.van", "supply": "join" },
	] }, _catalog())
	var updated := RosterService.update_after_clear([], s)
	assert_eq(_actors(updated), ["t3.van"], "actor のある仲間だけが載る")

func test_unreleased_neutral_is_not_enrolled() -> void:
	# 中立のまま取り逃した駒は帰属が自軍にならない＝名簿に載らない。
	var s := StageLoader.build({ "cols": 8, "rows": 4,
		"player": [{ "type": "knight", "col": 1, "row": 1, "actor": "t3.van", "supply": "join" }],
		"bases": [{ "col": 4, "row": 1, "team": "neutral",
			"garrison": [{ "type": "elf", "actor": "t3.elf" }] }] }, _catalog())
	var updated := RosterService.update_after_clear([], s)
	assert_eq(_actors(updated), ["t3.van"], "解放していないエルフは加入しない")

func test_enemy_released_neutral_is_not_enrolled() -> void:
	# 敵が先に解放した駒は帰属が敵で確定＝自軍の名簿には載らない。
	var s := StageLoader.build({ "cols": 8, "rows": 4,
		"player": [{ "type": "knight", "col": 1, "row": 1, "actor": "t3.van", "supply": "join" }],
		"bases": [{ "col": 4, "row": 1, "team": "neutral",
			"garrison": [{ "type": "elf", "actor": "t3.elf" }] }] }, _catalog())
	var base_hex := Hex.offset_to_axial(4, 1)
	s.base_at(base_hex).team = 1
	s.current_team = 1
	assert_true(s.deploy(base_hex, 0, Hex.offset_to_axial(4, 0)), "敵が解放")
	var updated := RosterService.update_after_clear([], s)
	assert_eq(_actors(updated), ["t3.van"], "敵に取られたエルフは加入しない")

func test_captive_after_release_is_still_enrolled() -> void:
	# 味方が解放した後で拠点ごと奪われ、捕虜のままクリアしても加入する（帰属は動かない）。
	var s := StageLoader.build({ "cols": 8, "rows": 4,
		"player": [{ "type": "cleric", "col": 3, "row": 1 }],
		"bases": [{ "col": 4, "row": 1, "team": "neutral",
			"garrison": [{ "type": "elf", "actor": "t3.elf" }] }] }, _catalog())
	var base_hex := Hex.offset_to_axial(4, 1)
	s.move_unit(1, base_hex)  # 占領
	assert_true(s.deploy(base_hex, 0, Hex.offset_to_axial(4, 0)), "味方が解放")
	var elf := s.unit_at(Hex.offset_to_axial(4, 0))
	# エルフを拠点へ戻し（駐留）、そのまま敵に奪わせる。
	s.end_turn(); s.end_turn()
	s.move_unit(1, Hex.offset_to_axial(3, 1))  # 占領兵が退く
	s.end_turn(); s.end_turn()
	s.move_unit(elf.id, base_hex)
	assert_true(s.enter_base(elf.id), "拠点に駐留")
	s.base_at(base_hex).team = 1  # 敵が奪う＝捕虜
	var updated := RosterService.update_after_clear([], s)
	assert_true("t3.elf" in _actors(updated), "捕虜でも加入している")

func test_passengers_are_collected() -> void:
	# 輸送に乗ったまま決着した駒も名簿に載る（盤上リストには居ないため取りこぼしやすい）。
	var cat := _catalog()
	cat["wagon"] = UnitType.from_dict({ "id": "wagon", "atk_ground": 0, "defense": 4, "move": 5, "max_troops": 8, "capacity": 4 })
	var s := StageLoader.build({ "cols": 8, "rows": 4, "player": [
		{ "type": "wagon", "col": 1, "row": 1, "passengers": [{ "type": "elf", "actor": "t3.elf" }] },
	] }, cat)
	var updated := RosterService.update_after_clear([], s)
	assert_true("t3.elf" in _actors(updated), "搭乗中の仲間も名簿に載る")
