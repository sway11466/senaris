extends RefCounted
class_name UnitType
## ユニット種別＝性能（ステータス）だけ。純データ・ノード非依存。
## 詳細 → doc/gdd/units.md
##
## 名前・説明・画像は持たない（それらは UnitSkin に分離）。性能は1原型に1セットだけ持ち、
## 名前/スプライトはスキンという上書きレイヤーで足す（テーマ差し替えで原型を複製しない）。
##
## move_type（移動）・atk_air（対空）・attack_range（>1=間接）・pierce（防御貫通）は
## いずれも戦闘/移動に配線済み。

var id: String           ## 種別ID（ステージ/カタログ/スキンの参照キー）
var atk_ground: int      ## 対地攻撃（— は 0）
var atk_air: int         ## 対空攻撃（0＝対空不可＝飛行を攻撃・反撃できない）
var pierce: float        ## 防御貫通率（攻撃時に相手の実効防御を pierce ぶん減らす。0=なし・0.5=半減）
var defense: int         ## 防御
var move: int            ## 移動力
var move_type: String    ## 移動タイプ（movement表のキー。"ground"/"flight"…）
var attack_range: int    ## 射程。1=近接、>1=間接
var move_after_attack: bool  ## 攻撃後に再移動できるか（ヒット&アウェイ）
var can_capture: bool    ## 占領可否
var max_troops: int      ## 満員兵数
var capacity: int        ## 輸送の搭載数（0=輸送不可。馬車4・飛空艇6）

## 辞書（JSONの1要素）から UnitType を作る。欠けたキーは無難な既定値。
static func from_dict(d: Dictionary) -> UnitType:
	var t := UnitType.new()
	t.id = String(d.get("id", ""))
	t.atk_ground = int(d.get("atk_ground", 0))
	t.atk_air = int(d.get("atk_air", 0))
	t.pierce = float(d.get("pierce", 0.0))
	t.defense = int(d.get("defense", 0))
	t.move = int(d.get("move", 0))
	t.move_type = String(d.get("move_type", "ground"))
	t.attack_range = int(d.get("range", 1))
	t.move_after_attack = bool(d.get("move_after_attack", false))
	t.can_capture = bool(d.get("can_capture", false))
	t.max_troops = int(d.get("max_troops", 8))
	t.capacity = int(d.get("capacity", 0))
	return t
