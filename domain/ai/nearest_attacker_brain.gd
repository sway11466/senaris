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

## スキル発動条件（skill 軸）と対象優先（skill_target 軸）で実装済みの値。
## 未実装の値は「該当なし」と同じ扱いにする＝データに書いてあっても素通りする（doc/gdd/ai.md §4・§5）。
## always＝対象にできる相手が範囲内にいれば放つ。包囲まわりの2語は攻撃条件と同じ意味（_surround_passes）。
const SKILL_TRIGGERS := ["always", "surround_able", "surrounded"]
const NO_HEX := Vector2i(1 << 30, 1 << 30)  ## 「対象なし」の番兵（盤の外）
const SKILL_TARGET_KEYS := ["troops", "weak", "atk", "near"]

## 攻撃条件（attack 軸）で実装済みの値。solo_adv / no_retal / kill は未実装＝素通り（doc/gdd/ai.md §6）。
const ATTACK_CONDITIONS := ["always", "prey", "surround_able", "surrounded"]

## 全軸の既定値＝「素の charge AI」。プリセット/上書きにその軸が無いときの唯一のフォールバック。
## 以前は各所に散っていた既定リテラル（"max"/"charge"/"always"/…）をここへ集約＝ドリフト源を撤去（doc/gdd/ai.md）。
## ai.csv 由来のプリセットは全軸そろい（生成時に検証済み）なので実データでは使われない＝テスト等の部分プリセット用の保険。
const DEFAULT_PRESET := {
	"engage": "charge", "sight": 0, "retreat": 0,
	"skill": "-", "skill_target": "-",
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

## 行動順は部隊(squad)単位。order の小さい部隊から、部隊の中は前線に近い駒から動かし、
## その部隊の拠点の出撃は盤上の駒を捌いたあと。詳細 → doc/gdd/ai.md（行動順）
func next_action(state: BattleState, team: int) -> AiAction:
	for si in _squad_order(state):
		for u in _units_in_order(state, team, si):
			var action := _unit_action(state, u)
			if action != null:
				return action
		# 拠点出撃(deploy): この部隊の拠点から起動成立時に出せるだけ出す（1手ずつ）。ai.md §7
		for b in state.bases():
			if b.team != team or b.squad_index != si:
				continue
			var deploy_action := _try_deploy(state, b)
			if deploy_action != null:
				return deploy_action
	return null

## u が今できる1手（無ければ null）。占領 → 攻撃 → 前進の順で、doc/gdd/ai.md の思考の流れに対応する。
func _unit_action(state: BattleState, u: Unit) -> AiAction:
	if state.is_done(u.id):
		return null
	if not _ensure_engaged(state, u):
		return null  # 未起動（待機AI）＝その場で待つ。起動条件は _ensure_engaged 参照
	# 占領: 今ターンの移動範囲に自陣営以外の拠点があれば取りに行く（攻撃より優先）。
	if u.can_capture and not state.has_moved(u.id):
		var base_hex := _reachable_capture_hex(state, u)
		if base_hex != u.pos:
			return AiAction.move_to(u.id, base_hex)
	# スキル: 放つと行動完了＝そのターンは殴らないので、攻撃より前に決める（doc/gdd/ai.md §4）。
	var skill_action := _try_skill(state, u)
	if skill_action != null:
		return skill_action
	# 攻撃: 射程内の敵がいれば殴る。攻撃条件(attack)で絞った結果が空なら殴らずに前進を続ける
	# （獲物のみ＝硬い前衛を素通り、包囲可能／包囲状態＝独りでは突っ込まない）。
	var targets := _attack_allowed_targets(state, u, state.attack_targets(u.id))
	if not targets.is_empty():
		return AiAction.attack(u.id, _pick_target(state, u, targets))
	# 前進: まだ動いていなければ目標へ寄る。
	if not state.has_moved(u.id):
		var dest := _advance_dest(state, u)
		if dest != u.pos:
			return AiAction.move_to(u.id, dest)
	return null

# --- 行動順（doc/gdd/ai.md 行動順） ---

## 部隊を動かす順に並べた index の列。order 昇順（同値・省略は登録順）、末尾に -1＝部隊に属さない駒。
func _squad_order(state: BattleState) -> Array[int]:
	var idx: Array[int] = []
	for i in state.squads.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ka := _order_of(state, a)
		var kb := _order_of(state, b)
		return ka < kb or (ka == kb and a < b))
	idx.append(-1)  # 部隊に属さない駒（テスト・素の敵）は最後
	return idx

