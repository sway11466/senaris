extends RefCounted
class_name BattleState
## 戦闘全体の状態 ＝ 中断セーブの本体（唯一の真実）。
## Godot ノード非依存（extends RefCounted）。見た目の状態はここに含めない。
## 詳細 → doc/tech/architecture.md, doc/tech/gamesystem.md

var cols: int  ## 矩形フィールドの幅（offset col 数）
var rows: int  ## 矩形フィールドの高さ（offset row 数）

var current_team: int = 0  ## 現在の手番の陣営
var turn_number: int = 1   ## ターン番号（両陣営が1巡で+1）

var _units: Array[Unit] = []
var _moved := {}       # unit_id -> true（攻撃前の移動を1回使った）
var _post_moved := {}  # unit_id -> true（攻撃後の再移動を1回使った）
var _attacked := {}    # unit_id -> true（このターンに攻撃済み）
var _done := {}        # unit_id -> true（コマンドメニューの「待機」等で明示的に行動終了）
var _spent := {}       # unit_id -> int（このターンに使った移動コスト。move と比較）
var _terrain := {}   # Vector2i(axial) -> terrain_id（未登録は平地）
var _movement := {}  # move_type -> { 地形名: コスト }（空＝全地形コスト1の従来挙動）
var _bases: Array[Base] = []  # 拠点（占領・出撃・回復）。詳細 → doc/gdd/map.md

## 勝利条件リスト（OR＝どれか1つ満たせば勝利）。空＝殲滅のみ（従来挙動）。詳細 → doc/gdd/map.md（勝敗条件）
## 要素は dict。現在対応: { "type": "defeat_unit", "unit_id": <int> } ＝ ボス撃破（id はステージJSONで明示採番）
var victory_conditions: Array = []

## 敵チーム既定のAIプリセットラベル（ステージJSONの "ai"。空＝charge）。詳細 → doc/gdd/ai.md
## 部隊(squad)に属するユニットは部隊の割り当てが優先。これは部隊外ユニットの既定。
var enemy_ai: String = ""

## 部隊(squad)＝AIプリセットを共有するユニットの束。詳細 → doc/gdd/ai.md
## 要素は dict: { "name": 表示名, "ai": プリセットラベル, ...プリセット値の上書き（sight/retreat/advance 等） }
var squads: Array = []
var _squad_of := {}  # unit_id -> squads の index（部隊に属さないユニットは未登録）

## unit_id を部隊 squad_index に所属させる（StageLoader が配線）。
func assign_squad(unit_id: int, squad_index: int) -> void:
	_squad_of[unit_id] = squad_index

## unit_id の所属部隊（dict）。部隊に属さなければ空 dict。
func squad_of(unit_id: int) -> Dictionary:
	var idx := squad_index_of(unit_id)
	return squads[idx] if idx >= 0 else {}

## unit_id の所属部隊 index（部隊に属さなければ -1）。一斉警戒（同部隊判定）に使う。
func squad_index_of(unit_id: int) -> int:
	var idx: Variant = _squad_of.get(unit_id)
	if idx == null or int(idx) < 0 or int(idx) >= squads.size():
		return -1
	return int(idx)

# --- AI起動状態（待機AIの「起きた」フラグ）。詳細 → doc/gdd/ai.md ---

var _engaged := {}  # unit_id -> true（待機AIが起動済み。一度起動したら戻らない）

## unit_id を起動済みにする（AIの起動判定・被弾で立つ）。
func mark_engaged(unit_id: int) -> void:
	_engaged[unit_id] = true

## unit_id が起動済みか。
func is_engaged(unit_id: int) -> bool:
	return _engaged.has(unit_id)
var _defeated := {}  # unit_id -> true（撃破で盤から消えた駒の記録。ボス撃破判定に使う）

func _init(p_cols: int = 12, p_rows: int = 8) -> void:
	cols = p_cols
	rows = p_rows

func add_unit(unit: Unit) -> void:
	_units.append(unit)

func units() -> Array[Unit]:
	return _units

func unit_by_id(id: int) -> Unit:
	for u in _units:
		if u.id == id:
			return u
	return null

func unit_at(hex: Vector2i) -> Unit:
	for u in _units:
		if u.pos == hex:
			return u
	return null

