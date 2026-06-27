extends RefCounted
class_name AttackCommand
## 「このユニットでこの敵を攻撃せよ」という操作意図。純データ。
## 妥当性判定は受け手(MatchController/BattleState)が行う。

var attacker_id: int
var target_id: int

func _init(p_attacker_id: int, p_target_id: int) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id
