extends RefCounted
class_name DeployCommand
## 「この拠点の控えユニットを、ここへ出撃させろ」という操作意図。純データ。
## presentation → application への下り。妥当性判定は受け手(MatchController/BattleState)が行う。
## 詳細 → doc/gdd/map.md（拠点・占領／出撃）

var base_hex: Vector2i   ## 出撃元の拠点
var garrison_index: int  ## 拠点の garrison 内インデックス（出す控え）
var to: Vector2i         ## 出撃先（拠点に隣接する空きhex・1歩）

func _init(p_base_hex: Vector2i, p_garrison_index: int, p_to: Vector2i) -> void:
	base_hex = p_base_hex
	garrison_index = p_garrison_index
	to = p_to