# --- 輸送（積載・運搬）。詳細 → doc/gdd/movement.md ---

var _passengers := {}  # transport_id -> Array[Unit]（搭乗中の駒。盤上には居ない＝殲滅カウント外）

## transport_id に搭乗中の駒（無ければ空配列）。
func passengers(transport_id: int) -> Array:
	return _passengers.get(transport_id, [])

## u が transport に乗れるか（同陣営・輸送どうし不可・capacity に空き）。
func can_board(u: Unit, transport: Unit) -> bool:
	if u == null or transport == null or not transport.is_transport():
		return false
	if u.is_transport() or u.team != transport.team:
		return false
	return passengers(transport.id).size() < transport.capacity

## 駒を輸送へ直接積む（初期配置・乗車の内部処理。行動フラグは触らない）。
func put_passenger(transport_id: int, u: Unit) -> void:
	if not _passengers.has(transport_id):
		var list: Array[Unit] = []
		_passengers[transport_id] = list
	_passengers[transport_id].append(u)

## 降車先候補の {hex: コスト}。搭乗駒が「輸送の位置を起点に」自力で動ける空きhex（通常移動と同じ規則）。
## 隣接1マスの特例: 輸送に隣接する進入可能な空きマスは、移動力・地形コストに関係なく常に含める
## （積み降ろしは人手＝移動0の駒も隣へ降ろせる）。進入不可地形（x）は特例でも不可。
## 乗車したターン（行動済み）の駒は降りられない＝空。
func _unload_map(transport_id: int, index: int) -> Dictionary:
	var t := unit_by_id(transport_id)
	var list := passengers(transport_id)
	if t == null or index < 0 or index >= list.size():
		return {}
	var p: Unit = list[index]
	if has_moved(p.id):
		return {}  # 乗車したターンは行動完了＝降りられない（翌ターンから）
	var m := Hex.flood_reach_cost_map(t.pos, p.move, _enter_cost.bind(p), _move_stop.bind(p))
	var cells := {}
	for h in m:
		if h != t.pos and unit_at(h) == null:  # 起点（輸送のマス）と占有マスは降車先にしない
			cells[h] = m[h]
	for nb in Hex.neighbors(t.pos):
		if cells.has(nb) or unit_at(nb) != null:
			continue
		if _enter_cost(nb, p) == Movement.IMPASSABLE:
			continue  # 盤外・進入不可地形（崖など）へは特例でも降ろせない
		cells[nb] = p.move  # 特例の降車は移動予算を使い切る扱い
	return cells

