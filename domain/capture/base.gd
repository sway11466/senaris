extends RefCounted
class_name Base
## 拠点1つ（城・砦）。占領・出撃・所属を持つ純データ。ノード非依存。
## 地形（防御係数 fort/castle）とは別レイヤー: 地形は見た目と攻防補正、Base は占領ロジック。
## 詳細 → doc/gdd/map.md（拠点・占領）
##
## - team   … 所属（0=自軍, 1=敵, NEUTRAL=未占領/中立）。占領で current owner が変わる。
## - garrison … 中に控える「出撃待ち」ユニット（＝解放される捕虜）。占領すると所属チームが
##   隣接へ1体ずつ出撃させられる（ネクタリス方式・出撃は1歩）。出撃時に team/pos が決まる。

const NEUTRAL := -1  ## 未占領（どの陣営でもない拠点）

var hex: Vector2i           ## 拠点の位置（axial）
var team: int               ## 所属（0/1/NEUTRAL）。占領で変わる
var native_team: int        ## 本来の持ち主（ステージ初期の所属）。占領では変わらない＝本拠地判定に使う
var kind: String            ## 拠点種別（"fort"=通常 / "hq"=本拠地）。勝敗条件が参照。詳細 → doc/gdd/map.md
var garrison: Array[Unit]   ## 出撃待ちユニット（盤上には未登場。占領後に deploy で出す）
var squad_index: int = -1   ## この拠点の AI プリセット部隊（state.squads の index）。-1＝AI出撃しない。詳細 → doc/gdd/ai.md §7

func _init(p_hex: Vector2i, p_team: int = NEUTRAL, p_kind: String = "fort") -> void:
	hex = p_hex
	team = p_team
	native_team = p_team
	kind = p_kind

## 本拠地（hq）か。
func is_hq() -> bool:
	return kind == "hq"

## 中断セーブ用の直列化。位置は axial(q,r)。garrison は出撃待ちユニットの full 直列化。詳細 → doc/tech/gamesystem.md
func to_dict() -> Dictionary:
	var g: Array = []
	for u in garrison:
		g.append(u.to_full_dict())
	return {
		"q": hex.x, "r": hex.y,
		"team": team, "native": native_team, "kind": kind,
		"squad_index": squad_index, "garrison": g,
	}

## to_dict からの復元。garrison ユニットの性能は catalog（{id: UnitType}）から再構築する。
static func from_dict(data: Dictionary, catalog: Dictionary = {}) -> Base:
	var b := Base.new(Vector2i(int(data.get("q", 0)), int(data.get("r", 0))), int(data.get("team", NEUTRAL)), String(data.get("kind", "fort")))
	b.native_team = int(data.get("native", b.team))
	b.squad_index = int(data.get("squad_index", -1))
	for gd in data.get("garrison", []):
		if typeof(gd) == TYPE_DICTIONARY:
			b.garrison.append(Unit.from_full_dict(gd, catalog.get(String(gd.get("type", "")))))
	return b
