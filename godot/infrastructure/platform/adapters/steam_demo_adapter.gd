extends RefCounted
class_name SteamDemoAdapter
## アダプター（steam-demo）。Steam 体験版。実績は Steam に立てず実績ファイルに溜める（製品版が流し込む）。Stats は Steam。
## 部品を選んで束ねるだけで、中身の処理は持たない。仕様 → doc/tech/platform.md チャネル×機能

static func build() -> Platform:
	return Platform.new(AlwaysOwned.new(), AchievementFile.new(), SteamStats.new())
