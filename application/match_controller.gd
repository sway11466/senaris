extends Node
class_name MatchController
## ゲーム進行のまとめ役（Application 層）。
## Presentation からコマンドを受け、domain(BattleState) を呼び、結果をシグナルで上へ返す。
## 状態の真実は BattleState に置き、ここは進行管理のみ。

## 上り: 純データのシグナルで Presentation に通知する。
signal unit_moved(unit_id: int, from: Vector2i, to: Vector2i)
signal move_rejected(unit_id: int, to: Vector2i)
signal unit_attacked(attacker_id: int, target_id: int, damage: int, killed: bool)
signal combat_resolved(detail: Dictionary)  # 戦闘結果ビュー用の内訳（攻防の導出・損害）
signal formation_resolved(result: Dictionary)  # 陣形スキルの解決結果（着弾ごとの損害・撃破）
signal unit_deployed(unit_id: int, base_hex: Vector2i, to: Vector2i)
signal unit_unloaded(unit_id: int, transport_id: int, to: Vector2i)
signal unit_entered_base(unit_id: int, base_hex: Vector2i)
signal unit_died(unit_id: int)
signal turn_changed(team: int, turn_number: int)
signal battle_finished(outcome: int)  # BattleState.ONGOING/PLAYER_WIN/PLAYER_LOSS

var state: BattleState
var _finished := false

## AI設定（ステージごとに差し替え可能）。ai_brain が null の陣営は手動操作（ホットシート）。
var ai_team := 1
var ai_brain: AiBrain = null
var ai_delay := 0.35  # AIの各手を見せるための間（秒）
var combat_pace := Callable()  # AI手番で戦闘演出の完了を待つフック（presentation が注入）。空なら待たない

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
		_check_finished()  # 移動＝占領が起きうる（本拠地の占領/喪失はこの瞬間に決着する）
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
	combat_resolved.emit(result["detail"])  # unit_attacked の後＝盤の選択解除より後に結果表示
	_check_finished()
	return true

## 下り: 陣形スキルの処理。成功すれば盤に適用し formation_resolved（＋撃破ごとに unit_died）を発行。
func execute_formation(cmd: FormationCommand) -> bool:
	if _finished:
		return false
	var result := state.resolve_formation(cmd.option, cmd.target)
	if result.is_empty():
		return false
	for r in result["results"]:
		if bool(r["killed"]):
			unit_died.emit(int(r["target_id"]))
	formation_resolved.emit(result)
	_check_finished()  # 陣形でボスを撃破しうる（勝利条件）
	return true

## 下り: 出撃コマンドの処理。成功すれば garrison から駒を出し unit_deployed を発行。
## 出撃先が輸送のマスなら直接搭乗（盤上には出ない）＝unit_at では引けないため id は事前に取る。
func execute_deploy(cmd: DeployCommand) -> bool:
	if _finished:
		return false
	var b := state.base_at(cmd.base_hex)
	var uid := -1
	if b != null and cmd.garrison_index >= 0 and cmd.garrison_index < b.garrison.size():
		uid = (b.garrison[cmd.garrison_index] as Unit).id
	if state.deploy(cmd.base_hex, cmd.garrison_index, cmd.to):
		unit_deployed.emit(uid, cmd.base_hex, cmd.to)
		return true
	return false

## 表示用: base_hex の拠点から出撃できるhex一覧（状態は変えない）。
## garrison_index を渡すと、その駒が乗れる隣接輸送のマスも含む（省略時はいずれかの控えが乗れるもの）。
func deploy_cells_for(base_hex: Vector2i, garrison_index := -1) -> Array[Vector2i]:
	return state.deploy_cells(base_hex, garrison_index)

## 下り: 降車コマンドの処理。成功すれば unit_unloaded を発行（降車＝占領が起きうるので決着チェック）。
func execute_unload(cmd: UnloadCommand) -> bool:
	if _finished:
		return false
	if state.unload(cmd.transport_id, cmd.index, cmd.to):
		var u := state.unit_at(cmd.to)
		unit_unloaded.emit(u.id if u != null else -1, cmd.transport_id, cmd.to)
		_check_finished()
		return true
	return false

## 表示用: 輸送 transport_id の搭乗駒 index の降車先候補（状態は変えない）。
func unload_cells_for(transport_id: int, index: int) -> Array[Vector2i]:
	return state.unload_cells(transport_id, index)

## 表示用: 搭乗駒が from_hex に降りたと仮定したときの攻撃対象（降車確認メニュー用）。
func unload_attack_targets_for(transport_id: int, index: int, from_hex: Vector2i) -> Array[int]:
	return state.unload_attack_targets(transport_id, index, from_hex)

## 下り: 拠点に「入る」（駐留＝回復）。成功すれば unit_entered_base を発行。
func enter_base(unit_id: int) -> bool:
	if _finished:
		return false
	var u := state.unit_by_id(unit_id)
	if u == null:
		return false
	var hex := u.pos
	if state.enter_base(unit_id):
		unit_entered_base.emit(unit_id, hex)
		return true
	return false

## 手番を終了して次の陣営へ渡す。AIの手番に入ったら自動で思考を回す。
func end_turn() -> void:
	if _finished:
		return
	state.end_turn()
	turn_changed.emit(state.current_team, state.turn_number)
	_check_finished()  # ターン跨ぎで決着が付くことがある（ターン制限＝時間切れ敗北）
	if not _finished and is_ai_turn():
		run_ai_turn()  # async（fire-and-forget）

## AIの手番を実行。next_action が尽きるまで1手ずつ実行し、最後に手番を返す。
func run_ai_turn() -> void:
	while not _finished:
		var action := ai_brain.next_action(state, state.current_team)
		if action == null:
			break
		var shown_combat := _apply_ai_action(action)
		# 攻撃なら演出の完了を待つ＝盤に戻ってから次の手へ（プレイヤーが流れを追える）。
		if shown_combat and not _finished and combat_pace.is_valid():
			await combat_pace.call()
		if is_inside_tree() and not _finished:  # 各手の間を置いて見せる
			await get_tree().create_timer(ai_delay).timeout
	if not _finished:
		end_turn()

## 1手を適用する。戦闘演出が出た（＝攻撃が成立した）なら true。
func _apply_ai_action(action: AiAction) -> bool:
	match action.kind:
		AiAction.Kind.MOVE:
			execute(MoveCommand.new(action.unit_id, action.to))
		AiAction.Kind.ATTACK:
			return execute_attack(AttackCommand.new(action.unit_id, action.target_id))
		AiAction.Kind.DEPLOY:
			execute_deploy(DeployCommand.new(action.base_hex, action.garrison_index, action.to))
	return false

func _check_finished() -> void:
	if not _finished and state.is_over():
		_finished = true
		battle_finished.emit(state.outcome())

## 表示用の問い合わせ（状態は変えない）。
func reachable_for(unit_id: int) -> Array[Vector2i]:
	return state.reachable(unit_id)

func attack_targets_for(unit_id: int) -> Array[int]:
	return state.attack_targets(unit_id)

## 表示用: from_hex に居ると仮定したときの攻撃対象（コマンドメニューの「攻撃」可否判定）。
func attack_targets_from(unit_id: int, from_hex: Vector2i) -> Array[int]:
	return state.attack_targets_from(unit_id, from_hex)

## コマンドメニューの「待機」: そのユニットの行動をこのターン終了させる。
func stand(unit_id: int) -> void:
	if _finished:
		return
	state.set_done(unit_id)
