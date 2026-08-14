extends GutTest
## player の駒と名簿の突き合わせ（actor なし＝配給／actor だけ＝名簿から／supply＝join・refill・revive）。
## 仕様 → doc/gdd/map.md（配置）

func _catalog() -> Dictionary:
	return {
		"elf": UnitType.from_dict({ "id": "elf", "atk_ground": 6, "defense": 5, "move": 5, "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 6 }),
		"recruit": UnitType.from_dict({ "id": "recruit", "atk_ground": 5, "defense": 5, "move": 3, "max_troops": 8 }),
	}

func _member(type_id: String, actor: String, troops: int = 8) -> Dictionary:
	return { "type": type_id, "skin": type_id, "level": 1, "troops": troops, "max_troops": 8, "actor": actor }

func _at(s: BattleState, col: int, row: int) -> Unit:
	return s.unit_at(Hex.offset_to_axial(col, row))

func test_actor_only_piece_comes_from_the_roster() -> void:
	var carried: Array = [_member("elf", "t3.elf", 5)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.elf" },
	] }, _catalog(), {}, carried)
	var u := _at(s, 1, 1)
	assert_eq(u.actor, "t3.elf", "名簿の仲間がその位置に出る")
	assert_eq(u.troops, 5, "損耗を持ち越す")
	assert_eq(u.unit_attack, 6, "性能は type から再構築")

func test_actor_missing_from_roster_is_not_deployed() -> void:
	# 勧誘し損ねた仲間・まだ登場していない仲間は湧かない＝その位置は空のまま。
	var carried: Array = [_member("knight", "t3.van")]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.elf" },
		{ "col": 2, "row": 1, "actor": "t3.van" },
	] }, _catalog(), {}, carried)
	assert_null(_at(s, 1, 1), "未加入の駒は出ない")
	assert_eq(_at(s, 2, 1).actor, "t3.van", "在籍している仲間は自分の位置に出る")
	assert_eq(s.units().size(), 1)

func test_zero_troops_member_is_not_deployed() -> void:
	# 兵力ゼロの離脱者は名簿に在籍するが盤には出ない（会話には出る）。
	var carried: Array = [_member("knight", "t3.van", 0), _member("elf", "t3.elf", 5)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.van" },
		{ "col": 2, "row": 1, "actor": "t3.elf" },
	] }, _catalog(), {}, carried)
	assert_eq(s.units().size(), 1, "出撃するのは兵力の残る1体だけ")
	assert_eq(_at(s, 2, 1).actor, "t3.elf")

func test_join_supplies_a_fresh_unit() -> void:
	# supply:"join"＝名簿への初登場。名簿を見ずに配給する＝満員・Lv1 で出る。
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "recruit", "col": 1, "row": 1, "actor": "t3.new", "supply": "join" },
	] }, _catalog(), {}, [])
	var u := _at(s, 1, 1)
	assert_eq(u.actor, "t3.new", "名簿が空でも配給される")
	assert_eq(u.troops, 8, "満員")
	assert_eq(u.level, 1)

func test_join_ignores_the_roster_snapshot() -> void:
	# 既に名簿へ載っている actor に join を書いたら配給が勝つ（再挑戦で同じ初回を再現する）。
	var carried: Array = [_member("elf", "t3.elf", 2)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "elf", "col": 1, "row": 1, "actor": "t3.elf", "supply": "join" },
	] }, _catalog(), {}, carried)
	assert_eq(_at(s, 1, 1).troops, 8, "名簿の損耗を引き継がない")

func test_refill_tops_up_troops_but_keeps_growth() -> void:
	# supply:"refill"＝幕間の補充。兵数だけ満員へ戻し、Lv（成長）は名簿のまま。
	var member := _member("elf", "t3.elf", 3)
	member["level"] = 4
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.elf", "supply": "refill" },
	] }, _catalog(), {}, [member])
	var u := _at(s, 1, 1)
	assert_eq(u.troops, 8, "兵数は満員へ戻る")
	assert_eq(u.level, 4, "レベルは名簿のまま＝成長は消えない")

func test_refill_uses_the_new_max_when_the_stage_changes_type() -> void:
	# 満員値は駒の max_troops＝ステージ側で type を変えていれば新しい型のもの。
	var carried: Array = [_member("elf", "t3.elf", 3)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "knight", "col": 1, "row": 1, "actor": "t3.elf", "supply": "refill" },
	] }, _catalog(), {}, carried)
	assert_eq(_at(s, 1, 1).troops, 6, "knight の満員値まで")

func test_refill_does_not_recall_a_lost_member() -> void:
	# 兵力ゼロの離脱者は refill では戻らない（戦線離脱は回復手段に届かない）。
	var carried: Array = [_member("knight", "t3.van", 0)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.van", "supply": "refill" },
	] }, _catalog(), {}, carried)
	assert_null(_at(s, 1, 1), "離脱者は盤に出ない")

