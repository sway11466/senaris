extends RefCounted
class_name AiBrain
## 敵思考の基底。ステージごとに差し替え可能な戦略インターフェース。
## 純ロジック: BattleState を読んで「次の1手」を返すだけで、状態は変えない。
##
## 1手ずつ返す設計: 呼び出し側が「next_action → 実行 → また next_action」を
## null が返るまで繰り返す。これにより移動→攻撃の段階実行ができ、
## 将来の高度AI（マップ全体を見てユニットごとに動かし方を変える）も
## 同じ next_action 内で全盤面を評価すればよい。

## team の手番で行う次の行動を1つ返す。もう行動が無ければ null。
func next_action(_state: BattleState, _team: int) -> AiAction:
	return null

## unit の検知半径（索敵範囲の可視化用）。「まだ寝ていて sight で起きる待機ユニット」なら索敵半径、
## それ以外（起動済み・sight トリガー無し・AI対象外）は 0（＝検知域を描かない）。既定は 0。
func detection_radius(_state: BattleState, _unit: Unit) -> int:
	return 0
