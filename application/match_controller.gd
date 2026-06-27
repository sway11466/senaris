extends Node
class_name MatchController
## ゲーム進行のまとめ役（Application 層）。
## Presentation からコマンドを受け、domain を呼び、結果をシグナルで上へ返す。
## 状態の真実は domain/battle_state.gd に置き、ここは進行管理のみ。

# 上り: 純データのシグナルで Presentation に通知する（例）。
# signal unit_moved(unit_id: int, from: Vector2i, to: Vector2i)
# signal combat_resolved(result: Dictionary)
