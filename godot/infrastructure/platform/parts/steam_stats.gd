extends StatsSink
class_name SteamStats
## Stats の部品「Steam に送る」。仕様 → doc/tech/platform.md アダプターと部品
## 中身は GodotSteam の導入（doc/backlog.md feature-40）で書く。それまでは呼ばれたら声を出す。

func add(stat_id: String, _amount: int = 1) -> void:
	push_error("SteamStats: 未実装（feature-40）: %s" % stat_id)
