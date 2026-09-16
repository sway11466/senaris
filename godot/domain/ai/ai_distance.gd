extends RefCounted
class_name AiDistance
## 敵AIが標的や行き先を測る距離（純ロジック・読み取り専用）。state を引数に取る static ヘルパー。
## 3つの距離＝移動距離（駒を壁に数える）・地形距離（地形だけ）・迂回距離（移動距離に敵ZOCの壁を足す）と、
## それぞれの道のり表 { ヘックス: コスト }。用語の正本は doc/gdd/ai.md（用語 > 距離）。
##
## 測れないときの値は BattleState.UNREACHABLE（番兵は state 側に置く＝呼び手の比較式を変えない）。
## 地形だけの道のり表（travel_cost_field）は reachable と同じメモを共有するので BattleState に残し、
## ここはそれを駒の規則（移動タイプ・移動力・現在地）で引く口と、駒・ZOCを壁にする流し方だけを持つ。

## 移動距離の表＝handle の駒の移動規則で、from を起点に流した道のり表。
## 侵入できないマス（地形・すでに駒がいるマス・1マスのコストが移動力を超えるマス）は載らない。
##
## 起点を引数に取るのは、AIが表を2方向に使うため。標的選び＝行動ユニットから流して各標的の
## 攻撃可能なマスを読む。前進＝標的から流して移動範囲の各マスを読む（縮むマスを探す）。
## 向きが違うだけで規則は同じなので、1駒につき「自分から3種類」＋「決めた標的へ1種類」で足りる。
##
## 行動ユニットが今いるマスは、起点でなくても壁にしない（自分自身で道を塞がない）。
static func move_cost_field(state: BattleState, handle: int, from: Vector2i) -> Dictionary:
	return move_cost_field_without(state, handle, from, {})

## 盤全体を流す予算（何ターンぶんでも載る）。
const WHOLE_BOARD := 1 << 24

## 移動距離の表を、ignore_ids の駒が居ないものとして流したもの。
## AIが「その敵をどければ道が良くなるか」を測るのに使う（doc/gdd/ai.md 経路上の敵）。
static func move_cost_field_without(state: BattleState, handle: int, from: Vector2i,
		ignore_ids: Dictionary) -> Dictionary:
	return move_cost_field_within(state, handle, from, ignore_ids, WHOLE_BOARD)

## 移動距離の表を budget（コスト上限）で切って流したもの。載る範囲の値は WHOLE_BOARD と同じで、
## 1ターンで届く範囲（budget＝移動力）だけ要るときに盤全体を流さずに済む（脅威圏が使う）。
static func move_cost_field_within(state: BattleState, handle: int, from: Vector2i,
		ignore_ids: Dictionary, budget: int) -> Dictionary:
	var u := state.unit_by_handle(handle)
	if u == null:
		return {}
	return state.travel_cost_field_avoiding_units(from, u.move_type, budget, u.move, u.pos, ignore_ids)

## 地形距離の表＝駒を壁として数えず、地形だけで測った道のり表。
## 仲間や敵に塞がれていても、その駒がどいたあとに通れる道を測る（見込前進が使う）。
## travel_cost_field のメモに乗る＝同じ起点・同じ移動タイプなら流し直さない。
static func terrain_cost_field(state: BattleState, handle: int, from: Vector2i) -> Dictionary:
	var u := state.unit_by_handle(handle)
	if u == null:
		return {}
	return state.travel_cost_field(from, u.move_type, u.move)

