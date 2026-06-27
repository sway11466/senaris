extends RefCounted
class_name BattleState
## 戦闘全体の状態 ＝ 中断セーブの本体（唯一の真実）。
## Godot ノード非依存（extends RefCounted）。見た目の状態はここに含めない。
## 詳細 → doc/design/architecture.md, doc/gamesystem/save.md

var cols: int  ## 矩形フィールドの幅（offset col 数）
var rows: int  ## 矩形フィールドの高さ（offset row 数）

var _units: Array[Unit] = []

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

## unit_id を to へ動かせるか（空きマスかつ移動範囲内）。
func can_move(unit_id: int, to: Vector2i) -> bool:
	if unit_at(to) != null:
		return false
	return reachable(unit_id).has(to)

## 妥当なら移動を適用して true。不正なら何もせず false。
func move_unit(unit_id: int, to: Vector2i) -> bool:
	if not can_move(unit_id, to):
		return false
	unit_by_id(unit_id).pos = to
	return true
