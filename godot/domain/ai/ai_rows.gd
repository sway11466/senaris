extends RefCounted
class_name AiRows
## 敵AIの「行」の部品（純ロジック・Node非依存）。
## 1行＝行動条件と行動内容の組で、成立すればその1手（AiAction）を、しなければ null を返す。
## 特性（AiTrait）は行を上から順に当て、最初に成立した行を採る。複数の特性が共有する行をここに置き、
## 標的の物差しは AiPick、パラメーターは AiParams に任せる。盤は書き換えない。
## 詳細 → doc/gdd/ai.md（用語・特性詳細）

## 輸送ユニット（特殊特性）＝搭載数がこの値以上の駒。特性に重ねて働き、ステージデータには書かない
## ＝駒の性能から決まる。搭載数1の駒（1体だけ乗せて戦う騎乗など）は運搬役として扱わない。
## 詳細 → doc/gdd/ai.md（特殊特性詳細・輸送ユニット）
const TRANSPORT_CAPACITY_MIN := 2

var params: AiParams
var pick: AiPick

func _init(p_params: AiParams, p_pick: AiPick) -> void:
	params = p_params
	pick = p_pick

# --- 特殊特性＝輸送ユニット（doc/gdd/ai.md 特殊特性詳細） ---

## 輸送ユニットか（搭載数で決まる。乗員の有無は問わない）。
static func is_transport(u: Unit) -> bool:
	return u != null and u.capacity >= TRANSPORT_CAPACITY_MIN

## 攻撃の行が見る標的。輸送ユニットは攻撃しない＝どの特性でも空になる（自分から仕掛けないだけで、
## 殴られたときの反撃は戦闘解決の側で起きる）。
## 攻撃済みの駒も空。ヒット&アウェイ持ち（move_after_attack）は撃ったあとも動けるので行を見直すが、
## そこで撃てる相手を返すと成立しない攻撃を返し続けることになる。
func attack_targets(state: BattleState, u: Unit) -> Array[int]:
	var none: Array[int] = []
	if is_transport(u) or state.has_attacked(u.handle):
		return none
	return state.attack_targets(u.handle)

## 前進で止まってはいけないマス。輸送ユニットは目的地hex（自陣営以外の拠点）に乗らない
## ＝塞ぐと運んできた占領兵も他の味方も拠点へ入れない。
func forbidden_cells(state: BattleState, u: Unit) -> Dictionary:
	var out := {}
	if not is_transport(u):
		return out
	for h in pick.hostile_base_hexes(state, u):
		out[h] = true
	return out

## いま移動を伴う行を実行できるか（移動を使い切っていないか）。
func can_advance(state: BattleState, u: Unit) -> bool:
	return state.can_still_move(u.handle)

## 「拠点に入る」行＝損耗が retreat 以上で、自陣営の休める拠点hexに立ち、まだ攻撃も待機もしていなければ入る。
## flee #2 / withdraw #2 が共有する（doc/gdd/ai.md）。
func enter_base_row(state: BattleState, u: Unit) -> AiAction:
	if AiPick.damage_percent(u) < params.retreat_percent_of(state, u):
		return null
	if not state.has_action_left(u.handle) or not state.can_enter_base(u.handle):
		return null
	return AiAction.enter_base(u.handle)

# --- 占領・スキル ---

## 占領の行＝占領兵で、移動範囲に自陣営以外の拠点があれば盤上距離が最小の拠点へ動く。
## 拠点hexへ進入すればその場で占領（BattleState.move_unit）。
func capture_row(state: BattleState, u: Unit) -> AiAction:
	if not u.can_capture or not can_advance(state, u):
		return null
	var reach := state.reachable(u.handle)
	var best := AiPick.NO_HEX
	for b in state.bases():
		if b.team == u.team or b.hex == u.pos or not (b.hex in reach):
			continue  # 自陣営の拠点は対象外（敵・中立を取る）。すでに乗っているマスは動く先にならない
		if state.unit_at(b.hex) != null:
			continue  # 味方輸送が拠点に乗っている＝そこへ動くと占領ではなく乗車になる
		if best == AiPick.NO_HEX or AiPick.nearer_hex(u.pos, b.hex, best):
			best = b.hex
	return AiAction.move_to(u.handle, best) if best != AiPick.NO_HEX else null

