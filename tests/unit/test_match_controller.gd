extends GutTest
## application/match_controller.gd（進行のまとめ役）のテスト。
## 下りコマンド→domain 呼び出し→上りシグナル発行、の配線と _finished ラッチを検証する。
## 戦闘式・占領などの状態遷移そのものは domain 側のテストに任せ、ここではシグナルに絞る。
## 詳細 → doc/tech/testing.md, doc/tech/architecture.md

## 手を積んでおくと1手ずつ返すスタブAI（尽きたら null＝手番を返す）。
class QueueBrain extends AiBrain:
	var queue: Array = []
	func next_action(_state: BattleState, _team: int) -> AiAction:
		if queue.is_empty():
			return null
		return queue.pop_front()

## MatchController を生成して state を配線し、シグナル監視を開始する。
func _mc(s: BattleState) -> MatchController:
	var mc: MatchController = autofree(MatchController.new())
	mc.setup(s)
	watch_signals(mc)
	return mc

# 三重詠唱の成立盤（test_formation.gd と同じ配置）。敵 id9 は def 低め＝撃破される。
func _trinity_state(s: BattleState, enemy_def := 1) -> Dictionary:
	var c := Hex.offset_to_axial(3, 3)
	var w1 := Unit.new(1, 0, c, 3, 8, 40, 30, 1, "wizard")
	var w2 := Unit.new(2, 0, Hex.neighbor(c, 0), 3, 8, 40, 30, 1, "wizard")
	var w3 := Unit.new(3, 0, Hex.neighbor(c, 1), 3, 8, 40, 30, 1, "wizard")
	w1.pierce = 0.5
	var enemy_hex := c + Hex.direction(0) * 3
	var enemy := Unit.new(9, 1, enemy_hex, 3, 8, 10, enemy_def)
	for u in [w1, w2, w3, enemy]:
		s.add_unit(u)
	return {"leader": w1, "enemy_hex": enemy_hex}

func _formation_cmd(s: BattleState, leader: Unit, target: Vector2i) -> FormationCommand:
	var opts := Formation.available_for(s, leader)
	assert_eq(opts.size(), 1, "前提: 三重詠唱が検出される")
	return FormationCommand.new(opts[0], target)

# --- _finished ラッチ（決着後は全コマンドが no-op） ---

func test_finished_latch_blocks_all_commands() -> void:
	var s := BattleState.new(12, 8)
	s.turn_limit = 1
	var u1 := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3)          # 移動・攻撃・待機役
	var e1 := Unit.new(2, 1, Hex.neighbor(u1.pos, 0), 3)            # u1 に隣接する敵
	var u2 := Unit.new(3, 0, Hex.offset_to_axial(8, 2), 3)          # 自軍拠点の上＝駐留役
	var t := Unit.new(4, 0, Hex.offset_to_axial(5, 5), 3)           # 輸送（搭乗1体）
	t.capacity = 4
	for u in [u1, e1, u2, t]:
		s.add_unit(u)
	s.put_passenger(t.id, Unit.new(5, 0, Vector2i.ZERO, 2))
	var b := Base.new(Hex.offset_to_axial(8, 5), 0)                 # 出撃役の拠点
	b.garrison.append(Unit.new(6, 0, Vector2i.ZERO, 2))
	s.add_base(b)
	s.add_base(Base.new(u2.pos, 0))                                 # u2 の駐留先
	var mc := _mc(s)
	mc.end_turn()  # → 敵軍（turn 1）
	mc.end_turn()  # → 自軍 turn 2 > limit 1 ＝時間切れ敗北で決着
	assert_signal_emit_count(mc, "battle_finished", 1, "時間切れで battle_finished が1回")
	assert_signal_emitted_with_parameters(mc, "battle_finished", [BattleState.PLAYER_LOSS])
	# 前提: state 上は全コマンドが成立しうる（塞ぐのはラッチだけ）ことを確認しておく。
	var move_to := Hex.neighbor(u1.pos, 3)
	var unload_to: Vector2i = s.unload_cells(4, 0)[0]
	assert_true(s.can_move(1, move_to), "前提: 移動は state 的には妥当")
	assert_true(s.can_attack(1, 2), "前提: 攻撃は state 的には妥当")
	assert_true(s.can_deploy(b.hex), "前提: 出撃は state 的には妥当")
	assert_true(s.can_enter_base(3), "前提: 駐留は state 的には妥当")
	# 決着後は全コマンドが no-op（false）でシグナルも出ない。
	assert_false(mc.execute(MoveCommand.new(1, move_to)), "決着後の移動は no-op")
	assert_false(mc.execute_attack(AttackCommand.new(1, 2)), "決着後の攻撃は no-op")
	assert_false(mc.execute_formation(FormationCommand.new({}, Vector2i.ZERO)), "決着後の陣形は no-op")
	assert_false(mc.execute_deploy(DeployCommand.new(b.hex, 0, Hex.neighbor(b.hex, 0))), "決着後の出撃は no-op")
	assert_false(mc.execute_unload(UnloadCommand.new(4, 0, unload_to)), "決着後の降車は no-op")
	assert_false(mc.enter_base(3), "決着後の駐留は no-op")
	mc.stand(1)
	assert_true(s.can_select(1), "決着後の待機は no-op（行動終了が付かない）")
	mc.end_turn()
	assert_signal_emit_count(mc, "turn_changed", 2, "決着後の end_turn は手番を回さない")
	assert_signal_emit_count(mc, "battle_finished", 1, "battle_finished は二重発行されない")
	for sig in ["unit_moved", "move_rejected", "unit_attacked", "combat_resolved",
			"formation_resolved", "unit_deployed", "unit_unloaded", "unit_entered_base", "unit_died"]:
		assert_signal_not_emitted(mc, sig, "決着後は %s が出ない" % sig)

