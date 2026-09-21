extends Node
class_name MatchController
## ゲーム進行のまとめ役（Application 層）。
## Presentation からコマンドを受け、domain(BattleState) を呼び、結果をシグナルで上へ返す。
## 状態の真実は BattleState に置き、ここは進行管理のみ。

## 上り: 純データのシグナルで Presentation に通知する。
## path は from→to の通過ヘックス列（両端含む）＝移動アニメの経路。
## 経路を引けなかった場合は空＝受け手は瞬間移動にフォールバックする（盤の状態には影響しない）。
signal unit_moved(handle: int, from: Vector2i, to: Vector2i, path: Array[Vector2i])
signal move_rejected(handle: int, to: Vector2i)
signal unit_attacked(attacker_id: int, target_id: int, damage: int, killed: bool)
signal combat_resolved(result: AttackResult)  # 戦闘結果（スナップショット・攻防の内訳・損害）
signal formation_resolved(result: SkillResult)  # 陣形スキルの解決結果（着弾ごとの損害・撃破）
signal unit_deployed(handle: int, base_hex: Vector2i, to: Vector2i)
signal unit_unloaded(handle: int, transport_id: int, to: Vector2i)
signal unit_entered_base(handle: int, base_hex: Vector2i)
signal base_captured(base_hex: Vector2i, team: int)  # 拠点の所属が変わった＝占領成立
signal unit_stood(handle: int)  # 「待機」＝盤は動かないが行動終了（見た目を暗くする）
signal unit_died(handle: int)
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
var focus_pace := Callable()   # AIターンで見せたい hex の一覧（先頭＝行動主体）をカメラに収めるフック（同上）。空なら何もしない
var turn_start_pace := Callable()  # AIターンの頭で一拍置くフック（同上・ターンバナー）。空なら待たない
var dialogue_pace := Callable()  # AIターンで会話の読了を待つフック（同上）。空なら待たない

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
	var u := state.unit_by_handle(cmd.handle)
	if u == null:
		return false
	var from := u.pos
	var path := state.path_to(cmd.handle, cmd.to)
	var before := _base_team_at(cmd.to)
	if state.move_unit(cmd.handle, cmd.to):
		unit_moved.emit(cmd.handle, from, cmd.to, path)
		_emit_if_captured(cmd.to, before)
		_check_finished()  # 移動＝占領が起きうる（本拠地の占領/喪失はこの瞬間に決着する）
		return true
	move_rejected.emit(cmd.handle, cmd.to)
	return false

## 下り: 攻撃コマンドの処理。成功すれば unit_attacked（撃破時は unit_died）を発行。
func execute_attack(cmd: AttackCommand) -> bool:
	if _finished:
		return false
	var result := state.attack(cmd.attacker_id, cmd.target_id)
	if result == null:
		return false
	unit_attacked.emit(cmd.attacker_id, cmd.target_id, result.damage(), result.killed())
	if result.killed():
		unit_died.emit(cmd.target_id)
	if result.attacker_killed():  # 反撃で攻撃側も倒れうる
		unit_died.emit(cmd.attacker_id)
	combat_resolved.emit(result)  # unit_attacked の後＝盤の選択解除より後に結果表示
	_check_finished()
	return true

## 下り: 陣形スキルの処理。成功すれば盤に適用し formation_resolved（＋撃破ごとに unit_died）を発行。
func execute_formation(cmd: FormationCommand) -> bool:
	if _finished:
		return false
	var result := FormationResolver.resolve(state, cmd.option, cmd.target)
	if result == null:
		return false
	for h in result.hits:
		if h.killed:
			unit_died.emit(h.target_id)
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
		uid = (b.garrison[cmd.garrison_index] as Unit).handle
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
		unit_unloaded.emit(u.handle if u != null else -1, cmd.transport_id, cmd.to)
		_emit_if_captured(cmd.to, before)
		_check_finished()
		return true
	return false

## 敵ターンに占領で起きたイベントの控え（会話つきのぶん）。AI が動いている最中に盤を止めないよう、
## 1手の切れ目（run_ai_turn）まで持ち越してから流す。自軍のターンでは控えずその場で流す。
var _pending_events: Array = []

## 占領の検出。domain は所属を書き換えるだけでシグナルを持たない（_try_capture は移動・降車の
## 内側で静かに起きる）ため、行き先の拠点の所属を操作の前後で見比べて発火させる。
## 拠点が無いマスは NO_BASE。Base.NEUTRAL（中立）は -1 なので、それとは別の値にする＝
## 同じにすると「中立拠点を占領した」が「拠点が無い所へ動いた」と見分けられなくなる。
const NO_BASE := -99

func _base_team_at(hex: Vector2i) -> int:
	var b := state.base_at(hex)
	return b.team if b != null else NO_BASE

