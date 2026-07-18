extends RefCounted
class_name Unit
## 盤上のユニット1体（＝小隊）の状態。純データ・ノード非依存。
## skin_id だけは presentation 専用の同乗データ（純ロジック＝combat/surround/movement/AI は読まない）。
## 詳細 → doc/gdd/combat.md

const MAX_LEVEL := 8   ## 経験値（＝レベル）の上限

var id: int            ## 一意なID
var team: int          ## 陣営（0=自軍, 1=敵軍 ...）。中立garrisonの寝返り等で変わりうる
var native_team: int   ## 生来の陣営（不変）。-1(Base.NEUTRAL)=中立＝占領した側に寝返る。
                       ## 味方/敵 native の駒は寝返らない＝拠点を奪われると閉じ込め。詳細 → doc/gdd/map.md
var pos: Vector2i      ## axial 座標
var move: int          ## 移動力（ヘックス数）
var troops: int        ## 兵数（1〜8）。残存兵数。0で消滅
var max_troops: int    ## 満員時の兵数
var unit_attack: int   ## ユニット攻撃力＝対地（兵1体あたり。原典 BuA 相当）
var atk_air: int = 0   ## 対空攻撃力（0＝対空不可＝飛行ユニットを攻撃・反撃できない）。UnitType から設定
var unit_defense: int  ## ユニット防御力（兵1体あたり。原典 BuD 相当。対地/対空で分けない単一値）
var pierce: float = 0.0  ## 防御貫通率（攻撃時に相手の実効防御を pierce ぶん減らす。0=なし・0.5=半減）。UnitType から設定
var level: int         ## 経験値＝レベル（1〜MAX_LEVEL）。初期Lv1＝補正なし。詳細 → combat.md
var type_id: String    ## 種別ID（UnitType/スキンの参照キー。空＝未指定）。描画・占領で使う
var skin_id: String = ""  ## スキンID（見た目の指定。空＝type_id+team の既定スキンで描画）。StageLoader が設定
var move_type: String  ## 移動タイプ（movement表のキー。空＝未指定→全地形コスト1の従来挙動）
var min_range: int = 1  ## 最短射程（下限）。≥2＝懐に死角（砲兵など近接不可）。UnitType から設定
var attack_range: int = 1  ## 最大射程（上限）。1=近接、≥2=遠隔可。距離1の攻撃は近接扱い（反撃あり）。UnitType から設定
var move_after_attack: bool = false  ## 攻撃後に残り移動力で再移動できるか（ヒット&アウェイ）。UnitType から設定
var can_capture: bool = false  ## 拠点を占領できるか（cleric/bishop/paladin等）。UnitType から設定。詳細 → doc/gdd/map.md
var capacity: int = 0  ## 輸送の搭載数（0=輸送不可。馬車4・飛空艇6）。UnitType から設定。詳細 → doc/gdd/movement.md

## 輸送ユニットか（駒を載せて運べるか）。
func is_transport() -> bool:
	return capacity > 0

## 飛行ユニットか。判定は移動タイプ（flight）で行う＝飛べる＝飛行、と一元化する。
func is_aerial() -> bool:
	return move_type == "flight"

## target を攻撃するときに使うユニット攻撃力。相手が飛行なら対空、地上なら対地。
## 0 なら「その相手を攻撃できない」（対空0＝飛行を狙えない）。詳細 → doc/gdd/combat.md
func attack_against(target: Unit) -> int:
	return atk_air if target.is_aerial() else unit_attack

## 距離 d を射程で狙えるか（下限 min_range 〜 上限 attack_range）。
## 反撃も同じ判定を使う（距離1でも min_range≥2 の砲兵は反撃できない）。詳細 → doc/gdd/combat.md
func can_reach(d: int) -> bool:
	return d >= min_range and d <= attack_range

func _init(p_id: int, p_team: int, p_pos: Vector2i, p_move: int,
		p_troops: int = 8, p_unit_attack: int = 10, p_unit_defense: int = 10,
		p_level: int = 1, p_type_id: String = "") -> void:
	id = p_id
	team = p_team
	native_team = p_team  # 既定は初期陣営（中立garrison等は生成側が上書き）
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

## 種別(UnitType)の性能をこの駒に写す（type が唯一の出どころ＝数値を焼かない）。
## 成長・損耗（level/troops）と盤依存の状態（id/team/pos）は触らない＝呼び出し側の管轄。
## max_troops は type の満員値にするので、損耗を保つ用途では呼び出し後に上書きする。
## 注: StageLoader._make_unit は個別キー上書きを挟む別経路で、将来この写しへ寄せられる（refactoring-1）。
func apply_type(t: UnitType) -> void:
	move = t.move
	move_type = t.move_type
	unit_attack = t.atk_ground
	atk_air = t.atk_air
	unit_defense = t.defense
	pierce = t.pierce
	min_range = t.min_range
	attack_range = t.attack_range
	move_after_attack = t.move_after_attack
	can_capture = t.can_capture
	capacity = t.capacity
	max_troops = t.max_troops

## 直列化（セーブの土台）。素性・成長・損耗だけを出す＝type/skin/level/troops/max_troops。
## 性能値（攻防・射程…）は type から再構築するので焼かない。盤依存の状態（id/team/pos/行動済み）も持たない
## ＝戦力スナップショット（継承）はこれそのもの、中断セーブはこれに盤情報を足す。詳細 → doc/tech/gamesystem.md
func to_dict() -> Dictionary:
	return {
		"type": type_id,
		"skin": skin_id,
		"level": level,
		"troops": troops,
		"max_troops": max_troops,
	}

## 直列化から駒を復元。性能は t（type_id で解決した UnitType）から再構築する。
## t 省略/未解決なら既定性能（move3/atk10/def10）で復元＝データ欠損に耐える（catalog 解決は呼び出し側）。
## id/team/pos は placeholder（0/0/ZERO）＝配置する側（次ステージ or 中断復元）が決める。
static func from_dict(data: Dictionary, t: UnitType = null) -> Unit:
	var type_id := String(data.get("type", ""))
	var level := int(data.get("level", 1))
	var max_troops := int(data.get("max_troops", 8))
	var troops := int(data.get("troops", max_troops))
	var unit := Unit.new(0, 0, Vector2i.ZERO, 3, troops, 10, 10, level, type_id)
	if t != null:
		unit.apply_type(t)
	else:
		push_warning("Unit.from_dict: type '%s' 未解決＝既定性能で復元" % type_id)
	unit.troops = troops        # apply_type が max_troops を type 既定に戻すので損耗を再適用
	unit.max_troops = max_troops
	unit.skin_id = String(data.get("skin", type_id))
	return unit