## スキルの行＝掛けられる対象のうち stack 条件を満たすものを集め、pick_rule で1体に絞って放つ。
## 放つと発動者は行動完了になるので攻撃より前に置く。移動後でも放てる（doc/gdd/skills.md）。
## require_surround＝対象が敵のときだけ、包囲可能であることも条件に足す（swarm）。味方に掛ける
## 強化・解除に包囲可能を課すと永久に成立しない（包囲は敵にしか成り立たないため）。
func skill_row(state: BattleState, u: Unit, pick_rule: String, require_surround := false) -> AiAction:
	for option in Formation.available_for(state, u):
		if not option.needs_target():
			return AiAction.skill(u.handle, option, u.pos)  # 陣営全体＝対象を選ばない
		if option.has_impact() and not option.targets_unit():
			# 面を焼くスキル（ドラゴンブレス）は駒ではなく着弾先を選ぶ＝stack 条件は掛からない。
			var cell := _best_blast_cell(state, u, option)
			if cell != AiPick.NO_HEX:
				return AiAction.skill(u.handle, option, cell)
			continue
		var kind := option.stack_kind()
		var candidates: Array[Unit] = []
		for other in state.units():
			if not Formation.can_target(state, option, other.pos):
				continue
			if require_surround and other.team != u.team and not pick.surround_able(state, u, other):
				continue  # 包囲可能を課すのは敵対象のときだけ（doc/gdd/ai.md swarm #5）
			if not pick.stack_passes(state, u, kind, other):
				continue
			candidates.append(other)
		if candidates.is_empty():
			continue
		return AiAction.skill(u.handle, option, pick.pick_skill_target(state, u, candidates, pick_rule).pos)
	return null

## 面を焼くスキルの着弾先＝範囲に入る敵の数が最大のもの。巻き込む自陣営の駒は数えない。
## 同数は範囲内の最も近い敵の盤上距離が小さい方 → 着弾先の col → row の若い方。
## 敵が1体も入らなければ NO_HEX＝放たない。詳細 → doc/gdd/ai.md スキル対象
func _best_blast_cell(state: BattleState, u: Unit, option: FormationOption) -> Vector2i:
	var best := AiPick.NO_HEX
	var best_n := 0
	var best_d := 0
	for cell in Formation.targetable_cells(state, option):
		var n := 0
		var d := BattleState.UNREACHABLE
		for h in Formation.blast_cells(option, cell, u.pos):
			var v := state.unit_at(h)
			if v == null or v.team == u.team:
				continue
			n += 1
			d = mini(d, Hex.distance(u.pos, v.pos))
		if n == 0:
			continue
		if best == AiPick.NO_HEX or n > best_n or (n == best_n and (d < best_d \
				or (d == best_d and AiPick.is_younger_hex(cell, best)))):
			best = cell
			best_n = n
			best_d = d
	return best

# --- 最大間合い（doc/gdd/ai.md 最大間合い） ---

