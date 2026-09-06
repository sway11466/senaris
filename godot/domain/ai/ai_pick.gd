extends RefCounted
class_name AiPick
## 敵AIの標的の選び方（純ロジック・Node非依存）。
## 「誰を狙うか」「どのマスが近いか」の物差し＝doc/gdd/ai.md の用語（獲物・手負い・空敵・反撃されない・
## 仕留められる敵・戦果・stack 条件・包囲可能・損耗）をそのまま関数にしたもの。盤は書き換えない。
## 行（AiRows）と特性（AiTrait）がこれを組み合わせて1手を決める。

## 「対象なし」の番兵（盤の外）。
const NO_HEX := Vector2i(1 << 30, 1 << 30)

## 獲物の層の幅。ユニット防御力は10刻みの段なので +10＝「最も柔らかい段とその次の段」。
## 1体に固定すると盤の隅の最弱1体を全員で追って手近な柔らかい敵を素通りする（doc/gdd/ai.md 獲物）。
const PREY_DEFENSE_BAND := 10

## スキル対象の選び方（行ごとに違う）。near＝盤上距離が最小／weak＝防御力が最小／damaged＝損耗が最大。
const PICK_NEAR := "near"
const PICK_WEAK := "weak"
const PICK_DAMAGED := "damaged"

var params: AiParams

func _init(p_params: AiParams) -> void:
	params = p_params

# --- 敵の集合と距離 ---

