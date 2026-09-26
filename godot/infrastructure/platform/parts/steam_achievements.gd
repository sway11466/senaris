extends AchievementVault
class_name SteamAchievements
## 実績の保管庫の部品「Steamworks 実績」。読み書きとも Steamworks の API で行い、ローカルに持たない。
## 起動のたびに実績ファイル（体験版が溜めたもの）を読んで Steamworks に立てる＝読むだけで書かない。
## 仕様 → doc/tech/platform.md 体験版からの引き継ぎ

var _handoff: AchievementFile  # 体験版が溜めた実績ファイル（流し込み元）

func _init(handoff: AchievementFile) -> void:
	_handoff = handoff

## 体験版の実績を Steamworks に流し込む。Steamworks に繋がってから呼ぶ。
## 立て済みの実績を立て直しても何も起きない＝初回かどうかを判定しない。
func import_handoff() -> void:
	var ids := _handoff.unlocked_ids()
	if ids.is_empty():
		return
	var steam := SteamSession.api()
	for id in ids:
		steam.setAchievement(id)
	steam.storeStats()

func unlock(id: String) -> void:
	if is_unlocked(id):
		return
	var steam := SteamSession.api()
	if not bool(steam.setAchievement(id)):
		push_error("SteamAchievements: 立てられない（Steamworks に無い ID？）: %s" % id)
		return
	steam.storeStats()
	print("Achievement unlocked: %s" % id)

func is_unlocked(id: String) -> bool:
	var got: Dictionary = SteamSession.api().getAchievement(id)
	return bool(got.get("ret", false)) and bool(got.get("achieved", false))

func unlocked_ids() -> PackedStringArray:
	var steam := SteamSession.api()
	var out := PackedStringArray()
	for i in int(steam.getNumAchievements()):
		var id := String(steam.getAchievementName(i))
		if is_unlocked(id):
			out.append(id)
	return out
