extends AiBrain
class_name TraitBrain
## 特性ベースの敵AI。特性ごとの行動ルールを上から順に当て、最初に成立した行を採る。
## 仕様の正本は doc/gdd/ai.md（特性詳細）＝ここは表を写して実行するだけ。
##
## 1行＝行動条件と行動内容の組で、行動内容には対象の選び方まで含む。条件と対象選びを別の軸に
## 分けない＝「放つかどうか」と「誰に放つか」は同じ候補集合を絞る操作なので1箇所に書く。
##
## 1手ずつ返す（AiBrain の約束）。どの行も成立しなければ null＝待機で、その駒はその場に留まる。
## 移動を使い切った駒は、移動を伴う行（占領・前進）を飛ばして次の行を見る。

## 特性表（特性id -> { name, sight, stack }＝AiCatalog.load_default()）。部隊の特性解決に使う。
var presets := {}

## 実装済みの特性id。部隊が未知の値・特性なしなら charge として扱う。
const TRAITS := ["charge", "ambush", "raid", "predator", "swarm", "flee", "withdraw", "preempt"]
const DEFAULT_TRAIT := "charge"

## 輸送ユニット（特殊特性）＝搭載数がこの値以上の駒。特性に重ねて働き、ステージデータには書かない
## ＝駒の性能から決まる。搭載数1の駒（1体だけ乗せて戦う騎乗など）は運搬役として扱わない。
## 詳細 → doc/gdd/ai.md（特殊特性詳細・輸送ユニット）
const TRANSPORT_CAPACITY_MIN := 2

## 行動開始条件が視線距離で決まる特性＝盤に検知域を描く対象（doc/gdd/ai.md 特性詳細）。
const SIGHT_TRAITS := ["ambush", "predator"]

## sight `*`（上限なし）の視線予算。盤のどの距離にも届き、かつ壁（TerrainType.SIGHT_OPAQUE＝1<<20）
## 1枚で必ず遮られる大きさ。「上限なし・ただし壁は遮る」を1つの数で表す（doc/gdd/ai.md データ構成）。
const SIGHT_UNLIMITED := 1 << 16

## stack `-`（上限なし）。強化・弱体では常に成立し、解除では1本以上あれば成立する。
const NO_LIMIT := -1

## 獲物の層の幅。ユニット防御力は10刻みの段なので +10＝「最も柔らかい段とその次の段」。
## 1体に固定すると盤の隅の最弱1体を全員で追って手近な柔らかい敵を素通りする（doc/gdd/ai.md 獲物）。
const PREY_DEFENSE_BAND := 10

const NO_HEX := Vector2i(1 << 30, 1 << 30)  ## 「対象なし」の番兵（盤の外）

## スキル対象の選び方（行ごとに違う）。near＝盤上距離が最小／weak＝防御力が最小／damaged＝損耗が最大。
const PICK_NEAR := "near"
const PICK_WEAK := "weak"
const PICK_DAMAGED := "damaged"

# --- 特性とパラメーターの解決 ---

## u の特性id。部隊に属さない駒・未知の特性は charge（常時起動・前へ出る）として扱う。
func _trait_of(state: BattleState, u: Unit) -> String:
	var id := String(state.squad_of(u.id).get("ai", ""))
	return id if id in TRAITS else DEFAULT_TRAIT

## u のパラメーター（解決順＝部隊の上書き ＞ 特性の既定）。どちらにも無ければ "-"（該当なし）。
func _param(state: BattleState, u: Unit, key: String) -> Variant:
	var squad := state.squad_of(u.id)
	if squad.has(key):
		return squad[key]
	return _preset_param(_trait_of(state, u), key)

## 特性の既定パラメーター。特性表に無ければ "-"。
func _preset_param(trait_id: String, key: String) -> Variant:
	var p: Dictionary = presets.get(trait_id, {})
	return p.get(key, "-")

