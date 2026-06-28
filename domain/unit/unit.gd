extends RefCounted
class_name Unit
## 盤上のユニット1体（＝小隊）の状態。純データ・ノード非依存。
## 見た目は持たない（描画は presentation 側が team/pos から決める）。
## 詳細 → doc/gdd/combat.md

const MAX_LEVEL := 8   ## 経験値（＝レベル）の上限

var id: int            ## 一意なID
var team: int          ## 陣営（0=自軍, 1=敵軍 ...）
var pos: Vector2i      ## axial 座標
var move: int          ## 移動力（ヘックス数）
var troops: int        ## 兵数（1〜8）。残存兵数。0で消滅
var max_troops: int    ## 満員時の兵数
var unit_attack: int   ## ユニット攻撃力（兵1体あたり。原典 BuA 相当）
var unit_defense: int  ## ユニット防御力（兵1体あたり。原典 BuD 相当）
var level: int         ## 経験値＝レベル（1〜MAX_LEVEL）。初期Lv1＝補正なし。詳細 → combat.md

func _init(p_id: int, p_team: int, p_pos: Vector2i, p_move: int,
		p_troops: int = 8, p_unit_attack: int = 10, p_unit_defense: int = 10,
		p_level: int = 1) -> void:
	id = p_id
	team = p_team
	pos = p_pos
	move = p_move
	troops = p_troops
	max_troops = p_troops
	unit_attack = p_unit_attack
	unit_defense = p_unit_defense
	level = clampi(p_level, 1, MAX_LEVEL)

## 経験値（＝レベル）を加算。1〜MAX_LEVEL にクランプ。詳細 → combat.md
func add_experience(n: int) -> void:
	level = clampi(level + n, 1, MAX_LEVEL)
