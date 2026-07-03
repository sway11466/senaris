extends RefCounted
class_name UnloadCommand
## 降車コマンド: 輸送 transport_id の搭乗リスト index の駒を to へ降ろす。
## 詳細 → doc/gdd/movement.md（輸送）

var transport_id: int
var index: int      ## passengers() のインデックス
var to: Vector2i    ## 降車先（その駒が進入できる空きhex）

func _init(p_transport_id: int, p_index: int, p_to: Vector2i) -> void:
	transport_id = p_transport_id
	index = p_index
	to = p_to
