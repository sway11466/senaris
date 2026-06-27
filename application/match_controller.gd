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
signal battle_finished(outcome: int)  # BattleState.ONGOING/PLAYER_WIN/PLAYER_LOSS

var state: BattleState
var _finished := false

## AI設定（ステージごとに差し替え可能）。ai_brain が null の陣営は手動操作（ホットシート）。
var ai_team := 1
var ai_brain: AiBrain = null
var ai_delay := 0.35  # AIの各手を見せるための間（秒）

func setup(p_state: BattleState) -> void:
	state = p_state

## 現在の手番が AI に委ねられているか（presentation の入力ロック判定に使う）。
func is_ai_turn() -> bool:
	return ai_brain != null and state.current_team == ai_team

## 下りコマンドの処理。成功すれば状態を更新し unit_moved を発行。
func execute(cmd: MoveCommand) -> bool:
	if _finished:
		return false
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
	if _finished:
		return false
	var result := state.attack(cmd.attacker_id, cmd.target_id)
	if result.is_empty():
		return false
	unit_attacked.emit(cmd.attacker_id, cmd.target_id, result["damage"], result["killed"])
	if result["killed"]:
		unit_died.emit(cmd.target_id)
	if result["attacker_killed"]:  # 反撃で攻撃側も倒れうる
		unit_died.emit(cmd.attacker_id)
	_check_finished()
	return true

## 手番を終了して次の陣営へ渡す。AIの手番に入ったら自動で思考を回す。
func end_turn() -> void:
	if _finished:
		return
	state.end_turn()
	turn_changed.emit(state.current_team, state.turn_number)
	if is_ai_turn():
		run_ai_turn()  # async（fire-and-forget）

## AIの手番を実行。next_action が尽きるまで1手ずつ実行し、最後に手番を返す。
func run_ai_turn() -> void:
	while not _finished:
		var action := ai_brain.next_action(state, state.current_team)
		if action == null:
			break
		_apply_ai_action(action)
		if is_inside_tree():  # 各手の間を置いて見せる
			await get_tree().create_timer(ai_delay).timeout
	if not _finished:
		end_turn()

func _apply_ai_action(action: AiAction) -> void:
	match action.kind:
		AiAction.Kind.MOVE:
			execute(MoveCommand.new(action.unit_id, action.to))
		AiAction.Kind.ATTACK:
			execute_attack(AttackCommand.new(action.unit_id, action.target_id))

func _check_finished() -> void:
	if not _finished and state.is_over():
		_finished = true
		battle_finished.emit(state.outcome())

## 表示用の問い合わせ（状態は変えない）。
func reachable_for(unit_id: int) -> Array[Vector2i]:
	return state.reachable(unit_id)

func attack_targets_for(unit_id: int) -> Array[int]:
	return state.attack_targets(unit_id)
