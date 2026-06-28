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
var _moved := {}     # unit_id -> true（このターンに移動済み）
var _attacked := {}  # unit_id -> true（このターンに攻撃済み）
var _terrain := {}   # Vector2i(axial) -> terrain_id（未登録は平地）
var _movement := {}  # move_type -> { 地形名: コスト }（空＝全地形コスト1の従来挙動）

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

## hex の地形タイプ（未設定は平地）。
func terrain_at(hex: Vector2i) -> int:
	return _terrain.get(hex, Terrain.PLAINS)

## hex に地形を設定する。
func set_terrain(hex: Vector2i, terrain_id: int) -> void:
	_terrain[hex] = terrain_id

## 移動コスト表を設定する（move_type -> {地形名: コスト}）。
func set_movement(table: Dictionary) -> void:
	_movement = table

## hex が矩形フィールド内か。
func in_field(hex: Vector2i) -> bool:
	var off := Hex.axial_to_offset(hex)
	return off.x >= 0 and off.x < cols and off.y >= 0 and off.y < rows

## unit_id が移動できるヘックス（起点を含む）。盤外・他ユニットは進入不可、地形は移動コスト。
## 敵ZOC（敵に隣接するマス）に入ると停止＝その先へは進めない（飛行含む全移動タイプ）。
func reachable(unit_id: int) -> Array[Vector2i]:
	var u := unit_by_id(unit_id)
	if u == null:
		return []
	return Hex.flood_reach_cost(u.pos, u.move, _enter_cost.bind(u), _in_enemy_zoc.bind(u))

## u が hex に進入するコスト。盤外・占有は進入不可（Movement.IMPASSABLE）。それ以外は地形コスト。
func _enter_cost(hex: Vector2i, u: Unit) -> int:
	if not in_field(hex) or unit_at(hex) != null:
		return Movement.IMPASSABLE
	return Movement.cost(_movement, u.move_type, Terrain.name_of(terrain_at(hex)))

## hex が u から見た敵ZOC内か（敵ユニットに隣接しているか）。ZOCに入ると移動が止まる。
func _in_enemy_zoc(hex: Vector2i, u: Unit) -> bool:
	for nb in Hex.neighbors(hex):
		var occ := unit_at(nb)
		if occ != null and occ.team != u.team:
			return true
	return false

## unit_id を to へ動かせるか（空きマスかつ移動範囲内）。地形のみの判定で手番は見ない。
func can_move(unit_id: int, to: Vector2i) -> bool:
	if unit_at(to) != null:
		return false
	return reachable(unit_id).has(to)

## 妥当なら移動を適用して true。手番違い・移動済/攻撃済・不正先なら false。
func move_unit(unit_id: int, to: Vector2i) -> bool:
	if not _can_act_move(unit_id):
		return false
	if not can_move(unit_id, to):
		return false
	unit_by_id(unit_id).pos = to
	_moved[unit_id] = true
	return true

func _can_act_move(unit_id: int) -> bool:
	return is_current_unit(unit_by_id(unit_id)) and not has_moved(unit_id) and not has_attacked(unit_id)

# --- 攻撃 ---

## attacker が target を攻撃できるか（現手番・未攻撃・隣接する敵）。
func can_attack(attacker_id: int, target_id: int) -> bool:
	var a := unit_by_id(attacker_id)
	var t := unit_by_id(target_id)
	if a == null or t == null:
		return false
	if not is_current_unit(a) or has_attacked(attacker_id):
		return false
	if t.team == a.team:
		return false
	return Hex.distance(a.pos, t.pos) == 1

## attacker が今攻撃できる敵ユニットIDの一覧。
func attack_targets(attacker_id: int) -> Array[int]:
	var ids: Array[int] = []
	for u in _units:
		if can_attack(attacker_id, u.id):
			ids.append(u.id)
	return ids

## 攻撃を解決。両軍同時攻撃（防御側は反撃する）。
## 成功なら {damage, killed, retaliation, attacker_killed, target_troops, attacker_troops}、不正なら空。
func attack(attacker_id: int, target_id: int) -> Dictionary:
	if not can_attack(attacker_id, target_id):
		return {}
	var a := unit_by_id(attacker_id)
	var t := unit_by_id(target_id)
	# 同時攻撃: 戦闘前の兵数で双方の損害を確定させてから適用（決定的）。
	var dmg_to_target := Combat.casualties(self, a, t)
	var dmg_to_attacker := Combat.casualties(self, t, a)  # 反撃: tの攻撃力 vs aの防御力
	t.troops -= dmg_to_target
	a.troops -= dmg_to_attacker
	var target_killed := t.troops <= 0
	var attacker_killed := a.troops <= 0
	# 経験値: 戦ったら+1・倒したらさらに+1。攻撃側は常に参加。
	# 防御側は反撃が成立したときだけ+1（近接は必ず反撃する→+1）。
	# ※将来 間接攻撃／対空なしで反撃不成立なら、防御側はここで+0にする。
	a.add_experience(1 + (1 if target_killed else 0))
	t.add_experience(1 + (1 if attacker_killed else 0))
	if target_killed:
		_remove_unit(target_id)
	if attacker_killed:
		_remove_unit(attacker_id)
	_moved[attacker_id] = true
	_attacked[attacker_id] = true
	return {
		"damage": dmg_to_target,
		"killed": target_killed,
		"retaliation": dmg_to_attacker,
		"attacker_killed": attacker_killed,
		"target_troops": maxi(t.troops, 0),
		"attacker_troops": maxi(a.troops, 0),
	}

func _remove_unit(unit_id: int) -> void:
	for i in _units.size():
		if _units[i].id == unit_id:
			_units.remove_at(i)
			return

# --- 勝敗（自軍＝team 0 視点。暫定: 拠点占領勝利・ターン制限は未実装） ---

enum { ONGOING, PLAYER_WIN, PLAYER_LOSS }

func team_unit_count(team: int) -> int:
	var n := 0
	for u in _units:
		if u.team == team:
			n += 1
	return n

## 決着結果。自軍全滅は負け（相討ち全滅も負け＝自軍が消えていれば敗北を優先）。
func outcome() -> int:
	if team_unit_count(0) == 0:
		return PLAYER_LOSS
	if team_unit_count(1) == 0:
		return PLAYER_WIN
	return ONGOING

func is_over() -> bool:
	return outcome() != ONGOING

# --- 手番 ---

## この陣営/ユニットが現在の手番か。
func is_current_unit(u: Unit) -> bool:
	return u != null and u.team == current_team

## このターンに移動済みか。
func has_moved(unit_id: int) -> bool:
	return _moved.has(unit_id)

## このターンに攻撃済みか。
func has_attacked(unit_id: int) -> bool:
	return _attacked.has(unit_id)

## このターンの行動を使い切ったか（攻撃済み、または移動済みで攻撃対象なし）。
func is_done(unit_id: int) -> bool:
	if has_attacked(unit_id):
		return true
	if has_moved(unit_id) and attack_targets(unit_id).is_empty():
		return true
	return false

## 選択して操作できる状態か（現手番・まだ行動が残っている）。
func can_select(unit_id: int) -> bool:
	return is_current_unit(unit_by_id(unit_id)) and not is_done(unit_id)

## 手番を次の陣営へ。行動済みフラグを一掃し、0 に戻ったらターン+1。
func end_turn() -> void:
	_moved.clear()
	_attacked.clear()
	current_team = 1 - current_team
	if current_team == 0:
		turn_number += 1
