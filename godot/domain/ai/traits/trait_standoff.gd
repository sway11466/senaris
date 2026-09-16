extends AiTrait
class_name TraitStandoff
## standoff（睨み合い）の行動ルール。先手を取れる距離まで詰めて、そこを保つ。詳細 → doc/gdd/ai.md standoff
## 1 占領兵で移動範囲に自陣営以外の拠点 → 盤上距離が最小の拠点へ移動して占領
## 2 スキル射程内に stack 条件を満たす対象 → 盤上距離が最小の対象にスキル
## 3〜6 攻撃射程内に敵 → 空敵を優先し、次に仕留められる敵、次に反撃されない敵を優先し、
##   その中で戦果（減らせる兵数）が最大の敵を攻撃（同値は盤上距離が最小）
## 7 移動距離が測れる敵 → 移動距離が最小の敵へ間合取り
## 8 地形距離が測れる敵 → 地形距離が最小の敵へ見込前進
## 9 盤上に攻撃できる敵 → 盤上距離が最小の敵へ直線寄せ
##
## 移動先は脅威圏の外のマスに限る（1 占領を除く）。7〜9 はどれもこの制約の中で行き先を選ぶ。
## 3〜6 を 7 より上に置くのは、間合いに入ってきた敵を撃つのがこの特性の目的だから。
## 最後の物差しが盤上距離でなく戦果なのは、反撃を受けない位置を保って削り続けるのが
## この特性の稼ぎ方で、近さそのものに意味が無いため。
## 最大間合いの行は持たない＝間合取りが詰めると下がるの両方を兼ねる。

func id() -> String:
	return "standoff"

func action(state: BattleState, u: Unit) -> AiAction:
	var row := rows.capture_row(state, u)
	if row != null:
		return row
	row = rows.skill_row(state, u, AiPick.PICK_NEAR)
	if row != null:
		return row
	var in_range := rows.attack_targets(state, u)
	if not in_range.is_empty():
		var ids := pick.air_first(pick.air_prey(state, u), in_range)
		ids = pick.killable_first(state, u, ids)
		return AiAction.attack(u.handle, pick.most_gain_id(state, u, ids))
	return _spacing_advance(state, u)

## standoff の移動（7〜9）。行き先は脅威圏の外に限り、外に1マスも無ければ動かない。
## 隣接されて撃てない駒（min_range≥2）はここで脅威圏の外へ出る。移動後にもう一度表を上から
## 当てるので、同じ手番のうちに 3〜6 が撃つ。
func _spacing_advance(state: BattleState, u: Unit) -> AiAction:
	if not rows.can_advance(state, u):
		return null
	var enemies := pick.attackable_enemies(state, u)
	if enemies.is_empty():
		return null
	var safe := rows.safe_cells(state, u)
	if safe.is_empty():
		return null
	var move_field := AiDistance.move_cost_field(state, u.handle, u.pos)
	var target := pick.nearest_target(state, u, enemies, move_field)
	if target != null:
		return rows.spacing_step(state, u, safe, AiDistance.move_cost_field(state, u.handle, target.pos),
			state.attack_cells(u.handle, target.handle))
	target = pick.nearest_target(state, u, enemies, AiDistance.terrain_cost_field(state, u.handle, u.pos))
	if target != null:
		return rows.advance(state, u, AiDistance.terrain_cost_field(state, u.handle, target.pos),
			state.attack_cells(u.handle, target.handle), safe)
	return rows.advance_straight(state, u, pick.nearest_unit_by_board(u.pos, enemies).pos, safe)
