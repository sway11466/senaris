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

## 部隊に属さないユニットの既定プリセット（ステージ直下 "ai" のラベルぶん）。空＝DEFAULT_PRESET（charge相当）。
var default_preset := {}

## 全軸の既定値＝「素の charge AI」。プリセット/上書きにその軸が無いときの唯一のフォールバック。
## 以前は各所に散っていた既定リテラル（"max"/"charge"/"always"/…）をここへ集約＝ドリフト源を撤去（doc/gdd/ai.md）。
## ai.csv 由来のプリセットは全軸そろい（生成時に検証済み）なので実データでは使われない＝テスト等の部分プリセット用の保険。
const DEFAULT_PRESET := {
	"engage": "charge", "sight": 0, "retreat": 0,
	"attack": "always", "target": "near", "advance": "max",
}

## プリセット辞書（ai.csv の1行＝AiCatalog が返す値）から Brain を組み立てる。
## 効く列: engage/sight（起動）・advance（前進。max/base/flank）・attack（prey のみ）・target（weak のみ）。
## retreat は未配線（既定動作）。空辞書・未知ラベル → 既定（charge 相当）。
static func from_preset(p: Dictionary) -> NearestAttackerBrain:
	var brain := NearestAttackerBrain.new()
	brain.default_preset = p
	brain.advance_to_base = String(p.get("advance", DEFAULT_PRESET["advance"])) == "base"
	return brain

## u のAIパラメーターを解決: 部隊の上書き ＞ 部隊プリセット ＞ Brain既定プリセット ＞ DEFAULT_PRESET。
## 最終フォールバックは単一の DEFAULT_PRESET のみ（呼び出し側に既定リテラルを散らさない）。
func _param(state: BattleState, u: Unit, key: String) -> Variant:
	var fallback: Variant = DEFAULT_PRESET.get(key)
	var squad := state.squad_of(u.id)
	if squad.is_empty():
		return default_preset.get(key, fallback)
	var preset: Dictionary = presets.get(String(squad.get("ai", "")), {})
	return squad.get(key, preset.get(key, fallback))

## u の前進が「拠点前進」か。部隊があれば 部隊の上書き > 部隊プリセット、無ければ Brain の既定。
func _unit_advances_to_base(state: BattleState, u: Unit) -> bool:
	if state.squad_of(u.id).is_empty():
		return advance_to_base
	return String(_param(state, u, "advance")) == "base"

# --- 起動（engage）＝待機AI。詳細 → doc/gdd/ai.md（思考の流れ 1.起動） ---

## u が起動済みか判定し、起動条件を満たしたら起動済みにして true。
## トリガー: charge=常時 / sight=索敵半径内に敵 / squad=部隊の誰かが起動（一斉警戒）
##          / 被ダメ=確定（BattleState.attack が mark）/ 自衛=射程内に敵（隣で寝続けない）。
## 一度起動したら戻らない（状態は BattleState 側に持つ＝セーブに乗る）。
func _ensure_engaged(state: BattleState, u: Unit) -> bool:
	if state.is_engaged(u.id):
		return true
	var tokens := String(_param(state, u, "engage")).split("|")
	var engaged := "charge" in tokens
	if not engaged and "sight" in tokens:
		engaged = _enemy_within(state, u, _sight_of(state, u))
	if not engaged and "squad" in tokens:
		engaged = _squadmate_engaged(state, u)
	if not engaged:
		engaged = not state.attack_targets(u.id).is_empty()  # 自衛: 射程内に敵が来たら起きる
	if engaged:
		state.mark_engaged(u.id)
	return engaged

## u の索敵半径（sight）。"-"（トリガー不使用相当）や欠落は 0＝引っかからない。
func _sight_of(state: BattleState, u: Unit) -> int:
	var s: Variant = _param(state, u, "sight")
	return int(s) if typeof(s) == TYPE_INT or typeof(s) == TYPE_FLOAT else 0

