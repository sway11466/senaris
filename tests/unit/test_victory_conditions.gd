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

# --- 本拠地占領（capture_hq）と自軍本拠地の喪失 ---

## 自軍の占領役＋敵hq（隣接）＋離れた敵、の盤。
func _hq_state() -> BattleState:
	var s := BattleState.new(8, 8)
	s.victory_conditions = [{ "type": "capture_hq" }]
	var hq_hex := Hex.offset_to_axial(4, 4)
	var cap := Unit.new(1, 0, Hex.neighbor(hq_hex, 3), 3)  # 占領役（hqの隣）
	cap.can_capture = true
	s.add_unit(cap)
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(7, 7), 3, 8, 10, 4))  # 離れた敵
	s.add_base(Base.new(hq_hex, 1, "hq"))  # 敵本拠地
	return s

func test_capture_enemy_hq_wins_even_with_enemies_left() -> void:
	var s := _hq_state()
	assert_eq(s.outcome(), BattleState.ONGOING, "開戦時は継続")
	var hq_hex := Hex.offset_to_axial(4, 4)
	assert_true(s.move_unit(1, hq_hex), "占領役がhqへ進入")
	assert_eq(s.base_at(hq_hex).team, 0, "進入した瞬間に占領")
	assert_eq(s.team_unit_count(1), 1, "敵が盤上に残っている")
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "敵が残っていても本拠地占領で勝利")

func test_capture_normal_fort_does_not_win() -> void:
	var s := _hq_state()
	var fort_hex := Hex.offset_to_axial(2, 2)
	s.add_base(Base.new(fort_hex, 1, "fort"))  # 通常の砦
	s.base_at(fort_hex).team = 0  # 砦を奪っても…
	assert_eq(s.outcome(), BattleState.ONGOING, "通常砦(fort)の占領では勝たない（hqのみ）")

func test_capture_hq_without_enemy_hq_never_wins() -> void:
	# 敵 native の hq が存在しないステージで capture_hq を書いても空勝ちしない。
	var s := BattleState.new(8, 8)
	s.victory_conditions = [{ "type": "capture_hq" }]
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	assert_eq(s.outcome(), BattleState.ONGOING, "敵hqが無ければ条件は不成立（空勝ち防止）")

func test_losing_own_hq_is_defeat() -> void:
	# 自軍 native の hq を敵に奪われたら敗北（勝利条件リストと無関係の常時ルール）。
	var s := BattleState.new(8, 8)
	var hq_hex := Hex.offset_to_axial(3, 3)
	s.add_base(Base.new(hq_hex, 0, "hq"))  # 自軍本拠地
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(6, 6), 3))
	var raider := Unit.new(2, 1, Hex.neighbor(hq_hex, 0), 3)
	raider.can_capture = true
	s.add_unit(raider)
	s.current_team = 1  # 敵ターン
	assert_true(s.move_unit(2, hq_hex), "敵の占領役が自軍hqへ進入")
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "本拠地を奪われて敗北")

func test_recapture_restores_native_and_clears_loss() -> void:
	# native_team は占領で変わらない＝奪還すれば敗北状態が解消される。
	var s := BattleState.new(8, 8)
	var hq_hex := Hex.offset_to_axial(3, 3)
	var b := Base.new(hq_hex, 0, "hq")
	s.add_base(b)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(6, 6), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(7, 7), 3))
	b.team = 1  # 奪われた…
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS)
	b.team = 0  # 奪還
	assert_eq(b.native_team, 0, "native_team は不変")
	assert_eq(s.outcome(), BattleState.ONGOING, "奪還すれば継続に戻る")

# --- StageLoader 配線 ---

func test_loader_wires_base_kind_and_native() -> void:
	var data := { "cols": 6, "rows": 6,
		"bases": [
			{ "col": 4, "row": 4, "team": "enemy", "kind": "hq" },
			{ "col": 1, "row": 1, "team": "player" },
		],
	}
	var s := StageLoader.build(data)
	var hq := s.base_at(Hex.offset_to_axial(4, 4))
	assert_true(hq.is_hq(), "kind=hq が載る")
	assert_eq(hq.native_team, 1, "native_team＝初期所属")
	assert_false(s.base_at(Hex.offset_to_axial(1, 1)).is_hq(), "kind 省略＝fort")

func test_loader_wires_victory_and_explicit_id() -> void:
	var data := { "cols": 6, "rows": 6,
		"player": [
			{ "col": 1, "row": 1 },
		],
		"enemy": [
			{ "ai": "charge", "units": [ { "id": 99, "col": 4, "row": 4 } ] },
		],
		"victory": [ { "type": "defeat_unit", "unit_id": 99 } ],
	}
	var s := StageLoader.build(data)
	assert_eq(s.victory_conditions.size(), 1, "victory リストが載る")
	assert_not_null(s.unit_by_id(99), "id 明示採番（99）でボスが引ける")

func test_loader_defaults_to_empty_conditions() -> void:
	var s := StageLoader.build({ "cols": 6, "rows": 6 })
	assert_true(s.victory_conditions.is_empty(), "victory 未指定＝空リスト（殲滅のみ＝従来挙動）")

# --- Victory ヘルパー（BattleState.outcome の実体） ---