# --- battle_finished の単発性（決着契機ごと） ---

func test_move_capture_hq_finishes_once() -> void:
	var s := BattleState.new(12, 8)
	s.victory_conditions = [{"type": "capture_hq"}]
	var hq_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(hq_hex, 1, "hq"))
	var c := Unit.new(1, 0, Hex.neighbor(hq_hex, 3), 3)
	c.can_capture = true
	s.add_unit(c)
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(10, 6), 3))  # 残存する敵＝殲滅勝ちではない
	var mc := _mc(s)
	assert_true(mc.execute(MoveCommand.new(1, hq_hex)), "本拠地への移動＝占領が成立")
	assert_signal_emitted(mc, "unit_moved")
	assert_signal_emit_count(mc, "battle_finished", 1, "移動＝HQ占領で決着が1回")
	assert_signal_emitted_with_parameters(mc, "battle_finished", [BattleState.PLAYER_WIN])
	mc.end_turn()  # 決着後の追い打ちでも再発行されない
	assert_signal_emit_count(mc, "battle_finished", 1, "二重発行されない")

func test_attack_annihilation_finishes_once() -> void:
	var s := BattleState.new(8, 8)
	var a := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 100, 100)
	var e := Unit.new(2, 1, Hex.neighbor(a.pos, 0), 3, 1, 1, 1)  # 最後の敵＝一撃で全滅
	s.add_unit(a)
	s.add_unit(e)
	var mc := _mc(s)
	assert_true(mc.execute_attack(AttackCommand.new(1, 2)))
	assert_signal_emitted_with_parameters(mc, "unit_died", [2])
	assert_signal_emit_count(mc, "battle_finished", 1, "敵全滅で決着が1回")
	assert_signal_emitted_with_parameters(mc, "battle_finished", [BattleState.PLAYER_WIN])
	assert_false(mc.execute_attack(AttackCommand.new(1, 2)), "決着後の攻撃は no-op")
	assert_signal_emit_count(mc, "battle_finished", 1, "二重発行されない")

