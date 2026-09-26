extends AchievementVault
class_name SteamAchievements
## 実績の保管庫の部品「Steamworks 実績」。読み書きとも Steamworks の API で行い、ローカルに持たない。
## 起動のたびに実績ファイル（体験版が溜めたもの）を読んで Steamworks に立てる＝読むだけで書かない。
## 仕様 → doc/tech/platform.md 体験版からの引き継ぎ
## 中身は GodotSteam の導入（doc/backlog.md feature-40）で書く。それまでは呼ばれたら声を出す。

var _handoff: AchievementFile  # 体験版が溜めた実績ファイル（流し込み元）

func _init(handoff: AchievementFile) -> void:
	_handoff = handoff

func unlock(id: String) -> void:
	push_error("SteamAchievements: 未実装（feature-40）: %s" % id)

func is_unlocked(id: String) -> bool:
	push_error("SteamAchievements: 未実装（feature-40）: %s" % id)
	return false

func unlocked_ids() -> PackedStringArray:
	push_error("SteamAchievements: 未実装（feature-40）")
	return PackedStringArray()
