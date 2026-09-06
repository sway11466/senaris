extends TraitCharge
class_name TraitAmbush
## ambush（待ち伏せ）。視線距離が sight 以内に敵が入るまで動かず、動き出したあとの行は突撃と同じ。
## 攻撃を受けた駒はその時点で起動する（BattleState.attack が mark_engaged を呼ぶ）。
## 詳細 → doc/gdd/ai.md ambush

func id() -> String:
	return "ambush"

func engages_by_sight() -> bool:
	return true

## 視線距離が sight 以内に敵。
func starts_engaged(state: BattleState, u: Unit) -> bool:
	return pick.enemy_in_sight(state, u.pos, u.team, params.sight_of(state, u))

## 拠点hexから sight 内に敵。
func base_starts_engaged(state: BattleState, b: Base, budget: int) -> bool:
	return pick.enemy_in_sight(state, b.hex, b.team, budget)
