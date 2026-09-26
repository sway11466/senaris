extends RefCounted
class_name ItchAdapter
## アダプター（itch）。itch。体験版も製品版も同じ。
## 部品を選んで束ねるだけで、中身の処理は持たない。仕様 → doc/tech/platform.md チャネル×機能

static func build() -> Platform:
	return Platform.new(AlwaysOwned.new(), AchievementFile.new(), NoStats.new())
