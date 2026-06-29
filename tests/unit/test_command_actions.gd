extends GutTest
## domain/battle_state.gd のコマンドメニュー向け追加（仮移動の攻撃可否・待機フラグ）のテスト。

const ATTACKER := Vector2i(2, 2)  # offset
const ENEMY := Vector2i(4, 2)     # offset（攻撃側 move3 で隣接マスに届く距離）

func _state() -> BattleState:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(ATTACKER.x, ATTACKER.y), 3))  # 自軍（攻撃力10・射程1）
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(ENEMY.x, ENEMY.y), 3))        # 敵軍
	return s

## around の6近傍のうち toward に最も近いもの（攻撃側が確実に届く隣接マスを選ぶ）。
func _closest_adj(around: Vector2i, toward: Vector2i) -> Vector2i:
	var best := around
	var best_d := 1 << 30
	for nb in Hex.neighbors(around):
		var d := Hex.distance(nb, toward)
		if d < best_d:
			best_d = d
			best = nb
	return best

func test_attack_targets_from_sees_targets_at_hypothetical_pos() -> void:
	var s := _state()
	var enemy_axial := Hex.offset_to_axial(ENEMY.x, ENEMY.y)
	assert_true(s.attack_targets(1).is_empty(), "今の位置（離れている）からは攻撃対象なし")
	var adj := _closest_adj(enemy_axial, Hex.offset_to_axial(ATTACKER.x, ATTACKER.y))
	assert_true(s.attack_targets_from(1, adj).has(2), "敵の隣へ移動すれば攻撃対象に入る")

func test_attack_targets_from_empty_after_attacked() -> void:
	var s := _state()
	var enemy_axial := Hex.offset_to_axial(ENEMY.x, ENEMY.y)
	var adj := _closest_adj(enemy_axial, Hex.offset_to_axial(ATTACKER.x, ATTACKER.y))
	assert_true(s.move_unit(1, adj), "隣接マスへ移動できる")
	assert_true(s.attack(1, 2).size() > 0, "隣接で攻撃成立")
	assert_true(s.attack_targets_from(1, adj).is_empty(), "攻撃済みなら仮移動でも対象は出ない")

func test_set_done_ends_unit_turn() -> void:
	var s := _state()
	assert_true(s.can_select(1), "初期は選択可")
	s.set_done(1)
	assert_true(s.is_done(1), "待機で行動終了")
	assert_false(s.can_select(1), "待機後は再選択不可")

func test_done_flag_cleared_next_turn() -> void:
	var s := _state()
	s.set_done(1)
	s.end_turn()  # → 敵軍
	s.end_turn()  # → 自軍へ戻る
	assert_false(s.is_done(1), "次の自軍手番では待機が解除される")
	assert_true(s.can_select(1), "再び選択可")