func test_formation_boss_kill_finishes_once() -> void:
	var s := BattleState.new(12, 8)
	s.victory_conditions = [{"type": "defeat_unit", "unit_id": 9}]
	var f := _trinity_state(s)  # 敵 id9＝ボス（def 1＝撃破される）
	s.add_unit(Unit.new(11, 1, Hex.offset_to_axial(10, 6), 3))  # 残存する敵＝殲滅勝ちではない
	var mc := _mc(s)
	var cmd := _formation_cmd(s, f["leader"], f["enemy_hex"])
	assert_true(mc.execute_formation(cmd), "陣形の発動が成立")
	assert_signal_emitted_with_parameters(mc, "unit_died", [9])
	assert_signal_emit_count(mc, "battle_finished", 1, "ボス撃破で決着が1回")
	assert_signal_emitted_with_parameters(mc, "battle_finished", [BattleState.PLAYER_WIN])
	assert_false(mc.execute_formation(cmd), "決着後の陣形は no-op")
	assert_signal_emit_count(mc, "battle_finished", 1, "二重発行されない")

func test_unload_capture_finishes_once() -> void:
	var s := BattleState.new(12, 8)
	s.victory_conditions = [{"type": "capture_hq"}]
	var t := Unit.new(1, 0, Hex.offset_to_axial(6, 4), 3)
	t.capacity = 4
	s.add_unit(t)
	var p := Unit.new(2, 0, Vector2i.ZERO, 2)
	p.can_capture = true
	s.put_passenger(t.id, p)
	var hq_hex := Hex.neighbor(t.pos, 0)
	s.add_base(Base.new(hq_hex, 1, "hq"))
	s.add_unit(Unit.new(3, 1, Hex.offset_to_axial(10, 6), 3))  # 残存する敵＝殲滅勝ちではない
	var mc := _mc(s)
	assert_true(mc.execute_unload(UnloadCommand.new(1, 0, hq_hex)), "本拠地への降車＝占領が成立")
	assert_signal_emitted_with_parameters(mc, "unit_unloaded", [2, 1, hq_hex])
	assert_eq(s.base_at(hq_hex).team, 0, "降車で占領される")
	assert_signal_emit_count(mc, "battle_finished", 1, "降車＝HQ占領で決着が1回")
	assert_signal_emitted_with_parameters(mc, "battle_finished", [BattleState.PLAYER_WIN])
	mc.end_turn()
	assert_signal_emit_count(mc, "battle_finished", 1, "二重発行されない")

# --- execute_move（unit_moved / move_rejected） ---

func test_execute_move_emits_unit_moved() -> void:
	var s := BattleState.new(8, 8)
	var u := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3)
	s.add_unit(u)
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	var from := u.pos
	var to := Hex.neighbor(from, 0)
	var mc := _mc(s)
	assert_true(mc.execute(MoveCommand.new(1, to)))
	assert_signal_emitted_with_parameters(mc, "unit_moved", [1, from, to])
	assert_signal_not_emitted(mc, "move_rejected")

func test_execute_move_failure_emits_move_rejected() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	var far := Hex.offset_to_axial(7, 7)  # 移動力3では届かない
	var mc := _mc(s)
	assert_false(mc.execute(MoveCommand.new(1, far)))
	assert_signal_emitted_with_parameters(mc, "move_rejected", [1, far])
	assert_signal_not_emitted(mc, "unit_moved")

func test_execute_move_unknown_unit_fails_without_reject() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	var mc := _mc(s)
	assert_false(mc.execute(MoveCommand.new(99, Hex.offset_to_axial(3, 3))), "居ない駒は false")
	assert_signal_not_emitted(mc, "move_rejected", "駒が特定できない失敗は move_rejected も出ない")

# --- execute_attack（複合シグナル） ---

func test_execute_attack_emits_attacked_then_resolved() -> void:
	var s := BattleState.new(8, 8)
	var a := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3)
	var t := Unit.new(2, 1, Hex.neighbor(a.pos, 0), 3)  # 同格＝倒し切れない
	s.add_unit(a)
	s.add_unit(t)
	var mc := _mc(s)
	assert_true(mc.execute_attack(AttackCommand.new(1, 2)))
	var pr: Array = get_signal_parameters(mc, "unit_attacked")
	assert_eq(pr[0], 1, "attacker_id")
	assert_eq(pr[1], 2, "target_id")
	assert_eq(pr[2], 8 - t.troops, "damage は盤の兵数減と一致")
	assert_false(bool(pr[3]), "非撃破なら killed=false")
	assert_signal_emit_count(mc, "combat_resolved", 1, "結果内訳が1回届く")
	assert_signal_not_emitted(mc, "unit_died", "非撃破なら unit_died は出ない")
	assert_signal_not_emitted(mc, "battle_finished")

