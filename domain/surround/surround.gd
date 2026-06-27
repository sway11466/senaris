extends RefCounted
class_name Surround
## 包囲判定（純ロジック）。詳細 → doc/design/combat.md
##
## ユニットの周囲6ヘックスがすべて「敵に占有 ＋ または敵のZOC下（敵に隣接）」なら包囲。
## 包囲された側は攻撃力・防御力がともに ×0.5（combat.gd で適用）。
## 盤外ヘックスは覆いに数えない（盤端・隅は包囲されにくい＝防御的退避になる）。

## unit が包囲されているか。
static func is_surrounded(state: BattleState, unit: Unit) -> bool:
	for h in Hex.neighbors(unit.pos):
		if not state.in_field(h):
			return false  # 盤外があるなら包囲不成立
		if not _covered_by_enemy(state, h, unit.team):
			return false
	return true

## hex が ally_team から見た敵に占有、または敵のZOC下（敵に隣接）か。
static func _covered_by_enemy(state: BattleState, hex: Vector2i, ally_team: int) -> bool:
	for u in state.units():
		if u.team == ally_team:
			continue
		if Hex.distance(u.pos, hex) <= 1:  # 占有(=0) または ZOC(=1)
			return true
	return false
