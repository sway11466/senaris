extends RefCounted
class_name FormationCommand
## 「この陣形スキル（option）をこの着弾中心（target）で発動せよ」という操作意図。純データ。
## option＝Formation.available_for の1要素。妥当性判定は受け手(MatchController/BattleState)が行う。

var option: Dictionary
var target: Vector2i

func _init(p_option: Dictionary, p_target: Vector2i) -> void:
	option = p_option
	target = p_target