## 部隊の order。省略・非数値は登録順（index）で代用する＝データが欠けても順番が壊れない。
## 実データは全部隊に order を書く（抜けはデータ整合テストで検出）。doc/gdd/ai.md 行動順
func _order_of(state: BattleState, squad_index: int) -> int:
	if squad_index < 0 or squad_index >= state.squads.size():
		return 1 << 30
	var v: Variant = (state.squads[squad_index] as Dictionary).get("order")
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return squad_index

## 部隊 squad_index に属する team の駒を、動かす順に並べる。
## 前線に近い順（最寄り敵までの距離が短い順）。同距離は col → row → 駒番号。
## 前の駒から動かさないと後ろが塞がれて進めないので、毎回いまの盤面で並べ直す。
func _units_in_order(state: BattleState, team: int, squad_index: int) -> Array[Unit]:
	var list: Array[Unit] = []
	for u in state.units():
		if u.team == team and state.squad_index_of(u.id) == squad_index:
			list.append(u)
	var dist := {}  # unit_id -> 最寄り敵までの距離（並べ替え中に何度も引くのでここで1回だけ計算）
	for u in list:
		dist[u.id] = _distance_to_nearest_enemy(state, u)
	list.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da: int = dist[a.id]
		var db: int = dist[b.id]
		if da != db:
			return da < db
		var oa := Hex.axial_to_offset(a.pos)
		var ob := Hex.axial_to_offset(b.pos)
		if oa.x != ob.x:
			return oa.x < ob.x
		if oa.y != ob.y:
			return oa.y < ob.y
		return a.id < b.id)
	return list

## u から最寄りの敵までの距離（敵がいなければ 0＝全員同値になり col → row で並ぶ）。
func _distance_to_nearest_enemy(state: BattleState, u: Unit) -> int:
	var enemy := _nearest_enemy(state, u)
	return Hex.distance(u.pos, enemy.pos) if enemy != null else 0

# --- スキル（skill / skill_target）。詳細 → doc/gdd/ai.md §4・§5 ---

## u が今ターン放てるユニットスキルの1手（無ければ null）。
## 放つと発動者は行動完了になるので、攻撃より前に呼ぶ。移動後でも放てる（skills.md 共通ルール）。
func _try_skill(state: BattleState, u: Unit) -> AiAction:
	var triggers := String(_param(state, u, "skill")).split("|")
	var live: Array[String] = []
	for t in triggers:
		if t in SKILL_TRIGGERS:
			live.append(t)
	if live.is_empty():
		return null  # 放たない（"-"）／未実装のトリガーだけ＝素通り
	for option in Formation.available_for(state, u):
		var target := _pick_skill_target(state, u, option, live)
		if target != NO_HEX:
			return AiAction.skill(u.id, option, target)
	return null

## 対象を選ぶ（skill_target 軸の優先順位順）。放てる相手がいなければ番兵を返す。
## 候補は「その option で狙えるヘックス」＝Formation.can_target が通るマスのうち、
## 発動条件（live）を満たす相手だけ。条件は対象1体ごとに見る＝包囲まわりは相手の状態で決まる。
func _pick_skill_target(state: BattleState, u: Unit, option: Dictionary, live: Array[String]) -> Vector2i:
	var candidates: Array[Unit] = []
	for other in state.units():
		if not Formation.can_target(state, option, other.pos):
			continue
		if not _skill_trigger_passes(state, u, other, live):
			continue
		candidates.append(other)
	if candidates.is_empty():
		return NO_HEX
	var keys := String(_param(state, u, "skill_target")).split(";")
	for key in keys:
		if not (key in SKILL_TARGET_KEYS) or candidates.size() == 1:
			continue
		candidates = _narrow_skill_targets(state, u, candidates, key)
	var best: Unit = candidates[0]
	for c in candidates:
		if c.id < best.id:  # 絞りきれなければ駒番号の小さいほう（攻撃対象と同じ）
			best = c
	return best.pos