## 最大間合いの行＝間接攻撃できる駒が、撃てる敵から距離を取ってから撃つための移動（doc/gdd/ai.md
## 用語 > 最大間合い）。撃つのはこの行ではなく、移動後にもう一度表を上から当てた攻撃の行。
##
## 標的を渡すとその1体へ間合いを取る（predator＝狙う獲物・swarm＝手負い＝前進の行と同じ1体へ向かう）。
## 渡さなければ「移動範囲のどこかから撃てる敵」のうち盤上距離が最小のもの（charge / ambush）。
## どちらもいまの位置から撃てるかは問わない＝射程の外から詰めるときも射程の外縁で止まる。
##
## 行き先はその標的を撃てるマスのうち標的への盤上距離が最大のもので、同値は現在地優先 →
## col → row の若い方。
##
## 近接しかできない駒は撃てるマスがどれも距離1＝最大間合いが現在地と同じになるので、この行では
## 動かない。射程で先に弾いておくと、盤を流さずに済む。
func standoff_row(state: BattleState, u: Unit, target: Unit = null,
		pool: Array[Unit] = []) -> AiAction:
	if u.attack_range < 2 or is_transport(u) or not can_advance(state, u):
		return null
	var reach := state.reachable(u.handle)
	var cells: Array[Vector2i] = []
	if target != null:
		cells = standing_attack_cells(state, u, target, reach)
		if cells.is_empty():
			return null  # 今ターン撃てる位置が無い＝前進の行に任せる
	else:
		for e in (pool if not pool.is_empty() else pick.attackable_enemies(state, u)):
			if target != null and not AiPick.nearer_hex(u.pos, e.pos, target.pos):
				continue
			var spots := standing_attack_cells(state, u, e, reach)
			if spots.is_empty():
				continue  # 今ターン撃てる位置が無い敵は標的にしない（前進の行に任せる）
			target = e
			cells = spots
	if target == null:
		return null
	var best := AiPick.NO_HEX
	var best_d := -1
	for h in cells:
		var d := Hex.distance(h, target.pos)
		var better := best == AiPick.NO_HEX or d > best_d
		if not better and d == best_d and best != u.pos:
			better = h == u.pos or AiPick.is_younger_hex(h, best)
		if better:
			best = h
			best_d = d
	return AiAction.move_to(u.handle, best) if best != u.pos else null

## swarm #3 の標的＝移動範囲のどこかから撃てて、自分を除いても包囲可能な敵のうち損耗が最大の
## もの（doc/gdd/ai.md swarm #3）。同値は盤上距離 → col → row。
##
## 自分を除いて数えるのは、下がった先では隣接しなくなって包囲の頭数から外れるため。数えたまま
## 下がると、動いた先で包囲が崩れて攻撃の行が不成立になり、撃たないまま前進の行へ落ちる。
func surroundable_standoff_target(state: BattleState, u: Unit) -> Unit:
	if u.attack_range < 2 or is_transport(u) or not can_advance(state, u):
		return null
	var reach := state.reachable(u.handle)
	var ids: Array[int] = []
	for e in pick.attackable_enemies(state, u):
		if not pick.surround_able(state, u, e, true):
			continue
		if standing_attack_cells(state, u, e, reach).is_empty():
			continue  # 今ターン撃てる位置が無い敵は標的にしない（前進の行に任せる）
		ids.append(e.handle)
	if ids.is_empty():
		return null
	return state.unit_by_handle(pick.most_damaged_id(state, u, ids))