## unit の検知半径（索敵範囲の可視化用）。まだ寝ていて sight で起きる待機ユニットなら sight 半径、
## それ以外（起動済み・sight トリガー無し）は 0。表示側はこれ>0のときだけ検知域を描く。詳細 → doc/gdd/movement.md（視線）
func detection_radius(state: BattleState, unit: Unit) -> int:
	if unit == null or state.is_engaged(unit.id):
		return 0
	if not ("sight" in String(_param(state, unit, "engage")).split("|")):
		return 0
	return _sight_of(state, unit)

## u から索敵 radius 以内（＝視線が通り累積視線コスト ≤ radius）に敵ユニットがいるか。
## 壁の裏・遠い森ごしは遮蔽/減衰で届かない（全地形コスト1なら距離判定に一致）。詳細 → doc/gdd/movement.md（視線）
func _enemy_within(state: BattleState, u: Unit, radius: int) -> bool:
	if radius <= 0:
		return false
	for other in state.units():
		if other.team != u.team and state.sight_reaches(u.pos, other.pos, radius):
			return true
	return false

## u と同じ部隊の誰かが起動済みか（一斉警戒）。
func _squadmate_engaged(state: BattleState, u: Unit) -> bool:
	var idx := state.squad_index_of(u.id)
	if idx < 0:
		return false
	for other in state.units():
		if other.id != u.id and state.squad_index_of(other.id) == idx and state.is_engaged(other.id):
			return true
	return false

func next_action(state: BattleState, team: int) -> AiAction:
	for u in state.units():
		if u.team != team or state.is_done(u.id):
			continue
		if not _ensure_engaged(state, u):
			continue  # 未起動（待機AI）＝その場で待つ。起動条件は _ensure_engaged 参照
		# 占領: 今ターンの移動範囲に自陣営以外の拠点があれば取りに行く（攻撃より優先）。
		if u.can_capture and not state.has_moved(u.id):
			var base_hex := _reachable_capture_hex(state, u)
			if base_hex != u.pos:
				return AiAction.move_to(u.id, base_hex)
		# 攻撃: 射程内の敵がいれば殴る。獲物のみ(attack=prey)は獲物・確殺以外を素通しして前進を続ける。
		var targets := state.attack_targets(u.id)
		if _attack_prey_only(state, u):
			targets = _prey_or_kill_targets(state, u, targets)
		if not targets.is_empty():
			return AiAction.attack(u.id, _pick_target(state, u, targets))
		# 前進: まだ動いていなければ目標へ寄る。
		if not state.has_moved(u.id):
			var dest := _advance_dest(state, u)
			if dest != u.pos:
				return AiAction.move_to(u.id, dest)
	# 拠点出撃(deploy): 盤上ユニットを捌いた後、AI所有の拠点から起動成立時に出せるだけ出す（1手ずつ）。ai.md §7
	for b in state.bases():
		if b.team != team:
			continue
		var deploy_action := _try_deploy(state, b)
		if deploy_action != null:
			return deploy_action
	return null

# --- 弱者狙い（attack=prey / target=weak / advance=flank）。詳細 → doc/gdd/ai.md（弱者狙いの設計） ---

## u の攻撃条件が「獲物のみ」(prey) か。attack 軸（"|"＝OR リスト）に prey を含むかで判定。
func _attack_prey_only(state: BattleState, u: Unit) -> bool:
	return "prey" in String(_param(state, u, "attack")).split("|")

## u の対象優先が「弱者狙い」(weak) か。target 軸（";"＝順序リスト）に weak を含むかで判定。
func _targets_weak(state: BattleState, u: Unit) -> bool:
	return "weak" in String(_param(state, u, "target")).split(";")

## u の前進が「回り込み」(flank) か。
func _advance_is_flank(state: BattleState, u: Unit) -> bool:
	return String(_param(state, u, "advance")) == "flank"