## スキル発動条件を対象1体に当てる。always は誰でも通す。包囲まわりは攻撃条件と共通の判定へ。
func _skill_trigger_passes(state: BattleState, u: Unit, target: Unit, live: Array[String]) -> bool:
	if "always" in live:
		return true
	return _surround_passes(state, u, target, live)

## 優先順位1つぶんの絞り込み。同値の候補は全部残して次の項目へ渡す。
func _narrow_skill_targets(state: BattleState, u: Unit, candidates: Array[Unit], key: String) -> Array[Unit]:
	var score := func(c: Unit) -> int:
		match key:
			"troops":
				return c.troops
			"weak":
				return -c.unit_defense  # 防御が低いほど良い
			"atk":
				return int(Combat.attack_breakdown(state, c, u)["total"])  # c が u を殴るときの実効攻撃力
			"near":
				return -Hex.distance(u.pos, c.pos)
		return 0
	var best_score := -(1 << 30)
	for c in candidates:
		best_score = maxi(best_score, int(score.call(c)))
	var out: Array[Unit] = []
	for c in candidates:
		if int(score.call(c)) == best_score:
			out.append(c)
	return out

# --- 包囲まわりの条件（surround_able / surrounded）。skill 軸・attack 軸で共通。ai.md §4・§6 ---

## 包囲まわりの条件を対象1体に当てる（live に含まれる語だけ見る＝"|" は OR）。
## 語の意味を skill 軸と attack 軸で揃えるため、判定はここ1か所に置く。
## 包囲は敵に向ける条件なので、味方に掛けるスキル（buff_side=ally）の対象はここを通らない
## ＝そういうスキルを持つ駒に包囲条件を書くと放たなくなる。
func _surround_passes(state: BattleState, u: Unit, target: Unit, live: Array[String]) -> bool:
	if target == null or target.team == u.team:
		return false
	if "surrounded" in live and Surround.factor(state, target) < 1.0:
		return true
	if "surround_able" in live and _surround_reach_count(state, u, target) >= Surround.GATE:
		return true
	return false

## 今ターン中に target へ隣接できる自陣営の駒の数（包囲可能の判定材料）。
## すでに隣接している駒と、まだ動いておらず target の隣のマスへ停まれる駒を数える。
## 発動者自身も同じ規則で数に入る（移動後なら「すでに隣接」のときだけ）。
## Surround.GATE に届けば、あとから寄って包囲が成立する＝先に弱らせる価値がある（ai.md §4）。
func _surround_reach_count(state: BattleState, u: Unit, target: Unit) -> int:
	var ring := Hex.neighbors(target.pos)
	var count := 0
	for other in state.units():
		if other.team != u.team:
			continue
		if Hex.distance(other.pos, target.pos) == 1:
			count += 1
			continue
		if state.has_moved(other.id) or state.is_done(other.id):
			continue  # もう動けない駒は今ターン中には寄れない
		var reach := state.reachable(other.id)
		for h in ring:
			if h in reach:
				count += 1
				break
	return count

# --- 弱者狙い（attack=prey / target=weak / advance=flank）。詳細 → doc/gdd/ai.md（弱者狙いの設計） ---

