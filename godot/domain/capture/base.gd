extends RefCounted
class_name Base
## 拠点1つ（城・砦）。占領・出撃・所属を持つ純データ。ノード非依存。
## 地形（防御係数 fort/castle）とは別レイヤー: 地形は見た目と攻防補正、Base は占領ロジック。
## 詳細 → doc/gdd/map.md（拠点・占領）
##
## - team   … 所属（0=自軍, 1=敵, NEUTRAL=未占領/中立）。占領で current owner が変わる。
## - rest   … 誰が中に入って回復できるか（REST_PLAYER / REST_ENEMY / REST_BOTH）。占領では変わらない。
## - hq     … 本拠地の印と、その陣営（0=自軍の本拠地 / 1=敵の本拠地 / NO_HQ=普通の砦）。勝敗条件だけが見る。
##   所有者（team）とは独立＝開始時に敵へ奪われている味方の本拠地（hq=0, team=1）も表せる。
## - garrison … 中に控える「出撃待ち」ユニット（＝解放される捕虜）。占領すると所属チームが
##   隣接へ1体ずつ出撃させられる（ネクタリス方式・出撃は1歩）。出撃時に team/pos が決まる。
##   どちらの戦力になるか（寝返り／閉じ込め）は駒側の native で決まる＝拠点は「生来の持ち主」を持たない。

const NEUTRAL := -1  ## 未占領（どの陣営でもない拠点）
const NO_HQ := -1    ## 本拠地ではない（hq の値）

const REST_PLAYER := "player"  ## 味方だけ休める
const REST_ENEMY := "enemy"    ## 敵だけ休める（奪っても味方は休めない＝納骨堂など）
const REST_BOTH := "both"      ## 所有者なら誰でも休める
const REST_VALUES := [REST_PLAYER, REST_ENEMY, REST_BOTH]

var hex: Vector2i           ## 拠点の位置（axial）
var team: int               ## 所属（0/1/NEUTRAL）。占領で変わる
var hq: int                 ## 本拠地の陣営（0/1）。NO_HQ＝普通の砦
var rest: String            ## 誰が中に入って回復できるか（REST_*）
var garrison: Array[Unit]   ## 出撃待ちユニット（盤上には未登場。占領後に deploy で出す）
var squad_index: int = -1   ## この拠点＝1部隊（state.squads の index）。-1＝AI出撃しない。詳細 → doc/gdd/ai.md（拠点出撃）

func _init(p_hex: Vector2i, p_team: int = NEUTRAL, p_hq: int = NO_HQ, p_rest: String = REST_BOTH) -> void:
	hex = p_hex
	team = p_team
	hq = p_hq
	rest = p_rest if REST_VALUES.has(p_rest) else REST_BOTH

## 本拠地（どちらかの陣営の hq）か。
func is_hq() -> bool:
	return hq != NO_HQ

## p_team の本拠地か。
func is_hq_of(p_team: int) -> bool:
	return hq == p_team

## p_team の駒が中に入って休める（回復できる）拠点か。所有しているかは見ない（呼び出し側が team を見る）。
func can_rest(p_team: int) -> bool:
	match rest:
		REST_PLAYER:
			return p_team == 0
		REST_ENEMY:
			return p_team == 1
		_:
			return true

## 控え u を所有者が出撃させられるか＝帰属が未確定（中立）か、所有者と同じ。閉じ込め（捕虜）は false。
## 行動済みかは見ない（それは BattleState.can_deploy_garrison）。出撃メニューはこれで出す項目を絞る。
func deployable_by_owner(u: Unit) -> bool:
	return u.is_unclaimed() or u.recruited_team == team

## 所有者が出せる控えが1体でもいるか（閉じ込めだけの拠点は false＝出撃メニューを開かない）。
func has_deployable_garrison() -> bool:
	for u in garrison:
		if deployable_by_owner(u):
			return true
	return false

## 控えの内訳＝帰属先ごとの人数 { 0: 自軍, 1: 敵, NEUTRAL: 未確定 }。0体の陣営はキーを持たない。
## 盤上の「+N」表示が帰属ごとに色分けするために使う（doc/gdd/uiux.md 盤上の印）。
func garrison_counts() -> Dictionary:
	var out := {}
	for u in garrison:
		var key := NEUTRAL if u.is_unclaimed() else u.recruited_team
		out[key] = int(out.get(key, 0)) + 1
	return out

## 中断セーブ用の直列化（動的差分）。位置 axial(q,r) は復元時の突き合わせの鍵。持つのは戦闘中に
## 動くもの＝現在の帰属と駐留兵（full 直列化）だけで、hq/rest/squad_index はステージJSONから
## 引き直す。復元は BattleState.apply_save_diff。詳細 → doc/tech/gamesystem.md
func to_save_diff() -> Dictionary:
	var g: Array = []
	for u in garrison:
		g.append(u.to_full_dict())
	return { "q": hex.x, "r": hex.y, "team": team, "garrison": g }