## 盤上の敵のうち最も低いユニット防御力（敵がいなければ -1）。獲物の判定基準。
func _min_enemy_defense(state: BattleState, u: Unit) -> int:
	var min_def := -1
	for other in state.units():
		if other.team != u.team and (min_def < 0 or other.unit_defense < min_def):
			min_def = other.unit_defense
	return min_def

## 獲物＝盤上の敵のうちユニット防御力（素のステータス）が最も低いもの。兵数は見ない。
## 同率は u から近い方 → id小。獲物が倒れたら次に低いものが自動的に次の獲物になる。
func _prey_of(state: BattleState, u: Unit) -> Unit:
	var min_def := _min_enemy_defense(state, u)
	var best: Unit = null
	var best_d := 1 << 30
	for other in state.units():
		if other.team == u.team or other.unit_defense != min_def:
			continue
		var d := Hex.distance(u.pos, other.pos)
		if best == null or d < best_d or (d == best_d and other.id < best.id):
			best = other
			best_d = d
	return best

## 攻撃条件「獲物のみ」: 射程内のうち獲物（最低防御）と確殺（一撃で倒しきれる相手）だけ残す。
## 与ダメは戦闘式で厳密計算（combat.md＝決定的）。
func _prey_or_kill_targets(state: BattleState, u: Unit, ids: Array[int]) -> Array[int]:
	var min_def := _min_enemy_defense(state, u)
	var out: Array[int] = []
	for id in ids:
		var t := state.unit_by_id(id)
		var melee := Hex.distance(u.pos, t.pos) <= 1  # 距離1なら近接＝支援が乗る（解決式と一致）
		if t.unit_defense == min_def or Combat.casualties(state, u, t, melee) >= t.troops:
			out.append(id)
	return out

## 射程内の攻撃対象を選ぶ。weak＝攻撃後の残兵最小（確殺を自然に最優先）、既定＝兵数最小。
func _pick_target(state: BattleState, u: Unit, ids: Array[int]) -> int:
	if _targets_weak(state, u):
		return _most_killable(state, u, ids)
	return _weakest(state, ids)

