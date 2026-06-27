extends RefCounted
class_name Unit
## 盤上のユニット1体の状態。純データ・ノード非依存。
## 見た目は持たない（描画は presentation 側が team/pos から決める）。

var id: int        ## 一意なID
var team: int      ## 陣営（0=自軍, 1=敵軍 ...）
var pos: Vector2i  ## axial 座標
var move: int      ## 移動力（ヘックス数）
var hp: int        ## 現在HP
var max_hp: int    ## 最大HP
var power: int     ## 攻撃力

func _init(p_id: int, p_team: int, p_pos: Vector2i, p_move: int, p_hp: int = 10, p_power: int = 4) -> void:
	id = p_id
	team = p_team
	pos = p_pos
	move = p_move
	hp = p_hp
	max_hp = p_hp
	power = p_power
