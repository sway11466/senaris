extends AiTrait
class_name TraitSwarm
## swarm（群れ）の行動ルール。傷ついた敵へ集まり、無傷の敵には頭数が揃ってから手を出す。
## 詳細 → doc/gdd/ai.md swarm
## 1 間接攻撃できる駒で、移動範囲のどこかから手負いを撃てる → 手負いへ最大間合い
## 2 攻撃射程内に手負い → 手負いを攻撃（ここだけ包囲を条件にしない＝単独でも噛みつく）
## 3 間接攻撃できる駒で、移動範囲のどこかから自分を除いても包囲可能な敵を撃てる
##   → 損耗が最大のその敵へ最大間合い
## 4 攻撃射程内に stack 条件を満たさない包囲可能な敵 → 損耗が最大の敵を攻撃
## 5 スキル射程内に stack 条件を満たす包囲可能な対象 → 損耗が最大の対象にスキル
## 6 攻撃射程内に包囲可能な敵 → 損耗が最大の敵を攻撃
## 7/8 sight 範囲内の手負いへ 最大前進 → 見込前進
## 9/10 移動距離／地形距離が最小の敵へ 最大前進 → 見込前進
## 11 盤上に攻撃できる敵 → 盤上距離が最小の敵へ直線寄せ
##
## 1・3 で下がった駒は包囲の頭数から外れる（隣接しなくなる）。包囲は間接にも効くので、囲むのは
## 近接の駒に任せ、間接の駒は外から撃つという住み分けになる。3 が「自分を除いても包囲可能」を
## 見るのはそのため＝数えたまま下がると、動いた先で包囲が崩れて 4・6 が不成立になる。
##
## 拠点は取らない（占領の行を持たない）。占領兵を混ぜても拠点へは向かわない。

func id() -> String:
	return "swarm"

func action(state: BattleState, u: Unit) -> AiAction:
	var move_field := AiDistance.move_cost_field(state, u.id, u.pos)
	var wounded := pick.wounded_of(state, u, move_field)
	if wounded != null:
		var standoff := rows.standoff_row(state, u, wounded)
		if standoff != null:
			return standoff
	var in_range := rows.attack_targets(state, u)
	if wounded != null and wounded.id in in_range:
		return AiAction.attack(u.id, wounded.id)
	# 3 自分を除いても包囲可能な敵へ最大間合い
	var pinned := rows.surroundable_standoff_target(state, u)
	if pinned != null:
		var back := rows.standoff_row(state, u, pinned)
		if back != null:
			return back
	var kind := pick.skill_kind_of(state, u)
	var surroundable: Array[int] = []
	var stacked: Array[int] = []  # stack 条件を満たさない＝もう重ねる価値がない相手
	for id in in_range:
		var t := state.unit_by_id(id)
		if not pick.surround_able(state, u, t):
			continue
		surroundable.append(id)
		if not pick.stack_passes(state, u, kind, t):
			stacked.append(id)
	if not stacked.is_empty():
		return AiAction.attack(u.id, pick.most_damaged_id(state, u, stacked))
	var row := rows.skill_row(state, u, AiPick.PICK_DAMAGED, true)
	if row != null:
		return row
	if not surroundable.is_empty():
		return AiAction.attack(u.id, pick.most_damaged_id(state, u, surroundable))
	if not rows.can_advance(state, u):
		return null
	# 7/8 手負いへ。sight 範囲内に居るときだけ（選び終えた1体が範囲に入っているかを見る）。
	if wounded != null and pick.in_sight(state, u, wounded):
		var cells := state.attack_cells(u.id, wounded.id)
		if AiDistance.min_cost_in(move_field, cells) < BattleState.UNREACHABLE:
			return rows.advance(state, u, AiDistance.move_cost_field(state, u.id, wounded.pos), cells)
		if AiDistance.terrain_distance(state, u.id, cells) < BattleState.UNREACHABLE:
			return rows.advance(state, u, AiDistance.terrain_cost_field(state, u.id, wounded.pos), cells)
	return rows.advance_to_nearest_enemy(state, u)