## 与ダメを戦闘式で厳密計算し、攻撃後の残兵が最小になる敵。同値は近い方 → id小。
func _most_killable(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var best := ids[0]
	var best_left := 1 << 30
	var best_d := 1 << 30
	for id in ids:
		var t := state.unit_by_id(id)
		var melee := Hex.distance(u.pos, t.pos) <= 1  # 距離1なら近接＝支援が乗る（解決式と一致）
		var left := t.troops - Combat.casualties(state, u, t, melee)
		var d := Hex.distance(u.pos, t.pos)
		if left < best_left or (left == best_left and (d < best_d or (d == best_d and id < best))):
			best = id
			best_left = left
			best_d = d
	return best

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
## 占領できる拠点へ。標的は target 軸で決まる（weak＝獲物、既定＝最寄りの敵）。
## 詰め方は advance 軸で決まる（flank＝回り込み、既定＝距離が縮むヘックス。縮まないなら現在地）。
func _advance_dest(state: BattleState, u: Unit) -> Vector2i:
	if _unit_advances_to_base(state, u):
		var goal := _nearest_capture_base_hex(state, u)
		if goal != u.pos:
			return _step_toward(state, u, goal)
	var enemy := _prey_of(state, u) if _targets_weak(state, u) else _nearest_enemy(state, u)
	if enemy == null:
		return u.pos
	if _advance_is_flank(state, u):
		return _flank_step(state, u, enemy.pos)
	return _step_toward(state, u, enemy.pos)

## 回り込み(advance=flank): 移動範囲のうち敵のZOC（敵に隣接するマス）に入らないマスを優先して
## goal への距離を縮める＝前衛の正面を避けて横へ滑る。安全なマスで縮まらないときは通常の
## 最大前進で詰める（獲物自身のZOCへの最終接近はこのフォールバックで成立）。
func _flank_step(state: BattleState, u: Unit, goal: Vector2i) -> Vector2i:
	var best := u.pos
	var best_d := Hex.distance(u.pos, goal)
	for h in state.reachable(u.id):
		if _hex_in_enemy_zoc(state, u, h):
			continue
		var d := Hex.distance(h, goal)
		if d < best_d:
			best_d = d
			best = h
	if best != u.pos:
		return best
	return _step_toward(state, u, goal)

## hex が u から見た敵のZOC内（敵ユニットに隣接）か。回り込みの「安全なマス」判定に使う。
func _hex_in_enemy_zoc(state: BattleState, u: Unit, hex: Vector2i) -> bool:
	for nb in Hex.neighbors(hex):
		var occ := state.unit_at(nb)
		if occ != null and occ.team != u.team:
			return true
	return false

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

# --- 拠点出撃（deploy）。詳細 → doc/gdd/ai.md §7 拠点出撃 ---

## 拠点 b から出せる控えが1体でもあれば、その出撃1手を返す（起動条件を満たすときのみ）。無ければ null。
## run_ai_turn が next_action を尽きるまで回すので、この1手ずつ返しが「出せるだけ出す」になる。
func _try_deploy(state: BattleState, b: Base) -> AiAction:
	if b.squad_index < 0:
		return null  # ai 未指定の拠点はAI出撃しない（opt-in）。ai.md §7
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

## 拠点の起動判定＝ユニットの engage を拠点hex基準で再利用（charge＝常時／sight＝索敵内に敵）。
func _base_engaged(state: BattleState, b: Base) -> bool:
	var tokens := String(_base_param(state, b, "engage", "charge")).split("|")
	if "charge" in tokens:
		return true
	if "sight" in tokens:
		var s: Variant = _base_param(state, b, "sight", 0)
		var radius := int(s) if typeof(s) == TYPE_INT or typeof(s) == TYPE_FLOAT else 0
		return _enemy_within_hex(state, b.hex, b.team, radius)
	return false

## 拠点のAIパラメーター解決: 拠点squadの上書き ＞ そのプリセット ＞ default。squad未設定は default。
func _base_param(state: BattleState, b: Base, key: String, default: Variant) -> Variant:
	if b.squad_index < 0 or b.squad_index >= state.squads.size():
		return default
	var squad: Dictionary = state.squads[b.squad_index]
	var preset: Dictionary = presets.get(String(squad.get("ai", "")), {})
	return squad.get(key, preset.get(key, default))

## hex から索敵 radius 以内（視線が通り累積視線コスト ≤ radius）に team 以外のユニットがいるか（拠点の索敵起動用）。
func _enemy_within_hex(state: BattleState, hex: Vector2i, team: int, radius: int) -> bool:
	if radius <= 0:
		return false
	for other in state.units():
		if other.team != team and state.sight_reaches(hex, other.pos, radius):
			return true
	return false

## 出撃先候補のうち、最寄り敵に一番近いマス（敵がいなければ先頭）。
func _best_deploy_cell(state: BattleState, b: Base, cells: Array[Vector2i]) -> Vector2i:
	var goal := _nearest_enemy_pos(state, b.hex, b.team)
	var best := cells[0]
	var best_d := 1 << 30
	for c in cells:
		var d := Hex.distance(c, goal)
		if d < best_d:
			best_d = d
			best = c
	return best

## from_hex に最も近い team 以外のユニットの位置（いなければ from_hex）。
func _nearest_enemy_pos(state: BattleState, from_hex: Vector2i, team: int) -> Vector2i:
	var best := from_hex
	var best_d := 1 << 30
	for other in state.units():
		if other.team == team:
			continue
		var d := Hex.distance(from_hex, other.pos)
		if d < best_d:
			best_d = d
			best = other.pos
	return best
