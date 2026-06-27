extends RefCounted
class_name BattleState
## 戦闘全体の状態 ＝ 中断セーブの本体（唯一の真実）。
## Godot ノード非依存（extends RefCounted）。見た目の状態はここに含めない。
## 詳細 → doc/design/architecture.md, doc/gamesystem/save.md

var cols: int  ## 矩形フィールドの幅（offset col 数）
var rows: int  ## 矩形フィールドの高さ（offset row 数）

var current_team: int = 0  ## 現在の手番の陣営
var turn_number: int = 1   ## ターン番号（両陣営が1巡で+1）

var _units: Array[Unit] = []
var _moved := {}     # unit_id -> true（このターンに移動済み）
var _attacked := {}  # unit_id -> true（このターンに攻撃済み）

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

## hex が矩形フィールド内か。
func in_field(hex: Vector2i) -> bool:
	var off := Hex.axial_to_offset(hex)
	return off.x >= 0 and off.x < cols and off.y >= 0 and off.y < rows

## unit_id が移動できるヘックス（起点を含む）。フィールド外と他ユニットは通行不可。
func reachable(unit_id: int) -> Array[Vector2i]:
	var u := unit_by_id(unit_id)
	if u == null:
		return []
	var passable := func(h: Vector2i) -> bool:
		return in_field(h) and unit_at(h) == null
	return Hex.flood_reach(u.pos, u.move, passable)

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

## 攻撃を解決。成功なら {damage, killed, target_hp}、不正なら空 Dictionary。
func attack(attacker_id: int, target_id: int) -> Dictionary:
	if not can_attack(attacker_id, target_id):
		return {}
	var a := unit_by_id(attacker_id)
	var t := unit_by_id(target_id)
	var dmg := Combat.resolve_damage(a, t)
	t.hp -= dmg
	var killed := t.hp <= 0
	if killed:
		_remove_unit(target_id)
	_moved[attacker_id] = true
	_attacked[attacker_id] = true
	return {"damage": dmg, "killed": killed, "target_hp": maxi(t.hp, 0)}

func _remove_unit(unit_id: int) -> void:
	for i in _units.size():
		if _units[i].id == unit_id:
			_units.remove_at(i)
			return

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