## 降車先候補（表示用）。
func unload_cells(transport_id: int, index: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for h in _unload_map(transport_id, index):
		cells.append(h)
	return cells

## 搭乗駒 index が from_hex に降りたと仮定したときの攻撃対象（降車確認メニューの「攻撃」可否）。
func unload_attack_targets(transport_id: int, index: int, from_hex: Vector2i) -> Array[int]:
	var list := passengers(transport_id)
	var ids: Array[int] = []
	if index < 0 or index >= list.size():
		return ids
	var p: Unit = list[index]
	for u in _units:
		if _can_attack_from(p, u, from_hex):
			ids.append(u.id)
	return ids

## 搭乗駒 index を to へ降ろす。降車＝その駒の通常移動（コスト消費・以後攻撃は可能）。
## 占領可ユニットが拠点hexへ降りれば即占領（移動と同じ扱い）。
func unload(transport_id: int, index: int, to: Vector2i) -> bool:
	var m := _unload_map(transport_id, index)
	if not m.has(to):
		return false
	var p: Unit = passengers(transport_id)[index]
	_passengers[transport_id].remove_at(index)
	p.pos = to
	_units.append(p)
	_moved[p.id] = true
	_spent[p.id] = int(m[to])
	_try_capture(p)
	return true

# --- 拠点（占領・出撃・回復）。詳細 → doc/gdd/map.md ---

func add_base(base: Base) -> void:
	_bases.append(base)

func bases() -> Array[Base]:
	return _bases

## hex にある拠点（無ければ null）。
func base_at(hex: Vector2i) -> Base:
	for b in _bases:
		if b.hex == hex:
			return b
	return null

## hex の地形id（未設定は既定地形 "plain"）。
func terrain_at(hex: Vector2i) -> String:
	return _terrain.get(hex, TerrainType.DEFAULT_ID)

## hex に地形を設定する。
func set_terrain(hex: Vector2i, terrain_id: String) -> void:
	_terrain[hex] = terrain_id

## 移動コスト表を設定する（move_type -> {地形名: コスト}）。
func set_movement(table: Dictionary) -> void:
	_movement = table

## hex が矩形フィールド内か。
func in_field(hex: Vector2i) -> bool:
	var off := Hex.axial_to_offset(hex)
	return off.x >= 0 and off.x < cols and off.y >= 0 and off.y < rows

## unit_id が「残り移動力」で到達できるヘックス（起点を含む）。盤外・敵は進入不可、地形はコスト。
## 味方のマスは通過できるが停止できない（到達候補には含めない）。
## 敵ZOC（敵に隣接するマス）に入ると停止＝その先へは進めない（飛行含む全移動タイプ）。
func reachable(unit_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in _reach_map(unit_id):
		result.append(h)
	return result

## reachable の {ヘックス: 到達コスト} 版（残り移動力で計算）。移動コスト消費に使う。
## 隣接1マスの特例: 隣接する乗れる輸送のマスは、移動力・地形コストに関係なく常に含める
## （積み降ろしは人手＝移動0の駒も隣の輸送には乗れる）。詳細 → doc/gdd/movement.md（輸送）
func _reach_map(unit_id: int) -> Dictionary:
	var u := unit_by_id(unit_id)
	if u == null:
		return {}
	var budget := maxi(u.move - int(_spent.get(unit_id, 0)), 0)
	var m := Hex.flood_reach_cost_map(u.pos, budget, _enter_cost.bind(u), _move_stop.bind(u))
	# 味方のマスは通過できるが停止できない＝到達候補から除外（起点・乗れる輸送は残す）。
	var result := {}
	for h in m:
		var occ := unit_at(h)
		if h == u.pos or occ == null or can_board(u, occ):
			result[h] = m[h]
	for h in _adjacent_boardable(u):
		if not result.has(h):
			result[h] = 0  # コスト値は未使用（乗車は move_unit が予算を使い切る扱いにする）
	return result

## u に隣接する「乗れる輸送」のマス一覧（隣接1マスの特例の対象）。
func _adjacent_boardable(u: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for nb in Hex.neighbors(u.pos):
		if in_field(nb) and can_board(u, unit_at(nb)):
			cells.append(nb)
	return cells

## u が hex に進入するコスト。盤外・敵ユニットのマスは進入不可（Movement.IMPASSABLE）。
## 味方のマスは通過できる（地形コスト）が停止はできない（到達候補からは _reach_map で除外）。
## 乗れる味方輸送のマスへは進入できる（＝移動先に選ぶと乗車）。それ以外は地形コスト。
func _enter_cost(hex: Vector2i, u: Unit) -> int:
	if not in_field(hex):
		return Movement.IMPASSABLE
	var occ := unit_at(hex)
	if occ != null and occ.team != u.team:
		return Movement.IMPASSABLE  # 敵の上は通れない（味方は通過可）
	return Movement.cost(_movement, u.move_type, terrain_at(hex))

## hex で移動が止まるか（その先へ展開しない）。敵ZOC＝停止／乗れる輸送＝乗車先なので通過不可。
## 味方のマスでは止まらず先へ展開する（通過はできるが停止はできない＝到達候補にはならない）。
func _move_stop(hex: Vector2i, u: Unit) -> bool:
	var occ := unit_at(hex)
	if occ != null and can_board(u, occ):
		return true  # 乗れる輸送のマス（終点としてのみ有効）
	return _in_enemy_zoc(hex, u)

## hex が u から見た敵ZOC内か（敵ユニットに隣接しているか）。ZOCに入ると移動が止まる。
func _in_enemy_zoc(hex: Vector2i, u: Unit) -> bool:
	for nb in Hex.neighbors(hex):
		var occ := unit_at(nb)
		if occ != null and occ.team != u.team:
			return true
	return false

## unit_id を to へ動かせるか（空きマスかつ残り移動範囲内）。地形のみの判定で手番は見ない。
func can_move(unit_id: int, to: Vector2i) -> bool:
	if unit_at(to) != null:
		return false
	var u := unit_by_id(unit_id)
	if u == null or to == u.pos:
		return false
	return _reach_map(unit_id).has(to)

## 妥当なら移動を適用して true。手番違い・移動権なし・不正先なら false。移動コストを予算から消費。
## 移動先が「乗れる味方輸送」のマスなら乗車＝盤から降りて搭乗し、その駒は行動完了になる。
func move_unit(unit_id: int, to: Vector2i) -> bool:
	if not _can_act_move(unit_id):
		return false
	var rm := _reach_map(unit_id)
	var u := unit_by_id(unit_id)
	if to == u.pos or not rm.has(to):
		return false
	var occ := unit_at(to)
	if occ != null:
		if not can_board(u, occ):
			return false
		_take_off_board(unit_id)  # 乗車: 盤から外して輸送へ（撃破記録は付かない）
		put_passenger(occ.id, u)
		_moved[unit_id] = true    # 乗った駒は行動完了（doc/gdd/movement.md）
		_post_moved[unit_id] = true
		_attacked[unit_id] = true
		_spent[unit_id] = u.move
		return true
	u.pos = to
	_spent[unit_id] = int(_spent.get(unit_id, 0)) + int(rm[to])
	# 攻撃前なら通常移動、攻撃後なら再移動として消費（どちらも1回）。
	if has_attacked(unit_id):
		_post_moved[unit_id] = true
	else:
		_moved[unit_id] = true
	_try_capture(u)  # 占領可ユニットが敵/中立拠点に入ったら即占領
	return true

## u が今いる拠点を占領できるなら所属を u の陣営へ移す（占領＝即時・進入した瞬間）。
func _try_capture(u: Unit) -> void:
	if not u.can_capture:
		return
	var b := base_at(u.pos)
	if b != null and b.team != u.team:
		b.team = u.team

## いま移動できるか（手番・移動権・残り予算）。
## 攻撃前: 通常移動を未使用なら可。攻撃後: 再移動可ユニットが再移動を未使用なら可。
func _can_act_move(unit_id: int) -> bool:
	var u := unit_by_id(unit_id)
	if not is_current_unit(u):
		return false
	if int(_spent.get(unit_id, 0)) >= u.move and _adjacent_boardable(u).is_empty():
		return false  # 予算切れ（隣接に乗れる輸送があれば特例で乗車だけはできる）
	if has_attacked(unit_id):
		return u.move_after_attack and not _post_moved.has(unit_id)
	return not _moved.has(unit_id)

## いま移動できるか（公開）。盤の移動範囲表示などに使う。
func can_still_move(unit_id: int) -> bool:
	return _can_act_move(unit_id)

# --- 出撃（ネクタリス方式・占領済み拠点から1歩で出す） ---

## base_hex の拠点から出撃できるhex（拠点に隣接・盤内の空き＋乗れる味方輸送のマス）。出撃先候補の表示に使う。
## garrison_index を渡すとその駒が乗れる輸送だけ含める（省略＝控えのどれかが乗れる輸送を含める）。
func deploy_cells(base_hex: Vector2i, garrison_index := -1) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var b := base_at(base_hex)
	if b == null or b.team != current_team or b.garrison.is_empty():
		return cells
	for nb in Hex.neighbors(base_hex):
		if not in_field(nb):
			continue
		var occ := unit_at(nb)
		if occ == null:
			cells.append(nb)
		elif _deploy_boardable(b, garrison_index, occ):
			cells.append(nb)  # 出撃＝そのまま搭乗（隣接1マスの特例の拠点版）
	return cells

## 拠点 b の控え（index 指定 or いずれか）が輸送 occ に出撃で直接乗れるか。
## can_board 相当だが、控えの team は出撃時に確定するため拠点の所属で判定する。
func _deploy_boardable(b: Base, garrison_index: int, occ: Unit) -> bool:
	if not occ.is_transport() or occ.team != b.team:
		return false
	if passengers(occ.id).size() >= occ.capacity:
		return false
	if garrison_index >= 0:
		return garrison_index < b.garrison.size() and not (b.garrison[garrison_index] as Unit).is_transport()
	for gu in b.garrison:
		if not (gu as Unit).is_transport():
			return true  # 輸送でない控えが1体でも居れば候補（輸送は輸送に乗れない）
	return false

## いま出撃させられるか（自軍拠点・控えあり・出せる先あり）。
func can_deploy(base_hex: Vector2i) -> bool:
	return not deploy_cells(base_hex).is_empty()

## garrison[index] を出撃させられるか（native ルール）。中立 native は誰の拠点からでも出せる（寝返り）。
## 味方/敵 native の駒は「拠点の現所有者＝生来の陣営」のときだけ＝奪われた拠点の駒は閉じ込め。
func can_deploy_garrison(base_hex: Vector2i, index: int) -> bool:
	var b := base_at(base_hex)
	if b == null or index < 0 or index >= b.garrison.size():
		return false
	var u: Unit = b.garrison[index]
	return u.native_team == Base.NEUTRAL or u.native_team == b.team

## 拠点の garrison[index] を隣接 to_hex へ出撃させる。出撃は1歩＝そのターンは行動完了。
## to_hex が「乗れる味方輸送」のマスなら出撃＝そのまま搭乗（盤上には出ない）。
## 成否を返す。手番違い・非占領・索引外・native不一致（閉じ込め）・隣接でない・乗れない占有マスなら false。
func deploy(base_hex: Vector2i, garrison_index: int, to_hex: Vector2i) -> bool:
	var b := base_at(base_hex)
	if b == null or b.team != current_team:
		return false
	if not can_deploy_garrison(base_hex, garrison_index):
		return false
	if not in_field(to_hex):
		return false
	if Hex.distance(base_hex, to_hex) != 1:
		return false
	var occ := unit_at(to_hex)
	if occ != null and not _deploy_boardable(b, garrison_index, occ):
		return false
	var u: Unit = b.garrison[garrison_index]
	b.garrison.remove_at(garrison_index)
	u.team = current_team  # 中立 native はここで寝返る（味方/敵 native は自陣営のまま＝値は変わらない）
	if occ != null:
		put_passenger(occ.id, u)  # 出撃先が輸送＝直接乗車（盤上には出ない）
	else:
		u.pos = to_hex
		_units.append(u)
	if b.squad_index >= 0:
		assign_squad(u.id, b.squad_index)  # 拠点=squad の駒として振る舞う（敵AIの拠点出撃。ai.md §7）
	# 出撃した駒はそのターン行動完了（1歩のみ＝移動も再移動も攻撃も降車もこれ以上しない）。
	_moved[u.id] = true
	_post_moved[u.id] = true
	_attacked[u.id] = true
	_spent[u.id] = u.move
	return true

## 自軍所有の拠点に「入る」（駐留）。拠点hexに立っている駒を garrison へ移す＝盤上から消える。
## 中で手番開始ごとに回復（_heal_garrisons）。出るのは出撃（deploy）＝1歩・行動完了。
func can_enter_base(unit_id: int) -> bool:
	var u := unit_by_id(unit_id)
	return u != null and can_enter_base_at(unit_id, u.pos)

## dest_hex（自軍拠点）へ移動して「入る」が許されるか。メニュー表示は移動前に先読みするため、
## 現在位置ではなく移動先を仮定して判定する（実行時は dest_hex＝現在位置で同じ規則になる）。
## 案B: 盤上最後の1体でも、入った直後に復帰手段が残るなら入れる（即敗北を防ぐ）。
func can_enter_base_at(unit_id: int, dest_hex: Vector2i) -> bool:
	var u := unit_by_id(unit_id)
	if not is_current_unit(u):
		return false
	var b := base_at(dest_hex)
	if b == null or b.team != u.team:
		return false
	if team_unit_count(u.team) > 1:
		return true  # 入っても盤上に他の駒が残る
	# 盤上最後の1体：入った駒自身が b の出せる控えになる＝b に空き隣接があれば復帰可。
	# 他拠点で既に復帰可能でもよい（＝入った瞬間に「盤上0かつ復帰なし」の敗北にならない）。
	return _base_has_open_neighbor(b) or _has_reinforcement(u.team)

func enter_base(unit_id: int) -> bool:
	if not can_enter_base(unit_id):
		return false
	var u := unit_by_id(unit_id)
	var b := base_at(u.pos)
	_take_off_board(unit_id)
	b.garrison.append(u)
	return true

# --- 攻撃 ---

## attacker が target を攻撃できるか（現手番・未攻撃・射程内の敵）。
func can_attack(attacker_id: int, target_id: int) -> bool:
	var a := unit_by_id(attacker_id)
	if a == null:
		return false
	return _can_attack_from(a, unit_by_id(target_id), a.pos)

## from_hex に attacker が居ると仮定したときの攻撃可否。仮移動でメニューを出す（移動確定前）ために使う。
func _can_attack_from(a: Unit, t: Unit, from_hex: Vector2i) -> bool:
	if a == null or t == null:
		return false
	if not is_current_unit(a) or has_attacked(a.id):
		return false
	if t.team == a.team:
		return false
	if a.attack_against(t) <= 0:
		return false  # 対空0の駒は飛行を狙えない（攻撃力が無い相手は対象外）
	return Hex.distance(from_hex, t.pos) <= a.attack_range  # 近接=1, 間接=射程内

## attacker が今いる位置から攻撃できる敵ユニットIDの一覧。
func attack_targets(attacker_id: int) -> Array[int]:
	var a := unit_by_id(attacker_id)
	return attack_targets_from(attacker_id, a.pos) if a != null else []

## from_hex に居ると仮定して攻撃できる敵ID一覧（移動を確定せずコマンドメニューを出すため）。
func attack_targets_from(attacker_id: int, from_hex: Vector2i) -> Array[int]:
	var a := unit_by_id(attacker_id)
	var ids: Array[int] = []
	if a == null:
		return ids
	for u in _units:
		if _can_attack_from(a, u, from_hex):
			ids.append(u.id)
	return ids

## 攻撃を解決。両軍同時攻撃（防御側は反撃する）。
## 成功なら {damage, killed, retaliation, attacker_killed, target_troops, attacker_troops}、不正なら空。
func attack(attacker_id: int, target_id: int) -> Dictionary:
	if not can_attack(attacker_id, target_id):
		return {}
	var a := unit_by_id(attacker_id)
	var t := unit_by_id(target_id)
	var melee := a.attack_range <= 1  # 近接なら反撃あり、間接なら反撃なし
	# 反撃は「近接」かつ「防御側が攻撃側を攻撃できる」ときだけ成立。
	# 例: 対空0の地上ユニットが飛行に殴られても反撃できない（→被反撃なし・経験+0）。
	var can_retaliate := melee and t.attack_against(a) > 0
	# 同時攻撃: 戦闘前の状態で内訳ごと確定してから適用（決定的）。表示はこの内訳をそのまま使う。
	var fwd := Combat.hit_detail(self, a, t, melee)
	var ret: Variant = Combat.hit_detail(self, t, a, melee) if can_retaliate else null
	# 戦闘前スナップショット（撃破で盤から消えても結果表示できるよう値を固める）。
	var a_snap := _unit_snapshot(a)
	var t_snap := _unit_snapshot(t)
	var dmg_to_target: int = fwd["loss"]
	var dmg_to_attacker: int = (ret["loss"] if ret != null else 0)
	t.troops -= dmg_to_target
	a.troops -= dmg_to_attacker
	var target_killed := t.troops <= 0
	var attacker_killed := a.troops <= 0
	a_snap["troops_after"] = maxi(a.troops, 0)
	t_snap["troops_after"] = maxi(t.troops, 0)
	# 経験値: 戦ったら+1・倒したらさらに+1。攻撃側は常に参加。
	# 防御側は反撃が成立したときだけ+1（間接で撃たれた側／対空なしで飛行に撃たれた側は+0）。
	a.add_experience(1 + (1 if target_killed else 0))
	if can_retaliate:
		t.add_experience(1 + (1 if attacker_killed else 0))
	if target_killed:
		_remove_unit(target_id)
	if attacker_killed:
		_remove_unit(attacker_id)
	_attacked[attacker_id] = true  # 移動可否は move_after_attack で判定（再移動）
	# 被ダメは待機AIの確定起動トリガー（攻撃した側も当然起動済み）。詳細 → doc/gdd/ai.md
	mark_engaged(attacker_id)
	mark_engaged(target_id)
	return {
		"damage": dmg_to_target,
		"killed": target_killed,
		"retaliation": dmg_to_attacker,
		"attacker_killed": attacker_killed,
		"target_troops": maxi(t.troops, 0),
		"attacker_troops": maxi(a.troops, 0),
		"detail": {  # 戦闘結果ビュー用（式は Combat.hit_detail の1か所＝盤の兵数と一致）
			"attacker": a_snap,
			"defender": t_snap,
			"to_defender": fwd,
			"to_attacker": ret,
			"melee": melee,
		},
	}

## 表示用のユニットスナップショット（戦闘前）。撃破後も値が要るので dict に固める。
func _unit_snapshot(u: Unit) -> Dictionary:
	return {
		"id": u.id, "type_id": u.type_id, "skin_id": u.skin_id, "team": u.team, "level": u.level,
		"troops_before": u.troops, "max": u.max_troops, "terrain": terrain_at(u.pos),
	}

## 撃破された駒を盤から除去し、撃破済みとして記録（勝利条件「ボス撃破」の判定材料）。
## 輸送が撃破された場合、搭乗中の駒も失われる（ネクタリス準拠）。
func _remove_unit(unit_id: int) -> void:
	_defeated[unit_id] = true
	for p in passengers(unit_id):
		_defeated[p.id] = true  # 巻き添え（盤上には居ないのでリストから消すだけ）
	_passengers.erase(unit_id)
	_take_off_board(unit_id)

## 駒を盤上リストから外す（撃破記録は付けない。乗車・撃破処理の内部用）。
func _take_off_board(unit_id: int) -> void:
	for i in _units.size():
		if _units[i].id == unit_id:
			_units.remove_at(i)
			return

# --- 勝敗（自軍＝team 0 視点。ターン制限は未実装） ---

enum { ONGOING, PLAYER_WIN, PLAYER_LOSS }

func team_unit_count(team: int) -> int:
	var n := 0
	for u in _units:
		if u.team == team:
			n += 1
	return n

## team が「復帰手段」を持つか＝所有拠点に、実際に盤上へ出せる控えが1体でもいる（案B）。
## 盤上0でもこれが真なら、その陣営はまだ消滅していない＝敗北/勝利にしない。
func _has_reinforcement(team: int) -> bool:
	for b in _bases:
		if b.team == team and _base_has_deployable_garrison(b) and _base_has_open_neighbor(b):
			return true
	return false

## 拠点 b の控えに、native ルールで出撃できる駒が1体でもいるか（中立、または所有者と同 native）。
func _base_has_deployable_garrison(b: Base) -> bool:
	for gu in b.garrison:
		var u := gu as Unit
		if u.native_team == Base.NEUTRAL or u.native_team == b.team:
			return true
	return false

## 拠点 b の周囲に、盤上へ出せる空きマスが1つでもあるか（＝盤上復帰の余地）。
## 盤上0の判定用なので味方輸送は考慮不要（盤上に味方が居ない＝味方輸送も盤上に無い）。
func _base_has_open_neighbor(b: Base) -> bool:
	for nb in Hex.neighbors(b.hex):
		if in_field(nb) and unit_at(nb) == null:
			return true
	return false

## 決着結果。敗北を優先（自軍消滅／自軍本拠地の喪失）。相討ち消滅も負け。
## 消滅＝盤上0 かつ 復帰手段なし（案B）。勝利は 殲滅（常に有効）＋ victory_conditions のいずれか（OR）。
func outcome() -> int:
	if team_unit_count(0) == 0 and not _has_reinforcement(0):
		return PLAYER_LOSS
	if _own_hq_lost():
		return PLAYER_LOSS  # 味方本拠地を奪われたら敗北（hq を置いたステージだけ効く）
	if team_unit_count(1) == 0 and not _has_reinforcement(1):
		return PLAYER_WIN
	for c in victory_conditions:
		if _victory_met(c):
			return PLAYER_WIN
	return ONGOING

## 自軍 native の本拠地（hq）が敵の手に落ちているか。hq が無いステージでは常に false。
func _own_hq_lost() -> bool:
	for b in _bases:
		if b.is_hq() and b.native_team == 0 and b.team != 0:
			return true
	return false

## 勝利条件1件の判定。未知の type は満たさない扱い（前方互換）。
func _victory_met(c: Dictionary) -> bool:
	match String(c.get("type", "")):
		"defeat_unit":  # ボス撃破＝指定IDの駒が撃破済み
			return _defeated.has(int(c.get("unit_id", -1)))
		"capture_hq":   # 本拠地占領＝敵 native の hq をすべて自軍が保持（hq が無ければ不成立）
			return _enemy_hq_all_captured()
	return false

## 敵 native の本拠地（hq）がすべて自軍所属になっているか。該当 hq が1つも無ければ false（空勝ち防止）。
func _enemy_hq_all_captured() -> bool:
	var found := false
	for b in _bases:
		if b.is_hq() and b.native_team == 1:
			found = true
			if b.team != 0:
				return false
	return found

func is_over() -> bool:
	return outcome() != ONGOING

# --- 手番 ---

## この陣営/ユニットが現在の手番か。
func is_current_unit(u: Unit) -> bool:
	return u != null and u.team == current_team

## このターンに（攻撃前の）移動を使ったか。
func has_moved(unit_id: int) -> bool:
	return _moved.has(unit_id)

## このターンに攻撃済みか。
func has_attacked(unit_id: int) -> bool:
	return _attacked.has(unit_id)

## このターンの行動を使い切ったか（もう移動も攻撃もできない／明示的に待機した）。
## 降車は「搭乗駒の行動」＝輸送自身が行動完了（待機・攻撃済み）でも、降ろせる駒が居る限り
## 選択可能にする（未行動の搭乗駒はいつでも降ろせる）。詳細 → doc/gdd/movement.md
func is_done(unit_id: int) -> bool:
	if _has_unloadable_passenger(unit_id):
		return false  # 「待機」済みでも降車のために選択できる
	if _done.has(unit_id):
		return true  # 「待機」で行動終了済み
	var can_atk := not has_attacked(unit_id) and not attack_targets(unit_id).is_empty()
	var can_mv := _can_act_move(unit_id) and reachable(unit_id).size() > 1  # 自分以外に行ける
	return not can_atk and not can_mv

## 降ろせる搭乗駒（このターン未行動）が居るか。
func _has_unloadable_passenger(unit_id: int) -> bool:
	for p in passengers(unit_id):
		if not has_moved(p.id):
			return true
	return false

## 明示的に行動終了させる（コマンドメニューの「待機」）。再選択・再行動を止める。
func set_done(unit_id: int) -> void:
	_done[unit_id] = true

## 選択して操作できる状態か（現手番・まだ行動が残っている）。
func can_select(unit_id: int) -> bool:
	return is_current_unit(unit_by_id(unit_id)) and not is_done(unit_id)

## 手番を次の陣営へ。行動済みフラグを一掃し、0 に戻ったらターン+1。
## 手番開始時に、拠点に駐留中（garrison）の駒を回復（休憩＝中に入るモデル）。
func end_turn() -> void:
	_moved.clear()
	_post_moved.clear()
	_attacked.clear()
	_done.clear()
	_spent.clear()
	current_team = 1 - current_team
	if current_team == 0:
		turn_number += 1
	_heal_garrisons()

## 手番が始まる陣営の「拠点に駐留中の駒」を満員へ回復（兵数のみ・経験Lvは据え置き）。
## 回復できるのは native が自陣営/中立の拠点だけ＝奪った敵 native 拠点は出撃拠点にはなるが回復しない。
## 閉じ込め駒（native≠所有者）も回復しない。hexの上に立っている駒は回復しない（中に入るモデル）。
func _heal_garrisons() -> void:
	for b in _bases:
		if b.team != current_team:
			continue
		if b.native_team != current_team and b.native_team != Base.NEUTRAL:
			continue  # 敵 native の拠点では回復しない
		for u in b.garrison:
			if u.native_team == current_team or u.native_team == Base.NEUTRAL:
				u.troops = u.max_troops
