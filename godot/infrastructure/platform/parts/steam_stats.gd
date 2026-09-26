extends StatsSink
class_name SteamStats
## Stats の部品「Steam に送る」。整数の Stat に足して Steamworks へ送る。仕様 → doc/tech/platform.md アダプターと部品

func add(stat_id: String, amount: int = 1) -> void:
	var steam := SteamSession.api()
	var now := int(steam.getStatInt(stat_id))
	if not bool(steam.setStatInt(stat_id, now + amount)):
		push_error("SteamStats: 書けない（Steamworks に無い ID？）: %s" % stat_id)
		return
	steam.storeStats()
