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

# --- 部隊(squad)単位のAI割り当て ---

const PRESETS := {
	"charge": { "advance": "max" },
	"raid": { "advance": "base" },
}

func test_loader_wires_squads() -> void:
	var data := { "cols": 8, "rows": 8,
		"units": [ { "team": "player", "col": 1, "row": 1 } ],
		"squads": [
			{ "name": "強襲", "ai": "raid",
				"units": [ { "team": "enemy", "col": 5, "row": 5 }, { "team": "enemy", "col": 6, "row": 5 } ] },
		],
	}
	var s := StageLoader.build(data)
	assert_eq(s.units().size(), 3, "直書き1＋部隊2が盤に載る")
	assert_eq(s.squads.size(), 1)
	var sq2 := s.squad_of(2)  # 採番は直書きから連続（部隊の1体目=id2）
	assert_eq(String(sq2.get("ai", "")), "raid", "部隊メンバーは部隊のラベルを持つ")
	assert_eq(String(sq2.get("name", "")), "強襲")
	assert_true(s.squad_of(1).is_empty(), "直書きユニットは部隊なし")

func test_squad_units_follow_squad_preset() -> void:
	# 同じ盤で、raid部隊のユニットは拠点へ・部隊外（既定charge）のユニットは敵へ向かう。
	_brain.presets = PRESETS
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(10, 1, start, 3))                    # 部隊なし（既定=敵へ）
	var raider := Unit.new(11, 1, Hex.offset_to_axial(5, 0), 3)
	s.add_unit(raider)
	s.squads.append({ "name": "強襲", "ai": "raid" })
	s.assign_squad(11, 0)
	var base_hex := Hex.offset_to_axial(11, 1)               # 右に拠点
	s.add_base(Base.new(base_hex, 0))
	var enemy_pos := Hex.offset_to_axial(0, 1)               # 左に敵
	s.add_unit(Unit.new(1, 0, enemy_pos, 3))
	# id順に手を返す: 最初は部隊なし(10)＝敵へ
	var a := _brain.next_action(s, 1)
	assert_eq(a.unit_id, 10)
	assert_lt(Hex.distance(a.to, enemy_pos), Hex.distance(start, enemy_pos), "部隊なしは敵へ")
	assert_true(s.move_unit(10, a.to))
	# 次はraid部隊(11)＝拠点へ
	var b := _brain.next_action(s, 1)
	assert_eq(b.unit_id, 11)
	assert_lt(Hex.distance(b.to, base_hex), Hex.distance(raider.pos, base_hex), "raid部隊は拠点へ")

func test_squad_override_beats_preset() -> void:
	# 部隊の上書き（advance）はプリセット値より優先される。
	_brain.presets = PRESETS
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(10, 1, start, 3))
	s.squads.append({ "name": "上書き", "ai": "charge", "advance": "base" })  # charge だが base に上書き
	s.assign_squad(10, 0)
	var base_hex := Hex.offset_to_axial(11, 1)
	s.add_base(Base.new(base_hex, 0))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(0, 1), 3))
	var a := _brain.next_action(s, 1)
	assert_lt(Hex.distance(a.to, base_hex), Hex.distance(start, base_hex), "上書き advance=base が効く")

# --- 待機AI（guard）＝起動（engage）判定 ---

const GUARD := { "engage": "sight|squad", "sight": 3, "advance": "max" }

## guard部隊に属するAIユニットを1体足す（部隊は共有 index 0）。
func _add_guard(s: BattleState, id: int, pos: Vector2i) -> void:
	if s.squads.is_empty():
		s.squads.append({ "name": "見張り", "ai": "guard" })
	s.add_unit(Unit.new(id, 1, pos, 3))
	s.assign_squad(id, 0)

func test_guard_sleeps_when_enemy_far() -> void:
	_brain.presets = { "guard": GUARD }
	var s := BattleState.new(12, 3)
	s.current_team = 1
	_add_guard(s, 10, Hex.offset_to_axial(8, 1))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(0, 1), 3))  # 距離8＝索敵3の外
	assert_null(_brain.next_action(s, 1), "索敵外なら動かない（待機）")
	assert_false(s.is_engaged(10), "未起動のまま")

func test_guard_wakes_on_sight() -> void:
	_brain.presets = { "guard": GUARD }
	var s := BattleState.new(12, 3)
	s.current_team = 1
	_add_guard(s, 10, Hex.offset_to_axial(8, 1))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(5, 1), 3))  # 距離3＝索敵内
	var a := _brain.next_action(s, 1)
	assert_not_null(a, "索敵内に敵が入ったら起動して動く")
	assert_true(s.is_engaged(10), "起動済みになる")

