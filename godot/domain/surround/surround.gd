extends RefCounted
class_name Surround
## 包囲判定（純ロジック・段階式）。詳細 → doc/gdd/combat.md
##
## 隣接する敵ユニットが2体以上で初めて包囲が成立する。成立時、対象の攻撃力・防御力に
## 係数を乗じる（係数<1.0）。占有（敵が隣接マスにいる）は ZOC（空きマスが敵に隣接）より重い。
##
##   隣接敵 < 2          → 係数 1.0（包囲不成立）
##   隣接敵 ≧ 2          → 係数 ＝ clamp(1 − (P_OCC×占有数 + P_ZOC×ZOC数), FLOOR, 1.0)
##
## 盤外マスは覆いに数えない（盤端・隅は包囲されにくい＝防御的退避）。

const GATE := 2      ## 包囲成立に必要な隣接敵ユニット数
const P_OCC := 0.08  ## 占有1マスあたりのペナルティ
const P_ZOC := 0.04  ## ZOC1マスあたりのペナルティ
const FLOOR := 0.10  ## 係数の下限

## unit の包囲係数（攻撃力・防御力に乗る）。1.0 ＝ 影響なし。
static func factor(state: BattleState, unit: Unit) -> float:
	var n_occ := 0
	var n_zoc := 0
	for h in Hex.neighbors(unit.pos):
		if not state.in_field(h):
			continue  # 盤外は数えない
		match _coverage(state, h, unit.team):
			2:
				n_occ += 1
			1:
				n_zoc += 1
	return factor_from_counts(n_occ, n_zoc)

## 占有数・ZOC数から包囲係数を出す（段階式の本体）。盤ベースの factor() も
## 開発ツール（tools/combat_sim）も、係数計算はここに集約する＝式を二重に持たない。
static func factor_from_counts(n_occ: int, n_zoc: int) -> float:
	if n_occ < GATE:
		return 1.0  # 包囲不成立
	return clampf(1.0 - (P_OCC * n_occ + P_ZOC * n_zoc), FLOOR, 1.0)

## hex の覆い種別: 2=敵が占有, 1=敵ZOC下（空きマスが敵に隣接）, 0=なし。
static func _coverage(state: BattleState, hex: Vector2i, ally_team: int) -> int:
	var occupied := false
	var in_zoc := false
	for u in state.units():
		if u.team == ally_team:
			continue
		var dist := Hex.distance(u.pos, hex)
		if dist == 0:
			occupied = true
		elif dist == 1:
			in_zoc = true
	if occupied:
		return 2
	if in_zoc:
		return 1
	return 0
