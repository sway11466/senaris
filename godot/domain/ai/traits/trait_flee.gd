extends AiTrait
class_name TraitFlee
## flee（逃走）の行動ルール。戦わずに拠点へ走る。詳細 → doc/gdd/ai.md flee
## 1 占領兵で、移動範囲に自陣営以外の拠点 → 占領
## 2 損耗 ≧ retreat で、自陣営の拠点hexにいる → 拠点に入る
## 3 損耗 ≧ retreat で、迂回距離が測れる自陣営拠点 → 自陣営拠点へ回り込み
## 4 損耗 < retreat で、迂回距離が測れる敵拠点 → 敵拠点へ回り込み

func id() -> String:
	return "flee"

func action(state: BattleState, u: Unit) -> AiAction:
	var row := rows.capture_row(state, u)
	if row != null:
		return row
	# #2 自陣営の拠点hexにいる → 入る
	row = enter_base_row(state, u)
	if row != null:
		return row
	var damaged := AiPick.damage_percent(u) >= params.retreat_percent_of(state, u)
	if damaged:
		# #3 自陣営拠点へ回り込み
		if rows.can_advance(state, u):
			return rows.detour_to_base(state, u, pick.friendly_base_hexes(state, u))
	else:
		# #4 敵拠点へ回り込み
		if rows.can_advance(state, u):
			return rows.detour_to_base(state, u, pick.hostile_base_hexes(state, u))
	return null

func enter_base_row(state: BattleState, u: Unit) -> AiAction:
	return rows.enter_base_row(state, u)
