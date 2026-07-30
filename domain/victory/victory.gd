extends RefCounted
class_name Victory
## 勝敗判定（純ロジック・読み取り専用）。state を引数に取る static ヘルパー。詳細 → doc/gdd/map.md
##
## 敗北を優先する（自軍消滅／自軍本拠地の喪失）。相討ち消滅も負け。
## 消滅＝盤上0 かつ 復帰手段なし（案B）。勝利は 殲滅（常に有効）＋ victory_conditions のいずれか（OR）。
##
## 決着の3値（ONGOING/PLAYER_WIN/PLAYER_LOSS）は BattleState が持つ＝セーブ・呼び出し側の参照名を変えない。
## 「復帰手段があるか」（has_reinforcement）も BattleState に残す＝駐留の可否（can_enter_base_at）と共有するため。

## 決着結果。敗北を優先（自軍消滅／自軍本拠地の喪失）。相討ち消滅も負け。
static func outcome(state: BattleState) -> int:
	if state.team_unit_count(0) == 0 and not state.has_reinforcement(0):
		return BattleState.PLAYER_LOSS
	if _own_hq_lost(state):
		return BattleState.PLAYER_LOSS  # 味方本拠地を奪われたら敗北（hq を置いたステージだけ効く）
	if state.team_unit_count(1) == 0 and not state.has_reinforcement(1):
		return BattleState.PLAYER_WIN
	for c in state.victory_conditions:
		if condition_met(state, c):
			return BattleState.PLAYER_WIN
	if state.turn_limit > 0 and state.turn_number > state.turn_limit:
		return BattleState.PLAYER_LOSS  # ターン制限超過＝時間切れ敗北（引き分けなし）。詳細 → doc/gdd/map.md
	return BattleState.ONGOING

static func is_over(state: BattleState) -> bool:
	return outcome(state) != BattleState.ONGOING

## 勝利条件1件の判定。未知の type は満たさない扱い（前方互換）。
## 勝利条件タイプを足すときは、ここに分岐を1つと判定関数を1つ足す（BattleState は触らない）。
static func condition_met(state: BattleState, c: Dictionary) -> bool:
	match String(c.get("type", "")):
		"defeat_unit":  # ボス撃破＝指定IDの駒が撃破済み
			return state.is_defeated(int(c.get("unit_id", -1)))
		"capture_hq":   # 本拠地占領＝敵 native の hq をすべて自軍が保持（hq が無ければ不成立）
			return _enemy_hq_all_captured(state)
	return false

## 自軍 native の本拠地（hq）が敵の手に落ちているか。hq が無いステージでは常に false。
static func _own_hq_lost(state: BattleState) -> bool:
	for b in state.bases():
		if b.is_hq() and b.native_team == 0 and b.team != 0:
			return true
	return false

## 敵 native の本拠地（hq）がすべて自軍所属になっているか。該当 hq が1つも無ければ false（空勝ち防止）。
static func _enemy_hq_all_captured(state: BattleState) -> bool:
	var found := false
	for b in state.bases():
		if b.is_hq() and b.native_team == 1:
			found = true
			if b.team != 0:
				return false
	return found
