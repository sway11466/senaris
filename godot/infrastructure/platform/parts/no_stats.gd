extends StatsSink
class_name NoStats
## Stats の部品「何もしない」。送り先の無いチャネル（itch・booth・dev）で使う。
## 自前で集計もしない（doc/sales/monetization.md 計測）。仕様 → doc/tech/platform.md アダプターと部品

func add(_stat_id: String, _amount: int = 1) -> void:
	pass
