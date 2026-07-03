extends AiBrain
class_name NearestAttackerBrain
## 最小AI: 各ユニットについて「取れる拠点があれば占領／攻撃できるなら殴る／できなければ前進」。
## 1手ずつ返す（移動した次の呼び出しで隣接していれば攻撃を返す）。
## 思考の流れ（doc/gdd/ai.md）: 占領は起動の直後＝攻撃より優先。占領可ユニット(can_capture)のみ。
## 隣接敵が複数なら最もHPの低い相手を狙う。

## 前進オプション「拠点前進」: 攻撃も占領もできないターン、**全ユニット**が最寄りの
## 「占領できる拠点」へ向かう＝部隊ごと拠点攻略に向かう動き（占領できるのは占領可ユニットだけ。
## 護衛はそこで戦う）。拠点が無ければ従来どおり最寄りの敵へ。既定はOFF＝敵へ前進。
## 部隊(squad)に属するユニットは、部隊のプリセット＋上書きがこの既定より優先される。
var advance_to_base := false

## AIプリセット表（label -> パラメーター辞書＝AiCatalog.load_default()）。部隊のラベル解決に使う。
var presets := {}

## プリセット辞書（ai.csv の1行＝AiCatalog が返す値）から Brain を組み立てる。
## 現状使うのは advance のみ（"base"＝拠点前進）。engage/sight 等は待機AI実装時に配線する。
## 空辞書・未知ラベル → 既定（charge 相当）。
static func from_preset(p: Dictionary) -> NearestAttackerBrain:
	var brain := NearestAttackerBrain.new()
	brain.advance_to_base = String(p.get("advance", "max")) == "base"
	return brain

## u の前進が「拠点前進」か。部隊があれば 部隊の上書き > 部隊プリセット、無ければ Brain の既定。
func _unit_advances_to_base(state: BattleState, u: Unit) -> bool:
	var squad := state.squad_of(u.id)
	if squad.is_empty():
		return advance_to_base
	var preset: Dictionary = presets.get(String(squad.get("ai", "")), {})
	return String(squad.get("advance", preset.get("advance", "max"))) == "base"

func next_action(state: BattleState, team: int) -> AiAction:
	for u in state.units():
		if u.team != team or state.is_done(u.id):
			continue
		# 占領: 今ターンの移動範囲に自陣営以外の拠点があれば取りに行く（攻撃より優先）。
		if u.can_capture and not state.has_moved(u.id):
			var base_hex := _reachable_capture_hex(state, u)
			if base_hex != u.pos:
				return AiAction.move_to(u.id, base_hex)
		# 攻撃: 射程内の敵がいれば殴る。
		var targets := state.attack_targets(u.id)
		if not targets.is_empty():
			return AiAction.attack(u.id, _weakest(state, targets))
		# 前進: まだ動いていなければ目標へ寄る。
		if not state.has_moved(u.id):
			var dest := _advance_dest(state, u)
			if dest != u.pos:
				return AiAction.move_to(u.id, dest)
	return null

func _weakest(state: BattleState, ids: Array[int]) -> int:
	var best := ids[0]
	var best_troops := state.unit_by_id(best).troops
	for id in ids:
		var troops := state.unit_by_id(id).troops
		if troops < best_troops:
			best_troops = troops
			best = id
	return best

## 今ターンの移動範囲内にある「占領できる拠点」のhex（複数なら最寄り）。無ければ現在地。
func _reachable_capture_hex(state: BattleState, u: Unit) -> Vector2i:
	var reach := state.reachable(u.id)
	var best := u.pos
	var best_d := 1 << 30
	for b in state.bases():
		if b.team == u.team:
			continue  # 自陣営の拠点は対象外（敵・中立を取る）
		if not reach.has(b.hex):
			continue
		var d := Hex.distance(u.pos, b.hex)
		if d < best_d:
			best_d = d
			best = b.hex
	return best

## 攻撃できないターンの前進先。拠点前進（部隊 or Brain既定で解決）なら最寄りの
## 占領できる拠点へ、それ以外は最寄りの敵へ距離が縮むヘックスへ（縮まないなら現在地）。
func _advance_dest(state: BattleState, u: Unit) -> Vector2i:
	if _unit_advances_to_base(state, u):
		var goal := _nearest_capture_base_hex(state, u)
		if goal != u.pos:
			return _step_toward(state, u, goal)
	var enemy := _nearest_enemy(state, u)
	if enemy == null:
		return u.pos
	return _step_toward(state, u, enemy.pos)

## 盤上で最寄りの「占領できる拠点」のhex。無ければ現在地。
func _nearest_capture_base_hex(state: BattleState, u: Unit) -> Vector2i:
	var best := u.pos
	var best_d := 1 << 30
	for b in state.bases():
		if b.team == u.team:
			continue
		var d := Hex.distance(u.pos, b.hex)
		if d < best_d:
			best_d = d
			best = b.hex
	return best

## 移動範囲のうち、goal への距離が最も縮むヘックスを返す（縮まないなら現在地）。
func _step_toward(state: BattleState, u: Unit, goal: Vector2i) -> Vector2i:
	var best := u.pos
	var best_d := Hex.distance(u.pos, goal)
	for h in state.reachable(u.id):
		var d := Hex.distance(h, goal)
		if d < best_d:
			best_d = d
			best = h
	return best

func _nearest_enemy(state: BattleState, u: Unit) -> Unit:
	var best: Unit = null
	var best_d := 1 << 30
	for other in state.units():
		if other.team == u.team:
			continue
		var d := Hex.distance(u.pos, other.pos)
		if d < best_d:
			best_d = d
			best = other
	return best