## before と変わっていれば占領。中立→自軍も敵→自軍も同じ扱い（どちらも盤の支配が動いた）。
## 占領を引き金にしたイベント（on: "capture"）もここで起こす。決着した占領では知らせない
## ＝戦果票と会話を重ねない（増援と同じ扱い。詳細 → doc/gdd/map.md イベント）。
func _emit_if_captured(hex: Vector2i, before: int) -> void:
	var after := _base_team_at(hex)
	if after == NO_BASE or after == before:
		return
	base_captured.emit(hex, after)
	var fired := state.fire_capture_events(hex, after)
	if state.is_over():
		return
	for e in fired:
		var info := _event_info(e, hex)
		if is_ai_turn():
			_pending_events.append(info)
		else:
			event_fired.emit(info)

## 表示用: 輸送 transport_id の搭乗駒 index の降車先候補（状態は変えない）。
func unload_cells_for(transport_id: int, index: int) -> Array[Vector2i]:
	return state.unload_cells(transport_id, index)

## 下り: 拠点に「入る」（駐留＝回復）。成功すれば unit_entered_base を発行。
func enter_base(handle: int) -> bool:
	if _finished:
		return false
	var u := state.unit_by_handle(handle)
	if u == null:
		return false
	var hex := u.pos
	if state.enter_base(handle):
		unit_entered_base.emit(handle, hex)
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
		event_fired.emit(_event_info(e, e.placed[0] if not e.placed.is_empty() else Vector2i.MAX))

## イベント1件 → 上へ渡す素データ。focus_hex＝カメラの行き先（増援は実際に駒が出た場所、
## 占領は拠点の hex）。type は引き金の別＝presentation が敵ターンに出してよいかの判断に使う。
## entry／from／units は登場の見せ方＝どこから何が出てきたか（doc/gdd/map.md イベント）。
## units は実際に盤へ出た駒の id（置けなかった駒は載らない）＝並びは units に書いた順。
func _event_info(e: StageEvent, focus_hex: Vector2i) -> Dictionary:
	return {
		"id": e.id,
		"label": e.label,
		"dialogue": e.dialogue,
		"focus": e.focus,
		"type": e.trigger_id(),
		"hex": focus_hex,
		"entry": e.entry_id(),
		"from": e.from,
		"units": e.placed_ids.duplicate(),
	}

## 敵ターンに溜めた占領イベントを1件ずつ流し、会話が閉じるまで待つ。
## 呼ぶのは1手を見せ切った後＝駒が拠点に着いてから喋る。
func _drain_pending_events() -> void:
	while not _pending_events.is_empty():
		var info: Dictionary = _pending_events.pop_front()
		event_fired.emit(info)
		if dialogue_pace.is_valid():
			await dialogue_pace.call()

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
		# 行動を見せる前に、その主体（攻撃なら相手も）をカメラに収める（画面外なら寄せて待つ・画面内なら即返る）。
		# 「敵が何をしたか」を毎手見せるため＝いつの間にか位置が変わる事態を防ぐ（doc/gdd/uiux.md）。
		if not _finished and focus_pace.is_valid():
			await focus_pace.call(_action_focus_hexes(action))
		var shown_combat := _apply_ai_action(action)
		# 移動アニメの完了を待つ＝駒が歩き切ってから次の手へ（手が重ならず追える）。歩いている間の
		# カメラ追従も presentation がこの待ちの中で行う。アニメが無ければ即戻る。攻撃より先＝移動→攻撃の順に見せる。
		if not _finished and move_pace.is_valid():
			await move_pace.call()
		# 歩き切った先も見せる。出発点しか見ないと、着地が情報板の裏や画面外でも追わない
		# （doc/gdd/uiux.md 敵ターンのカメラ）。すでに見えていれば追従側が即返る。
		if action.kind == AiAction.Kind.MOVE and not _finished and focus_pace.is_valid():
			await focus_pace.call([action.to] as Array[Vector2i])
		# 攻撃なら演出の完了を待つ＝盤に戻ってから次の手へ（プレイヤーが流れを追える）。
		if shown_combat and not _finished and combat_pace.is_valid():
			await combat_pace.call()
		# その手で拠点を取っていたら、ここで会話を挟む＝手を見せ切ってから盤を止める。
		if not _finished and not _pending_events.is_empty():
			await _drain_pending_events()
		else:
			_pending_events.clear()  # 決着した手のぶんは流さない
		if is_inside_tree() and not _finished:  # 各手の間を置いて見せる
			await get_tree().create_timer(ai_delay).timeout
	if not _finished:
		end_turn()

