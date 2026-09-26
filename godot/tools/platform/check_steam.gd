extends SceneTree
## Steam の部品を、テスト用 AppID 480（Valve が公開している Spacewar）に繋いで確かめる。
## 仕様 → doc/tech/platform.md ／ 進め方 → doc/backlog.md feature-40
## 前提: Steam クライアントが起動しログイン済み。godot/steam_appid.txt に「480」の1行（git には載らない）。
## 起動: godot --headless --path godot -s res://tools/platform/check_steam.gd
##
## 実績名・Stat 名は Spacewar に定義済みのものを仮に使う。立てた実績は最後に戻す
## ＝手元の Steam アカウントの Spacewar に跡を残さない。

const ACHIEVEMENT := "ACH_WIN_ONE_GAME"
const STAT := "NumGames"

var _failures := 0

func _initialize() -> void:
	var steam := SteamSession.api()
	_check(steam != null, "GodotSteam が読み込まれている")
	if steam == null:
		quit(1)
		return
	var err := SteamSession.start()
	_check(err.is_empty(), "Steamworks に繋がる（%s）" % err)
	if not err.is_empty():
		quit(1)
		return
	print("AppID=%d user=%s" % [int(steam.getAppID()), String(steam.getPersonaName())])

	var vault := SteamAchievements.new(AchievementFile.new("user://check_steam_handoff.json"))
	steam.clearAchievement(ACHIEVEMENT)
	_check(not vault.is_unlocked(ACHIEVEMENT), "戻した実績は未解除に見える")
	vault.unlock(ACHIEVEMENT)
	_check(vault.is_unlocked(ACHIEVEMENT), "unlock した実績が解除済みに見える")
	_check(vault.unlocked_ids().has(ACHIEVEMENT), "解除済みの一覧に出る")
	print("Spacewar の実績: %d 個" % int(steam.getNumAchievements()))

	var stats := SteamStats.new()
	var before := int(steam.getStatInt(STAT))
	stats.add(STAT)
	_check(int(steam.getStatInt(STAT)) == before + 1, "Stat が1増える（%d → %d）" % [before, int(steam.getStatInt(STAT))])

	steam.clearAchievement(ACHIEVEMENT)
	steam.storeStats()
	print("完了: 失敗 %d 件" % _failures)
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["OK  " if ok else "FAIL", label])
	if not ok:
		_failures += 1
