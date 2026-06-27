extends RefCounted
class_name Combat
## 戦闘解決（純ロジック）。
## 当面は補正なしの素の威力を返すだけ。将来ここに doc/design/combat.md の
## 補正チェーン（経験→包囲→支援→地形）を決定的パイプラインとして差し込む。

static func resolve_damage(attacker: Unit, _defender: Unit) -> int:
	return maxi(attacker.power, 0)