## 迂回距離の表＝移動距離の表に加えて敵ZOC（敵ユニットに隣接するマス）も壁にしたもの。
## ZOCは入ると移動が終わるので、避けて進めば前衛の帯に触れずに横へ滑れる（回り込みが使う）。
##
## ignore_zoc_id＝ZOCを数えないユニット（＝狙っている標的自身）。標的のZOCまで避けると
## 標的の隣へ入れず必ず測れなくなるので、そこだけ外す。-1＝全ての敵のZOCを避ける（拠点が標的のとき）。
##
## 行動ユニットが今いるマスはZOCでも壁にしない。起点から流すときは Dijkstra が起点にコストを
## 掛けないので、標的から流すときと値が食い違わないよう向きを揃える。
## 駒もZOCも1手ごとに動くのでメモしない（地形だけの terrain_cost_field と違って使い捨て）。
## ignore_ids＝「居ないもの」として測る駒のid。壁にもZOCの主にも数えない。
static func detour_cost_field(state: BattleState, handle: int, from: Vector2i,
		ignore_zoc_id: int = -1, ignore_ids: Dictionary = {}) -> Dictionary:
	var u := state.unit_by_handle(handle)
	if u == null or not state.in_field(from):
		return {}
	var table := state.movement_table()
	var cost_fn := func(hex: Vector2i) -> int:
		if not state.in_field(hex):
			return Movement.IMPASSABLE
		if hex != from and hex != u.pos:
			var occ := state.unit_at(hex)
			if occ != null and not ignore_ids.has(occ.handle):
				return Movement.IMPASSABLE  # 起点・自分以外の駒は壁
			if state.in_enemy_zoc(hex, u, ignore_zoc_id, ignore_ids):
				return Movement.IMPASSABLE  # 敵ZOCは踏まない＝これが迂回
		var c := Movement.cost(table, u.move_type, state.terrain_at(hex))
		if u.move > 0 and c > u.move:
			return Movement.IMPASSABLE  # 何ターンかけても入れない＝この駒には壁
		return c
	return Hex.flood_reach_cost_map(from, WHOLE_BOARD, cost_fn)

## field 上で cells に届く最小コスト。1マスも載っていなければ UNREACHABLE（＝測れない）。
## 同値をどう捌くか（col → row の若い方）は行き先を選ぶ側の話なので、ここでは値だけ返す。
static func min_cost_in(field: Dictionary, cells: Array) -> int:
	var best := BattleState.UNREACHABLE
	for hex in cells:
		var c := int(field.get(hex, BattleState.UNREACHABLE))
		if c < best:
			best = c
	return best

## 移動距離＝行動ユニットが侵入できないマスを除いて、現在地から cells までを地形コストで測った最小距離。
## 標的を1つ測る口。同じターンに複数の標的を測るなら move_cost_field を1枚作って min_cost_in で読む
## （この口は呼ぶたびに盤を流し直す）。以下の2つも同じ。
static func move_distance(state: BattleState, handle: int, cells: Array) -> int:
	var u := state.unit_by_handle(handle)
	if u == null:
		return BattleState.UNREACHABLE
	return min_cost_in(move_cost_field(state, handle, u.pos), cells)

## 地形距離＝移動距離から駒の除外を外し、地形だけで測った最小距離。
static func terrain_distance(state: BattleState, handle: int, cells: Array) -> int:
	var u := state.unit_by_handle(handle)
	if u == null:
		return BattleState.UNREACHABLE
	return min_cost_in(terrain_cost_field(state, handle, u.pos), cells)

## 迂回距離＝移動距離に敵ZOCの除外を加えた最小距離。ignore_zoc_id は detour_cost_field と同じ。
static func detour_distance(state: BattleState, handle: int, cells: Array,
		ignore_zoc_id: int = -1) -> int:
	var u := state.unit_by_handle(handle)
	if u == null:
		return BattleState.UNREACHABLE
	return min_cost_in(detour_cost_field(state, handle, u.pos, ignore_zoc_id), cells)

## 標的がユニットのときの迂回距離の表。ignore_zoc_id に標的自身を埋める＝素の detour_cost_field は
## 既定（-1）が「全ての敵ZOCを避ける」で、ユニットを狙うと必ず測れなくなる側に転ぶ。
## 拠点を狙うとき（raid）は標的がユニットでないので、素の口を -1 のまま使うのが正しい。
static func detour_cost_field_to(state: BattleState, handle: int, from: Vector2i,
		target_id: int) -> Dictionary:
	return detour_cost_field(state, handle, from, target_id)

## 標的がユニットのときの迂回距離＝その標的に攻撃可能なマスまで、標的自身のZOCだけ外して測る。
static func detour_distance_to(state: BattleState, handle: int, target_id: int) -> int:
	return detour_distance(state, handle, state.attack_cells(handle, target_id), target_id)
