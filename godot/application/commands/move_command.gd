extends RefCounted
class_name MoveCommand
## 「このユニットをここへ動かせ」という操作意図。純データ。
## presentation → application への下り。妥当性判定は受け手(MatchController/BattleState)が行う。

var handle: int
var to: Vector2i

func _init(p_unit_id: int, p_to: Vector2i) -> void:
	handle = p_unit_id
	to = p_to
