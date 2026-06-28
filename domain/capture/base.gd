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
var team: int               ## 所属（0/1/NEUTRAL）
var garrison: Array[Unit]   ## 出撃待ちユニット（盤上には未登場。占領後に deploy で出す）

func _init(p_hex: Vector2i, p_team: int = NEUTRAL) -> void:
	hex = p_hex
	team = p_team
