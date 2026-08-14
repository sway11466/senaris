extends Node
class_name MatchController
## ゲーム進行のまとめ役（Application 層）。
## Presentation からコマンドを受け、domain(BattleState) を呼び、結果をシグナルで上へ返す。
## 状態の真実は BattleState に置き、ここは進行管理のみ。

## 上り: 純データのシグナルで Presentation に通知する。
## path は from→to の通過ヘックス列（両端含む）＝移動アニメの経路。
## 経路を引けなかった場合は空＝受け手は瞬間移動にフォールバックする（盤の状態には影響しない）。
signal unit_moved(unit_id: int, from: Vector2i, to: Vector2i, path: Array[Vector2i])
signal move_rejected(unit_id: int, to: Vector2i)
signal unit_attacked(attacker_id: int, target_id: int, damage: int, killed: bool)
signal combat_resolved(detail: Dictionary)  # 戦闘結果ビュー用の内訳（攻防の導出・損害）
signal formation_resolved(result: Dictionary)  # 陣形スキルの解決結果（着弾ごとの損害・撃破）
signal unit_deployed(unit_id: int, base_hex: Vector2i, to: Vector2i)
signal unit_unloaded(unit_id: int, transport_id: int, to: Vector2i)
signal unit_entered_base(unit_id: int, base_hex: Vector2i)
signal base_captured(base_hex: Vector2i, team: int)  # 拠点の所属が変わった＝占領成立
signal unit_stood(unit_id: int)  # 「待機」＝盤は動かないが行動終了（見た目を暗くする）
signal unit_died(unit_id: int)
signal turn_changed(team: int, turn_number: int)
signal event_fired(info: Dictionary)  # イベント（増援）が起きた＝{ label, dialogue }。台本そのものは presentation が持つ
signal battle_finished(outcome: int)  # BattleState.ONGOING/PLAYER_WIN/PLAYER_LOSS

var state: BattleState
var _finished := false

## AI設定（ステージごとに差し替え可能）。ai_brain が null の陣営は手動操作（ホットシート）。
var ai_team := 1
var ai_brain: AiBrain = null
var ai_delay := 0.35  # AIの各手を見せるための間（秒）
var combat_pace := Callable()  # AIターンで戦闘演出の完了を待つフック（presentation が注入）。空なら待たない
var move_pace := Callable()    # AIターンで移動アニメの完了を待つフック（同上）。空なら待たない
var focus_pace := Callable()   # AIターンで次の行動主体(hex)をカメラに収めるフック（同上）。空なら何もしない
var turn_start_pace := Callable()  # AIターンの頭で一拍置くフック（同上・ターンバナー）。空なら待たない

func setup(p_state: BattleState) -> void:
	state = p_state

## 現在のターンが AI に委ねられているか（presentation の入力ロック判定に使う）。
func is_ai_turn() -> bool:
	return ai_brain != null and state.current_team == ai_team

## 索敵範囲の可視化用：unit の検知半径（待機中の見張りなら sight 半径・他は0）。AI無しの陣営は0。
func detection_radius(unit: Unit) -> int:
	return ai_brain.detection_radius(state, unit) if ai_brain != null else 0

## 下りコマンドの処理。成功すれば状態を更新し unit_moved を発行。
## 経路は move_unit より前に引く（移動後は位置と消費が変わり、同じ経路を復元できない）。
func execute(cmd: MoveCommand) -> bool:
	if _finished:
		return false
	var u := state.unit_by_id(cmd.unit_id)
	if u == null:
		return false
	var from := u.pos
	var path := state.path_to(cmd.unit_id, cmd.to)
	var before := _base_team_at(cmd.to)
	if state.move_unit(cmd.unit_id, cmd.to):
		unit_moved.emit(cmd.unit_id, from, cmd.to, path)
		_emit_if_captured(cmd.to, before)
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
	var before := _base_team_at(cmd.to)
	if state.unload(cmd.transport_id, cmd.index, cmd.to):
		var u := state.unit_at(cmd.to)
		unit_unloaded.emit(u.id if u != null else -1, cmd.transport_id, cmd.to)
		_emit_if_captured(cmd.to, before)
		_check_finished()
		return true
	return false

## 占領の検出。domain は所属を書き換えるだけでシグナルを持たない（_try_capture は移動・降車の
## 内側で静かに起きる）ため、行き先の拠点の所属を操作の前後で見比べて発火させる。
## 拠点が無いマスは NO_BASE。Base.NEUTRAL（中立）は -1 なので、それとは別の値にする＝
## 同じにすると「中立拠点を占領した」が「拠点が無い所へ動いた」と見分けられなくなる。
const NO_BASE := -99

func _base_team_at(hex: Vector2i) -> int:
	var b := state.base_at(hex)
	return b.team if b != null else NO_BASE

## before と変わっていれば占領。中立→自軍も敵→自軍も同じ扱い（どちらも盤の支配が動いた）。
func _emit_if_captured(hex: Vector2i, before: int) -> void:
	var after := _base_team_at(hex)
	if after != NO_BASE and after != before:
		base_captured.emit(hex, after)

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

