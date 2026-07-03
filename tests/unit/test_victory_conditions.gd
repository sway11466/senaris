extends GutTest
## 勝利条件リスト（OR）と「ボス撃破(defeat_unit)」のテスト。詳細 → doc/gdd/map.md（勝敗条件）
## 殲滅勝ち／全滅負けは従来どおり常に有効で、victory_conditions はそれに OR で加わる。

const BOSS_ID := 99

## 自軍1体＋ボス＋雑魚1体の盤。ボスは troops=1（一撃で落ちる）。
func _boss_state() -> BattleState:
	var s := BattleState.new(8, 8)
	s.victory_conditions = [{ "type": "defeat_unit", "unit_id": BOSS_ID }]
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 50, 40))                        # 自軍
	s.add_unit(Unit.new(BOSS_ID, 1, Hex.neighbor(ap, 0), 3, 1, 50, 40))  # ボス（隣接・兵1）
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3, 8, 10, 4))   # 離れた雑魚
	return s

func test_defeat_boss_wins_even_with_enemies_left() -> void:
	var s := _boss_state()
	assert_eq(s.outcome(), BattleState.ONGOING, "開戦時は継続")
	var r := s.attack(1, BOSS_ID)
	assert_true(bool(r["killed"]), "ボス（兵1）は一撃で落ちる")
	assert_eq(s.team_unit_count(1), 1, "雑魚が盤上に残っている")
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "敵が残っていてもボス撃破で勝利")
	assert_true(s.is_over())

func test_ongoing_while_boss_alive() -> void:
	var s := _boss_state()
	# 雑魚だけ倒してもボス条件は満たさない（殲滅もしていない）。
	s.add_unit(Unit.new(3, 0, Hex.offset_to_axial(6, 5), 3, 8, 50, 40))  # 雑魚の隣に自軍
	s.attack(3, 2)
	assert_eq(s.team_unit_count(1), 1, "ボスは健在")
	assert_eq(s.outcome(), BattleState.ONGOING, "ボスが生きている限り勝利しない")

func test_annihilation_still_wins_with_condition_list() -> void:
	# 条件リストがあっても、殲滅（盤上の敵0）での勝利は従来どおり有効。
	var s := BattleState.new(8, 8)
	s.victory_conditions = [{ "type": "defeat_unit", "unit_id": BOSS_ID }]
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 50, 40))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 1, 10, 4))  # ボスでない敵1体だけ
	s.attack(1, 2)
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "敵全滅なら（ボス未指定でも）勝利")

func test_mutual_destruction_on_boss_kill_is_loss() -> void:
	# 相討ち: 最後の自軍がボスを倒しつつ反撃で全滅 → 敗北優先（従来ルールを維持）。
	var s := BattleState.new(8, 8)
	s.victory_conditions = [{ "type": "defeat_unit", "unit_id": BOSS_ID }]
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 1, 50, 4))                          # 自軍最後の1体・兵1・紙防御
	s.add_unit(Unit.new(BOSS_ID, 1, Hex.neighbor(ap, 0), 3, 1, 90, 4))    # ボス・兵1・高火力
	var r := s.attack(1, BOSS_ID)
	assert_true(bool(r["killed"]) and bool(r["attacker_killed"]), "相討ちが成立")
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "自軍が盤上から消えていれば敗北優先")

func test_unknown_condition_type_is_ignored() -> void:
	var s := _boss_state()
	s.victory_conditions.append({ "type": "capture_hq" })  # 未実装タイプは満たさない扱い
	assert_eq(s.outcome(), BattleState.ONGOING, "未知の条件タイプで誤勝利しない")

# --- StageLoader 配線 ---

func test_loader_wires_victory_and_explicit_id() -> void:
	var data := { "cols": 6, "rows": 6,
		"units": [
			{ "team": 0, "col": 1, "row": 1 },
			{ "id": 99, "team": 1, "col": 4, "row": 4 },
		],
		"victory": [ { "type": "defeat_unit", "unit_id": 99 } ],
	}
	var s := StageLoader.build(data)
	assert_eq(s.victory_conditions.size(), 1, "victory リストが載る")
	assert_not_null(s.unit_by_id(99), "id 明示採番（99）でボスが引ける")

func test_loader_defaults_to_empty_conditions() -> void:
	var s := StageLoader.build({ "cols": 6, "rows": 6 })
	assert_true(s.victory_conditions.is_empty(), "victory 未指定＝空リスト（殲滅のみ＝従来挙動）")
