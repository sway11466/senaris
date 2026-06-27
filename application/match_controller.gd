extends Node
class_name MatchController
## ゲーム進行のまとめ役（Application 層）。
## Presentation からコマンドを受け、domain(BattleState) を呼び、結果をシグナルで上へ返す。
## 状態の真実は BattleState に置き、ここは進行管理のみ。

## 上り: 純データのシグナルで Presentation に通知する。
signal unit_moved(unit_id: int, from: Vector2i, to: Vector2i)
signal move_rejected(unit_id: int, to: Vector2i)
signal unit_attacked(attacker_id: int, target_id: int, damage: int, killed: bool)
signal unit_died(unit_id: int)
signal turn_changed(team: int, turn_number: int)

var state: BattleState

func setup(p_state: BattleState) -> void:
	state = p_state

## 下りコマンドの処理。成功すれば状態を更新し unit_moved を発行。
func execute(cmd: MoveCommand) -> bool:
	var u := state.unit_by_id(cmd.unit_id)
	if u == null:
		return false
	var from := u.pos
	if state.move_unit(cmd.unit_id, cmd.to):
		unit_moved.emit(cmd.unit_id, from, cmd.to)
		return true
	move_rejected.emit(cmd.unit_id, cmd.to)
	return false

## 下り: 攻撃コマンドの処理。成功すれば unit_attacked（撃破時は unit_died）を発行。
func execute_attack(cmd: AttackCommand) -> bool:
	var result := state.attack(cmd.attacker_id, cmd.target_id)
	if result.is_empty():
		return false
	unit_attacked.emit(cmd.attacker_id, cmd.target_id, result["damage"], result["killed"])
	if result["killed"]:
		unit_died.emit(cmd.target_id)
	if result["attacker_killed"]:  # 反撃で攻撃側も倒れうる
		unit_died.emit(cmd.attacker_id)
	return true

## 手番を終了して次の陣営へ渡す。
func end_turn() -> void:
	state.end_turn()
	turn_changed.emit(state.current_team, state.turn_number)

## 表示用の問い合わせ（状態は変えない）。
func reachable_for(unit_id: int) -> Array[Vector2i]:
	return state.reachable(unit_id)

func attack_targets_for(unit_id: int) -> Array[int]:
	return state.attack_targets(unit_id)
