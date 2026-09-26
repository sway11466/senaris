extends RefCounted
class_name SteamAdapter
## アダプター（steam）。Steam 製品版。所有権は Steam DLC、実績は Steamworks（体験版の実績ファイルを流し込む）、Stats は Steam。
## 部品を選んで束ねるだけで、中身の処理は持たない。仕様 → doc/tech/platform.md チャネル×機能

static func build() -> Platform:
	var achievements := SteamAchievements.new(AchievementFile.new())
	var p := Platform.new(SteamDlcOwnership.new(), achievements, SteamStats.new())
	p.set_starter(func() -> String:
		var err := SteamSession.start()
		if err.is_empty():
			achievements.import_handoff()
		return err)
	return p