## 攻撃条件（attack 軸）で射程内の候補を絞る。"|"＝OR なので、どれか1つでも通れば殴ってよい。
## 未実装の値（solo_adv / no_retal / kill）だけ・always・軸なしは従来どおり全部通す。
## 返す順は ids の並びのまま＝同値の対象を選ぶときの決まり方を変えない。
func _attack_allowed_targets(state: BattleState, u: Unit, ids: Array[int]) -> Array[int]:
	var live: Array[String] = []
	for t in String(_param(state, u, "attack")).split("|"):
		if t in ATTACK_CONDITIONS and not (t in live):
			live.append(t)
	if live.is_empty() or "always" in live:
		return ids
	var allowed := {}
	if "prey" in live:
		for id in _prey_or_kill_targets(state, u, ids):
			allowed[id] = true
	var out: Array[int] = []
	for id in ids:
		if allowed.has(id) or _surround_passes(state, u, state.unit_by_id(id), live):
			out.append(id)
	return out

## u の対象優先が「弱者狙い」(weak) か。target 軸（";"＝順序リスト）に weak を含むかで判定。
func _targets_weak(state: BattleState, u: Unit) -> bool:
	return "weak" in String(_param(state, u, "target")).split(";")

## u の前進が「回り込み」(flank) か。
func _advance_is_flank(state: BattleState, u: Unit) -> bool:
	return String(_param(state, u, "advance")) == "flank"

## u から実際に歩いて隣まで行ける敵の一覧（標的以外の駒を壁として測ったルートがある相手）。
## 標的の選び方はここから選ぶ＝道の無い相手を選んで前進が止まるのを防ぐ。
## 1体も届かない（自分が完全に囲まれている等）なら盤上の敵をそのまま返す＝従来どおりの選び方。
## 返り値は [敵, その敵の隣までの道のり] の配列。詳細 → doc/gdd/ai.md（標的の選び方）
func _enemies_in_reach(state: BattleState, u: Unit) -> Array:
	# u を起点に流す＝自分から見た道のり。自分のマスは壁にしない（起点なので当然通れる）。
	var field := state.travel_cost_field_avoiding_units(u.pos, u.move_type, u.move, u.pos)
	var reachable_list: Array = []
	var all_list: Array = []
	for other in state.units():
		if other.team == u.team:
			continue
		var best_c := 1 << 30
		for nb in Hex.neighbors(other.pos):
			var c := int(field.get(nb, 1 << 30))
			if c < best_c:
				best_c = c
		all_list.append([other, Hex.distance(u.pos, other.pos)])
		if best_c < (1 << 30):
			reachable_list.append([other, best_c])
	return reachable_list if not reachable_list.is_empty() else all_list

## 獲物の層の幅。ユニット防御力は10刻みの段（10=エルフ/馬車 … 80=バリケード）なので、
## +10＝「いちばん柔らかい段とその次の段」。1体に固定すると、盤の隅の最弱1体を全員で
## 追いかけて手近な柔らかい相手を素通りする。詳細 → doc/gdd/ai.md（弱者狙いの設計）
const PREY_DEFENSE_BAND := 10

## 獲物の層の上限＝届く敵の最小防御 ＋ PREY_DEFENSE_BAND（届く敵がいなければ -1）。
func _prey_defense_ceiling(state: BattleState, u: Unit) -> int:
	var min_def := -1
	for entry in _enemies_in_reach(state, u):
		var d: int = (entry[0] as Unit).unit_defense
		if min_def < 0 or d < min_def:
			min_def = d
	return min_def + PREY_DEFENSE_BAND if min_def >= 0 else -1

## 獲物＝届く敵のうち「防御の低い層」にいるもの。層の中は道のりが短い方 → id小。兵数は見ない。
## 「届く敵」から選ぶので、壁や群れの向こうで手の出せない相手を眺めて止まることがない。
## 獲物が倒れたら層を測り直す＝次に柔らかい相手が自動的に次の獲物になる。
func _prey_of(state: BattleState, u: Unit) -> Unit:
	var ceiling := _prey_defense_ceiling(state, u)
	if ceiling < 0:
		return null
	var best: Unit = null
	var best_c := 1 << 30
	for entry in _enemies_in_reach(state, u):
		var other: Unit = entry[0]
		var c := int(entry[1])
		if other.unit_defense > ceiling:
			continue
		if best == null or c < best_c or (c == best_c and other.id < best.id):
			best = other
			best_c = c
	return best