func test_attack_mutual_kill_emits_unit_died_twice_in_order() -> void:
	var s := BattleState.new(12, 8)
	var a := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 1, 100, 1)  # 兵1・高火力＝相打ち
	var t := Unit.new(2, 1, Hex.neighbor(a.pos, 0), 3, 1, 100, 1)
	s.add_unit(a)
	s.add_unit(t)
	s.add_unit(Unit.new(3, 0, Hex.offset_to_axial(9, 6), 3))   # 双方に残存駒＝決着しない
	s.add_unit(Unit.new(4, 1, Hex.offset_to_axial(11, 7), 3))
	var mc := _mc(s)
	var order: Array = []
	mc.unit_attacked.connect(func(_a: int, _t: int, _d: int, _k: bool) -> void: order.append("attacked"))
	mc.unit_died.connect(func(uid: int) -> void: order.append("died:%d" % uid))
	mc.combat_resolved.connect(func(_d: Dictionary) -> void: order.append("resolved"))
	assert_true(mc.execute_attack(AttackCommand.new(1, 2)))
	assert_eq(order, ["attacked", "died:2", "died:1", "resolved"],
			"unit_attacked → 撃破(標的) → 反撃死(攻撃側) → combat_resolved の順")
	assert_signal_emit_count(mc, "unit_died", 2, "相打ちは unit_died が2回")
	assert_signal_not_emitted(mc, "battle_finished")

func test_execute_attack_invalid_fails_without_signals() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 2), 3))  # 射程1では届かない
	var mc := _mc(s)
	assert_false(mc.execute_attack(AttackCommand.new(1, 2)), "不成立（空result）は false")
	assert_signal_not_emitted(mc, "unit_attacked")
	assert_signal_not_emitted(mc, "combat_resolved")

# --- execute_formation（killed ごとの unit_died・formation_resolved） ---

func test_execute_formation_emits_died_per_kill() -> void:
	var s := BattleState.new(12, 8)
	var f := _trinity_state(s)  # 敵 id9（def 1）＝着弾中心
	s.add_unit(Unit.new(10, 1, Hex.neighbor(f["enemy_hex"], 2), 3, 8, 10, 1))  # 面内の敵＝同時撃破
	s.add_unit(Unit.new(11, 1, Hex.offset_to_axial(10, 6), 3))                 # 残存する敵＝決着しない
	var mc := _mc(s)
	assert_true(mc.execute_formation(_formation_cmd(s, f["leader"], f["enemy_hex"])))
	assert_signal_emit_count(mc, "unit_died", 2, "撃破された2体ぶん unit_died")
	var died: Array = [get_signal_parameters(mc, "unit_died", 0)[0], get_signal_parameters(mc, "unit_died", 1)[0]]
	died.sort()
	assert_eq(died, [9, 10], "撃破された id が届く")
	assert_signal_emit_count(mc, "formation_resolved", 1)
	var result: Dictionary = get_signal_parameters(mc, "formation_resolved")[0]
	assert_eq((result["results"] as Array).size(), 2, "着弾結果が2件")
	assert_signal_not_emitted(mc, "battle_finished")

func test_execute_formation_invalid_fails_without_signals() -> void:
	var s := BattleState.new(12, 8)
	var f := _trinity_state(s)
	var far := Hex.offset_to_axial(3, 3) + Hex.direction(0) * 8  # 射程5超＝不成立
	var mc := _mc(s)
	assert_false(mc.execute_formation(_formation_cmd(s, f["leader"], far)))
	assert_signal_not_emitted(mc, "formation_resolved")
	assert_signal_not_emitted(mc, "unit_died")

# --- end_turn / is_ai_turn / AI手番 ---

func test_end_turn_emits_turn_changed() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	var mc := _mc(s)
	mc.end_turn()
	assert_signal_emitted_with_parameters(mc, "turn_changed", [1, 1], 0)
	mc.end_turn()
	assert_signal_emitted_with_parameters(mc, "turn_changed", [0, 2], 1)
	assert_signal_not_emitted(mc, "battle_finished")

