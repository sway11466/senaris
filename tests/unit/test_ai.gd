extends GutTest
## domain/ai/nearest_attacker_brain.gd の思考テスト（純ロジック・ツリー不要）。

var _brain: NearestAttackerBrain

func before_each() -> void:
	_brain = NearestAttackerBrain.new()

# 指定 team の手番として、行動が尽きるまで AI を実際に適用する（安全のため上限付き）。
func _run_turn(state: BattleState, team: int) -> void:
	state.current_team = team
	var guard := 0
	while guard < 100:
		guard += 1
		var a := _brain.next_action(state, team)
		if a == null:
			return
		if a.kind == AiAction.Kind.MOVE:
			assert_true(state.move_unit(a.unit_id, a.to), "AIの移動は妥当であるべき")
		else:
			assert_false(state.attack(a.unit_id, a.target_id).is_empty(), "AIの攻撃は妥当であるべき")
	fail_test("AIの手番が終了しなかった（無限ループの疑い）")

func test_attacks_adjacent_enemy() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var ep := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(10, 1, ep, 3))                  # AIユニット
	s.add_unit(Unit.new(1, 0, Hex.neighbor(ep, 0), 3))  # 隣接する自軍
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "隣接敵がいれば攻撃を選ぶ")
	assert_eq(a.target_id, 1)

func test_moves_closer_when_far() -> void:
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var ai_pos := Hex.offset_to_axial(0, 1)
	var enemy_pos := Hex.offset_to_axial(10, 1)
	s.add_unit(Unit.new(10, 1, ai_pos, 3))
	s.add_unit(Unit.new(1, 0, enemy_pos, 3))
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.MOVE, "遠ければ近づく")
	assert_lt(Hex.distance(a.to, enemy_pos), Hex.distance(ai_pos, enemy_pos), "距離が縮む")

func test_focuses_weakest_adjacent() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var ep := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(10, 1, ep, 3))
	s.add_unit(Unit.new(1, 0, Hex.neighbor(ep, 0), 3, 8))   # 兵数8
	s.add_unit(Unit.new(2, 0, Hex.neighbor(ep, 2), 3, 3))   # 兵数3（弱い）
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, 2, "最も兵数の少ない敵を狙う")

func test_no_action_without_enemies() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	s.add_unit(Unit.new(10, 1, Hex.offset_to_axial(3, 3), 3))
	assert_null(_brain.next_action(s, 1), "敵がいなければ何もしない")

func test_full_turn_engages_and_damages() -> void:
	# 数ヘックス離れた敵へ寄って殴る一連の流れ。AIは強くて落ちない設定。
	var s := BattleState.new(12, 3)
	s.add_unit(Unit.new(10, 1, Hex.offset_to_axial(0, 1), 4, 8, 20, 20))  # AI 移動力4・強い
	var enemy_pos := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(1, 0, enemy_pos, 3, 8, 1, 10))                    # 反撃は微弱
	_run_turn(s, 1)
	var ai := s.unit_by_id(10)
	assert_not_null(ai, "AIユニットは生存（敵の反撃が微弱なので）")
	assert_eq(Hex.distance(ai.pos, enemy_pos), 1, "敵に隣接するまで前進する")
	assert_lt(s.unit_by_id(1).troops, 8, "前進後に攻撃して兵数を削る")

# --- 占領ステップ（起動の後・攻撃の前）と前進オプション「拠点前進」 ---

## 占領可のAIユニットを作る（cleric相当）。
func _capturer(id: int, team: int, pos: Vector2i, move := 3) -> Unit:
	var u := Unit.new(id, team, pos, move)
	u.can_capture = true
	return u

func test_capturer_takes_reachable_base_over_attack() -> void:
	# 隣に殴れる敵がいても、移動範囲に取れる拠点があれば占領を優先する。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var ep := Hex.offset_to_axial(3, 3)
	s.add_unit(_capturer(10, 1, ep))
	s.add_unit(Unit.new(1, 0, Hex.neighbor(ep, 0), 3))       # 隣接する自軍（殴れる）
	var base_hex := Hex.offset_to_axial(3, 5)                # 距離2＝移動範囲内
	s.add_base(Base.new(base_hex, 0))                        # 自軍所属の拠点＝AIから見て奪える
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "攻撃より占領を優先")
	assert_eq(a.to, base_hex, "拠点hexへ移動（進入＝占領）")

