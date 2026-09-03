extends RefCounted
class_name Victory
## 勝敗判定（純ロジック・読み取り専用）。state を引数に取る static ヘルパー。詳細 → doc/gdd/map.md
##
## 敗北を優先する（自軍消滅／自軍本拠地の喪失）。相討ち消滅も負け。
## 消滅＝盤上0 かつ 復帰手段なし（案B）。勝利は 殲滅（常に有効）＋ victory_conditions のいずれか（OR）。
##
## 決着の3値（ONGOING/PLAYER_WIN/PLAYER_LOSS）は BattleState が持つ＝セーブ・呼び出し側の参照名を変えない。
## 「復帰手段があるか」（has_reinforcement）も BattleState に残す＝駐留の可否（can_enter_base_at）と共有するため。

## 決着結果。敗北を優先（自軍消滅／自軍本拠地の喪失／敗北条件）。相討ち消滅も負け。
static func outcome(state: BattleState) -> int:
	if state.team_unit_count(0) == 0 and not state.has_reinforcement(0):
		return BattleState.PLAYER_LOSS
	if _own_hq_lost(state):
		return BattleState.PLAYER_LOSS  # 味方本拠地を奪われたら敗北（hq を置いたステージだけ効く）
	for c in state.defeat_conditions:
		if defeat_condition_met(state, c):
			return BattleState.PLAYER_LOSS
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
		"defeat_unit":  # ボス撃破＝名指し(actor)の駒が撃破済み
			return state.is_actor_defeated(String(c.get("actor", "")))
		"capture_hq":   # 本拠地占領＝敵 native の hq をすべて自軍が保持（hq が無ければ不成立）
			return _enemy_hq_all_captured(state)
	return false

## 敗北条件1件の判定。未知の type は満たさない扱い（前方互換）。
## 敗北条件タイプを足すときは、ここに分岐を1つと判定関数を1つ足す（BattleState は触らない）。
## 本拠地の喪失（_own_hq_lost）とは別軸＝あちらは hq の常時ルール、こちらはステージが名指しする守り物。
##
## 1件が複数の対象を持ち、その中は AND＝すべて失って初めて成立。条件どうしは OR（outcome のループ）。
## 「AもBも失ったら負け」は1件に2つ、「AかBを失ったら負け」は1つずつ2件、と書き分ける。
static func defeat_condition_met(state: BattleState, c: Dictionary) -> bool:
	match String(c.get("type", "")):
		"lose_base":  # 名指しした拠点をすべて敵に取られる（1つでも保持していれば不成立。奪還で解消）
			return _all_bases_taken(state, c.get("bases"))
		"lose_unit":  # 護衛対象をすべて失う（勝利側の defeat_unit と対）
			return _all_actors_defeated(state, c.get("actors"))
	return false

## 指定した拠点がすべて敵の手に落ちているか。対象が空なら false（空指定で即敗北にしない）。
## 盤に無い座標は「まだ失っていない」扱い＝不成立（作者の指定ミスで遊べなくならない）。
static func _all_bases_taken(state: BattleState, targets: Variant) -> bool:
	if typeof(targets) != TYPE_ARRAY or (targets as Array).is_empty():
		return false
	for t in targets:
		if typeof(t) != TYPE_DICTIONARY:
			return false
		if not _base_taken_by_enemy(state, int(t.get("col", -1)), int(t.get("row", -1))):
			return false
	return true

## 名指し(actor)した駒をすべて失っているか。対象が空なら false（空指定で即敗北にしない）。
static func _all_actors_defeated(state: BattleState, actors: Variant) -> bool:
	if typeof(actors) != TYPE_ARRAY or (actors as Array).is_empty():
		return false
	for a in actors:
		if not state.is_actor_defeated(String(a)):
			return false
	return true

## 指定マスの拠点が敵陣営の所属になっているか。拠点が無いマスは false（作者の指定ミスで即敗北にしない）。
static func _base_taken_by_enemy(state: BattleState, col: int, row: int) -> bool:
	if col < 0 or row < 0:
		return false
	var b := state.base_at(Hex.offset_to_axial(col, row))
	return b != null and b.team > 0

## 自軍の本拠地（hq:"player"）が敵の手に落ちているか。hq が無いステージでは常に false。
static func _own_hq_lost(state: BattleState) -> bool:
	for b in state.bases():
		if b.is_hq_of(0) and b.team != 0:
			return true
	return false

## 敵の本拠地（hq:"enemy"）がすべて自軍所属になっているか。該当 hq が1つも無ければ false（空勝ち防止）。
static func _enemy_hq_all_captured(state: BattleState) -> bool:
	var found := false
	for b in state.bases():
		if b.is_hq_of(1):
			found = true
			if b.team != 0:
				return false
	return found
