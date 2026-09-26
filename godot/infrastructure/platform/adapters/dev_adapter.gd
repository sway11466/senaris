extends RefCounted
class_name DevAdapter
## アダプター（dev）。エディタ実行（チャネルのタグが立っていないビルドも）。実績は実績ファイル＝エディタで解除を確かめられる。
## 部品を選んで束ねるだけで、中身の処理は持たない。仕様 → doc/tech/platform.md チャネル×機能

static func build() -> Platform:
	return Platform.new(AlwaysOwned.new(), AchievementFile.new(), NoStats.new())