func test_non_capturer_ignores_base() -> void:
	# 占領不可ユニットは拠点を無視して従来どおり攻撃する。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var ep := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(10, 1, ep, 3))                       # can_capture=false
	s.add_unit(Unit.new(1, 0, Hex.neighbor(ep, 0), 3))
	s.add_base(Base.new(Hex.offset_to_axial(3, 5), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "占領不可なら拠点を無視して攻撃")

func test_capturer_ignores_own_base() -> void:
	# 自陣営の拠点は占領対象でない（敵がいなければ何もしない）。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	s.add_unit(_capturer(10, 1, Hex.offset_to_axial(3, 3)))
	s.add_base(Base.new(Hex.offset_to_axial(3, 5), 1))       # 自陣営(team1)の拠点
	assert_null(_brain.next_action(s, 1), "自陣営の拠点しか無ければ動かない")

func test_full_turn_capture_flips_base() -> void:
	# 実際に手番を回すと、拠点へ進入して所属が変わる（自動占領）。
	var s := BattleState.new(8, 8)
	var base_hex := Hex.offset_to_axial(3, 5)
	s.add_unit(_capturer(10, 1, Hex.offset_to_axial(3, 3)))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(7, 7), 3))  # 遠くの自軍（起動のため）
	s.add_base(Base.new(base_hex, 0))
	_run_turn(s, 1)
	assert_eq(s.base_at(base_hex).team, 1, "手番の中で拠点を占領して所属が変わる")

func test_advance_to_base_option_steps_toward_base() -> void:
	# 拠点前進オプション: 届かない拠点でも、敵ではなく拠点の方へ前進する。
	_brain.advance_to_base = true
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(_capturer(10, 1, start))
	var base_hex := Hex.offset_to_axial(11, 1)               # 右の彼方（届かない）
	s.add_base(Base.new(base_hex, 0))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(0, 1), 3)) # 敵は左の彼方
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, base_hex), Hex.distance(start, base_hex), "拠点への距離が縮む＝敵でなく拠点へ向かう")

func test_advance_to_base_applies_to_non_capturer_too() -> void:
	# 拠点前進は部隊ごと拠点攻略へ向かう動き＝占領不可ユニット（護衛）も拠点方向へ前進する。
	_brain.advance_to_base = true
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(10, 1, start, 3))                    # can_capture=false（護衛）
	var base_hex := Hex.offset_to_axial(11, 1)
	s.add_base(Base.new(base_hex, 0))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(0, 1), 3)) # 敵は逆方向
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, base_hex), Hex.distance(start, base_hex), "護衛も拠点へ向かう")

func test_from_preset_wires_advance_base() -> void:
	# ai.csv の advance="base" → 拠点前進フラグ。空/未知は既定（charge相当）。
	assert_true(NearestAttackerBrain.from_preset({ "advance": "base" }).advance_to_base, "base＝拠点前進ON")
	assert_false(NearestAttackerBrain.from_preset({ "advance": "max" }).advance_to_base, "max＝既定")
	assert_false(NearestAttackerBrain.from_preset({}).advance_to_base, "空辞書＝既定")

func test_ai_catalog_default_has_raid_preset() -> void:
	# 生成物 ai.json に raid（拠点攻略）プリセットが載っている（CSV→JSONパイプラインの配線確認）。
	var presets := AiCatalog.load_default()
	assert_true(presets.has("charge"), "charge がある")
	assert_true(presets.has("raid"), "raid がある")
	assert_eq(String(presets["raid"]["advance"]), "base", "raid は拠点前進")

func test_loader_wires_enemy_ai_label() -> void:
	var s := StageLoader.build({ "cols": 6, "rows": 6, "ai": "raid" })
	assert_eq(s.enemy_ai, "raid", "ステージJSONの ai ラベルが載る")
	var s2 := StageLoader.build({ "cols": 6, "rows": 6 })
	assert_eq(s2.enemy_ai, "", "未指定＝空（既定 charge）")

func test_advance_default_still_heads_to_enemy() -> void:
	# 既定（advance_to_base=false）は従来どおり敵へ前進する（回帰）。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(_capturer(10, 1, start))
	s.add_base(Base.new(Hex.offset_to_axial(11, 1), 0))      # 右に拠点（届かない）
	var enemy_pos := Hex.offset_to_axial(0, 1)
	s.add_unit(Unit.new(1, 0, enemy_pos, 3))                 # 左に敵
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, enemy_pos), Hex.distance(start, enemy_pos), "既定は敵へ向かう")
