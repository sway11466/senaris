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
var unit_attack: int   ## ユニット攻撃力＝対地（兵1体あたり。原典 BuA 相当）
var atk_air: int = 0   ## 対空攻撃力（0＝対空不可＝飛行ユニットを攻撃・反撃できない）。UnitType から設定
var unit_defense: int  ## ユニット防御力（兵1体あたり。原典 BuD 相当。対地/対空で分けない単一値）
var level: int         ## 経験値＝レベル（1〜MAX_LEVEL）。初期Lv1＝補正なし。詳細 → combat.md
var type_id: String    ## 種別ID（UnitType/スキンの参照キー。空＝未指定）。描画・占領で使う
var move_type: String  ## 移動タイプ（movement表のキー。空＝未指定→全地形コスト1の従来挙動）
var attack_range: int = 1  ## 射程（1=近接・反撃あり／≥2=間接・反撃なし）。UnitType から設定
var move_after_attack: bool = false  ## 攻撃後に残り移動力で再移動できるか（ヒット&アウェイ）。UnitType から設定
var can_capture: bool = false  ## 拠点を占領できるか（cleric/bishop/paladin等）。UnitType から設定。詳細 → doc/gdd/map.md

## 飛行ユニットか。判定は移動タイプ（flight）で行う＝飛べる＝飛行、と一元化する。
func is_aerial() -> bool:
	return move_type == "flight"

## target を攻撃するときに使うユニット攻撃力。相手が飛行なら対空、地上なら対地。
## 0 なら「その相手を攻撃できない」（対空0＝飛行を狙えない）。詳細 → doc/gdd/combat.md
func attack_against(target: Unit) -> int:
	return atk_air if target.is_aerial() else unit_attack

func _init(p_id: int, p_team: int, p_pos: Vector2i, p_move: int,
		p_troops: int = 8, p_unit_attack: int = 10, p_unit_defense: int = 10,
		p_level: int = 1, p_type_id: String = "") -> void:
	id = p_id
	team = p_team
	pos = p_pos
	move = p_move
	troops = p_troops
	max_troops = p_troops
	unit_attack = p_unit_attack
	unit_defense = p_unit_defense
	level = clampi(p_level, 1, MAX_LEVEL)
	type_id = p_type_id

## 経験値（＝レベル）を加算。1〜MAX_LEVEL にクランプ。詳細 → combat.md
func add_experience(n: int) -> void:
	level = clampi(level + n, 1, MAX_LEVEL)
