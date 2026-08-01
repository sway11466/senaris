extends RefCounted
class_name Unit
## 盤上のユニット1体（＝小隊）の状態。純データ・ノード非依存。
## skin_id は主に描画のための同乗データ（combat/surround/movement/AI は読まない）。
## 例外は Formation＝陣形／エンチャントの成立条件だけは「見た目が同じか」で決めるため skin_id を見る。
## 詳細 → doc/gdd/combat.md

const MAX_LEVEL := 99  ## 経験値（＝レベル）の上限
const NEUTRAL_TEAM := -1  ## 中立（＝帰属未確定）。Base.NEUTRAL と同値（Base を参照すると循環するため別に置く）

var id: int            ## 一意なID
var team: int          ## 陣営（0=自軍, 1=敵軍 ...）。中立garrisonの寝返り等で変わりうる
var native_team: int   ## 生来の陣営（不変）。-1(Base.NEUTRAL)=中立＝まだ帰属が決まっていない。
                       ## 本拠地判定にも使う値なので、解放や占領では動かさない。詳細 → doc/gdd/map.md
var recruited_team: int  ## 帰属先＝どちらの戦力として世に出たか。既定は native_team と同じ。
                       ## 中立 native の駒が解放（出撃）された瞬間に出した側で確定し、以後は不変
                       ## ＝拠点ごと奪われても寝返らず捕虜になる。出撃・回復の可否はこの値で見る。
var actor: String = ""   ## 永続キャラ識別子（冒険譚をまたいで一意。例 "t3.elf"）。空＝名前のない雑兵。
                       ## 名簿の同一性・carryover_slots の名指し配置・会話の分岐がこの値を見る
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
var skin_id: String = ""  ## スキンID（見た目の指定。空＝type_id+team の既定スキンで描画）。StageLoader が設定。
                       ## 陣形／エンチャントの成立条件もこの値で照合する（空なら type_id）。詳細 → doc/gdd/formations.md
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
	recruited_team = p_team  # 帰属先は native に追従（native を変えたら set_native_team で揃える）
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

## 生来の陣営を設定する。帰属先も同じ値に揃える（生成時＝まだ解放されていない状態のため）。
## 解放後の帰属確定は BattleState.deploy が行う（そちらは native を触らない）。
func set_native_team(t: int) -> void:
	native_team = t
	recruited_team = t

## 帰属が未確定か（中立のまま、まだどちらにも解放されていない）。
func is_unclaimed() -> bool:
	return recruited_team == NEUTRAL_TEAM

## 種別(UnitType)の性能をこの駒に写す（type が唯一の出どころ＝数値を焼かない）。
## 成長・損耗（level/troops）と盤依存の状態（id/team/pos）は触らない＝呼び出し側の管轄。
## max_troops は type の満員値にするので、損耗を保つ用途では呼び出し後に上書きする。
## ステージ読み込み（StageLoader._make_unit）・セーブ復元（from_dict）とも、性能はこの写しだけで決まる。
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
	var d := {
		"type": type_id,
		"skin": skin_id,
		"level": level,
		"troops": troops,
		"max_troops": max_troops,
	}
	if actor != "":
		d["actor"] = actor  # 名前のない駒では出さない（名簿の対象外＝キーを増やさない）
	return d

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
	unit.actor = String(data.get("actor", ""))
	return unit

## 中断セーブ用の直列化＝スナップショット(to_dict)に盤情報（id/team/native/位置）を足したもの。
## 位置は axial 座標を q/r として直に持つ。詳細 → doc/tech/gamesystem.md
func to_full_dict() -> Dictionary:
	var d := to_dict()
	d["id"] = id
	d["team"] = team
	d["native"] = native_team
	d["recruited"] = recruited_team
	d["q"] = pos.x
	d["r"] = pos.y
	return d

## to_full_dict からの復元。性能は t（UnitType）から再構築し、盤情報を戻す。
static func from_full_dict(data: Dictionary, t: UnitType = null) -> Unit:
	var unit := from_dict(data, t)
	unit.id = int(data.get("id", 0))
	unit.team = int(data.get("team", 0))
	unit.set_native_team(int(data.get("native", unit.team)))
	unit.recruited_team = int(data.get("recruited", unit.native_team))  # 旧セーブは native と同値で復元
	unit.pos = Vector2i(int(data.get("q", 0)), int(data.get("r", 0)))
	return unit