func test_guard_squad_alarm_wakes_all() -> void:
	# 一斉警戒: 1体が索敵で起動すると、索敵外の同部隊メンバーも起動する。
	_brain.presets = { "guard": GUARD }
	var s := BattleState.new(14, 3)
	s.current_team = 1
	_add_guard(s, 10, Hex.offset_to_axial(6, 1))   # 敵まで3＝起動する
	_add_guard(s, 11, Hex.offset_to_axial(12, 1))  # 敵まで9＝索敵外だが部隊で起動
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(3, 1), 3, 8, 10, 40))
	var moved := {}
	var guard := 0
	while guard < 20:
		guard += 1
		var a := _brain.next_action(s, 1)
		if a == null:
			break
		moved[a.unit_id] = true
		if a.kind == AiAction.Kind.MOVE:
			s.move_unit(a.unit_id, a.to)
		else:
			s.attack(a.unit_id, a.target_id)
	assert_true(moved.has(10), "索敵した本人が動く")
	assert_true(moved.has(11), "索敵外の同部隊メンバーも一斉に動く")

func test_guard_wakes_when_damaged() -> void:
	# 被ダメ＝確定起動。撃たれた待機ユニットは次の手番から動く。
	_brain.presets = { "guard": GUARD }
	var s := BattleState.new(12, 3)
	_add_guard(s, 10, Hex.offset_to_axial(8, 1))
	var sniper := Unit.new(1, 0, Hex.offset_to_axial(4, 1), 3, 8, 30, 10)  # 距離4=索敵外
	sniper.attack_range = 4  # 索敵外から間接で撃つ
	s.add_unit(sniper)
	s.current_team = 0
	s.attack(1, 10)
	assert_true(s.is_engaged(10), "撃たれて起動")
	s.current_team = 1
	assert_not_null(_brain.next_action(s, 1), "起動済みなので動く")

func test_guard_self_defense_when_adjacent() -> void:
	# 索敵トリガー無し（squadのみ）でも、射程内に敵が来たら自衛で起動して殴る。
	_brain.presets = { "guard": { "engage": "squad", "sight": 0, "advance": "max" } }
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var gp := Hex.offset_to_axial(8, 1)
	_add_guard(s, 10, gp)
	s.add_unit(Unit.new(1, 0, Hex.neighbor(gp, 3), 3))  # 隣接
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "隣で寝続けず自衛で攻撃")

# --- 弱者狙い（weak）＝ attack=prey / target=weak / advance=flank。詳細 → doc/gdd/ai.md ---

const WEAK := { "engage": "charge", "attack": "prey", "target": "weak;near", "advance": "flank" }

func test_weak_advances_toward_prey_not_nearest() -> void:
	# 前進の目標＝獲物（盤上最低防御）。近い硬い敵ではなく、遠い脆い敵へ向かう。
	var brain := NearestAttackerBrain.from_preset(WEAK)
	var s := BattleState.new(13, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(10, 1, start, 3))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 1), 3, 8, 10, 40))   # 近い・硬い（防40）
	var frail_pos := Hex.offset_to_axial(11, 1)
	s.add_unit(Unit.new(2, 0, frail_pos, 3, 8, 10, 10))                   # 遠い・脆い（防10）＝獲物
	var a := brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, frail_pos), Hex.distance(start, frail_pos), "近い敵でなく獲物へ向かう")

func test_prey_only_skips_tough_frontline() -> void:
	# 攻撃条件「獲物のみ」: 硬い前衛が隣にいても殴らず、獲物へ前進を続ける。
	var brain := NearestAttackerBrain.from_preset(WEAK)
	var s := BattleState.new(13, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(10, 1, start, 3))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(4, 1), 3, 8, 10, 40))   # 隣接する硬い前衛（確殺不可）
	var frail_pos := Hex.offset_to_axial(11, 1)
	s.add_unit(Unit.new(2, 0, frail_pos, 3, 8, 10, 10))                   # 獲物
	var a := brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "前衛と殴り合わず前進")
	assert_lt(Hex.distance(a.to, frail_pos), Hex.distance(start, frail_pos), "獲物への距離が縮む")

func test_prey_only_still_takes_the_kill() -> void:
	# 確殺なら獲物でなくても殴る（隣の瀕死を無視して歩かない）。
	var brain := NearestAttackerBrain.from_preset(WEAK)
	var s := BattleState.new(13, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(10, 1, start, 3))
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(6, 1), 3, 1, 10, 30))   # 隣接・兵1＝確殺できる（獲物ではない）
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(11, 1), 3, 8, 10, 10))  # 獲物は遠く
	var a := brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "確殺は据え膳＝殴る")
	assert_eq(a.target_id, 1)