## target を攻撃できるマスのうち、今ターン実際に立てるもの。
## 駒の居るマス＝乗れる味方輸送は除く（前進と同じ理由＝踏むと乗るつもりのない乗車になる）。
## 自分が今いるマスは「動かない」という選択肢なので残す。
func standing_attack_cells(state: BattleState, u: Unit, target: Unit,
		reach: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in state.attack_cells(u.handle, target.handle):
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
func shift_to_shoot_row(state: BattleState, u: Unit) -> AiAction:
	if u.attack_range < 2 or is_transport(u) or state.has_attacked(u.handle) \
			or not can_advance(state, u):
		return null
	var goals := pick.hostile_base_hexes(state, u)
	if goals.is_empty():
		return null
	var reach := state.reachable(u.handle)
	var shootable: Array[int] = []
	var cells_of := {}
	for e in pick.attackable_enemies(state, u):
		var spots := standing_attack_cells(state, u, e, reach)
		if spots.is_empty():
			continue
		shootable.append(e.handle)
		cells_of[e.handle] = spots
	var blocker := _blocking_enemy_id(state, u, shootable)
	if blocker < 0:
		return null
	var cells: Array[Vector2i] = cells_of[blocker]
	var best := _nearest_cell_to_goals(state, u, cells, goals)
	return AiAction.move_to(u.handle, best) if best != AiPick.NO_HEX and best != u.pos else null

## cells のうち拠点へ最も近いマス（1つも測れなければ NO_HEX）。測る順は前進と同じ＝
## 移動距離 → 地形距離 → 盤上距離。
func _nearest_cell_to_goals(state: BattleState, u: Unit, cells: Array[Vector2i],
		goals: Array[Vector2i]) -> Vector2i:
	var goal := pick.nearest_hex_in(AiDistance.move_cost_field(state, u.handle, u.pos), goals)
	if goal != AiPick.NO_HEX:
		return _nearest_cell_in_field(u, cells, AiDistance.move_cost_field(state, u.handle, goal))
	goal = pick.nearest_hex_in(AiDistance.terrain_cost_field(state, u.handle, u.pos), goals)
	if goal != AiPick.NO_HEX:
		return _nearest_cell_in_field(u, cells, AiDistance.terrain_cost_field(state, u.handle, goal))
	goal = pick.nearest_hex_by_board(u.pos, goals)
	var board := {}
	for h in cells:
		board[h] = Hex.distance(h, goal)
	return _nearest_cell_in_field(u, cells, board)

## 表 field で測って距離が最小のマス。同値は現在地を優先し、次に col → row の若い方
## （最大間合いと同じ決め方＝動かずに済むならその手を選ぶ）。
func _nearest_cell_in_field(u: Unit, cells: Array[Vector2i], field: Dictionary) -> Vector2i:
	var best := AiPick.NO_HEX
	var best_c := BattleState.UNREACHABLE
	for h in cells:
		var c := int(field.get(h, BattleState.UNREACHABLE))
		if c >= BattleState.UNREACHABLE:
			continue
		var better := best == AiPick.NO_HEX or c < best_c
		if not better and c == best_c and best != u.pos:
			better = h == u.pos or AiPick.is_younger_hex(h, best)
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
	var blockers := blocking_enemy_ids(state, u, shootable)
	return frontmost_blocker_id(state, u, blockers) if not blockers.is_empty() else -1

## 経路上の敵の集合（塞いでいなければ空）。渡した敵をまとめてどけて道が良くなるかで見るので、
## 成立すれば渡した敵ぜんぶがこの集合になる。どれを狙うかは呼ぶ行が決める。
func blocking_enemy_ids(state: BattleState, u: Unit, shootable: Array[int]) -> Array[int]:
	var none: Array[int] = []
	if shootable.is_empty():
		return none
	var goals := pick.hostile_base_hexes(state, u)
	if goals.is_empty():
		return none
	var ignore := {}
	for id in shootable:
		ignore[id] = true
	return shootable if _route_improves(state, u, goals, ignore) else none

## 経路上の敵のうち一番前で塞いでいる駒＝拠点への地形距離が最小のもの。
## 同値は盤上距離 → col → row。
func frontmost_blocker_id(state: BattleState, u: Unit, shootable: Array[int]) -> int:
	var goals := pick.hostile_base_hexes(state, u)
	var best := -1
	var best_c := BattleState.UNREACHABLE
	for id in shootable:
		var e := state.unit_by_handle(id)
		var c := BattleState.UNREACHABLE
		for g in goals:
			c = mini(c, int(state.travel_cost_field(g, u.move_type, u.move)
				.get(e.pos, BattleState.UNREACHABLE)))
		if best < 0 or c < best_c \
				or (c == best_c and AiPick.nearer_hex(u.pos, e.pos, state.unit_by_handle(best).pos)):
			best = id
			best_c = c
	return best

## ignore の駒をどけると拠点への道が良くなるか。
func _route_improves(state: BattleState, u: Unit, goals: Array[Vector2i], ignore: Dictionary) -> bool:
	var before := AiDistance.min_cost_in(AiDistance.move_cost_field(state, u.handle, u.pos), goals)
	var after := AiDistance.min_cost_in(AiDistance.move_cost_field_without(state, u.handle, u.pos, ignore), goals)
	if after < before:
		return true  # 体で道を塞いでいる（測れるようになった場合も含む）
	var zoc_before := AiDistance.min_cost_in(AiDistance.detour_cost_field(state, u.handle, u.pos), goals)
	if zoc_before < BattleState.UNREACHABLE:
		return false  # ZOCを避ける道が残っている＝足は止まっていない
	return AiDistance.min_cost_in(AiDistance.detour_cost_field(state, u.handle, u.pos, -1, ignore), goals) \
		< BattleState.UNREACHABLE

# --- 降ろす・乗る（doc/gdd/ai.md raid #8〜#10・輸送ユニット） ---

## 8/9行のうち「いまの位置から降ろす」部分。降車は乗員の手番なので、輸送が動き終えていても打てる
## ＝運んだそのターンに降ろせる。1手で1体ずつ返し、次の手で残りを見る。
## 8 占領兵の乗員を自陣営以外の拠点hexへ降ろす（＝降りた瞬間に占領）
## 9 拠点に隣接する降車先へ降ろす。降りた先から拠点へたどり着けない乗員は乗せたまま
func unload_now_row(state: BattleState, u: Unit) -> AiAction:
	var list := state.passengers(u.handle)
	var goals := pick.hostile_base_hexes(state, u)
	if list.is_empty() or goals.is_empty():
		return null
	for i in list.size():
		if not (list[i] as Unit).can_capture:
			continue  # 占領できない駒を拠点hexへ降ろしても占領は起きず、拠点を塞ぐだけ
		var cells := state.unload_cells(u.handle, i)
		var best := AiPick.NO_HEX
		for b in goals:
			if b in cells and (best == AiPick.NO_HEX or AiPick.is_younger_hex(b, best)):
				best = b
		if best != AiPick.NO_HEX:
			return AiAction.unload(u.handle, i, best)
	for i in list.size():
		var p: Unit = list[i]
		var best := AiPick.NO_HEX
		for h in state.unload_cells(u.handle, i):
			if best != AiPick.NO_HEX and not AiPick.is_younger_hex(h, best):
				continue
			for b in goals:
				if Hex.distance(h, b) == 1 and _reaches(state, p, h, b):
					best = h
					break
		if best != AiPick.NO_HEX:
			return AiAction.unload(u.handle, i, best)
	return null

## 8/9行のうち「降ろせるマスへ移動する」部分。降車は移動後に unload_now_row が拾う。
## 行き先は、乗員を降ろせるマスのうち拠点に最も近いもの（同値は col → row の若い方）。
func unload_move_row(state: BattleState, u: Unit) -> AiAction:
	var list := state.passengers(u.handle)
	var goals := pick.hostile_base_hexes(state, u)
	if list.is_empty() or goals.is_empty() or not can_advance(state, u):
		return null
	var forbidden := forbidden_cells(state, u)  # 目的地hexに乗らない＝降ろすための移動でも同じ
	var best := AiPick.NO_HEX
	var best_d := 1 << 30
	for h in state.reachable(u.handle):
		if h == u.pos or forbidden.has(h) or state.unit_at(h) != null:
			continue
		for b in goals:
			var d := Hex.distance(h, b)
			if best != AiPick.NO_HEX and (d > best_d or (d == best_d and not AiPick.is_younger_hex(h, best))):
				continue
			if not _can_unload_near(state, u, list, h, b):
				continue
			best = h
			best_d = d
	return AiAction.move_to(u.handle, best) if best != AiPick.NO_HEX else null

## from_hex に立てば、いずれかの乗員を拠点 b に絡めて降ろせるか（移動先の見積もり）。
## 降車先は隣接1マスの特例で測る＝乗員の移動力に関係なく輸送の隣へは降ろせる。
func _can_unload_near(state: BattleState, u: Unit, list: Array, from_hex: Vector2i, b: Vector2i) -> bool:
	for i in list.size():
		var p: Unit = list[i]
		if state.has_moved(p.handle):
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
	return occ == null or occ.handle == u.handle

## p が from から goal へ自力でたどり着けるか＝地形距離が測れるか（doc/gdd/ai.md たどり着ける）。
## 道のり表は goal 自身を必ず 0 で載せる（起点だから）ので、goal に入れるかは別に見る
## ＝入れない地形の拠点へ「隣までは行ける」を、たどり着けると読まない。
func _reaches(state: BattleState, p: Unit, from: Vector2i, goal: Vector2i) -> bool:
	if not state.can_enter_terrain(p, goal):
		return false
	return state.travel_cost_field(goal, p.move_type, p.move).has(from)

## 10行 乗る＝移動範囲に、同じ部隊で空きのある輸送ユニットがあり、便乗のほうが拠点へ早く着くなら乗る。
## 乗車は移動そのもの（BattleState.move_unit が輸送のマスへの移動を搭乗に変える）。
## 目的地の違う部隊の輸送に乗ると見当違いの場所へ運ばれるので、同じ部隊の輸送だけを数える。
func board_row(state: BattleState, u: Unit) -> AiAction:
	if is_transport(u) or not can_advance(state, u):
		return null
	var squad := state.squad_index_of(u.handle)
	var goals := pick.hostile_base_hexes(state, u)
	if squad < 0 or goals.is_empty():
		return null
	var walk := _arrival_turns(state, u, goals, 0)
	var reach := state.reachable(u.handle)
	var best := AiPick.NO_HEX
	var best_turns := BattleState.UNREACHABLE
	for t in state.units():
		if not is_transport(t) or state.squad_index_of(t.handle) != squad:
			continue
		if not state.can_board(u, t) or not (t.pos in reach):
			continue  # 満車・敵陣営・輸送どうしは can_board が弾く
		var ride := _arrival_turns(state, t, goals, 1)  # +1＝最後に降りて拠点へ入るぶん
		if ride >= walk:
			continue  # 便乗のほうが早い、が成立しない（同値なら乗らない）
		if best == AiPick.NO_HEX or ride < best_turns \
				or (ride == best_turns and AiPick.nearer_hex(u.pos, t.pos, best)):
			best = t.pos
			best_turns = ride
	return AiAction.move_to(u.handle, best) if best != AiPick.NO_HEX else null

## goals のいずれかへ着くまでのターン数＝地形距離 ÷ 移動力の切り上げ（最寄りの拠点で測る）。
## extra は便乗の +1。測れない・移動力0は UNREACHABLE＝徒歩が測れなければ便乗が必ず勝つ。
func _arrival_turns(state: BattleState, u: Unit, goals: Array[Vector2i], extra: int) -> int:
	var field := AiDistance.terrain_cost_field(state, u.handle, u.pos)
	var best := BattleState.UNREACHABLE
	for g in goals:
		best = mini(best, _turns_needed(int(field.get(g, BattleState.UNREACHABLE)), u.move))
	return BattleState.UNREACHABLE if best >= BattleState.UNREACHABLE else best + extra

static func _turns_needed(cost: int, move: int) -> int:
	if cost >= BattleState.UNREACHABLE or move <= 0:
		return BattleState.UNREACHABLE
	return int(ceil(float(cost) / float(move)))

# --- 前進（doc/gdd/ai.md 前進） ---

## 今ターン攻撃できる位置まで届く空敵（doc/gdd/ai.md charge #6）＝移動範囲のどこかから撃てる飛行。
## 盤全体の空敵から選ぶと、何ターンもかかる位置の飛行1体に盤上の対空得意が全員吸われる。
func air_prey_in_reach(state: BattleState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	var reach := state.reachable(u.handle)
	for e in pick.air_prey(state, u):
		if not standing_attack_cells(state, u, e, reach).is_empty():
			out.append(e)
	return out

## 前進の行（敵向け・突撃と群れの末尾が共有）。移動距離 → 地形距離 → 盤上距離の順に測り、
## 測れた時点でその行が成立する＝縮むマスが無ければ現在地に留まって待機になる。
func advance_to_nearest_enemy(state: BattleState, u: Unit, prefer_air := false) -> AiAction:
	if not can_advance(state, u):
		return null
	var enemies := pick.attackable_enemies(state, u)
	if enemies.is_empty():
		return null
	var move_field := AiDistance.move_cost_field(state, u.handle, u.pos)
	# 空敵の行（charge #6）は最大前進だけ。見込前進・直線寄せまで空敵を優先すると、今ターン届かない
	# 飛行1体に盤上の対空得意が全員吸われる（doc/gdd/ai.md charge #6・#8・#9 の注記）。
	var target: Unit = null
	if prefer_air:
		target = pick.nearest_target(state, u, air_prey_in_reach(state, u), move_field)
	if target == null:
		target = pick.nearest_target(state, u, enemies, move_field)
	if target != null:
		return advance(state, u, AiDistance.move_cost_field(state, u.handle, target.pos),
			state.attack_cells(u.handle, target.handle))
	target = pick.nearest_target(state, u, enemies, AiDistance.terrain_cost_field(state, u.handle, u.pos))
	if target != null:
		return advance(state, u, AiDistance.terrain_cost_field(state, u.handle, target.pos),
			state.attack_cells(u.handle, target.handle))
	return advance_straight(state, u, pick.nearest_unit_by_board(u.pos, enemies).pos)

## 標的から流した道のり表の勾配を降りて、移動範囲のうち距離が最も縮むマスへ動く1手。
## 同値のマスは col → row の若い方、縮むマスが1つも無ければ現在地に留まる（＝null＝待機）。
## goal_cells＝標的に攻撃可能なマス（拠点なら拠点hex）＝そこに立てば距離0。表は標的から流して
## いるので、そのままでは「標的のマスからの遠さ」になり、懐に死角のある駒（min_range≥2）が
## 攻撃できない位置へ詰めてしまう。攻撃可能なマスを0として読むことで距離の定義と揃える。
## allow＝止まってよいマス（空＝制限なし）。standoff が脅威圏の外だけに絞るために渡す。
func advance(state: BattleState, u: Unit, field: Dictionary, goal_cells: Array,
		allow: Dictionary = {}) -> AiAction:
	var goals := {}
	for c in goal_cells:
		goals[c] = true
	var forbidden := forbidden_cells(state, u)
	var best := u.pos
	var best_c := _advance_score(field, goals, u.pos)
	for h in state.reachable(u.handle):
		if not allow.is_empty() and not allow.has(h):
			continue
		if forbidden.has(h) or state.unit_at(h) != null:
			continue  # 駒の居るマス＝乗れる味方輸送。前進で踏むと乗るつもりのない乗車になる
		var c := _advance_score(field, goals, h)
		if c < best_c or (c == best_c and best != u.pos and AiPick.is_younger_hex(h, best)):
			best = h
			best_c = c
	return AiAction.move_to(u.handle, best) if best != u.pos else null

## 直線寄せ＝盤上距離が縮むマスへ動く（距離が測れないときに使う）。壁の向こうの標的へ
## 壁際まで詰めて止まる動きになる。縮むマスが無ければ現在地。
func advance_straight(state: BattleState, u: Unit, goal: Vector2i,
		allow: Dictionary = {}) -> AiAction:
	var forbidden := forbidden_cells(state, u)
	var best := u.pos
	var best_d := Hex.distance(u.pos, goal)
	for h in state.reachable(u.handle):
		if not allow.is_empty() and not allow.has(h):
			continue
		if forbidden.has(h) or state.unit_at(h) != null:
			continue  # 前進では味方輸送のマスに止まらない（乗るかどうかは乗る行が決める）
		var d := Hex.distance(h, goal)
		if d < best_d or (d == best_d and best != u.pos and AiPick.is_younger_hex(h, best)):
			best = h
			best_d = d
	return AiAction.move_to(u.handle, best) if best != u.pos else null

## hex に立ったときの標的への距離。攻撃可能なマスは0、表に無いマスは測れない（UNREACHABLE）。
static func _advance_score(field: Dictionary, goals: Dictionary, hex: Vector2i) -> int:
	if goals.has(hex):
		return 0
	return int(field.get(hex, BattleState.UNREACHABLE))

## 逃げ足で拠点へ向かう1手（flee #3・#4 → doc/gdd/ai.md flee）。行き先は脅威圏の外の拠点のうち
## 迂回距離が最小のもの、止まるマスは脅威圏の外かつ敵ZOCの外。間合取りの距離を迂回距離に替えたもの。
## 行き先も止まれるマスも無ければ null＝待機（詰み）。
func flee_to_base(state: BattleState, u: Unit, goals: Array[Vector2i]) -> AiAction:
	var threat := threat_cells(state, u)
	var open: Array[Vector2i] = []
	for g in goals:
		if not threat.has(g):
			open.append(g)
	if open.is_empty():
		return null  # 逃げ先がすべて見張られている
	var goal := pick.nearest_hex_in(AiDistance.detour_cost_field(state, u.handle, u.pos), open)
	if goal == AiPick.NO_HEX:
		return null  # 迂回距離が測れない＝ZOCで全方位塞がれている
	var forbidden := forbidden_cells(state, u)
	var safe := {}
	for h in state.reachable(u.handle):
		if threat.has(h) or forbidden.has(h) or state.in_enemy_zoc(h, u):
			continue
		if h != u.pos and state.unit_at(h) != null:
			continue  # 駒の居るマス＝乗れる味方輸送。踏むと乗るつもりのない乗車になる
		safe[h] = true
	return spacing_step(state, u, safe, AiDistance.detour_cost_field(state, u.handle, goal), [goal])

## 最大前進（移動距離）で拠点へ向かう1手。測れる拠点が無ければ null＝この行は通らない。
func move_to_base(state: BattleState, u: Unit, goals: Array[Vector2i]) -> AiAction:
	if goals.is_empty():
		return null
	var goal := pick.nearest_hex_in(AiDistance.move_cost_field(state, u.handle, u.pos), goals)
	if goal == AiPick.NO_HEX:
		return null  # 移動距離が測れない＝道が塞がれている
	return advance(state, u, AiDistance.move_cost_field(state, u.handle, goal), [goal])

# --- 脅威圏と間合取り（doc/gdd/ai.md 脅威圏・間合取り） ---

## 脅威圏＝盤上の敵のどれかが移動力ぶん動いた先から u を攻撃できるマスの集合 { ヘックス: true }。
## 敵ごとに移動距離で動ける範囲を測り、そこから射程を伸ばして重ねる。相手が u を攻撃できるか
## （対空・対地）まで見る＝対空攻撃力の無い敵は飛行の駒を脅威圏に入れられない。
##
## ZOCは数えず、u 自身も敵の道を塞ぐ壁に数えない（ignore）。u はこれから動くので、いま自分が
## 敵を縛っていることを当てにすると、隣接から下がる手がそもそも成立しなくなる。
func threat_cells(state: BattleState, u: Unit) -> Dictionary:
	var out := {}
	var ignore := { u.handle: true }
	for e in state.units():
		if e.team == u.team or e.attack_against(u) <= 0:
			continue
		# 1ターンで届く範囲（移動力）で切って流す＝盤全体を流してから捨てるより敵の数ぶん軽い
		var field := AiDistance.move_cost_field_within(state, e.handle, e.pos, ignore, e.move)
		for r in field:
			for h in Hex.within_range(r, e.attack_range):
				if out.has(h) or not state.in_field(h):
					continue
				if e.can_reach(Hex.distance(r, h)):
					out[h] = true
	return out

## 移動範囲のうち脅威圏の外で、実際に止まれるマス { ヘックス: true }。standoff の行き先の母集合。
func safe_cells(state: BattleState, u: Unit) -> Dictionary:
	var threat := threat_cells(state, u)
	var out := {}
	for h in state.reachable(u.handle):
		if threat.has(h):
			continue
		if h != u.pos and state.unit_at(h) != null:
			continue  # 駒の居るマス＝乗れる味方輸送。踏むと乗るつもりのない乗車になる
		out[h] = true
	return out

## 間合取り＝safe のうち標的への距離が最小のマスへ動く1手。同値は現在地を優先し、次に col → row。
## 前進と違って「距離が縮むマス」に限らない＝いま脅威圏の中にいれば行き先は後ろになる。
## 測れるマスが1つも無ければ現在地に留まる（＝null＝次の行へ落ちる）。
func spacing_step(state: BattleState, u: Unit, safe: Dictionary,
		field: Dictionary, goal_cells: Array) -> AiAction:
	var goals := {}
	for c in goal_cells:
		goals[c] = true
	var best := AiPick.NO_HEX
	var best_c := BattleState.UNREACHABLE
	for h in safe:
		var c := _advance_score(field, goals, h)
		if c >= BattleState.UNREACHABLE:
			continue
		var better := best == AiPick.NO_HEX or c < best_c
		if not better and c == best_c and best != u.pos:
			better = h == u.pos or AiPick.is_younger_hex(h, best)
		if better:
			best = h
			best_c = c
	return AiAction.move_to(u.handle, best) if best != AiPick.NO_HEX and best != u.pos else null