## その1手でカメラが見るべき hex の一覧（先頭＝行動主体）。移動は主体の現在位置（歩き出しを見せる）、
## 攻撃・ユニットスキルは主体の現在位置と相手＝誰を殴ったか・着弾がどこかを見せる、
## 出撃・降車は駒が現れる先。行動を適用する前に呼ぶ＝主体はまだ動いていない。
## 移動はこれに加えて、歩き終わった先を run_ai_turn がもう一度渡す（doc/gdd/uiux.md 敵ターンのカメラ）。
func _action_focus_hexes(action: AiAction) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	match action.kind:
		AiAction.Kind.MOVE, AiAction.Kind.ENTER_BASE:
			var u := state.unit_by_handle(action.handle)
			hexes.append(u.pos if u != null else action.to)
		AiAction.Kind.ATTACK:
			var u := state.unit_by_handle(action.handle)
			var t := state.unit_by_handle(action.target_id)
			if u != null:
				hexes.append(u.pos)
			if t != null:
				hexes.append(t.pos)
		AiAction.Kind.SKILL:
			var u := state.unit_by_handle(action.handle)
			if u != null:
				hexes.append(u.pos)
			hexes.append(action.to)
		_:  # DEPLOY / UNLOAD＝駒が現れるマスを見せる
			hexes.append(action.to)
	return hexes

## 1手を適用する。演出が出た（＝攻撃かスキルが成立した）なら true＝呼び出し側が完了を待つ。
func _apply_ai_action(action: AiAction) -> bool:
	match action.kind:
		AiAction.Kind.MOVE:
			execute(MoveCommand.new(action.handle, action.to))
		AiAction.Kind.ATTACK:
			return execute_attack(AttackCommand.new(action.handle, action.target_id))
		AiAction.Kind.DEPLOY:
			execute_deploy(DeployCommand.new(action.base_hex, action.garrison_index, action.to))
		AiAction.Kind.UNLOAD:
			execute_unload(UnloadCommand.new(action.handle, action.passenger_index, action.to))
		AiAction.Kind.SKILL:
			# 効果対象が1体のユニットスキルは演出シーンに乗る（doc/tech/combat_scene.md）ので、
			# 攻撃と同じく閉じるまで待たせる。演出が出ないレシピなら pace 側が即返る。
			return execute_formation(FormationCommand.new(action.option, action.to))
		AiAction.Kind.ENTER_BASE:
			enter_base(action.handle)
	return false

func _check_finished() -> void:
	if not _finished and state.is_over():
		_finished = true
		battle_finished.emit(state.outcome())

## 表示用の問い合わせ（状態は変えない）。
func reachable_for(handle: int) -> Array[Vector2i]:
	return state.reachable(handle)

func attack_targets_for(handle: int) -> Array[int]:
	return state.attack_targets(handle)

## 表示用: from_hex に居ると仮定したときの攻撃対象（コマンドメニューの「攻撃」可否判定）。
func attack_targets_from(handle: int, from_hex: Vector2i) -> Array[int]:
	return state.attack_targets_from(handle, from_hex)

## コマンドメニューの「待機」: そのユニットの行動をこのターン終了させる。
func stand(handle: int) -> void:
	if _finished:
		return
	if state.unit_by_handle(handle) == null:  # 盤に居ない駒＝行動終了させる対象が無い
		return
	state.set_done(handle)
	unit_stood.emit(handle)

## デバッグ: 盤上の敵駒（team 1）を全て除去する。決着は既存の判定に委ねる＝殲滅で勝利になる
## ステージならそのまま通常の勝利フロー（戦果票→outro→完走イラスト）へ流れる。敵拠点に控えが
## 残るステージでは勝利にならない（盤上0体かつ復帰手段なしが勝利条件）。詳細 → doc/gdd/uiux.md
func wipe_enemies() -> void:
	if _finished:
		return
	for u in state.units().duplicate():  # 除去で盤上リストが縮む＝複製を回す
		if u.team != 1:
			continue
		if state.remove_unit(u.handle):
			unit_died.emit(u.handle)  # 撃破と同じ経路で盤から駒を消す
	_check_finished()

## デバッグ: 未発生イベント e を引き金を待たずに起こす。中身（増援・会話・カメラ寄せ）は通常の
## 発火と同じ経路（event_fired）へ流すが、引き金そのものは成立させない＝占領起点でも拠点の
## 所属は動かないまま会話だけが流れる。台本と増援の見た目を確かめるための道。
## 決着は既存の判定に委ねる＝増援で兵力が変われば通常どおり決着する。詳細 → doc/gdd/uiux.md
func force_event(e: StageEvent) -> void:
	if _finished:
		return
	if not state.fire_event(e):
		return  # 既に起きている（同じ once の兄弟が先に起きた等）
	var focus := e.placed[0] if not e.placed.is_empty() else e.hex
	event_fired.emit(_event_info(e, focus))
	_check_finished()