func test_target_weak_picks_most_killable_in_range() -> void:
	# 対象優先 weak: 兵数最小（既定）ではなく、攻撃後の残兵が最小の敵を選ぶ。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var ep := Hex.offset_to_axial(3, 3)
	s.add_unit(Unit.new(10, 1, ep, 3))
	s.add_unit(Unit.new(1, 0, Hex.neighbor(ep, 0), 3, 3, 10, 50))   # 兵3・防50＝削れない
	s.add_unit(Unit.new(2, 0, Hex.neighbor(ep, 2), 3, 4, 10, 5))    # 兵4・防5＝倒しきれる
	var d := _brain.next_action(s, 1)
	assert_eq(d.target_id, 1, "既定（兵数最小）は兵3を選ぶ")
	var weak_brain := NearestAttackerBrain.from_preset({ "attack": "always", "target": "weak;near", "advance": "max" })
	var a := weak_brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, 2, "weak は残兵最小（確殺）の兵4を選ぶ")

func test_flank_slides_around_zoc() -> void:
	# 回り込み: 前衛のZOC（隣接マス）に入らないマスを優先して獲物へ詰める。
	var brain := NearestAttackerBrain.from_preset(WEAK)
	var s := BattleState.new(13, 7)
	s.current_team = 1
	var start := Hex.offset_to_axial(2, 3)
	s.add_unit(Unit.new(10, 1, start, 3))
	var wall_pos := Hex.offset_to_axial(5, 3)
	s.add_unit(Unit.new(1, 0, wall_pos, 3, 8, 10, 40))                    # 進路上の前衛
	var wagon_pos := Hex.offset_to_axial(8, 3)
	s.add_unit(Unit.new(2, 0, wagon_pos, 3, 8, 10, 10))                   # 獲物（前衛の奥）
	var a := brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, wagon_pos), Hex.distance(start, wagon_pos), "獲物への距離が縮む")
	assert_gt(Hex.distance(a.to, wall_pos), 1, "前衛のZOC（隣接マス）は避ける")

func test_flank_falls_back_to_close_in_on_prey() -> void:
	# 獲物への最終接近: 安全なマスでは縮まらない（獲物自身のZOC）ので、詰めて隣接する。
	var brain := NearestAttackerBrain.from_preset(WEAK)
	var s := BattleState.new(13, 3)
	s.current_team = 1
	s.add_unit(Unit.new(10, 1, Hex.offset_to_axial(5, 1), 3))
	var wagon_pos := Hex.offset_to_axial(7, 1)
	s.add_unit(Unit.new(2, 0, wagon_pos, 3, 8, 10, 10))                   # 獲物（距離2）
	var a := brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(Hex.distance(a.to, wagon_pos), 1, "フォールバックで獲物に隣接まで詰める")

func test_squad_weak_preset_applies() -> void:
	# 部隊の ai=weak でも同じ思考が効く（プリセット解決の配線）。
	_brain.presets = { "weak": WEAK }
	var s := BattleState.new(13, 3)
	s.current_team = 1
	var start := Hex.offset_to_axial(5, 1)
	s.add_unit(Unit.new(10, 1, start, 3))
	s.squads.append({ "name": "狩り", "ai": "weak" })
	s.assign_squad(10, 0)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(4, 1), 3, 8, 10, 40))   # 隣接する硬い前衛
	var frail_pos := Hex.offset_to_axial(11, 1)
	s.add_unit(Unit.new(2, 0, frail_pos, 3, 8, 10, 10))                   # 獲物
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "部隊経由でも獲物のみ＝前衛を殴らない")
	assert_lt(Hex.distance(a.to, frail_pos), Hex.distance(start, frail_pos), "獲物へ向かう")

func test_weak_debug_stage_wires_squad() -> void:
	# デバッグステージ weak.json: 部隊が weak を参照し、馬車が獲物（盤上最低防御）になっている。
	var s := StageLoader.load_file("res://data/stages/debug/weak.json")
	assert_not_null(s, "weak.json が読める")
	assert_eq(s.squads.size(), 1)
	assert_eq(String(s.squads[0].get("ai", "")), "weak", "部隊のAIラベル＝weak")
	var wagon: Unit = null
	var min_def := 1 << 30
	for u in s.units():
		if u.team == 0:
			min_def = mini(min_def, u.unit_defense)
			if u.type_id == "wagon":
				wagon = u
	assert_not_null(wagon, "馬車がいる")
	assert_eq(wagon.unit_defense, min_def, "馬車が獲物（自軍最低防御）")

func test_ai_catalog_has_weak_preset() -> void:
	# 生成物 ai.json に weak（弱者狙い）が載っている（CSV→JSONパイプラインの配線確認）。
	var presets := AiCatalog.load_default()
	assert_true(presets.has("weak"), "weak がある")
	assert_eq(String(presets["weak"]["attack"]), "prey", "攻撃条件＝獲物のみ")
	assert_eq(String(presets["weak"]["target"]), "weak;near", "対象優先＝弱者狙い")
	assert_eq(String(presets["weak"]["advance"]), "flank", "前進＝回り込み")

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