func test_is_ai_turn() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	var mc := _mc(s)
	assert_false(mc.is_ai_turn(), "brain 無しは自軍手番で false")
	s.current_team = 1
	assert_false(mc.is_ai_turn(), "brain 無しは敵手番でも false（ホットシート）")
	mc.ai_brain = AiBrain.new()
	assert_true(mc.is_ai_turn(), "brain あり＋敵手番（ai_team）は true")
	s.current_team = 0
	assert_false(mc.is_ai_turn(), "brain ありでも自軍手番は false")

func test_end_turn_runs_ai_and_returns_turn() -> void:
	# ツリー外＝is_inside_tree() が false で await を踏まないため、AI手番は同期で回り切る。
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3))
	var e := Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3)
	s.add_unit(e)
	var from := e.pos
	var dest := Hex.neighbor(from, 0)
	var mc := _mc(s)
	var brain := QueueBrain.new()
	brain.queue.append(AiAction.move_to(2, dest))
	mc.ai_brain = brain
	mc.end_turn()  # → 敵手番 → AIが1手指して手番を返す
	assert_signal_emitted_with_parameters(mc, "unit_moved", [2, from, dest])
	assert_eq(s.current_team, 0, "AIが指し終えたら手番が自軍へ戻る")
	assert_eq(s.turn_number, 2, "1巡してターンが進む")
	assert_signal_emit_count(mc, "turn_changed", 2, "自軍→敵軍→自軍で2回")

# --- execute_deploy（uid の事前取得） ---

func test_execute_deploy_emits_garrison_uid() -> void:
	var s := BattleState.new(12, 8)
	var b := Base.new(Hex.offset_to_axial(5, 5), 0)
	b.garrison.append(Unit.new(42, 0, Vector2i.ZERO, 2))
	s.add_base(b)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(10, 6), 3))
	var to := Hex.neighbor(b.hex, 0)
	var mc := _mc(s)
	assert_true(mc.execute_deploy(DeployCommand.new(b.hex, 0, to)))
	assert_signal_emitted_with_parameters(mc, "unit_deployed", [42, b.hex, to])
	assert_eq(s.unit_at(to).id, 42, "出撃した駒が盤上に出る")

func test_execute_deploy_into_transport_uses_prefetched_uid() -> void:
	# 出撃先が輸送のマス＝盤上には出ない（unit_at では引けない）ため、uid は控えから事前に取る。
	var s := BattleState.new(12, 8)
	var b := Base.new(Hex.offset_to_axial(5, 5), 0)
	b.garrison.append(Unit.new(42, 0, Vector2i.ZERO, 2))
	s.add_base(b)
	var t := Unit.new(7, 0, Hex.neighbor(b.hex, 0), 3)
	t.capacity = 2
	s.add_unit(t)
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(10, 6), 3))
	var mc := _mc(s)
	assert_true(mc.execute_deploy(DeployCommand.new(b.hex, 0, t.pos)))
	assert_signal_emitted_with_parameters(mc, "unit_deployed", [42, b.hex, t.pos])
	assert_eq(s.unit_at(t.pos).id, 7, "出撃先のマスに居るのは輸送（出た駒ではない）")
	assert_eq((s.passengers(7)[0] as Unit).id, 42, "出た駒は輸送に搭乗している")

func test_execute_deploy_invalid_fails_without_signal() -> void:
	var s := BattleState.new(12, 8)
	var b := Base.new(Hex.offset_to_axial(5, 5), 0)
	b.garrison.append(Unit.new(42, 0, Vector2i.ZERO, 2))
	s.add_base(b)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(10, 6), 3))
	var mc := _mc(s)
	assert_false(mc.execute_deploy(DeployCommand.new(b.hex, 5, Hex.neighbor(b.hex, 0))), "garrison_index 範囲外は false")
	assert_false(mc.execute_deploy(DeployCommand.new(Hex.offset_to_axial(2, 2), 0, Hex.offset_to_axial(2, 3))), "拠点の無い hex は false")
	assert_signal_not_emitted(mc, "unit_deployed")