func test_victory_helper_matches_state_query() -> void:
	# state 側は委譲の薄い口＝どちらから聞いても同じ答えになる。
	var s := _boss_state()
	assert_eq(Victory.outcome(s), s.outcome(), "継続中は一致")
	assert_false(Victory.is_over(s), "継続中は決着していない")
	s.attack(1, BOSS_ID)
	assert_eq(Victory.outcome(s), BattleState.PLAYER_WIN, "ボス撃破で勝利")
	assert_eq(Victory.outcome(s), s.outcome(), "決着後も一致")
	assert_true(Victory.is_over(s))

func test_victory_helper_judges_single_condition() -> void:
	# 勝利条件1件の判定は condition_met＝タイプを足すときの入口。
	var s := _boss_state()
	var boss := { "type": "defeat_unit", "unit_id": BOSS_ID }
	assert_false(Victory.condition_met(s, boss), "ボスが生きていれば不成立")
	s.attack(1, BOSS_ID)
	assert_true(Victory.condition_met(s, boss), "撃破済みなら成立")
	assert_false(Victory.condition_met(s, { "type": "no_such_type" }), "未知の type は満たさない")
	assert_true(s.is_defeated(BOSS_ID), "撃破の記録は state 側の口から引ける")


# --- 敗北条件リスト（defeat）。本拠地喪失の常時ルールとは別軸＝ステージが名指しする守り物。---

## 自軍の駒＋敵の占領役＋守るべき中立拠点（col4,row4）の盤。
func _defend_state() -> BattleState:
	var s := BattleState.new(8, 8)
	var hex := Hex.offset_to_axial(4, 4)
	s.defeat_conditions = [{ "type": "lose_base", "col": 4, "row": 4 }]
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3))
	var raider := Unit.new(2, 1, Hex.neighbor(hex, 3), 3)  # 拠点の隣に敵の占領役
	raider.can_capture = true
	s.add_unit(raider)
	s.add_base(Base.new(hex, Base.NEUTRAL, "fort"))  # 中立の砦＝hqではない
	return s

func test_lose_base_defeat_when_enemy_takes_it() -> void:
	var s := _defend_state()
	assert_eq(s.outcome(), BattleState.ONGOING, "中立のうちは継続（未占領で即敗北にしない）")
	var hex := Hex.offset_to_axial(4, 4)
	s.current_team = 1  # 敵の手番にする（移動は手番側の駒しか動かせない）
	assert_true(s.move_unit(2, hex), "敵の占領役が拠点へ進入")
	assert_eq(s.base_at(hex).team, 1, "進入した瞬間に敵のもの")
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "hqでなくても、名指しした拠点を奪われたら敗北")

func test_lose_base_is_cleared_by_retaking() -> void:
	var s := _defend_state()
	var hex := Hex.offset_to_axial(4, 4)
	s.base_at(hex).team = 1
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS)
	s.base_at(hex).team = 0  # 奪還
	assert_eq(s.outcome(), BattleState.ONGOING, "取り返せば敗北条件は解消する")

func test_lose_base_ignores_missing_base() -> void:
	# 作者が消した拠点を指したままでも即敗北にしない（指定ミスで遊べなくならない）。
	var s := BattleState.new(8, 8)
	s.defeat_conditions = [{ "type": "lose_base", "col": 4, "row": 4 }]
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	assert_eq(s.outcome(), BattleState.ONGOING, "拠点が無いマスの指定は不成立")

func test_lose_unit_defeat_on_escort_death() -> void:
	# 護衛対象の喪失（勝利側の defeat_unit と対）。
	var s := BattleState.new(8, 8)
	s.defeat_conditions = [{ "type": "lose_unit", "unit_id": 7 }]
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3))
	var vip := Unit.new(7, 0, Hex.offset_to_axial(2, 2), 3, 1)  # 護衛対象（兵1）
	s.add_unit(vip)
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	assert_eq(s.outcome(), BattleState.ONGOING, "生きている間は継続")
	s.remove_unit(7)
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "護衛対象を失ったら敗北")

func test_unknown_defeat_type_is_ignored() -> void:
	var s := BattleState.new(8, 8)
	s.defeat_conditions = [{ "type": "no_such_defeat" }]
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	assert_eq(s.outcome(), BattleState.ONGOING, "未知タイプは満たさない扱い（前方互換）")

func test_defeat_wins_over_victory_condition() -> void:
	# 勝利条件と同時に成立したら敗北を優先（既存の敗北優先方針）。
	var s := _defend_state()
	var hex := Hex.offset_to_axial(4, 4)
	s.base_at(hex).team = 1
	s.victory_conditions = [{ "type": "defeat_unit", "unit_id": 2 }]
	s.remove_unit(2)  # 敵を全滅させたが拠点は奪われたまま
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "敗北条件が勝利より優先される")

func test_loader_reads_defeat_list() -> void:
	var s := StageLoader.build({
		"cols": 6, "rows": 6,
		"player": [ { "type": "cleric", "col": 0, "row": 0 } ],
		"bases": [ { "col": 3, "row": 3, "team": "neutral", "kind": "fort" } ],
		"defeat": [ { "type": "lose_base", "col": 3, "row": 3 } ],
	})
	assert_eq(s.defeat_conditions.size(), 1, "defeat リストが載る")
	assert_eq(String(s.defeat_conditions[0]["type"]), "lose_base")

func test_loader_defaults_to_empty_defeat() -> void:
	var s := StageLoader.build({ "cols": 6, "rows": 6 })
	assert_true(s.defeat_conditions.is_empty(), "defeat 未指定＝空リスト（常時ルールのみ）")
