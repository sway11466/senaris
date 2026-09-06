extends RefCounted
class_name AiTrait
## 特性1つぶんの行動ルール（純ロジック・Node非依存）。TraitBrain が特性idで引き、駒の1手と
## 行動開始条件を任せる。行の部品は AiRows、標的の物差しは AiPick、パラメーターは AiParams
## ＝brain が組み立てて bind で渡す。盤は書き換えない。
## 仕様の正本は doc/gdd/ai.md（特性詳細）＝サブクラスは表を写して実行するだけ。
##
## 1行＝行動条件と行動内容の組で、行動内容には対象の選び方まで含む。条件と対象選びを別の軸に
## 分けない＝「放つかどうか」と「誰に放つか」は同じ候補集合を絞る操作なので1箇所に書く。
## 1手ずつ返す（AiBrain の約束）。どの行も成立しなければ null＝待機で、その駒はその場に留まる。
## 移動を使い切った駒は、移動を伴う行（占領・前進）を飛ばして次の行を見る。

var params: AiParams
var pick: AiPick
var rows: AiRows

func bind(p_params: AiParams, p_pick: AiPick, p_rows: AiRows) -> void:
	params = p_params
	pick = p_pick
	rows = p_rows

## 特性id（部隊の ai に書く値）。
func id() -> String:
	return ""

## 行動開始条件が視線距離で決まるか＝盤に検知域を描く対象（doc/gdd/ai.md 特性詳細）。
func engages_by_sight() -> bool:
	return false

## u がいま行動開始条件を満たすか。一斉警戒（部隊の誰かが起きていれば起きる）は brain が別に見る。
## 既定は常時＝true。
func starts_engaged(_state: BattleState, _u: Unit) -> bool:
	return true

## 拠点 b がいま行動開始条件を満たすか（拠点hex基準。budget＝拠点の sight）。既定は常時＝true。
func base_starts_engaged(_state: BattleState, _b: Base, _budget: int) -> bool:
	return true

## u が今できる1手（無ければ null＝待機）。特性の行を上から当てる。
func action(_state: BattleState, _u: Unit) -> AiAction:
	return null

## 行動を終えた駒（is_done）にも残る手を持つか。輸送の降車だけがこれに当たる（乗員の手番で降ろす）。
## 既定は持たない。
func acts_when_done(_u: Unit) -> bool:
	return false

## 行動を終えた駒に残る手（acts_when_done が true のときだけ呼ばれる）。既定は無し。
func done_action(_state: BattleState, _u: Unit) -> AiAction:
	return null