## 攻撃条件「獲物のみ」: 射程内のうち獲物（最低防御）と確殺（一撃で倒しきれる相手）だけ残す。
## 与ダメは戦闘式で厳密計算（combat.md＝決定的）。
func _prey_or_kill_targets(state: BattleState, u: Unit, ids: Array[int]) -> Array[int]:
	# 獲物と同じ層に入る相手なら殴ってよい。ここを「獲物1体だけ」に絞ると、
	# 層で寄っていったのに隣の相手を殴らない、というちぐはぐが出る。
	var ceiling := _prey_defense_ceiling(state, u)
	var out: Array[int] = []
	for id in ids:
		var t := state.unit_by_id(id)
		var melee := Hex.distance(u.pos, t.pos) <= 1  # 距離1なら近接＝支援が乗る（解決式と一致）
		if (ceiling >= 0 and t.unit_defense <= ceiling) \
				or Combat.casualties(state, u, t, melee) >= t.troops:
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

## 移動範囲のうち、goal までの道のりが最も縮むヘックスを返す。3段で測り、上から順に試す。
## 1) 標的以外の駒を壁として測った道のり＝実際に歩けるルート。味方の上は通過できても止まれない
##    ので、駒を見ないまま測ると勾配が仲間の背中を指し、止まれるマスが全部「上り」になって固まる
## 2) 地形だけの道のり＝1で道が消えたとき（標的が駒に囲まれている）。駒はいずれ動くので寄せておく
## 3) 直線距離＝地形的にも goal と繋がっていないとき（壁の向こう）。壁際まで詰めてそこで止まる
## どれでも縮まないなら現在地＝今ターンは待つ。詳細 → doc/gdd/ai.md（前進）
func _step_toward(state: BattleState, u: Unit, goal: Vector2i) -> Vector2i:
	# 移動力を渡す＝1歩で入れないマス（移動2の駒にとっての柵）を道のりの計算から外す。
	# 外さないと勾配がそのマスを指し、踏めるマスが全部「上り」になって前進が止まる。
	var dest := _descend(state, u,
		state.travel_cost_field_avoiding_units(goal, u.move_type, u.move, u.pos), goal)
	if dest != u.pos:
		return dest
	dest = _descend(state, u, state.travel_cost_field(goal, u.move_type, u.move), goal)
	if dest != u.pos:
		return dest
	return _step_toward_straight(state, u, goal)

## 道のり表 field の勾配を1手ぶん降りる。同値なら直線距離が近い方（横に広がって次の一歩を作る）。
## 自分の位置が表に無い＝その表では goal と繋がっていない＝現在地を返す（呼び出し側が次の段へ）。
func _descend(state: BattleState, u: Unit, field: Dictionary, goal: Vector2i) -> Vector2i:
	if not field.has(u.pos):
		return u.pos
	var best := u.pos
	var best_c := int(field[u.pos])
	var best_d := Hex.distance(u.pos, goal)
	for h in state.reachable(u.id):
		if not field.has(h):
			continue
		var c := int(field[h])
		var d := Hex.distance(h, goal)
		if c < best_c or (c == best_c and d < best_d):
			best = h
			best_c = c
			best_d = d
	return best

## 直線距離だけで寄せる版（道のりが測れないときの退避）。縮まないなら現在地。
func _step_toward_straight(state: BattleState, u: Unit, goal: Vector2i) -> Vector2i:
	var best := u.pos
	var best_d := Hex.distance(u.pos, goal)
	for h in state.reachable(u.id):
		var d := Hex.distance(h, goal)
		if d < best_d:
			best_d = d
			best = h
	return best

## 最寄りの敵＝届く敵のうち道のりが短いもの（同値は id 小）。獲物と同じく「届く敵」から選ぶ。
func _nearest_enemy(state: BattleState, u: Unit) -> Unit:
	var best: Unit = null
	var best_c := 1 << 30
	for entry in _enemies_in_reach(state, u):
		var other: Unit = entry[0]
		var c := int(entry[1])
		if c < best_c or (c == best_c and best != null and other.id < best.id):
			best = other
			best_c = c
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
