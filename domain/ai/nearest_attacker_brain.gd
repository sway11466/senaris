extends AiBrain
class_name NearestAttackerBrain
## 最小AI: 各ユニットについて「攻撃できるなら殴る／できなければ最寄りの敵へ寄る」。
## 1手ずつ返す（移動した次の呼び出しで隣接していれば攻撃を返す）。
## 隣接敵が複数なら最もHPの低い相手を狙う。

func next_action(state: BattleState, team: int) -> AiAction:
	for u in state.units():
		if u.team != team or state.is_done(u.id):
			continue
		# 隣接敵がいれば攻撃。
		var targets := state.attack_targets(u.id)
		if not targets.is_empty():
			return AiAction.attack(u.id, _weakest(state, targets))
		# まだ動いておらず、近づけるなら最寄りの敵へ寄る。
		if not state.has_moved(u.id):
			var dest := _step_toward_nearest_enemy(state, u)
			if dest != u.pos:
				return AiAction.move_to(u.id, dest)
	return null

func _weakest(state: BattleState, ids: Array[int]) -> int:
	var best := ids[0]
	var best_hp := state.unit_by_id(best).hp
	for id in ids:
		var hp := state.unit_by_id(id).hp
		if hp < best_hp:
			best_hp = hp
			best = id
	return best

## 移動範囲のうち、最寄りの敵への距離が最も縮むヘックスを返す（縮まないなら現在地）。
func _step_toward_nearest_enemy(state: BattleState, u: Unit) -> Vector2i:
	var enemy := _nearest_enemy(state, u)
	if enemy == null:
		return u.pos
	var best := u.pos
	var best_d := Hex.distance(u.pos, enemy.pos)
	for h in state.reachable(u.id):
		var d := Hex.distance(h, enemy.pos)
		if d < best_d:
			best_d = d
			best = h
	return best

func _nearest_enemy(state: BattleState, u: Unit) -> Unit:
	var best: Unit = null
	var best_d := 1 << 30
	for other in state.units():
		if other.team == u.team:
			continue
		var d := Hex.distance(u.pos, other.pos)
		if d < best_d:
			best_d = d
			best = other
	return best
