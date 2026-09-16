extends AiTrait
class_name TraitPredator
## predator（弱者狙い）の行動ルール。前衛を避けて柔らかい敵へ回り込む。詳細 → doc/gdd/ai.md predator
## 1 占領／2 防御力が最小の対象にスキル
## 3 間接攻撃できる駒で、いま仕留められる敵がおらず狙う獲物を撃てる → 狙う獲物へ最大間合い
## 4 攻撃射程内に獲物 → 攻撃後の残兵が最小となる獲物を攻撃
## 5 攻撃射程内に仕留められる敵 → 反撃されない敵を優先し、その中で盤上距離が最小の敵を攻撃
## 6〜9 狙う獲物へ 回り込み → 最大前進 → 見込前進 → 直線寄せ
##
## 狙う獲物＝ sight 範囲内の獲物のうち移動距離が最小のもの（測れる獲物がいなければ盤上距離が最小）。
## 3 と 6〜9 はどれもこの1体へ向かう＝行の間で行き先が入れ替わらない。sight の判定は毎ターン行う＝
## 起動後に獲物が視線から消えたら前進だけ止まる（攻撃とスキルは続く）。
##
## 3 が「仕留められる敵がいない」を条件に持つのは、倒しきれる相手から下がらないため。倒しても
## 反撃は受ける（同時解決）が、獲物を1体減らす価値のほうが大きい。
##
## 行動開始条件＝視線距離が sight 以内に獲物。

func id() -> String:
	return "predator"

func engages_by_sight() -> bool:
	return true

func starts_engaged(state: BattleState, u: Unit) -> bool:
	return not pick.prey_in_sight(state, u).is_empty()

func base_starts_engaged(state: BattleState, b: Base, budget: int) -> bool:
	return not pick.base_prey_in_sight(state, b, budget).is_empty()

func action(state: BattleState, u: Unit) -> AiAction:
	var row := rows.capture_row(state, u)
	if row != null:
		return row
	row = rows.skill_row(state, u, AiPick.PICK_WEAK)
	if row != null:
		return row
	var in_range := rows.attack_targets(state, u)
	var prey_ids := AiPick.ids_of(pick.prey_of(state, u))
	var prey_in_range: Array[int] = []
	var killable: Array[int] = []
	for id in in_range:
		if id in prey_ids:
			prey_in_range.append(id)
		if pick.can_kill_in_one_hit(state, u, state.unit_by_handle(id)):
			killable.append(id)
	var can_move := rows.can_advance(state, u)
	var move_field := AiDistance.move_cost_field(state, u.handle, u.pos) if can_move else {}
	var target := pick.hunted_prey(state, u, move_field) if can_move else null
	if killable.is_empty() and target != null:
		row = rows.standoff_row(state, u, target)
		if row != null:
			return row
	if not prey_in_range.is_empty():
		return AiAction.attack(u.handle, pick.fewest_left_id(state, u, prey_in_range))
	if not killable.is_empty():
		return AiAction.attack(u.handle, pick.safest_id(state, u, killable))
	if not can_move or target == null:
		return null  # 移動を使い切った／sight 範囲内に獲物がいない＝前進はしない
	var cells := state.attack_cells(u.handle, target.handle)
	# 6 回り込み（迂回距離）。標的自身のZOCは外して測る＝外さないと隣へ入れず必ず測れない。
	# 表は標的から流して1枚だけ作り、自分のマスが載っているかで「測れる」を見る（両向きで一致する）。
	var detour_field := AiDistance.detour_cost_field_to(state, u.handle, target.pos, target.handle)
	if detour_field.has(u.pos):
		return rows.advance(state, u, detour_field, cells)
	if AiDistance.min_cost_in(move_field, cells) < BattleState.UNREACHABLE:
		return rows.advance(state, u, AiDistance.move_cost_field(state, u.handle, target.pos), cells)
	if AiDistance.terrain_distance(state, u.handle, cells) < BattleState.UNREACHABLE:
		return rows.advance(state, u, AiDistance.terrain_cost_field(state, u.handle, target.pos), cells)
	return rows.advance_straight(state, u, target.pos)
