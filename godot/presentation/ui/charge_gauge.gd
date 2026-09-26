class_name ChargeGauge
extends Control
## ユニットスキルのチャージ量のゲージ（情報パネルの能力タブ）。戦闘演出の兵量バーと同じ作り
## ＝必要量の数に刻み、溜まったぶんを陣営色で塗り、空きは暗い枠で見せる。
## 仕様 → doc/gdd/uiux.md ユニット情報パネル

const GAP := 2.0  # 刻みの間（px）

var have := 0
var need := 1
var team := 0

func setup(have_: int, need_: int, team_: int) -> void:
	have = have_
	need = maxi(need_, 1)
	team = team_
	queue_redraw()

func _draw() -> void:
	var cell := (size.x - GAP * (need - 1)) / need
	var col: Color = CombatStage.TEAM_COLOR.get(team, Color(0.5, 0.5, 0.5))
	for i in need:
		var slot := Rect2(Vector2(i * (cell + GAP), 0.0), Vector2(cell, size.y))
		draw_rect(slot, CombatStage.BAR_BG)
		if i < have:
			draw_rect(slot, col.lightened(0.15))
		draw_rect(slot, CombatStage.BAR_EDGE, false, 1.0)