## ターンを終了して次の陣営へ渡す。AIのターンに入ったら自動で思考を回す。
func end_turn() -> void:
	if _finished:
		return
	state.end_turn()
	turn_changed.emit(state.current_team, state.turn_number)
	_check_finished()  # ターン跨ぎで決着が付くことがある（ターン制限＝時間切れ敗北）
	# 増援は end_turn の内側で盤に出る＝ターン板・盤の同期が済んでから知らせる（会話は駒が見えてから）。
	# 決着していれば知らせない（戦果票と会話が重なる）。
	if not _finished:
		_announce_fired_events()
	if not _finished and is_ai_turn():
		run_ai_turn()  # async（fire-and-forget）

## このターンに起きたイベントを1件ずつ上へ流す。渡すのは素データ（label・台本キー・カメラ指定と
## その行き先）だけ＝何を見せるかは presentation が決める。hex は実際に駒が出た場所の先頭
## （置けずに1体も出なければ Vector2i.MAX）。詳細 → doc/gdd/map.md イベント
func _announce_fired_events() -> void:
	for e in state.last_fired_events:
		var placed: Array = e.get("placed", [])
		event_fired.emit({
			"label": String(e.get("label", "")),
			"dialogue": String(e.get("dialogue", "")),
			"focus": bool(e.get("focus", false)),
			"hex": placed[0] if not placed.is_empty() else Vector2i.MAX,
		})

## AIのターンを実行。next_action が尽きるまで1手ずつ実行し、最後にターンを返す。
func run_ai_turn() -> void:
	# ターンの頭で一拍置く（ターンバナーの表示ぶん）。1手も動かないターンでもここは通るので、
	# 敵のターンが1フレームも見えずに戻る事態を防ぐ。詳細 → doc/gdd/uiux.md
	if not _finished and turn_start_pace.is_valid():
		await turn_start_pace.call()
	while not _finished:
		var action := ai_brain.next_action(state, state.current_team)
		if action == null:
			break
		# 行動を見せる前に、その主体をカメラに収める（画面外なら寄せて待つ・画面内なら即返る）。
		# 「敵が何をしたか」を毎手見せるため＝いつの間にか位置が変わる事態を防ぐ（doc/gdd/uiux.md）。
		if not _finished and focus_pace.is_valid():
			await focus_pace.call(_action_focus_hex(action))
		var shown_combat := _apply_ai_action(action)
		# 移動アニメの完了を待つ＝駒が歩き切ってから次の手へ（手が重ならず追える）。
		# アニメが無ければ即戻る。攻撃より先＝移動→攻撃の順に見せる。
		if not _finished and move_pace.is_valid():
			await move_pace.call()
		# 攻撃なら演出の完了を待つ＝盤に戻ってから次の手へ（プレイヤーが流れを追える）。
		if shown_combat and not _finished and combat_pace.is_valid():
			await combat_pace.call()
		if is_inside_tree() and not _finished:  # 各手の間を置いて見せる
			await get_tree().create_timer(ai_delay).timeout
	if not _finished:
		end_turn()

## その1手でカメラが見るべき hex。移動・攻撃は主体の現在位置（歩き出し・攻撃元を見せる）、
## 出撃は駒が現れる出撃先。行動を適用する前に呼ぶ＝主体はまだ動いていない。
func _action_focus_hex(action: AiAction) -> Vector2i:
	match action.kind:
		AiAction.Kind.MOVE, AiAction.Kind.ATTACK, AiAction.Kind.SKILL:
			var u := state.unit_by_id(action.unit_id)
			return u.pos if u != null else action.to
		_:  # DEPLOY / UNLOAD＝駒が現れるマスを見せる
			return action.to

## 1手を適用する。演出が出た（＝攻撃かスキルが成立した）なら true＝呼び出し側が完了を待つ。
func _apply_ai_action(action: AiAction) -> bool:
	match action.kind:
		AiAction.Kind.MOVE:
			execute(MoveCommand.new(action.unit_id, action.to))
		AiAction.Kind.ATTACK:
			return execute_attack(AttackCommand.new(action.unit_id, action.target_id))
		AiAction.Kind.DEPLOY:
			execute_deploy(DeployCommand.new(action.base_hex, action.garrison_index, action.to))
		AiAction.Kind.UNLOAD:
			execute_unload(UnloadCommand.new(action.unit_id, action.passenger_index, action.to))
		AiAction.Kind.SKILL:
			# 効果対象が1体のユニットスキルは演出シーンに乗る（doc/tech/combat_scene.md）ので、
			# 攻撃と同じく閉じるまで待たせる。演出が出ないレシピなら pace 側が即返る。
			return execute_formation(FormationCommand.new(action.option, action.to))
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
	if state.unit_by_id(unit_id) == null:  # 盤に居ない駒＝行動終了させる対象が無い
		return
	state.set_done(unit_id)
	unit_stood.emit(unit_id)

## デバッグ: 盤上の敵駒（team 1）を全て除去する。決着は既存の判定に委ねる＝殲滅で勝利になる
## ステージならそのまま通常の勝利フロー（戦果票→outro→完走イラスト）へ流れる。敵拠点に控えが
## 残るステージでは勝利にならない（盤上0体かつ復帰手段なしが勝利条件）。詳細 → doc/gdd/uiux.md
func wipe_enemies() -> void:
	if _finished:
		return
	for u in state.units().duplicate():  # 除去で盤上リストが縮む＝複製を回す
		if u.team != 1:
			continue
		if state.remove_unit(u.id):
			unit_died.emit(u.id)  # 撃破と同じ経路で盤から駒を消す
	_check_finished()