## 視線の予算に読み替える。数値はそのまま／"*"＝上限なし／それ以外（"-"＝その特性は使わない）は0。
## ai.json は型が混ざる（int と String）ので typeof で分ける。
static func _sight_budget(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return maxi(int(v), 0)
	return SIGHT_UNLIMITED if String(v) == "*" else 0

## stack の本数に読み替える。数値はそのまま／それ以外（"-"）は NO_LIMIT＝上限なし。
static func _stack_limit(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return maxi(int(v), 0)
	return NO_LIMIT

func _sight_of(state: BattleState, u: Unit) -> int:
	return _sight_budget(_param(state, u, "sight"))

# --- 特殊特性＝輸送ユニット（doc/gdd/ai.md 特殊特性詳細） ---

## 輸送ユニットか（搭載数で決まる。乗員の有無は問わない）。
static func _is_transport(u: Unit) -> bool:
	return u != null and u.capacity >= TRANSPORT_CAPACITY_MIN

## 攻撃の行が見る標的。輸送ユニットは攻撃しない＝どの特性でも空になる（自分から仕掛けないだけで、
## 殴られたときの反撃は戦闘解決の側で起きる）。
## 攻撃済みの駒も空。ヒット&アウェイ持ち（move_after_attack）は撃ったあとも動けるので行を見直すが、
## そこで撃てる相手を返すと成立しない攻撃を返し続けることになる。
func _attack_targets(state: BattleState, u: Unit) -> Array[int]:
	var none: Array[int] = []
	if _is_transport(u) or state.has_attacked(u.id):
		return none
	return state.attack_targets(u.id)

## 前進で止まってはいけないマス。輸送ユニットは目的地hex（自陣営以外の拠点）に乗らない
## ＝塞ぐと運んできた占領兵も他の味方も拠点へ入れない。
func _forbidden_cells(state: BattleState, u: Unit) -> Dictionary:
	var out := {}
	if not _is_transport(u):
		return out
	for h in _hostile_base_hexes(state, u):
		out[h] = true
	return out

# --- 行動開始条件（doc/gdd/ai.md 特性の書き方） ---

## u が行動開始しているか判定し、条件が成立したら開始済みにして true。
## 一度成立したら以後は判定しない（成立したあとで敵が離れても止まらない）。
## 攻撃を受けた駒は特性によらずその時点で行動開始する＝BattleState.attack が mark_engaged を呼ぶ。
func _ensure_engaged(state: BattleState, u: Unit) -> bool:
	if state.is_engaged(u.id):
		return true
	var engaged := false
	match _trait_of(state, u):
		"ambush":  # 視線距離が sight 以内に敵 ／ 部隊の誰かが行動開始済み（一斉警戒）
			engaged = _enemy_in_sight(state, u.pos, u.team, _sight_of(state, u)) \
				or _squadmate_engaged(state, u)
		"predator":  # 視線距離が sight 以内に獲物
			engaged = not _prey_in_sight(state, u).is_empty()
		_:  # charge / raid / swarm＝常時
			engaged = true
	if engaged:
		state.mark_engaged(u.id)
	return engaged

## from から視線距離 budget 以内に team 以外のユニットがいるか。壁で途切れ、森ごしでは減衰する
## （全地形コスト1なら盤上距離と一致）。詳細 → doc/gdd/movement.md（視線）
func _enemy_in_sight(state: BattleState, from: Vector2i, team: int, budget: int) -> bool:
	if budget <= 0:
		return false
	for other in state.units():
		if other.team != team and state.sight_reaches(from, other.pos, budget):
			return true
	return false

## u と同じ部隊の誰かが行動開始済みか（一斉警戒）。拠点も部隊の一員として数える＝その拠点が
## 起きていれば、そこから出した駒も自分の sight で敵を捉えられなくても動き出す。
func _squadmate_engaged(state: BattleState, u: Unit) -> bool:
	var idx := state.squad_index_of(u.id)
	if idx < 0:
		return false
	return state.is_squad_engaged(idx) or _squad_unit_engaged(state, idx, u.id)

## 部隊 squad_index の盤上の駒に行動開始済みの者がいるか（except_id は自分＝数えない）。
func _squad_unit_engaged(state: BattleState, squad_index: int, except_id := -1) -> bool:
	if squad_index < 0:
		return false  # 部隊なし同士を「同じ部隊」と数えない
	for other in state.units():
		if other.id != except_id and state.squad_index_of(other.id) == squad_index \
				and state.is_engaged(other.id):
			return true
	return false

## unit の検知半径（索敵範囲の可視化用）。まだ動き出していない駒のうち、行動開始条件が
## 視線距離で決まる特性（SIGHT_TRAITS）なら sight、それ以外は0＝盤に検知域を描かない。
## swarm も sight を持つが行動開始条件は常時＝寝ている状態が無いのでここには入らない。
## `*`（上限なし）は SIGHT_UNLIMITED がそのまま返る。輪の走査は Sight 側が盤の広さで頭打ちにする。
func detection_radius(state: BattleState, unit: Unit) -> int:
	if unit == null or state.is_engaged(unit.id):
		return 0
	if not (_trait_of(state, unit) in SIGHT_TRAITS):
		return 0
	return _sight_of(state, unit)

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
		if u.team == team and state.squad_index_of(u.id) == squad_index:
			list.append(u)
	var dist := {}  # unit_id -> 最寄り敵までの盤上距離（並べ替え中に何度も引くので先に1回だけ）
	for u in list:
		dist[u.id] = _board_distance_to_nearest_enemy(state, u)
	list.sort_custom(func(a: Unit, b: Unit) -> bool:
		# 輸送ユニットは部隊の最後（同じ部隊の駒が乗り込んでから動く。doc/gdd/ai.md 輸送ユニット）
		var ta := _is_transport(a)
		if ta != _is_transport(b):
			return not ta
		var da: int = dist[a.id]
		var db: int = dist[b.id]
		if da != db:
			return da < db
		if a.pos != b.pos:
			return _is_younger_hex(a.pos, b.pos)
		return a.id < b.id)
	return list

## u から最寄りの敵までの盤上距離（敵がいなければ0＝全員同値になり col → row で並ぶ）。
func _board_distance_to_nearest_enemy(state: BattleState, u: Unit) -> int:
	var best := 1 << 30
	for other in state.units():
		if other.team != u.team:
			best = mini(best, Hex.distance(u.pos, other.pos))
	return 0 if best == (1 << 30) else best

# --- 行動ルール（doc/gdd/ai.md 特性詳細） ---

## u が今できる1手（無ければ null＝待機）。特性ごとの行を上から当てる。
func _unit_action(state: BattleState, u: Unit) -> AiAction:
	if state.is_done(u.id) or state.is_stuck(u.id):
		# 行動を終えた／打つ手が無い（囲まれて行ける先も撃てる相手も無い）。
		# ただし輸送ユニットは動き終えていても降ろす行だけは見る＝降車は乗員の手番で、
		# 運んだそのターンに降ろせる（doc/gdd/ai.md 輸送ユニット）。
		if _is_transport(u) and _trait_of(state, u) == "raid" and _ensure_engaged(state, u):
			return _unload_now_row(state, u)
		return null
	if not _ensure_engaged(state, u):
		return null  # まだ動き出していない
	match _trait_of(state, u):
		"raid":
			return _raid_action(state, u)
		"predator":
			return _weak_action(state, u)
		"swarm":
			return _swarm_action(state, u)
		"flee":
			return _flee_action(state, u)
		"withdraw":
			return _withdraw_action(state, u)
		"preempt":
			return _preempt_action(state, u)
	return _charge_action(state, u)  # charge / ambush は動き出したあとの行が同じ

## charge（突撃）／ambush（待ち伏せ）の行動ルール。
## 1 占領兵で移動範囲に自陣営以外の拠点 → 盤上距離が最小の拠点へ移動して占領
## 2 スキル射程内に stack 条件を満たす対象 → 盤上距離が最小の対象にスキル
## 3 間接攻撃できる駒で、移動範囲のどこかから撃てる敵 → 空敵を優先し、盤上距離が最小のその敵へ最大間合い
## 4 攻撃射程内に敵 → 空敵を優先し、次に反撃されない敵を優先し、その中で盤上距離が最小の敵を攻撃
## 5 移動距離が測れる敵 → 空敵を優先し、その中で移動距離が最小の敵へ最大前進
## 6 地形距離が測れる敵 → 地形距離が最小の敵へ見込前進
## 7 盤上に攻撃できる敵 → 盤上距離が最小の敵へ直線寄せ
func _charge_action(state: BattleState, u: Unit) -> AiAction:
	var row := _capture_row(state, u)
	if row != null:
		return row
	row = _skill_row(state, u, PICK_NEAR)
	if row != null:
		return row
	var air := _air_prey(state, u)
	row = _standoff_row(state, u, null, air)  # 3 空敵を優先（撃てる空敵が居なければ全体から）
	if row == null:
		row = _standoff_row(state, u)
	if row != null:
		return row
	var in_range := _attack_targets(state, u)
	if not in_range.is_empty():
		return AiAction.attack(u.id, _safest_id(state, u, _air_first(air, in_range)))
	return _advance_to_nearest_enemy(state, u, true)

## raid（拠点攻略）の行動ルール。1/2 は突撃と同じで、8〜10 の行き先が敵ではなく拠点。
## 3 撃てる位置へずれる／4 経路上の敵を殴る／5/6 降ろす（輸送ユニットだけに当たる）／
## 7 乗る（乗る側だけに当たる）。
## 拠点への距離は拠点hexそのものまで測る（拠点は攻撃の標的ではない）。
## 向かう拠点が盤上に無ければ待機する＝敵を追わない。
func _raid_action(state: BattleState, u: Unit) -> AiAction:
	var row := _capture_row(state, u)
	if row != null:
		return row
	row = _skill_row(state, u, PICK_NEAR)
	if row != null:
		return row
	# 3 撃てる位置へずれる（隣接されて撃てない射程2以上の駒を、撃てるマスへ置く行）
	row = _shift_to_shoot_row(state, u)
	if row != null:
		return row
	# 4 経路上の敵を殴る
	var blocker := _blocking_enemy_id(state, u, _attack_targets(state, u))
	if blocker >= 0:
		return AiAction.attack(u.id, blocker)
	# 5/6 降ろす（乗員を持つ駒＝輸送ユニットにしか当たらない）
	row = _unload_now_row(state, u)
	if row != null:
		return row
	row = _unload_move_row(state, u)
	if row != null:
		return row
	# 7 乗る（同じ部隊の輸送ユニットへ。便乗のほうが早いときだけ）
	row = _board_row(state, u)
	if row != null:
		return row
	if not _can_advance(state, u):
		return null
	var goals := _hostile_base_hexes(state, u)
	if goals.is_empty():
		return null
	# 8 移動距離／9 地形距離。測れた時点でその行が成立＝縮むマスが無ければ現在地に留まる。
	var move_field := state.move_cost_field(u.id, u.pos)
	var goal := _nearest_hex_in(move_field, goals)
	if goal != NO_HEX:
		return _advance(state, u, state.move_cost_field(u.id, goal), [goal])
	var terrain_field := state.terrain_cost_field(u.id, u.pos)
	goal = _nearest_hex_in(terrain_field, goals)
	if goal != NO_HEX:
		return _advance(state, u, state.terrain_cost_field(u.id, goal), [goal])
	# 10 盤上に自陣営以外の拠点がある → 盤上距離が最小の拠点へ直線寄せ
	return _advance_straight(state, u, _nearest_hex_by_board(u.pos, goals))

## weak（弱者狙い）の行動ルール。前衛を避けて柔らかい敵へ回り込む。
## 1 占領／2 防御力が最小の対象にスキル
## 3 間接攻撃できる駒で、いま一撃で倒せる敵がおらず狙う獲物を撃てる → 狙う獲物へ最大間合い
## 4 攻撃射程内に獲物 → 攻撃後の残兵が最小となる獲物を攻撃
## 5 攻撃射程内に一撃で倒せる敵 → 反撃されない敵を優先し、その中で盤上距離が最小の敵を攻撃
## 6〜9 狙う獲物へ 回り込み → 最大前進 → 見込前進 → 直線寄せ
##
## 狙う獲物＝ sight 範囲内の獲物のうち移動距離が最小のもの（測れる獲物がいなければ盤上距離が最小）。
## 3 と 6〜9 はどれもこの1体へ向かう＝行の間で行き先が入れ替わらない。sight の判定は毎ターン行う＝
## 起動後に獲物が視線から消えたら前進だけ止まる（攻撃とスキルは続く）。
##
## 3 が「一撃で倒せる敵がいない」を条件に持つのは、倒しきれる相手から下がらないため。倒しても
## 反撃は受ける（同時解決）が、獲物を1体減らす価値のほうが大きい。
func _weak_action(state: BattleState, u: Unit) -> AiAction:
	var row := _capture_row(state, u)
	if row != null:
		return row
	row = _skill_row(state, u, PICK_WEAK)
	if row != null:
		return row
	var in_range := _attack_targets(state, u)
	var prey_ids := _ids_of(_prey_of(state, u))
	var prey_in_range: Array[int] = []
	var killable: Array[int] = []
	for id in in_range:
		if id in prey_ids:
			prey_in_range.append(id)
		if _can_kill_in_one_hit(state, u, state.unit_by_id(id)):
			killable.append(id)
	var can_move := _can_advance(state, u)
	var move_field := state.move_cost_field(u.id, u.pos) if can_move else {}
	var target := _hunted_prey(state, u, move_field) if can_move else null
	if killable.is_empty() and target != null:
		row = _standoff_row(state, u, target)
		if row != null:
			return row
	if not prey_in_range.is_empty():
		return AiAction.attack(u.id, _fewest_left_id(state, u, prey_in_range))
	if not killable.is_empty():
		return AiAction.attack(u.id, _safest_id(state, u, killable))
	if not can_move or target == null:
		return null  # 移動を使い切った／sight 範囲内に獲物がいない＝前進はしない
	var cells := state.attack_cells(u.id, target.id)
	# 5 回り込み（迂回距離）。標的自身のZOCは外して測る＝外さないと隣へ入れず必ず測れない。
	# 表は標的から流して1枚だけ作り、自分のマスが載っているかで「測れる」を見る（両向きで一致する）。
	var detour_field := state.detour_cost_field_to(u.id, target.pos, target.id)
	if detour_field.has(u.pos):
		return _advance(state, u, detour_field, cells)
	if state.min_cost_in(move_field, cells) < BattleState.UNREACHABLE:
		return _advance(state, u, state.move_cost_field(u.id, target.pos), cells)
	if state.terrain_distance(u.id, cells) < BattleState.UNREACHABLE:
		return _advance(state, u, state.terrain_cost_field(u.id, target.pos), cells)
	return _advance_straight(state, u, target.pos)

## swarm（群れ）の行動ルール。傷ついた敵へ集まり、無傷の敵には頭数が揃ってから手を出す。
## 1 間接攻撃できる駒で、移動範囲のどこかから手負いを撃てる → 手負いへ最大間合い
## 2 攻撃射程内に手負い → 手負いを攻撃（ここだけ包囲を条件にしない＝単独でも噛みつく）
## 3 間接攻撃できる駒で、移動範囲のどこかから自分を除いても包囲可能な敵を撃てる
##   → 損耗が最大のその敵へ最大間合い
## 4 攻撃射程内に stack 条件を満たさない包囲可能な敵 → 損耗が最大の敵を攻撃
## 5 スキル射程内に stack 条件を満たす包囲可能な対象 → 損耗が最大の対象にスキル
## 6 攻撃射程内に包囲可能な敵 → 損耗が最大の敵を攻撃
## 7/8 sight 範囲内の手負いへ 最大前進 → 見込前進
## 9/10 移動距離／地形距離が最小の敵へ 最大前進 → 見込前進
## 11 盤上に攻撃できる敵 → 盤上距離が最小の敵へ直線寄せ
##
## 1・3 で下がった駒は包囲の頭数から外れる（隣接しなくなる）。包囲は間接にも効くので、囲むのは
## 近接の駒に任せ、間接の駒は外から撃つという住み分けになる。3 が「自分を除いても包囲可能」を
## 見るのはそのため＝数えたまま下がると、動いた先で包囲が崩れて 4・6 が不成立になる。
##
## 拠点は取らない（占領の行を持たない）。占領兵を混ぜても拠点へは向かわない。
func _swarm_action(state: BattleState, u: Unit) -> AiAction:
	var move_field := state.move_cost_field(u.id, u.pos)
	var wounded := _wounded_of(state, u, move_field)
	if wounded != null:
		var standoff := _standoff_row(state, u, wounded)
		if standoff != null:
			return standoff
	var in_range := _attack_targets(state, u)
	if wounded != null and wounded.id in in_range:
		return AiAction.attack(u.id, wounded.id)
	# 3 自分を除いても包囲可能な敵へ最大間合い
	var pinned := _surroundable_standoff_target(state, u)
	if pinned != null:
		var back := _standoff_row(state, u, pinned)
		if back != null:
			return back
	var kind := _skill_kind_of(state, u)
	var surroundable: Array[int] = []
	var stacked: Array[int] = []  # stack 条件を満たさない＝もう重ねる価値がない相手
	for id in in_range:
		var t := state.unit_by_id(id)
		if not _surround_able(state, u, t):
			continue
		surroundable.append(id)
		if not _stack_passes(state, u, kind, t):
			stacked.append(id)
	if not stacked.is_empty():
		return AiAction.attack(u.id, _most_damaged_id(state, u, stacked))
	var row := _skill_row(state, u, PICK_DAMAGED, true)
	if row != null:
		return row
	if not surroundable.is_empty():
		return AiAction.attack(u.id, _most_damaged_id(state, u, surroundable))
	if not _can_advance(state, u):
		return null
	# 7/8 手負いへ。sight 範囲内に居るときだけ（選び終えた1体が範囲に入っているかを見る）。
	if wounded != null and _in_sight(state, u, wounded):
		var cells := state.attack_cells(u.id, wounded.id)
		if state.min_cost_in(move_field, cells) < BattleState.UNREACHABLE:
			return _advance(state, u, state.move_cost_field(u.id, wounded.pos), cells)
		if state.terrain_distance(u.id, cells) < BattleState.UNREACHABLE:
			return _advance(state, u, state.terrain_cost_field(u.id, wounded.pos), cells)
	return _advance_to_nearest_enemy(state, u)

# --- 行の部品 ---

## 占領の行＝占領兵で、移動範囲に自陣営以外の拠点があれば盤上距離が最小の拠点へ動く。
## 拠点hexへ進入すればその場で占領（BattleState.move_unit）。
func _capture_row(state: BattleState, u: Unit) -> AiAction:
	if not u.can_capture or not _can_advance(state, u):
		return null
	var reach := state.reachable(u.id)
	var best := NO_HEX
	for b in state.bases():
		if b.team == u.team or b.hex == u.pos or not (b.hex in reach):
			continue  # 自陣営の拠点は対象外（敵・中立を取る）。すでに乗っているマスは動く先にならない
		if state.unit_at(b.hex) != null:
			continue  # 味方輸送が拠点に乗っている＝そこへ動くと占領ではなく乗車になる
		if best == NO_HEX or _nearer_hex(u.pos, b.hex, best):
			best = b.hex
	return AiAction.move_to(u.id, best) if best != NO_HEX else null

## スキルの行＝掛けられる対象のうち stack 条件を満たすものを集め、pick で1体に絞って放つ。
## 放つと発動者は行動完了になるので攻撃より前に置く。移動後でも放てる（doc/gdd/skills.md）。
## require_surround＝対象が包囲可能であることも条件に足す（swarm）。
func _skill_row(state: BattleState, u: Unit, pick: String, require_surround := false) -> AiAction:
	for option in Formation.available_for(state, u):
		if not bool(option.get("needs_target", true)):
			return AiAction.skill(u.id, option, u.pos)  # 陣営全体＝対象を選ばない
		var kind := _skill_kind(option)
		var candidates: Array[Unit] = []
		for other in state.units():
			if not Formation.can_target(state, option, other.pos):
				continue
			if require_surround and not _surround_able(state, u, other):
				continue
			if not _stack_passes(state, u, kind, other):
				continue
			candidates.append(other)
		if candidates.is_empty():
			continue
		return AiAction.skill(u.id, option, _pick_skill_target(state, u, candidates, pick).pos)
	return null

## 最大間合いの行＝間接攻撃できる駒が、撃てる敵から距離を取ってから撃つための移動（doc/gdd/ai.md
## 用語 > 最大間合い）。撃つのはこの行ではなく、移動後にもう一度表を上から当てた攻撃の行。
##
## 標的を渡すとその1体へ間合いを取る（weak＝狙う獲物・swarm＝手負い＝前進の行と同じ1体へ向かう）。
## 渡さなければ「移動範囲のどこかから撃てる敵」のうち盤上距離が最小のもの（charge / ambush）。
## どちらもいまの位置から撃てるかは問わない＝射程の外から詰めるときも射程の外縁で止まる。
##
## 行き先はその標的を撃てるマスのうち標的への盤上距離が最大のもので、同値は現在地優先 →
## col → row の若い方。
##
## 近接しかできない駒は撃てるマスがどれも距離1＝最大間合いが現在地と同じになるので、この行では
## 動かない。射程で先に弾いておくと、盤を流さずに済む。
func _standoff_row(state: BattleState, u: Unit, target: Unit = null,
		pool: Array[Unit] = []) -> AiAction:
	if u.attack_range < 2 or _is_transport(u) or not _can_advance(state, u):
		return null
	var reach := state.reachable(u.id)
	var cells: Array[Vector2i] = []
	if target != null:
		cells = _standing_attack_cells(state, u, target, reach)
		if cells.is_empty():
			return null  # 今ターン撃てる位置が無い＝前進の行に任せる
	else:
		for e in (pool if not pool.is_empty() else _attackable_enemies(state, u)):
			if target != null and not _nearer_hex(u.pos, e.pos, target.pos):
				continue
			var spots := _standing_attack_cells(state, u, e, reach)
			if spots.is_empty():
				continue  # 今ターン撃てる位置が無い敵は標的にしない（前進の行に任せる）
			target = e
			cells = spots
	if target == null:
		return null
	var best := NO_HEX
	var best_d := -1
	for h in cells:
		var d := Hex.distance(h, target.pos)
		var better := best == NO_HEX or d > best_d
		if not better and d == best_d and best != u.pos:
			better = h == u.pos or _is_younger_hex(h, best)
		if better:
			best = h
			best_d = d
	return AiAction.move_to(u.id, best) if best != u.pos else null

## swarm #3 の標的＝移動範囲のどこかから撃てて、自分を除いても包囲可能な敵のうち損耗が最大の
## もの（doc/gdd/ai.md swarm #3）。同値は盤上距離 → col → row。
##
## 自分を除いて数えるのは、下がった先では隣接しなくなって包囲の頭数から外れるため。数えたまま
## 下がると、動いた先で包囲が崩れて攻撃の行が不成立になり、撃たないまま前進の行へ落ちる。
func _surroundable_standoff_target(state: BattleState, u: Unit) -> Unit:
	if u.attack_range < 2 or _is_transport(u) or not _can_advance(state, u):
		return null
	var reach := state.reachable(u.id)
	var ids: Array[int] = []
	for e in _attackable_enemies(state, u):
		if not _surround_able(state, u, e, true):
			continue
		if _standing_attack_cells(state, u, e, reach).is_empty():
			continue  # 今ターン撃てる位置が無い敵は標的にしない（前進の行に任せる）
		ids.append(e.id)
	if ids.is_empty():
		return null
	return state.unit_by_id(_most_damaged_id(state, u, ids))

## target を攻撃できるマスのうち、今ターン実際に立てるもの。
## 駒の居るマス＝乗れる味方輸送は除く（前進と同じ理由＝踏むと乗るつもりのない乗車になる）。
## 自分が今いるマスは「動かない」という選択肢なので残す。
func _standing_attack_cells(state: BattleState, u: Unit, target: Unit,
		reach: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in state.attack_cells(u.id, target.id):
		if not (h in reach):
			continue
		if h != u.pos and state.unit_at(h) != null:
			continue
		out.append(h)
	return out

# --- 経路上の敵（doc/gdd/ai.md 経路上の敵） ---

## raid の「撃てる位置へずれる行」＝経路上の敵を撃てるマスのうち、拠点へ最も近いマスへ動く
## （doc/gdd/ai.md raid #3）。最大間合いにしないのは、下がると拠点から遠ざかって目の前の敵を
## 素通りする圧が鈍るため。撃つのはこの行ではなく、移動後にもう一度表を上から当てた #4。
##
## 経路上の敵を選ぶときの「撃てる敵」は移動範囲のどこかから撃てる敵＝隣接されて撃てない
## 射程2以上の駒でも、道を塞いでいる相手を見つけられる。
##
## 攻撃済みの駒は動かさない。ヒット&アウェイ持ち（move_after_attack）はもう撃てないので、
## 撃てる位置を探すより前進の行に任せたほうが拠点へ寄る。
func _shift_to_shoot_row(state: BattleState, u: Unit) -> AiAction:
	if u.attack_range < 2 or _is_transport(u) or state.has_attacked(u.id) \
			or not _can_advance(state, u):
		return null
	var goals := _hostile_base_hexes(state, u)
	if goals.is_empty():
		return null
	var reach := state.reachable(u.id)
	var shootable: Array[int] = []
	var cells_of := {}
	for e in _attackable_enemies(state, u):
		var spots := _standing_attack_cells(state, u, e, reach)
		if spots.is_empty():
			continue
		shootable.append(e.id)
		cells_of[e.id] = spots
	var blocker := _blocking_enemy_id(state, u, shootable)
	if blocker < 0:
		return null
	var cells: Array[Vector2i] = cells_of[blocker]
	var best := _nearest_cell_to_goals(state, u, cells, goals)
	return AiAction.move_to(u.id, best) if best != NO_HEX and best != u.pos else null

## cells のうち拠点へ最も近いマス（1つも測れなければ NO_HEX）。測る順は前進と同じ＝
## 移動距離 → 地形距離 → 盤上距離。
func _nearest_cell_to_goals(state: BattleState, u: Unit, cells: Array[Vector2i],
		goals: Array[Vector2i]) -> Vector2i:
	var goal := _nearest_hex_in(state.move_cost_field(u.id, u.pos), goals)
	if goal != NO_HEX:
		return _nearest_cell_in_field(u, cells, state.move_cost_field(u.id, goal))
	goal = _nearest_hex_in(state.terrain_cost_field(u.id, u.pos), goals)
	if goal != NO_HEX:
		return _nearest_cell_in_field(u, cells, state.terrain_cost_field(u.id, goal))
	goal = _nearest_hex_by_board(u.pos, goals)
	var board := {}
	for h in cells:
		board[h] = Hex.distance(h, goal)
	return _nearest_cell_in_field(u, cells, board)

## 表 field で測って距離が最小のマス。同値は現在地を優先し、次に col → row の若い方
## （最大間合いと同じ決め方＝動かずに済むならその手を選ぶ）。
func _nearest_cell_in_field(u: Unit, cells: Array[Vector2i], field: Dictionary) -> Vector2i:
	var best := NO_HEX
	var best_c := BattleState.UNREACHABLE
	for h in cells:
		var c := int(field.get(h, BattleState.UNREACHABLE))
		if c >= BattleState.UNREACHABLE:
			continue
		var better := best == NO_HEX or c < best_c
		if not better and c == best_c and best != u.pos:
			better = h == u.pos or _is_younger_hex(h, best)
		if better:
			best = h
			best_c = c
	return best

## 渡した「撃てる敵」のうち、拠点への道を塞いでいる1体（居なければ -1）。どこまでを撃てる敵と
## 数えるかは呼ぶ行が決める＝殴る行はいまの位置から撃てる敵、動く行は移動範囲のどこかから
## 撃てる敵（doc/gdd/ai.md 経路上の敵）。
## 塞いでいるかは、渡した敵をまとめてどけたと仮定して道が良くなるかで見る。
## 1体ずつ試さないのは、通路を2体で塞がれるとどちらを外しても道が開かないため。
##
## 良くなるのは2つ。移動距離が縮む（体で塞いでいる）か、迂回距離が測れないところから
## 測れるようになる（ZOCで足を止めている）か。迂回距離を縮んだかで見ないのは、隣に立って
## いるだけの敵でも、どければ避けるZOCが減って必ず短くなるため（それでは横の敵にもつられる）。
func _blocking_enemy_id(state: BattleState, u: Unit, shootable: Array[int]) -> int:
	if shootable.is_empty():
		return -1
	var goals := _hostile_base_hexes(state, u)
	if goals.is_empty():
		return -1
	var ignore := {}
	for id in shootable:
		ignore[id] = true
	if not _route_improves(state, u, goals, ignore):
		return -1
	# 一番前で塞いでいる駒＝拠点への地形距離が最小のもの。同値は盤上距離 → col → row。
	var best := -1
	var best_c := BattleState.UNREACHABLE
	for id in shootable:
		var e := state.unit_by_id(id)
		var c := BattleState.UNREACHABLE
		for g in goals:
			c = mini(c, int(state.travel_cost_field(g, u.move_type, u.move)
				.get(e.pos, BattleState.UNREACHABLE)))
		if best < 0 or c < best_c \
				or (c == best_c and _nearer_hex(u.pos, e.pos, state.unit_by_id(best).pos)):
			best = id
			best_c = c
	return best

## ignore の駒をどけると拠点への道が良くなるか。
func _route_improves(state: BattleState, u: Unit, goals: Array[Vector2i], ignore: Dictionary) -> bool:
	var before := state.min_cost_in(state.move_cost_field(u.id, u.pos), goals)
	var after := state.min_cost_in(state.move_cost_field_without(u.id, u.pos, ignore), goals)
	if after < before:
		return true  # 体で道を塞いでいる（測れるようになった場合も含む）
	var zoc_before := state.min_cost_in(state.detour_cost_field(u.id, u.pos), goals)
	if zoc_before < BattleState.UNREACHABLE:
		return false  # ZOCを避ける道が残っている＝足は止まっていない
	return state.min_cost_in(state.detour_cost_field(u.id, u.pos, -1, ignore), goals) \
		< BattleState.UNREACHABLE

# --- 降ろす・乗る（doc/gdd/ai.md raid #4〜#6・輸送ユニット） ---

## 4/5行のうち「いまの位置から降ろす」部分。降車は乗員の手番なので、輸送が動き終えていても打てる
## ＝運んだそのターンに降ろせる。1手で1体ずつ返し、次の手で残りを見る。
## 4 占領兵の乗員を自陣営以外の拠点hexへ降ろす（＝降りた瞬間に占領）
## 5 拠点に隣接する降車先へ降ろす。降りた先から拠点へたどり着けない乗員は乗せたまま
func _unload_now_row(state: BattleState, u: Unit) -> AiAction:
	var list := state.passengers(u.id)
	var goals := _hostile_base_hexes(state, u)
	if list.is_empty() or goals.is_empty():
		return null
	for i in list.size():
		if not (list[i] as Unit).can_capture:
			continue  # 占領できない駒を拠点hexへ降ろしても占領は起きず、拠点を塞ぐだけ
		var cells := state.unload_cells(u.id, i)
		var best := NO_HEX
		for b in goals:
			if b in cells and (best == NO_HEX or _is_younger_hex(b, best)):
				best = b
		if best != NO_HEX:
			return AiAction.unload(u.id, i, best)
	for i in list.size():
		var p: Unit = list[i]
		var best := NO_HEX
		for h in state.unload_cells(u.id, i):
			if best != NO_HEX and not _is_younger_hex(h, best):
				continue
			for b in goals:
				if Hex.distance(h, b) == 1 and _reaches(state, p, h, b):
					best = h
					break
		if best != NO_HEX:
			return AiAction.unload(u.id, i, best)
	return null

## 4/5行のうち「降ろせるマスへ移動する」部分。降車は移動後に _unload_now_row が拾う。
## 行き先は、乗員を降ろせるマスのうち拠点に最も近いもの（同値は col → row の若い方）。
func _unload_move_row(state: BattleState, u: Unit) -> AiAction:
	var list := state.passengers(u.id)
	var goals := _hostile_base_hexes(state, u)
	if list.is_empty() or goals.is_empty() or not _can_advance(state, u):
		return null
	var forbidden := _forbidden_cells(state, u)  # 目的地hexに乗らない＝降ろすための移動でも同じ
	var best := NO_HEX
	var best_d := 1 << 30
	for h in state.reachable(u.id):
		if h == u.pos or forbidden.has(h) or state.unit_at(h) != null:
			continue
		for b in goals:
			var d := Hex.distance(h, b)
			if best != NO_HEX and (d > best_d or (d == best_d and not _is_younger_hex(h, best))):
				continue
			if not _can_unload_near(state, u, list, h, b):
				continue
			best = h
			best_d = d
	return AiAction.move_to(u.id, best) if best != NO_HEX else null

## from_hex に立てば、いずれかの乗員を拠点 b に絡めて降ろせるか（移動先の見積もり）。
## 降車先は隣接1マスの特例で測る＝乗員の移動力に関係なく輸送の隣へは降ろせる。
func _can_unload_near(state: BattleState, u: Unit, list: Array, from_hex: Vector2i, b: Vector2i) -> bool:
	for i in list.size():
		var p: Unit = list[i]
		if state.has_moved(p.id):
			continue  # 乗車したターンは降りられない
		if p.can_capture and Hex.distance(from_hex, b) == 1 and _vacant(state, u, b) \
				and state.can_enter_terrain(p, b):
			return true
		for d in Hex.neighbors(from_hex):
			if Hex.distance(d, b) != 1 or not _vacant(state, u, d):
				continue
			if state.can_enter_terrain(p, d) and _reaches(state, p, d, b):
				return true
	return false

## hex が空くか。輸送自身が立っているマスは、そこから動けば空く＝空き扱い。
func _vacant(state: BattleState, u: Unit, hex: Vector2i) -> bool:
	var occ := state.unit_at(hex)
	return occ == null or occ.id == u.id

## p が from から goal へ自力でたどり着けるか＝地形距離が測れるか（doc/gdd/ai.md たどり着ける）。
## 道のり表は goal 自身を必ず 0 で載せる（起点だから）ので、goal に入れるかは別に見る
## ＝入れない地形の拠点へ「隣までは行ける」を、たどり着けると読まない。
func _reaches(state: BattleState, p: Unit, from: Vector2i, goal: Vector2i) -> bool:
	if not state.can_enter_terrain(p, goal):
		return false
	return state.travel_cost_field(goal, p.move_type, p.move).has(from)

## 6行 乗る＝移動範囲に、同じ部隊で空きのある輸送ユニットがあり、便乗のほうが拠点へ早く着くなら乗る。
## 乗車は移動そのもの（BattleState.move_unit が輸送のマスへの移動を搭乗に変える）。
## 目的地の違う部隊の輸送に乗ると見当違いの場所へ運ばれるので、同じ部隊の輸送だけを数える。
func _board_row(state: BattleState, u: Unit) -> AiAction:
	if _is_transport(u) or not _can_advance(state, u):
		return null
	var squad := state.squad_index_of(u.id)
	var goals := _hostile_base_hexes(state, u)
	if squad < 0 or goals.is_empty():
		return null
	var walk := _arrival_turns(state, u, goals, 0)
	var reach := state.reachable(u.id)
	var best := NO_HEX
	var best_turns := BattleState.UNREACHABLE
	for t in state.units():
		if not _is_transport(t) or state.squad_index_of(t.id) != squad:
			continue
		if not state.can_board(u, t) or not (t.pos in reach):
			continue  # 満車・敵陣営・輸送どうしは can_board が弾く
		var ride := _arrival_turns(state, t, goals, 1)  # +1＝最後に降りて拠点へ入るぶん
		if ride >= walk:
			continue  # 便乗のほうが早い、が成立しない（同値なら乗らない）
		if best == NO_HEX or ride < best_turns \
				or (ride == best_turns and _nearer_hex(u.pos, t.pos, best)):
			best = t.pos
			best_turns = ride
	return AiAction.move_to(u.id, best) if best != NO_HEX else null

## goals のいずれかへ着くまでのターン数＝地形距離 ÷ 移動力の切り上げ（最寄りの拠点で測る）。
## extra は便乗の +1。測れない・移動力0は UNREACHABLE＝徒歩が測れなければ便乗が必ず勝つ。
func _arrival_turns(state: BattleState, u: Unit, goals: Array[Vector2i], extra: int) -> int:
	var field := state.terrain_cost_field(u.id, u.pos)
	var best := BattleState.UNREACHABLE
	for g in goals:
		best = mini(best, _turns_needed(int(field.get(g, BattleState.UNREACHABLE)), u.move))
	return BattleState.UNREACHABLE if best >= BattleState.UNREACHABLE else best + extra

static func _turns_needed(cost: int, move: int) -> int:
	if cost >= BattleState.UNREACHABLE or move <= 0:
		return BattleState.UNREACHABLE
	return int(ceil(float(cost) / float(move)))

## 前進の行（敵向け・突撃と群れの末尾が共有）。移動距離 → 地形距離 → 盤上距離の順に測り、
## 測れた時点でその行が成立する＝縮むマスが無ければ現在地に留まって待機になる。
func _advance_to_nearest_enemy(state: BattleState, u: Unit, prefer_air := false) -> AiAction:
	if not _can_advance(state, u):
		return null
	var enemies := _attackable_enemies(state, u)
	if enemies.is_empty():
		return null
	var move_field := state.move_cost_field(u.id, u.pos)
	# 空敵の優先は最大前進の行だけ。見込前進・直線寄せまで優先すると、今ターン届かない飛行1体に
	# 盤上の対空得意が全員吸われる（doc/gdd/ai.md charge #6・#7 の注記）。
	var target: Unit = null
	if prefer_air:
		target = _nearest_target(state, u, _air_prey(state, u), move_field)
	if target == null:
		target = _nearest_target(state, u, enemies, move_field)
	if target != null:
		return _advance(state, u, state.move_cost_field(u.id, target.pos),
			state.attack_cells(u.id, target.id))
	target = _nearest_target(state, u, enemies, state.terrain_cost_field(u.id, u.pos))
	if target != null:
		return _advance(state, u, state.terrain_cost_field(u.id, target.pos),
			state.attack_cells(u.id, target.id))
	return _advance_straight(state, u, _nearest_unit_by_board(u.pos, enemies).pos)

## いま移動を伴う行を実行できるか（移動を使い切っていないか）。
func _can_advance(state: BattleState, u: Unit) -> bool:
	return state.can_still_move(u.id)

# --- 前進（doc/gdd/ai.md 前進） ---

## 標的から流した道のり表の勾配を降りて、移動範囲のうち距離が最も縮むマスへ動く1手。
## 同値のマスは col → row の若い方、縮むマスが1つも無ければ現在地に留まる（＝null＝待機）。
## goal_cells＝標的に攻撃可能なマス（拠点なら拠点hex）＝そこに立てば距離0。表は標的から流して
## いるので、そのままでは「標的のマスからの遠さ」になり、懐に死角のある駒（min_range≥2）が
## 攻撃できない位置へ詰めてしまう。攻撃可能なマスを0として読むことで距離の定義と揃える。
## allow＝止まってよいマス（空＝制限なし）。preempt が脅威圏の外だけに絞るために渡す。
func _advance(state: BattleState, u: Unit, field: Dictionary, goal_cells: Array,
		allow: Dictionary = {}) -> AiAction:
	var goals := {}
	for c in goal_cells:
		goals[c] = true
	var forbidden := _forbidden_cells(state, u)
	var best := u.pos
	var best_c := _advance_score(field, goals, u.pos)
	for h in state.reachable(u.id):
		if not allow.is_empty() and not allow.has(h):
			continue
		if forbidden.has(h) or state.unit_at(h) != null:
			continue  # 駒の居るマス＝乗れる味方輸送。前進で踏むと乗るつもりのない乗車になる
		var c := _advance_score(field, goals, h)
		if c < best_c or (c == best_c and best != u.pos and _is_younger_hex(h, best)):
			best = h
			best_c = c
	return AiAction.move_to(u.id, best) if best != u.pos else null

## 直線寄せ＝盤上距離が縮むマスへ動く（距離が測れないときに使う）。壁の向こうの標的へ
## 壁際まで詰めて止まる動きになる。縮むマスが無ければ現在地。
func _advance_straight(state: BattleState, u: Unit, goal: Vector2i,
		allow: Dictionary = {}) -> AiAction:
	var forbidden := _forbidden_cells(state, u)
	var best := u.pos
	var best_d := Hex.distance(u.pos, goal)
	for h in state.reachable(u.id):
		if not allow.is_empty() and not allow.has(h):
			continue
		if forbidden.has(h) or state.unit_at(h) != null:
			continue  # 前進では味方輸送のマスに止まらない（乗るかどうかは乗る行が決める）
		var d := Hex.distance(h, goal)
		if d < best_d or (d == best_d and best != u.pos and _is_younger_hex(h, best)):
			best = h
			best_d = d
	return AiAction.move_to(u.id, best) if best != u.pos else null

## hex に立ったときの標的への距離。攻撃可能なマスは0、表に無いマスは測れない（UNREACHABLE）。
static func _advance_score(field: Dictionary, goals: Dictionary, hex: Vector2i) -> int:
	if goals.has(hex):
		return 0
	return int(field.get(hex, BattleState.UNREACHABLE))

# --- 脅威圏と間合取り（doc/gdd/ai.md 脅威圏・間合取り） ---

## 脅威圏＝盤上の敵のどれかが移動力ぶん動いた先から u を攻撃できるマスの集合 { ヘックス: true }。
## 敵ごとに移動距離で動ける範囲を測り、そこから射程を伸ばして重ねる。相手が u を攻撃できるか
## （対空・対地）まで見る＝対空攻撃力の無い敵は飛行の駒を脅威圏に入れられない。
##
## ZOCは数えず、u 自身も敵の道を塞ぐ壁に数えない（ignore）。u はこれから動くので、いま自分が
## 敵を縛っていることを当てにすると、隣接から下がる手がそもそも成立しなくなる。
func _threat_cells(state: BattleState, u: Unit) -> Dictionary:
	var out := {}
	var ignore := { u.id: true }
	for e in state.units():
		if e.team == u.team or e.attack_against(u) <= 0:
			continue
		var field := state.move_cost_field_without(e.id, e.pos, ignore)
		for r in field:
			if int(field[r]) > e.move:
				continue  # 移動距離の表は何ターンぶんでも載る＝1ターンで届く範囲に切る
			for h in Hex.within_range(r, e.attack_range):
				if out.has(h) or not state.in_field(h):
					continue
				if e.can_reach(Hex.distance(r, h)):
					out[h] = true
	return out

## 移動範囲のうち脅威圏の外で、実際に止まれるマス { ヘックス: true }。preempt の行き先の母集合。
func _safe_cells(state: BattleState, u: Unit) -> Dictionary:
	var threat := _threat_cells(state, u)
	var out := {}
	for h in state.reachable(u.id):
		if threat.has(h):
			continue
		if h != u.pos and state.unit_at(h) != null:
			continue  # 駒の居るマス＝乗れる味方輸送。踏むと乗るつもりのない乗車になる
		out[h] = true
	return out

## 間合取り＝safe のうち標的への距離が最小のマスへ動く1手。同値は現在地を優先し、次に col → row。
## 前進と違って「距離が縮むマス」に限らない＝いま脅威圏の中にいれば行き先は後ろになる。
## 測れるマスが1つも無ければ現在地に留まる（＝null＝次の行へ落ちる）。
func _spacing_step(state: BattleState, u: Unit, safe: Dictionary,
		field: Dictionary, goal_cells: Array) -> AiAction:
	var goals := {}
	for c in goal_cells:
		goals[c] = true
	var best := NO_HEX
	var best_c := BattleState.UNREACHABLE
	for h in safe:
		var c := _advance_score(field, goals, h)
		if c >= BattleState.UNREACHABLE:
			continue
		var better := best == NO_HEX or c < best_c
		if not better and c == best_c and best != u.pos:
			better = h == u.pos or _is_younger_hex(h, best)
		if better:
			best = h
			best_c = c
	return AiAction.move_to(u.id, best) if best != NO_HEX and best != u.pos else null

# --- 標的の選び方 ---

## u が攻撃できる敵（対空・対地を見る）。飛行を狙えない駒はその相手を最初から数えない。
func _attackable_enemies(state: BattleState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for other in state.units():
		if other.team != u.team and u.attack_against(other) > 0:
			out.append(other)
	return out

## 表 field で測って距離が最小の標的（測れる標的が1つも無ければ null）。同値は col → row の若い方。
## 表は行動ユニットから1枚流したものを渡す＝標的ごとに盤を流し直さない。
func _nearest_target(state: BattleState, u: Unit, enemies: Array[Unit], field: Dictionary) -> Unit:
	var best: Unit = null
	var best_c := BattleState.UNREACHABLE
	for e in enemies:
		var c := state.min_cost_in(field, state.attack_cells(u.id, e.id))
		if c >= BattleState.UNREACHABLE:
			continue
		if best == null or c < best_c or (c == best_c and _is_younger_hex(e.pos, best.pos)):
			best = e
			best_c = c
	return best

## 表 field で測って距離が最小のヘックス（測れなければ NO_HEX）。同値は col → row の若い方。
func _nearest_hex_in(field: Dictionary, cells: Array[Vector2i]) -> Vector2i:
	var best := NO_HEX
	var best_c := BattleState.UNREACHABLE
	for h in cells:
		var c := int(field.get(h, BattleState.UNREACHABLE))
		if c >= BattleState.UNREACHABLE:
			continue
		if best == NO_HEX or c < best_c or (c == best_c and _is_younger_hex(h, best)):
			best = h
			best_c = c
	return best

## 反撃されない敵を優先し、その中で盤上距離が最小の敵ID（doc/gdd/ai.md 用語 > 反撃されない）。
## 同じ1手なら反撃を受けない相手を撃つほうが得なので、隣に敵がいても距離2で撃てる相手を先に見る。
## 反撃されない敵が1体もいなければ、これまで通り盤上距離が最小の敵を殴る。
func _safest_id(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var safe: Array[int] = []
	for id in ids:
		if not _retaliates(u, state.unit_by_id(id), u.pos):
			safe.append(id)
	return _nearest_id_by_board(state, u, safe if not safe.is_empty() else ids)

## from から t を攻撃したとき t が反撃してくるか。判定は戦闘解決（BattleState.attack）と同じ＝
## 距離1で、t が距離1を狙えて（min_range≤1）、t がこちらを攻撃できる（対空・対地）とき。
static func _retaliates(u: Unit, t: Unit, from: Vector2i) -> bool:
	if t == null:
		return false
	return Hex.distance(from, t.pos) <= 1 and t.can_reach(1) and t.attack_against(u) > 0

## 盤上距離が最小の敵ID。同値は col → row の若い方。
func _nearest_id_by_board(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var best := ids[0]
	for id in ids:
		var t := state.unit_by_id(id)
		if _nearer_hex(u.pos, t.pos, state.unit_by_id(best).pos):
			best = id
	return best

## 盤上距離が最小の敵。同値は col → row の若い方。
func _nearest_unit_by_board(from: Vector2i, units: Array[Unit]) -> Unit:
	var best: Unit = units[0]
	for other in units:
		if _nearer_hex(from, other.pos, best.pos):
			best = other
	return best

## 盤上距離が最小のヘックス。同値は col → row の若い方。
func _nearest_hex_by_board(from: Vector2i, cells: Array[Vector2i]) -> Vector2i:
	var best := cells[0]
	for h in cells:
		if _nearer_hex(from, h, best):
			best = h
	return best

## 自陣営以外の拠点hex（中立も含む）。
func _hostile_base_hexes(state: BattleState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b in state.bases():
		if b.team != u.team:
			out.append(b.hex)
	return out

## 自陣営の拠点hex。
func _friendly_base_hexes(state: BattleState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b in state.bases():
		if b.team == u.team:
			out.append(b.hex)
	return out

## retreat パラメーターを損耗率の閾値に読み替える。数値はそのまま、"-"＝使わない＝101（到達不能）。
static func _retreat_percent(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return clampi(int(v), 0, 100)
	return 101  # "-" = 使わない

# --- flee（逃走）の行動ルール（doc/gdd/ai.md flee） ---

## flee（逃走）の行動ルール。戦わずに拠点へ走る。
## 1 占領兵で、移動範囲に自陣営以外の拠点 → 占領
## 2 損耗 ≧ retreat で、自陣営の拠点hexにいる → 拠点に入る
## 3 損耗 ≧ retreat で、迂回距離が測れる自陣営拠点 → 自陣営拠点へ回り込み
## 4 損耗 < retreat で、迂回距離が測れる敵拠点 → 敵拠点へ回り込み
func _flee_action(state: BattleState, u: Unit) -> AiAction:
	var row := _capture_row(state, u)
	if row != null:
		return row
	var threshold := _retreat_percent(_param(state, u, "retreat"))
	var damaged := _damage_percent(u) >= threshold
	if damaged:
		# #2 自陣営の拠点hexにいる → 入る
		if state.can_enter_base(u.id):
			return AiAction.enter_base(u.id)
		# #3 自陣営拠点へ回り込み
		if _can_advance(state, u):
			return _detour_to_base(state, u, _friendly_base_hexes(state, u))
	else:
		# #4 敵拠点へ回り込み
		if _can_advance(state, u):
			return _detour_to_base(state, u, _hostile_base_hexes(state, u))
	return null

## 回り込み（迂回距離）で拠点へ向かう1手。ZOCを避けた道が無ければ null＝待機。
func _detour_to_base(state: BattleState, u: Unit, goals: Array[Vector2i]) -> AiAction:
	if goals.is_empty():
		return null
	var detour_field := state.detour_cost_field(u.id, u.pos)
	var goal := _nearest_hex_in(detour_field, goals)
	if goal == NO_HEX:
		return null  # 迂回距離が測れない＝ZOCで全方位塞がれている → 待機
	return _advance(state, u, state.detour_cost_field(u.id, goal), [goal])

# --- withdraw（撤退）の行動ルール（doc/gdd/ai.md withdraw） ---

## withdraw（撤退）の行動ルール。突撃と同じく前へ出るが、削られたら拠点へ退いて回復し、また出てくる。
## 1 占領兵で、移動範囲に自陣営以外の拠点 → 占領
## 2 損耗 ≧ retreat で、自陣営の拠点hexにいる → 拠点に入る
## 3 損耗 ≧ retreat で、移動距離が測れる自陣営拠点 → 移動距離が最小の自陣営拠点へ最大前進
## 4〜9 突撃と同じ（_charge_action）
##
## 2・3 を攻撃より上に置くのは、下に置くと退けないため。攻撃した駒はその時点で手番が終わるので、
## 退く行が攻撃より下だと、射程内に敵がいるかぎり殴り続けて拠点へ戻らない。上に置けば 3 で下がった
## あとに表を上から当て直し、移動を伴う行は飛ばされて攻撃の行が拾う＝退きながら撃ち返す。
##
## 帰り道は最大前進（移動距離）で敵ZOCを避けない（flee の回り込みとの差）。ZOCマスに入れば移動が
## 終わるので、プレイヤーはZOCの帯で足を止められる。自陣営の拠点が無い・道が塞がれて測れない・
## 縮むマスが無いときは 2・3 が通らず突撃として戦う＝退けないなら諦めて殴る。
func _withdraw_action(state: BattleState, u: Unit) -> AiAction:
	var row := _capture_row(state, u)
	if row != null:
		return row
	if _damage_percent(u) >= _retreat_percent(_param(state, u, "retreat")):
		if state.can_enter_base(u.id):
			return AiAction.enter_base(u.id)
		if _can_advance(state, u):
			row = _move_to_base(state, u, _friendly_base_hexes(state, u))
			if row != null:
				return row
	return _charge_action(state, u)

## 最大前進（移動距離）で拠点へ向かう1手。測れる拠点が無ければ null＝この行は通らない。
func _move_to_base(state: BattleState, u: Unit, goals: Array[Vector2i]) -> AiAction:
	if goals.is_empty():
		return null
	var goal := _nearest_hex_in(state.move_cost_field(u.id, u.pos), goals)
	if goal == NO_HEX:
		return null  # 移動距離が測れない＝道が塞がれている
	return _advance(state, u, state.move_cost_field(u.id, goal), [goal])

## preempt（先制）の行動ルール。先手を取れる距離まで詰めて、そこを保つ。
## 1 占領兵で移動範囲に自陣営以外の拠点 → 盤上距離が最小の拠点へ移動して占領
## 2 スキル射程内に stack 条件を満たす対象 → 盤上距離が最小の対象にスキル
## 3 攻撃射程内に敵 → 反撃されない敵を優先し、その中で盤上距離が最小の敵を攻撃
## 4 移動距離が測れる敵 → 移動距離が最小の敵へ間合取り
## 5 地形距離が測れる敵 → 地形距離が最小の敵へ見込前進
## 6 盤上に攻撃できる敵 → 盤上距離が最小の敵へ直線寄せ
##
## 移動先は脅威圏の外のマスに限る（1 占領を除く）。4〜6 はどれもこの制約の中で行き先を選ぶ。
## 3 を 4 より上に置くのは、間合いに入ってきた敵を撃つのがこの特性の目的だから。
## 最大間合いの行は持たない＝間合取りが詰めると下がるの両方を兼ねる。
func _preempt_action(state: BattleState, u: Unit) -> AiAction:
	var row := _capture_row(state, u)
	if row != null:
		return row
	row = _skill_row(state, u, PICK_NEAR)
	if row != null:
		return row
	var in_range := _attack_targets(state, u)
	if not in_range.is_empty():
		return AiAction.attack(u.id, _safest_id(state, u, in_range))
	return _spacing_advance(state, u)

## preempt の移動（4〜6）。行き先は脅威圏の外に限り、外に1マスも無ければ動かない。
## 隣接されて撃てない駒（min_range≥2）はここで脅威圏の外へ出る。移動後にもう一度表を上から
## 当てるので、同じ手番のうちに 3 が撃つ。
func _spacing_advance(state: BattleState, u: Unit) -> AiAction:
	if not _can_advance(state, u):
		return null
	var enemies := _attackable_enemies(state, u)
	if enemies.is_empty():
		return null
	var safe := _safe_cells(state, u)
	if safe.is_empty():
		return null
	var move_field := state.move_cost_field(u.id, u.pos)
	var target := _nearest_target(state, u, enemies, move_field)
	if target != null:
		return _spacing_step(state, u, safe, state.move_cost_field(u.id, target.pos),
			state.attack_cells(u.id, target.id))
	target = _nearest_target(state, u, enemies, state.terrain_cost_field(u.id, u.pos))
	if target != null:
		return _advance(state, u, state.terrain_cost_field(u.id, target.pos),
			state.attack_cells(u.id, target.id), safe)
	return _advance_straight(state, u, _nearest_unit_by_board(u.pos, enemies).pos, safe)

## 対空得意＝対地攻撃力が対空攻撃力以下（doc/gdd/ai.md 対空得意）。駒の性能だけで決まる。
static func _air_hunter(u: Unit) -> bool:
	return u.unit_attack <= u.atk_air

## 空敵＝対空得意な駒が攻撃できる飛行の敵（集合）。対空得意でない駒には空敵がいない。
## 対空も対地も0の駒（輸送・バリケード）は攻撃できる敵を持たないので、ここも空になる。
func _air_prey(state: BattleState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	if not _air_hunter(u):
		return out
	for e in _attackable_enemies(state, u):
		if e.is_aerial():
			out.append(e)
	return out

## ids を空敵だけに絞る（空敵が1体も入っていなければ ids のまま）＝「空敵を優先し」の実装。
func _air_first(air: Array[Unit], ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for e in air:
		if e.id in ids:
			out.append(e.id)
	return out if not out.is_empty() else ids

## 獲物＝ u が攻撃できる敵のうち、防御力が最小の敵の防御力 +10 までにいるもの（集合）。
## 上限は必ず盤全体の敵から計算する。射程内など狭い範囲から計算し直すと、硬い前衛しか
## 射程に入っていないターンにその前衛が獲物になってしまう（doc/gdd/ai.md 獲物）。
func _prey_of(state: BattleState, u: Unit) -> Array[Unit]:
	return _prey_among(_attackable_enemies(state, u))

## 候補の中から獲物の層を切り出す（防御力が最小のもの +PREY_DEFENSE_BAND まで）。
func _prey_among(enemies: Array[Unit]) -> Array[Unit]:
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

## sight 範囲内の獲物（weak の行動開始条件と、狙う獲物の候補）。
func _prey_in_sight(state: BattleState, u: Unit) -> Array[Unit]:
	var budget := _sight_of(state, u)
	var out: Array[Unit] = []
	if budget <= 0:
		return out
	for e in _prey_of(state, u):
		if state.sight_reaches(u.pos, e.pos, budget):
			out.append(e)
	return out

## 狙う獲物＝ sight 範囲内の獲物のうち移動距離が最小のもの。
## 移動距離が測れる獲物が1体もいなければ盤上距離が最小のもの（前進の行き先が消えない）。
func _hunted_prey(state: BattleState, u: Unit, move_field: Dictionary) -> Unit:
	var candidates := _prey_in_sight(state, u)
	if candidates.is_empty():
		return null
	var best := _nearest_target(state, u, candidates, move_field)
	return best if best != null else _nearest_unit_by_board(u.pos, candidates)

## 手負い＝ u が攻撃できる敵のうち損耗が最大のもの。同値は移動距離が最小（さらに同値は col → row）。
## 損耗に下限を置かない＝全員無傷のターンは最も近い敵が手負いになり、そこで最初の一噛みが起きる。
## 盤全体から1体だけ選ぶ（範囲の判定は選び終えたこの1体に対して行う）。
func _wounded_of(state: BattleState, u: Unit, move_field: Dictionary) -> Unit:
	var best: Unit = null
	var best_pct := -1
	var best_c := BattleState.UNREACHABLE
	for e in _attackable_enemies(state, u):
		var pct := _damage_percent(e)
		var c := state.min_cost_in(move_field, state.attack_cells(u.id, e.id))
		if best == null or pct > best_pct \
				or (pct == best_pct and (c < best_c \
					or (c == best_c and _is_younger_hex(e.pos, best.pos)))):
			best = e
			best_pct = pct
			best_c = c
	return best

## 選び終えた標的が u の sight 範囲内にいるか（swarm の前進の行）。
func _in_sight(state: BattleState, u: Unit, target: Unit) -> bool:
	var budget := _sight_of(state, u)
	return budget > 0 and state.sight_reaches(u.pos, target.pos, budget)

## 損耗率（失った兵の割合）を百分率の整数で。無傷＝0・全滅寸前ほど大きい。
## 割合で見るのは満員兵数が駒ごとに違っても並べられるため（doc/gdd/ai.md 損耗）。
static func _damage_percent(u: Unit) -> int:
	if u.max_troops <= 0:
		return 0
	return int(round(float(u.max_troops - u.troops) * 100.0 / float(u.max_troops)))

## 損耗が最大の敵ID。同値は盤上距離が近い方 → col → row。
func _most_damaged_id(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var best := ids[0]
	for id in ids:
		var t := state.unit_by_id(id)
		var b := state.unit_by_id(best)
		var pct := _damage_percent(t)
		var best_pct := _damage_percent(b)
		if pct > best_pct or (pct == best_pct and _nearer_hex(u.pos, t.pos, b.pos)):
			best = id
	return best

## 攻撃後の残兵が最小になる敵ID（確殺を自然に最優先）。同値は盤上距離が近い方 → col → row。
func _fewest_left_id(state: BattleState, u: Unit, ids: Array[int]) -> int:
	var best := ids[0]
	var best_left := 1 << 30
	for id in ids:
		var t := state.unit_by_id(id)
		var left := t.troops - Combat.casualties(state, u, t, Hex.distance(u.pos, t.pos) <= 1)
		if left < best_left or (left == best_left \
				and _nearer_hex(u.pos, t.pos, state.unit_by_id(best).pos)):
			best = id
			best_left = left
	return best

## u の一撃で倒しきれる相手か（与ダメは戦闘式で厳密計算＝combat.md は決定的）。
func _can_kill_in_one_hit(state: BattleState, u: Unit, t: Unit) -> bool:
	if t == null:
		return false
	var melee := Hex.distance(u.pos, t.pos) <= 1  # 距離1なら近接＝支援が乗る（解決式と一致）
	return Combat.casualties(state, u, t, melee) >= t.troops

# --- stack 条件（doc/gdd/ai.md stack 条件） ---

## option のスキルが強化・弱体・解除のどれか。判別はレシピのフラグから決める
## （effect が cleanse なら解除、buff_kind が debuff なら弱体、それ以外は強化）。
static func _skill_kind(option: Dictionary) -> String:
	if String(option.get("effect", "")) == "cleanse":
		return "cleanse"
	if String(option.get("buff_kind", "")) == StatusMod.KIND_DEBUFF:
		return StatusMod.KIND_DEBUFF
	return StatusMod.KIND_BUFF

## u がいま放てるスキルの種類（複数あれば最初の1つ。持たなければ弱体扱い）。
## swarm の「stack 条件を満たさない敵は殴りに切り替える」行が、掛ける側の種類を知るために読む。
func _skill_kind_of(state: BattleState, u: Unit) -> String:
	for option in Formation.available_for(state, u):
		return _skill_kind(option)
	return StatusMod.KIND_DEBUFF

## target が stack 条件を満たすか（＝そのスキルを掛ける価値があるか）。
## 強化・弱体は上限（stack 本未満なら掛ける）、解除は下限（stack 本以上なら掛ける）。
## 数えるのは対象1体に掛かった補正だけ＝陣営全体に掛かった補正（ホーリーアリア）は数えない。
func _stack_passes(state: BattleState, u: Unit, kind: String, target: Unit) -> bool:
	var limit := _stack_limit(_param(state, u, "stack"))
	if kind == "cleanse":
		return state.debuff_count(target) >= (1 if limit == NO_LIMIT else maxi(limit, 1))
	if limit == NO_LIMIT:
		return true
	if kind == StatusMod.KIND_DEBUFF:
		return state.debuff_count(target) < limit
	return state.buff_count(target) < limit

## スキル対象を1体に絞る。near＝盤上距離が最小／weak＝防御力が最小／damaged＝損耗が最大。
## 同値は col → row の若い方 → 駒番号の小さい方。
func _pick_skill_target(state: BattleState, u: Unit, candidates: Array[Unit], pick: String) -> Unit:
	var best: Unit = candidates[0]
	for c in candidates:
		if _skill_target_better(state, u, c, best, pick):
			best = c
	return best

func _skill_target_better(state: BattleState, u: Unit, c: Unit, best: Unit, pick: String) -> bool:
	var score := 0
	var best_score := 0
	match pick:
		PICK_WEAK:
			score = -c.unit_defense  # 防御が低いほど良い
			best_score = -best.unit_defense
		PICK_DAMAGED:
			score = _damage_percent(c)
			best_score = _damage_percent(best)
		_:
			score = -Hex.distance(u.pos, c.pos)
			best_score = -Hex.distance(u.pos, best.pos)
	if score != best_score:
		return score > best_score
	if c.pos != best.pos:
		return _is_younger_hex(c.pos, best.pos)
	return c.id < best.id

# --- 包囲可能（doc/gdd/ai.md 包囲可能） ---

## target を包囲できるか＝いま隣接している自陣営の駒と、まだ行動しておらず今ターン target の隣へ
## 寄れる味方を合わせて包囲成立数（Surround.GATE）に届くか。行動ユニット自身も数に入る。
## すでに包囲されている相手は隣接数が成立数に達しているので、必ず包囲可能でもある。
## exclude_self＝行動ユニット自身を数えない（下がる行が使う。動いた先では隣接しないため）。
func _surround_able(state: BattleState, u: Unit, target: Unit, exclude_self := false) -> bool:
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
static func _is_younger_hex(a: Vector2i, b: Vector2i) -> bool:
	var oa := Hex.axial_to_offset(a)
	var ob := Hex.axial_to_offset(b)
	if oa.x != ob.x:
		return oa.x < ob.x
	return oa.y < ob.y

## from から見て a のほうが b より近いか（盤上距離 → col → row）。
static func _nearer_hex(from: Vector2i, a: Vector2i, b: Vector2i) -> bool:
	var da := Hex.distance(from, a)
	var db := Hex.distance(from, b)
	if da != db:
		return da < db
	return _is_younger_hex(a, b)

static func _ids_of(units: Array[Unit]) -> Array[int]:
	var out: Array[int] = []
	for u in units:
		out.append(u.id)
	return out

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

## 拠点の行動開始条件＝ユニットと同じ条件を拠点hex基準で見る。
## charge / raid / swarm＝常時、ambush＝拠点hexから sight 内に敵、weak＝拠点hexから sight 内に獲物。
## 一度成立したら以後は判定しない（部隊のフラグに焼く）＝敵が索敵から出ても拠点は眠り直さない。
## 一斉警戒はその部隊の中で閉じる＝同じ部隊の盤上の駒（その拠点から出した駒）が起きていれば拠点も
## 起きる。別部隊が起きても拠点は起きない（部隊のフラグしか見ないため）。
func _base_engaged(state: BattleState, b: Base) -> bool:
	if state.is_squad_engaged(b.squad_index):
		return true
	var engaged := _squad_unit_engaged(state, b.squad_index)
	if not engaged:
		var budget := _sight_budget(_base_param(state, b, "sight"))
		match _base_trait(state, b):
			"ambush":
				engaged = _enemy_in_sight(state, b.hex, b.team, budget)
			"predator":
				engaged = not _base_prey_in_sight(state, b, budget).is_empty()
			_:  # charge / raid / swarm＝常時
				engaged = true
	if engaged:
		state.mark_squad_engaged(b.squad_index)
	return engaged

## 拠点の特性id（部隊の ai）。未設定・未知は charge。
func _base_trait(state: BattleState, b: Base) -> String:
	if b.squad_index < 0 or b.squad_index >= state.squads.size():
		return DEFAULT_TRAIT
	var id := String((state.squads[b.squad_index] as Dictionary).get("ai", ""))
	return id if id in TRAITS else DEFAULT_TRAIT

## 拠点のパラメーター解決: 部隊の上書き ＞ 特性の既定。部隊未設定は "-"。
func _base_param(state: BattleState, b: Base, key: String) -> Variant:
	if b.squad_index < 0 or b.squad_index >= state.squads.size():
		return "-"
	var squad: Dictionary = state.squads[b.squad_index]
	if squad.has(key):
		return squad[key]
	return _preset_param(_base_trait(state, b), key)

## 拠点hexから視線 budget 以内にいる獲物（拠点に攻撃力は無いので対空・対地では絞らない）。
func _base_prey_in_sight(state: BattleState, b: Base, budget: int) -> Array[Unit]:
	var out: Array[Unit] = []
	if budget <= 0:
		return out
	var enemies: Array[Unit] = []
	for other in state.units():
		if other.team != b.team:
			enemies.append(other)
	for e in _prey_among(enemies):
		if state.sight_reaches(b.hex, e.pos, budget):
			out.append(e)
	return out

## 出撃先候補のうち、盤上距離が最小の敵に最も近いマス（敵がいなければ col → row の若いマス）。
func _best_deploy_cell(state: BattleState, b: Base, cells: Array[Vector2i]) -> Vector2i:
	var enemies: Array[Unit] = []
	for other in state.units():
		if other.team != b.team:
			enemies.append(other)
	if enemies.is_empty():
		var young := cells[0]
		for c in cells:
			if _is_younger_hex(c, young):
				young = c
		return young
	var goal := _nearest_unit_by_board(b.hex, enemies).pos
	return _nearest_hex_by_board(goal, cells)
