extends AiTrait
class_name TraitRaid
## raid（拠点攻略）の行動ルール。1/2 は突撃と同じで、11〜13 の行き先が敵ではなく拠点。
## 3 撃てる位置へずれる／4〜7 経路上の敵を殴る／8/9 降ろす（輸送ユニットだけに当たる）／
## 10 乗る（乗る側だけに当たる）。
## 4〜7 は空敵を優先し、次に仕留められる敵を優先し、その中で地形距離が最小（＝一番前で塞ぐ駒）。
## 仕留めを先に見るのは、削るだけでは道が開かないため＝一番前でなくても、いま消せる駒から消す。
## 拠点への距離は拠点hexそのものまで測る（拠点は攻撃の標的ではない）。
## 向かう拠点が盤上に無ければ待機する＝敵を追わない。詳細 → doc/gdd/ai.md raid

func id() -> String:
	return "raid"

func action(state: BattleState, u: Unit) -> AiAction:
	var row := rows.capture_row(state, u)
	if row != null:
		return row
	row = rows.skill_row(state, u, AiPick.PICK_NEAR)
	if row != null:
		return row
	# 3 撃てる位置へずれる（隣接されて撃てない射程2以上の駒を、撃てるマスへ置く行）
	row = rows.shift_to_shoot_row(state, u)
	if row != null:
		return row
	# 4〜7 経路上の敵を殴る（集合を絞ってから1体を選ぶ＝どける判定は集合ぜんぶで見る）
	var blockers := rows.blocking_enemy_ids(state, u, rows.attack_targets(state, u))
	if not blockers.is_empty():
		var ids := pick.air_first(pick.air_prey(state, u), blockers)
		ids = pick.killable_first(state, u, ids)
		return AiAction.attack(u.handle, rows.frontmost_blocker_id(state, u, ids))
	# 8/9 降ろす（乗員を持つ駒＝輸送ユニットにしか当たらない）
	row = rows.unload_now_row(state, u)
	if row != null:
		return row
	row = rows.unload_move_row(state, u)
	if row != null:
		return row
	# 10 乗る（同じ部隊の輸送ユニットへ。便乗のほうが早いときだけ）
	row = rows.board_row(state, u)
	if row != null:
		return row
	if not rows.can_advance(state, u):
		return null
	var goals := pick.hostile_base_hexes(state, u)
	if goals.is_empty():
		return null
	# 11 移動距離／12 地形距離。測れた時点でその行が成立＝縮むマスが無ければ現在地に留まる。
	var move_field := AiDistance.move_cost_field(state, u.handle, u.pos)
	var goal := pick.nearest_hex_in(move_field, goals)
	if goal != AiPick.NO_HEX:
		return rows.advance(state, u, AiDistance.move_cost_field(state, u.handle, goal), [goal])
	var terrain_field := AiDistance.terrain_cost_field(state, u.handle, u.pos)
	goal = pick.nearest_hex_in(terrain_field, goals)
	if goal != AiPick.NO_HEX:
		return rows.advance(state, u, AiDistance.terrain_cost_field(state, u.handle, goal), [goal])
	# 13 盤上に自陣営以外の拠点がある → 盤上距離が最小の拠点へ直線寄せ
	return rows.advance_straight(state, u, pick.nearest_hex_by_board(u.pos, goals))

## 行動を終えた輸送ユニットでも降ろす行だけは見る＝降車は乗員の手番で、運んだそのターンに
## 降ろせる（doc/gdd/ai.md 輸送ユニット）。
func acts_when_done(u: Unit) -> bool:
	return AiRows.is_transport(u)

func done_action(state: BattleState, u: Unit) -> AiAction:
	return rows.unload_now_row(state, u)
