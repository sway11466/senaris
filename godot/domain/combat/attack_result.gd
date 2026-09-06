extends RefCounted
class_name AttackResult
## 1回の攻撃（往路＋反撃）の結果（純データ・Node非依存）。作るのは BattleState.attack だけ。
## 戦闘前のスナップショットと打撃ごとの内訳を持ち、損害・撃破はそこから導く＝盤の兵数の増減と
## 必ず一致する（式は Combat.hit_from_breakdowns の1か所）。
## 演出（CombatScene）と戦闘レポート（CombatReportView）はこの同じ結果を読む。
## 詳細 → doc/gdd/combat.md, doc/tech/combat_scene.md

var attacker: UnitSnapshot   ## 攻撃側（戦闘前の姿＋troops_after）
var defender: UnitSnapshot   ## 防御側（同上）
var to_defender: HitDetail   ## 往路＝攻撃側が防御側に与えた打撃
var to_attacker: HitDetail   ## 復路＝反撃。null＝反撃なし（間接・対空なし・懐の死角）
var melee: bool              ## 近接（距離1）の攻撃か

## 反撃が成立したか。
func has_counter() -> bool:
	return to_attacker != null

## 防御側が失った兵数。
func damage() -> int:
	return to_defender.loss

## 攻撃側が反撃で失った兵数（反撃なしは0）。
func retaliation() -> int:
	return to_attacker.loss if to_attacker != null else 0

## 防御側が撃破されたか。
func killed() -> bool:
	return defender.is_killed()

## 攻撃側が反撃で撃破されたか。
func attacker_killed() -> bool:
	return attacker.is_killed()
