extends AiBrain
class_name TraitBrain
## 特性ベースの敵AI。駒の特性（部隊の ai）ごとの行動ルールは AiTrait のサブクラスが持ち、
## ここは行動順・行動開始（起動）の判定・拠点出撃と、特性への振り分けを担う。
## 行の部品は AiRows、標的の物差しは AiPick、パラメーターの解決は AiParams。
## 仕様の正本は doc/gdd/ai.md＝ここは表を写して実行するだけ。
##
## 1手ずつ返す（AiBrain の約束）。どの行も成立しなければ null＝待機で、その駒はその場に留まる。

## sight `*`（上限なし）の視線予算（AiParams.SIGHT_UNLIMITED の別名。盤の可視化とテストが読む）。
const SIGHT_UNLIMITED := AiParams.SIGHT_UNLIMITED

## 特性表（特性id -> { name, sight, stack }＝AiCatalog.load_default()）。部隊の特性解決に使う。
var presets := {}:
	set(v):
		presets = v
		if _params != null:
			_params.presets = v

var _params: AiParams
var _pick: AiPick
var _rows: AiRows
var _traits := {}  # 特性id -> AiTrait

func _init() -> void:
	var list: Array[AiTrait] = [
		TraitCharge.new(), TraitAmbush.new(), TraitRaid.new(), TraitPredator.new(),
		TraitSwarm.new(), TraitFlee.new(), TraitWithdraw.new(), TraitStandoff.new(),
	]
	var ids: Array[String] = []
	for t in list:
		ids.append(t.id())
	_params = AiParams.new(ids)
	_pick = AiPick.new(_params)
	_rows = AiRows.new(_params, _pick)
	for t in list:
		t.bind(_params, _pick, _rows)
		_traits[t.id()] = t

## u の特性（部隊に属さない駒・未知の特性は charge）。
func _trait_of(state: BattleState, u: Unit) -> AiTrait:
	return _traits[_params.trait_id_of(state, u)] as AiTrait

## 拠点 b の特性（部隊の ai。未設定・未知は charge）。
func _trait_of_base(state: BattleState, b: Base) -> AiTrait:
	return _traits[_params.base_trait_id(state, b)] as AiTrait

# --- 行動開始条件（doc/gdd/ai.md 特性の書き方） ---

## u が行動開始しているか判定し、条件が成立したら開始済みにして true。
## 一度成立したら以後は判定しない（成立したあとで敵が離れても止まらない）。
## 攻撃を受けた駒は特性によらずその時点で行動開始する＝BattleState.attack が mark_engaged を呼ぶ。
## 条件は特性の starts_engaged と、部隊の誰かが行動開始済み（一斉警戒）のどちらか。
func _ensure_engaged(state: BattleState, u: Unit) -> bool:
	if state.is_engaged(u.handle):
		return true
	var engaged := _trait_of(state, u).starts_engaged(state, u) or _squadmate_engaged(state, u)
	if engaged:
		state.mark_engaged(u.handle)
	return engaged

## u と同じ部隊の誰かが行動開始済みか（一斉警戒）。拠点も部隊の一員として数える＝その拠点が
## 起きていれば、そこから出した駒も自分の sight で敵を捉えられなくても動き出す。
func _squadmate_engaged(state: BattleState, u: Unit) -> bool:
	var idx := state.squad_index_of(u.handle)
	if idx < 0:
		return false
	return state.is_squad_engaged(idx) or _squad_unit_engaged(state, idx, u.handle)

## 部隊 squad_index の盤上の駒に行動開始済みの者がいるか（except_id は自分＝数えない）。
func _squad_unit_engaged(state: BattleState, squad_index: int, except_id := -1) -> bool:
	if squad_index < 0:
		return false  # 部隊なし同士を「同じ部隊」と数えない
	for other in state.units():
		if other.handle != except_id and state.squad_index_of(other.handle) == squad_index \
				and state.is_engaged(other.handle):
			return true
	return false

## unit の検知半径（索敵範囲の可視化用）。まだ動き出していない駒のうち、行動開始条件が
## 視線距離で決まる特性（engages_by_sight）なら sight、それ以外は0＝盤に検知域を描かない。
## swarm も sight を持つが行動開始条件は常時＝寝ている状態が無いのでここには入らない。
## `*`（上限なし）は SIGHT_UNLIMITED がそのまま返る。輪の走査は Sight 側が盤の広さで頭打ちにする。
func detection_radius(state: BattleState, unit: Unit) -> int:
	if unit == null or state.is_engaged(unit.handle):
		return 0
	if not _trait_of(state, unit).engages_by_sight():
		return 0
	return _params.sight_of(state, unit)

# --- 行動順（doc/gdd/ai.md 行動順） ---

## 敵のターンで行う次の1手。部隊は order の小さいほうから、部隊の中は前線に近い駒から動かし、
## その部隊の拠点の出撃は盤上の駒を捌いたあと。
func next_action(state: BattleState, team: int) -> AiAction:
	for si in _squad_order(state):
		for u in _units_in_order(state, team, si):
			var action := _unit_action(state, u)
			if action != null:
				return action
		for b in state.bases():
			if b.team != team or b.squad_index != si:
				continue
			var deploy_action := _try_deploy(state, b)
			if deploy_action != null:
				return deploy_action
	return null

## 部隊を動かす順に並べた index の列。order 昇順（同値・省略は登録順）、末尾に -1＝部隊に属さない駒。
func _squad_order(state: BattleState) -> Array[int]:
	var idx: Array[int] = []
	for i in state.squads.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ka := _order_of(state, a)
		var kb := _order_of(state, b)
		return ka < kb or (ka == kb and a < b))
	idx.append(-1)
	return idx