func test_revive_recalls_a_lost_member_at_full_strength() -> void:
	# supply:"revive"＝離脱した隊が戦線に戻る。在籍者だけが対象。
	var member := _member("knight", "t3.van", 0)
	member["level"] = 3
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.van", "supply": "revive" },
	] }, _catalog(), {}, [member])
	var u := _at(s, 1, 1)
	assert_eq(u.troops, 8, "満員で戻る")
	assert_eq(u.level, 3, "レベルは名簿のまま")

func test_revive_does_not_summon_a_non_member() -> void:
	# 名簿に居ない actor は revive でも湧かない（勧誘し損ねた仲間はそこに出ない）。
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "elf", "col": 1, "row": 1, "actor": "t3.elf", "supply": "revive" },
	] }, _catalog(), {}, [])
	assert_null(_at(s, 1, 1), "未加入の駒は出ない")

func test_unknown_supply_falls_back_to_the_roster() -> void:
	var carried: Array = [_member("elf", "t3.elf", 3)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.elf", "supply": "heal" },
	] }, _catalog(), {}, carried)
	assert_push_warning("未知の supply")
	assert_eq(_at(s, 1, 1).troops, 3, "名簿の損耗のまま出す")

func test_legacy_join_key_warns() -> void:
	# 旧キーを黙って無視すると駒が盤から消えて気づけない＝警告を出す。
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "recruit", "col": 1, "row": 1, "actor": "t3.new", "join": true },
	] }, _catalog(), {}, [])
	assert_push_warning("'join' は廃止")
	assert_null(_at(s, 1, 1), "名簿に居ないので出ない（配給されない）")

func test_anonymous_pieces_are_always_supplied() -> void:
	# actor の無い駒（バリケードのような配給品）は名簿と無関係にそのステージが用意する。
	var carried: Array = [_member("elf", "t3.elf")]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "recruit", "col": 1, "row": 1 },
		{ "col": 2, "row": 1, "actor": "t3.elf" },
	] }, _catalog(), {}, carried)
	assert_eq(s.units().size(), 2, "配給品と継承が共存する")
	assert_eq(_at(s, 1, 1).type_id, "recruit")
	assert_eq(_at(s, 1, 1).actor, "", "名前なし＝名簿の外")

func test_ids_stay_unique_when_pieces_are_skipped() -> void:
	# 出さなかった駒は id を消費しない（採番は盤に乗った駒の順）。
	var carried: Array = [_member("elf", "t3.elf")]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.absent" },
		{ "col": 2, "row": 1, "actor": "t3.elf" },
		{ "type": "recruit", "col": 3, "row": 1 },
	] }, _catalog(), {}, carried)
	var ids := {}
	for u in s.units():
		ids[u.id] = true
	assert_eq(ids.size(), 2, "id が衝突しない")
	assert_eq(_at(s, 2, 1).id, 1, "採番は盤に乗った順に詰まる")

func test_stage_type_wins_over_the_roster() -> void:
	# 性能の出どころはステージJSON（名簿はプレイヤーの手元にあるセーブ）。
	var carried: Array = [_member("elf", "t3.elf", 5)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "knight", "col": 1, "row": 1, "actor": "t3.elf" },
	] }, _catalog(), {}, carried)
	var u := _at(s, 1, 1)
	assert_eq(u.type_id, "knight", "ステージの type が勝つ")
	assert_eq(u.unit_attack, 12, "性能も新しい type のもの")
	assert_eq(u.max_troops, 6, "満員値も新しい type のもの")
	assert_eq(u.troops, 5, "損耗は名簿のまま")

func test_stage_state_keys_do_not_override_the_roster() -> void:
	# 個体の状態（level/troops）は名簿が持つ＝継承の駒にステージ側から書いても効かない。
	var carried: Array = [_member("elf", "t3.elf", 5)]
	var s := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "col": 1, "row": 1, "actor": "t3.elf", "troops": 8, "level": 9 },
	] }, _catalog(), {}, carried)
	assert_push_warning("ステージ側では効かない")
	assert_eq(_at(s, 1, 1).troops, 5, "名簿の損耗のまま")
	assert_eq(_at(s, 1, 1).level, 1, "名簿のレベルのまま")

func test_carried_units_belong_to_player() -> void:
	var carried: Array = [_member("elf", "t3.elf")]
	var s := StageLoader.build({ "cols": 8, "rows": 6,
		"player": [{ "col": 1, "row": 1, "actor": "t3.elf" }] }, _catalog(), {}, carried)
	var u := _at(s, 1, 1)
	assert_eq(u.team, 0)
	assert_eq(u.recruited_team, 0, "名簿に載っている＝帰属は自軍で確定")