## u が攻撃できる敵（対空・対地を見る）。飛行を狙えない駒はその相手を最初から数えない。
func attackable_enemies(state: BattleState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for other in state.units():
		if other.team != u.team and u.attack_against(other) > 0:
			out.append(other)
	return out

## 表 field で測って距離が最小の標的（測れる標的が1つも無ければ null）。同値は col → row の若い方。
## 表は行動ユニットから1枚流したものを渡す＝標的ごとに盤を流し直さない。
func nearest_target(state: BattleState, u: Unit, enemies: Array[Unit], field: Dictionary) -> Unit:
	var best: Unit = null
	var best_c := BattleState.UNREACHABLE
	for e in enemies:
		var c := AiDistance.min_cost_in(field, state.attack_cells(u.id, e.id))
		if c >= BattleState.UNREACHABLE:
			continue
		if best == null or c < best_c or (c == best_c and is_younger_hex(e.pos, best.pos)):
			best = e
			best_c = c
	return best

## 表 field で測って距離が最小のヘックス（測れなければ NO_HEX）。同値は col → row の若い方。
func nearest_hex_in(field: Dictionary, cells: Array[Vector2i]) -> Vector2i:
	var best := NO_HEX
	var best_c := BattleState.UNREACHABLE
	for h in cells:
		var c := int(field.get(h, BattleState.UNREACHABLE))
		if c >= BattleState.UNREACHABLE:
			continue
		if best == NO_HEX or c < best_c or (c == best_c and is_younger_hex(h, best)):
			best = h
			best_c = c
	return best

## 盤上距離が最小の敵ID。同値は col → row の若い方。
func nearest_id_by_board(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var best := ids[0]
	for id in ids:
		var t := state.unit_by_id(id)
		if nearer_hex(u.pos, t.pos, state.unit_by_id(best).pos):
			best = id
	return best

## 盤上距離が最小の敵。同値は col → row の若い方。
func nearest_unit_by_board(from: Vector2i, units: Array[Unit]) -> Unit:
	var best: Unit = units[0]
	for other in units:
		if nearer_hex(from, other.pos, best.pos):
			best = other
	return best

## 盤上距離が最小のヘックス。同値は col → row の若い方。
func nearest_hex_by_board(from: Vector2i, cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	for h in cells:
		if nearer_hex(from, h, best):
			best = h
	return best

## 自陣営以外の拠点hex（中立も含む）。
func hostile_base_hexes(state: BattleState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b in state.bases():
		if b.team != u.team:
			out.append(b.hex)
	return out

## 自陣営の拠点のうち、この駒が入って休める（rest がその陣営を含む）拠点hex。退く先＝回復しに行く先なので、
## 休めない拠点（奪っただけの rest:"player" の砦など）は数えない＝着いても入れない拠点へ歩かせない。
func friendly_base_hexes(state: BattleState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b in state.bases():
		if b.team == u.team and b.can_rest(u.team):
			out.append(b.hex)
	return out

# --- 反撃されない・仕留められる・戦果（doc/gdd/ai.md 用語） ---

## 反撃されない敵を優先し、その中で盤上距離が最小の敵ID（doc/gdd/ai.md 用語 > 反撃されない）。
## 同じ1手なら反撃を受けない相手を撃つほうが得なので、隣に敵がいても距離2で撃てる相手を先に見る。
## 反撃されない敵が1体もいなければ、これまで通り盤上距離が最小の敵を殴る。
func safest_id(state: BattleState, u: Unit, ids: Array[int]) -> int:
	return nearest_id_by_board(state, u, retaliation_free(state, u, ids))

## 反撃されない敵を優先し、その中で戦果が最大の敵ID。同値は盤上距離が最小
## （doc/gdd/ai.md 用語 > 戦果）。近さそのものではなく、同じ1手でより多く削れる相手を選ぶ。
func most_gain_id(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var pool := retaliation_free(state, u, ids)
	var best := pool[0]
	var best_gain := -1
	for id in pool:
		var t := state.unit_by_id(id)
		var gain := Combat.casualties(state, u, t, Hex.distance(u.pos, t.pos) <= 1)
		if gain > best_gain or (gain == best_gain \
				and nearer_hex(u.pos, t.pos, state.unit_by_id(best).pos)):
			best = id
			best_gain = gain
	return best

## ids を反撃されない敵だけに絞る（1体も居なければ ids のまま）＝「反撃されない敵を優先し」。
func retaliation_free(state: BattleState, u: Unit, ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for id in ids:
		if not retaliates(u, state.unit_by_id(id), u.pos):
			out.append(id)
	return out if not out.is_empty() else ids

## ids を仕留められる敵だけに絞る（1体も居なければ ids のまま）＝「仕留められる敵を優先し」。
## いまの位置から撃った結果で数える＝包囲・支援・地形が乗ったあとの損失で決まる
## （doc/gdd/ai.md 用語 > 仕留められる敵）。
func killable_first(state: BattleState, u: Unit, ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for id in ids:
		if can_kill_in_one_hit(state, u, state.unit_by_id(id)):
			out.append(id)
	return out if not out.is_empty() else ids

## from から t を攻撃したとき t が反撃してくるか。判定は戦闘解決（BattleState.attack）と同じ＝
## 距離1で、t が距離1を狙えて（min_range≤1）、t がこちらを攻撃できる（対空・対地）とき。
static func retaliates(u: Unit, t: Unit, from: Vector2i) -> bool:
	if t == null:
		return false
	return Hex.distance(from, t.pos) <= 1 and t.can_reach(1) and t.attack_against(u) > 0

## u が仕留められる相手か＝一撃で倒しきれるか（与ダメは戦闘式で厳密計算＝combat.md は決定的）。
func can_kill_in_one_hit(state: BattleState, u: Unit, t: Unit) -> bool:
	if t == null:
		return false
	var melee := Hex.distance(u.pos, t.pos) <= 1  # 距離1なら近接＝支援が乗る（解決式と一致）
	return Combat.casualties(state, u, t, melee) >= t.troops

## 攻撃後の残兵が最小になる敵ID（確殺を自然に最優先）。同値は盤上距離が近い方 → col → row。
func fewest_left_id(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var best := ids[0]
	var best_left := 1 << 30
	for id in ids:
		var t := state.unit_by_id(id)
		var left := t.troops - Combat.casualties(state, u, t, Hex.distance(u.pos, t.pos) <= 1)
		if left < best_left or (left == best_left \
				and nearer_hex(u.pos, t.pos, state.unit_by_id(best).pos)):
			best = id
			best_left = left
	return best

# --- 空敵（doc/gdd/ai.md 対空得意・空敵） ---

## 対空得意＝対地攻撃力が対空攻撃力以下（doc/gdd/ai.md 対空得意）。駒の性能だけで決まる。
static func air_hunter(u: Unit) -> bool:
	return u.unit_attack <= u.atk_air

## 空敵＝対空得意な駒が攻撃できる飛行の敵（集合）。対空得意でない駒には空敵がいない。
## 対空も対地も0の駒（輸送・バリケード）は攻撃できる敵を持たないので、ここも空になる。
func air_prey(state: BattleState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	if not air_hunter(u):
		return out
	for e in attackable_enemies(state, u):
		if e.is_aerial():
			out.append(e)
	return out

## ids を空敵だけに絞る（空敵が1体も入っていなければ ids のまま）＝「空敵を優先し」の実装。
func air_first(air: Array[Unit], ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for e in air:
		if e.id in ids:
			out.append(e.id)
	return out if not out.is_empty() else ids

# --- 獲物（doc/gdd/ai.md 獲物） ---

## 獲物＝ u が攻撃できる敵のうち、防御力が最小の敵の防御力 +10 までにいるもの（集合）。
## 上限は必ず盤全体の敵から計算する。射程内など狭い範囲から計算し直すと、硬い前衛しか
## 射程に入っていないターンにその前衛が獲物になってしまう（doc/gdd/ai.md 獲物）。
func prey_of(state: BattleState, u: Unit) -> Array[Unit]:
	return prey_among(attackable_enemies(state, u))

## 候補の中から獲物の層を切り出す（防御力が最小のもの +PREY_DEFENSE_BAND まで）。
func prey_among(enemies: Array[Unit]) -> Array[Unit]:
	var min_def := -1
	for e in enemies:
		if min_def < 0 or e.unit_defense < min_def:
			min_def = e.unit_defense
	var out: Array[Unit] = []
	if min_def < 0:
		return out
	for e in enemies:
		if e.unit_defense <= min_def + PREY_DEFENSE_BAND:
			out.append(e)
	return out

## sight 範囲内の獲物（predator の行動開始条件と、狙う獲物の候補）。
func prey_in_sight(state: BattleState, u: Unit) -> Array[Unit]:
	var budget := params.sight_of(state, u)
	var out: Array[Unit] = []
	if budget <= 0:
		return out
	for e in prey_of(state, u):
		if state.sight_reaches(u.pos, e.pos, budget):
			out.append(e)
	return out

## 拠点hexから視線 budget 以内にいる獲物（拠点に攻撃力は無いので対空・対地では絞らない）。
func base_prey_in_sight(state: BattleState, b: Base, budget: int) -> Array[Unit]:
	var out: Array[Unit] = []
	if budget <= 0:
		return out
	var enemies: Array[Unit] = []
	for other in state.units():
		if other.team != b.team:
			enemies.append(other)
	for e in prey_among(enemies):
		if state.sight_reaches(b.hex, e.pos, budget):
			out.append(e)
	return out

## 狙う獲物＝ sight 範囲内の獲物のうち移動距離が最小のもの。
## 移動距離が測れる獲物が1体もいなければ盤上距離が最小のもの（前進の行き先が消えない）。
func hunted_prey(state: BattleState, u: Unit, move_field: Dictionary) -> Unit:
	var candidates := prey_in_sight(state, u)
	if candidates.is_empty():
		return null
	var best := nearest_target(state, u, candidates, move_field)
	return best if best != null else nearest_unit_by_board(u.pos, candidates)

# --- 視線（doc/gdd/ai.md 行動開始条件） ---

## from から視線距離 budget 以内に team 以外のユニットがいるか。壁で途切れ、森ごしでは減衰する
## （全地形コスト1なら盤上距離と一致）。詳細 → doc/gdd/movement.md（視線）
func enemy_in_sight(state: BattleState, from: Vector2i, team: int, budget: int) -> bool:
	if budget <= 0:
		return false
	for other in state.units():
		if other.team != team and state.sight_reaches(from, other.pos, budget):
			return true
	return false

## 選び終えた標的が u の sight 範囲内にいるか（swarm の前進の行）。
func in_sight(state: BattleState, u: Unit, target: Unit) -> bool:
	var budget := params.sight_of(state, u)
	return budget > 0 and state.sight_reaches(u.pos, target.pos, budget)

# --- 損耗・手負い（doc/gdd/ai.md 損耗・手負い） ---

## 損耗率（失った兵の割合）を百分率の整数で。無傷＝0・全滅寸前ほど大きい。
## 割合で見るのは満員兵数が駒ごとに違っても並べられるため（doc/gdd/ai.md 損耗）。
static func damage_percent(u: Unit) -> int:
	if u.max_troops <= 0:
		return 0
	return int(round(float(u.max_troops - u.troops) * 100.0 / float(u.max_troops)))

## 手負い＝ u が攻撃できる敵のうち損耗が最大のもの。同値は移動距離が最小（さらに同値は col → row）。
## 損耗に下限を置かない＝全員無傷のターンは最も近い敵が手負いになり、そこで最初の一噛みが起きる。
## 盤全体から1体だけ選ぶ（範囲の判定は選び終えたこの1体に対して行う）。
func wounded_of(state: BattleState, u: Unit, move_field: Dictionary) -> Unit:
	var best: Unit = null
	var best_pct := -1
	var best_c := BattleState.UNREACHABLE
	for e in attackable_enemies(state, u):
		var pct := damage_percent(e)
		var c := AiDistance.min_cost_in(move_field, state.attack_cells(u.id, e.id))
		if best == null or pct > best_pct \
				or (pct == best_pct and (c < best_c \
					or (c == best_c and is_younger_hex(e.pos, best.pos)))):
			best = e
			best_pct = pct
			best_c = c
	return best

## 損耗が最大の敵ID。同値は盤上距離が近い方 → col → row。
func most_damaged_id(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var best := ids[0]
	for id in ids:
		var t := state.unit_by_id(id)
		var b := state.unit_by_id(best)
		var pct := damage_percent(t)
		var best_pct := damage_percent(b)
		if pct > best_pct or (pct == best_pct and nearer_hex(u.pos, t.pos, b.pos)):
			best = id
	return best

# --- stack 条件（doc/gdd/ai.md stack 条件） ---

## u がいま放てるスキルの種類（複数あれば最初の1つ。持たなければ弱体扱い）。
## swarm の「stack 条件を満たさない敵は殴りに切り替える」行が、掛ける側の種類を知るために読む。
func skill_kind_of(state: BattleState, u: Unit) -> String:
	for option in Formation.available_for(state, u):
		return option.stack_kind()
	return StatusMod.KIND_DEBUFF

## target が stack 条件を満たすか（＝そのスキルを掛ける価値があるか）。
## 強化・弱体は上限（stack 本未満なら掛ける）、解除は下限（stack 本以上なら掛ける）。
## 数えるのは対象1体に掛かった補正だけ＝陣営全体に掛かった補正（グレイス）は数えない。
func stack_passes(state: BattleState, u: Unit, kind: String, target: Unit) -> bool:
	var limit := params.stack_limit_of(state, u)
	if kind == "cleanse":
		return state.debuff_count(target) >= (1 if limit == AiParams.NO_LIMIT else maxi(limit, 1))
	if limit == AiParams.NO_LIMIT:
		return true
	if kind == StatusMod.KIND_DEBUFF:
		return state.debuff_count(target) < limit
	return state.buff_count(target) < limit

## スキル対象を1体に絞る。near＝盤上距離が最小／weak＝防御力が最小／damaged＝損耗が最大。
## 同値は col → row の若い方 → 駒番号の小さい方。
func pick_skill_target(state: BattleState, u: Unit, candidates: Array[Unit], pick: String) -> Unit:
	var best: Unit = candidates[0]
	for c in candidates:
		if _skill_target_better(u, c, best, pick):
			best = c
	return best

func _skill_target_better(u: Unit, c: Unit, best: Unit, pick: String) -> bool:
	var score := 0
	var best_score := 0
	match pick:
		PICK_WEAK:
			score = -c.unit_defense  # 防御が低いほど良い
			best_score = -best.unit_defense
		PICK_DAMAGED:
			score = damage_percent(c)
			best_score = damage_percent(best)
		_:
			score = -Hex.distance(u.pos, c.pos)
			best_score = -Hex.distance(u.pos, best.pos)
	if score != best_score:
		return score > best_score
	if c.pos != best.pos:
		return is_younger_hex(c.pos, best.pos)
	return c.id < best.id

# --- 包囲可能（doc/gdd/ai.md 包囲可能） ---

## target を包囲できるか＝いま隣接している自陣営の駒と、まだ行動しておらず今ターン target の隣へ
## 寄れる味方を合わせて包囲成立数（Surround.GATE）に届くか。行動ユニット自身も数に入る。
## すでに包囲されている相手は隣接数が成立数に達しているので、必ず包囲可能でもある。
## exclude_self＝行動ユニット自身を数えない（下がる行が使う。動いた先では隣接しないため）。
func surround_able(state: BattleState, u: Unit, target: Unit, exclude_self := false) -> bool:
	if target == null or target.team == u.team:
		return false
	var ring := Hex.neighbors(target.pos)
	var count := 0
	for other in state.units():
		if other.team != u.team:
			continue
		if exclude_self and other.id == u.id:
			continue  # 下がる行が呼ぶ＝動いた先では隣接しない自分を頭数に入れない
		if Hex.distance(other.pos, target.pos) == 1:
			count += 1
			continue
		if state.has_moved(other.id) or state.is_done(other.id):
			continue  # もう動けない駒は今ターン中には寄れない
		for h in state.reachable(other.id):
			if h in ring:
				count += 1
				break
	return count >= Surround.GATE

# --- 座標の若さ（同値の決め方）。距離が同じなら col → row の若い方が近い ---

## a のほうが b より col → row で若いか。
static func is_younger_hex(a: Vector2i, b: Vector2i) -> bool:
	var oa := Hex.axial_to_offset(a)
	var ob := Hex.axial_to_offset(b)
	if oa.x != ob.x:
		return oa.x < ob.x
	return oa.y < ob.y

## from から見て a のほうが b より近いか（盤上距離 → col → row）。
static func nearer_hex(from: Vector2i, a: Vector2i, b: Vector2i) -> bool:
	var da := Hex.distance(from, a)
	var db := Hex.distance(from, b)
	if da != db:
		return da < db
	return is_younger_hex(a, b)

static func ids_of(units: Array[Unit]) -> Array[int]:
	var out: Array[int] = []
	for u in units:
		out.append(u.id)
	return out