## 部隊の order。省略・非数値は登録順（index）で代用する＝データが欠けても順番が壊れない。
## 実データは全部隊に order を書く（抜けはデータ整合テストで検出）。
func _order_of(state: BattleState, squad_index: int) -> int:
	if squad_index < 0 or squad_index >= state.squads.size():
		return 1 << 30
	var v: Variant = (state.squads[squad_index] as Dictionary).get("order")
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return squad_index

## 部隊 squad_index に属する team の駒を、動かす順に並べる。盤上距離で最寄りの敵に近い駒から、
## 同値は col → row の若い順。駒が動けば距離も変わるので毎ターン計算し直す。
## 前線から動かすのは、後ろの駒が先に動くと前の駒に塞がれて進めないため。
func _units_in_order(state: BattleState, team: int, squad_index: int) -> Array[Unit]:
	var list: Array[Unit] = []
	for u in state.units():
		if u.team == team and state.squad_index_of(u.handle) == squad_index:
			list.append(u)
	var dist := {}  # handle -> 最寄り敵までの盤上距離（並べ替え中に何度も引くので先に1回だけ）
	for u in list:
		dist[u.handle] = _board_distance_to_nearest_enemy(state, u)
	list.sort_custom(func(a: Unit, b: Unit) -> bool:
		# 輸送ユニットは部隊の最後（同じ部隊の駒が乗り込んでから動く。doc/gdd/ai.md 輸送ユニット）
		var ta := AiRows.is_transport(a)
		if ta != AiRows.is_transport(b):
			return not ta
		var da: int = dist[a.handle]
		var db: int = dist[b.handle]
		if da != db:
			return da < db
		if a.pos != b.pos:
			return AiPick.is_younger_hex(a.pos, b.pos)
		return a.handle < b.handle)
	return list

## u から最寄りの敵までの盤上距離（敵がいなければ0＝全員同値になり col → row で並ぶ）。
func _board_distance_to_nearest_enemy(state: BattleState, u: Unit) -> int:
	var best := 1 << 30
	for other in state.units():
		if other.team != u.team:
			best = mini(best, Hex.distance(u.pos, other.pos))
	return 0 if best == (1 << 30) else best

# --- 行動ルール（doc/gdd/ai.md 特性詳細）＝特性へ振り分ける ---

## u が今できる1手（無ければ null＝待機）。特性の行を上から当てる。
## 手詰まり（is_stuck＝行ける先も撃てる相手も無い）でも打ち切らない＝スキルの行と
## 「拠点に入る」行は移動も攻撃射程も要らないため、行の条件に任せる（doc/gdd/ai.md 行動ルール）。
func _unit_action(state: BattleState, u: Unit) -> AiAction:
	var trait_rule := _trait_of(state, u)
	if state.is_done(u.handle):
		# 行動を終えた駒に残る手（輸送の降車＝乗員の手番で、運んだそのターンに降ろせる）。
		if not trait_rule.acts_when_done(u) or not _ensure_engaged(state, u):
			return null
		return trait_rule.done_action(state, u)
	if not _ensure_engaged(state, u):
		return null  # まだ動き出していない
	return trait_rule.action(state, u)

# --- 拠点出撃（doc/gdd/ai.md 拠点出撃） ---

## 拠点 b から出せる控えが1体でもあれば、その出撃1手を返す（行動開始しているときのみ）。無ければ null。
## next_action を尽きるまで回すので、この1手ずつ返しが「出せるだけ出す」になる。
func _try_deploy(state: BattleState, b: Base) -> AiAction:
	if b.squad_index < 0:
		return null  # ai 未指定の拠点はAI出撃しない（opt-in）
	if not _base_engaged(state, b):
		return null
	for i in b.garrison.size():
		if not state.can_deploy_garrison(b.hex, i):
			continue  # 閉じ込め（native≠所有者）＝出せない
		var cells := state.deploy_cells(b.hex, i)
		if cells.is_empty():
			continue  # 空き隣接なし＝今は出せない
		return AiAction.deploy(b.hex, i, _best_deploy_cell(state, b, cells))
	return null

## 拠点の行動開始条件＝ユニットと同じ条件を拠点hex基準で見る（特性の base_starts_engaged）。
## 一度成立したら以後は判定しない（部隊のフラグに焼く）＝敵が索敵から出ても拠点は眠り直さない。
## 一斉警戒はその部隊の中で閉じる＝同じ部隊の盤上の駒（その拠点から出した駒）が起きていれば拠点も
## 起きる。別部隊が起きても拠点は起きない（部隊のフラグしか見ないため）。
func _base_engaged(state: BattleState, b: Base) -> bool:
	if state.is_squad_engaged(b.squad_index):
		return true
	var engaged := _squad_unit_engaged(state, b.squad_index)
	if not engaged:
		engaged = _trait_of_base(state, b).base_starts_engaged(state, b, _params.base_sight_of(state, b))
	if engaged:
		state.mark_squad_engaged(b.squad_index)
	return engaged

## 出撃先候補のうち、盤上距離が最小の敵に最も近いマス（敵がいなければ col → row の若いマス）。
func _best_deploy_cell(state: BattleState, b: Base, cells: Array[Vector2i]) -> Vector2i:
	var enemies: Array[Unit] = []
	for other in state.units():
		if other.team != b.team:
			enemies.append(other)
	if enemies.is_empty():
		var young := cells[0]
		for c in cells:
			if AiPick.is_younger_hex(c, young):
				young = c
		return young
	var goal := _pick.nearest_unit_by_board(b.hex, enemies).pos
	return _pick.nearest_hex_by_board(goal, cells)
