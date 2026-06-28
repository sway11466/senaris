extends RefCounted
class_name UnitType
## ユニット種別＝性能（ステータス）だけ。純データ・ノード非依存。
## 詳細 → doc/gdd/units.md
##
## 名前・説明・画像は持たない（それらは UnitSkin に分離）。性能は1原型に1セットだけ持ち、
## 名前/スプライトはスキンという上書きレイヤーで足す（テーマ差し替えで原型を複製しない）。
##
## move_type・atk_air・attack_range(>1=間接) は「箱」を先に用意（実装は将来）。
## 現状の戦闘は対地(atk_ground)＝攻撃、defense＝防御のみ使う。

var id: String           ## 種別ID（ステージ/カタログ/スキンの参照キー）
var role: String         ## 種類（歩兵/戦車/航空…）
var atk_ground: int      ## 対地攻撃（— は 0）
var atk_air: int         ## 対空攻撃（— は 0）。※将来
var defense: int         ## 防御
var move: int            ## 移動力
var move_type: String    ## 移動タイプ（"ground"/"air"…）。※実装は将来
var attack_range: int    ## 射程。1=近接、>1=間接。※間接は将来
var can_capture: bool    ## 占領可否
var max_troops: int      ## 満員兵数

## 辞書（JSONの1要素）から UnitType を作る。欠けたキーは無難な既定値。
static func from_dict(d: Dictionary) -> UnitType:
	var t := UnitType.new()
	t.id = String(d.get("id", ""))
	t.role = String(d.get("role", ""))
	t.atk_ground = int(d.get("atk_ground", 0))
	t.atk_air = int(d.get("atk_air", 0))
	t.defense = int(d.get("defense", 0))
	t.move = int(d.get("move", 0))
	t.move_type = String(d.get("move_type", "ground"))
	t.attack_range = int(d.get("range", 1))
	t.can_capture = bool(d.get("can_capture", false))
	t.max_troops = int(d.get("max_troops", 8))
	return t
