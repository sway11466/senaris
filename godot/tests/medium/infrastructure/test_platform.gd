extends GutTest
## Platform（チャネルごとのアダプターの選択と、Steam 以外の部品）のテスト。仕様 → doc/tech/platform.md
## アダプターは実績ファイルを開くので、置き場をその回だけのディレクトリへ向ける（doc/tech/testing.md）。

const DIR := "user://test_platform"

var _saved_dir := ""

func before_each() -> void:
	_saved_dir = SavePaths.dir
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	SavePaths.dir = DIR

func after_each() -> void:
	SavePaths.dir = _saved_dir
	_clean()

func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

func test_steam_full_uses_steam_parts() -> void:
	var p := Platform.for_channel("steam", BuildInfo.EDITION_FULL)
	assert_true(p.ownership is SteamDlcOwnership, "製品版の所有権は Steam DLC に問う")
	assert_true(p.achievements is SteamAchievements, "製品版の実績は Steamworks に置く")
	assert_true(p.stats is SteamStats)

func test_steam_demo_keeps_achievements_local() -> void:
	var p := Platform.for_channel("steam", BuildInfo.EDITION_DEMO)
	assert_true(p.ownership is AlwaysOwned)
	assert_true(p.achievements is AchievementFile, "体験版は実績を Steam に立てずファイルに溜める")
	assert_true(p.stats is SteamStats, "Stats は体験版も Steam へ")

func test_non_steam_channels_share_local_parts() -> void:
	for channel in ["itch", "booth", BuildInfo.CHANNEL_NONE]:
		for edition in [BuildInfo.EDITION_FULL, BuildInfo.EDITION_DEMO]:
			var p := Platform.for_channel(channel, edition)
			assert_true(p.ownership is AlwaysOwned, "%s/%s は常に所有" % [channel, edition])
			assert_true(p.achievements is AchievementFile, "%s/%s は実績ファイル" % [channel, edition])
			assert_true(p.stats is NoStats, "%s/%s は Stats を送らない" % [channel, edition])

func test_every_known_channel_has_an_adapter() -> void:
	# BuildInfo にチャネルを足したのにアダプターを足し忘れた、をここで捕まえる
	for channel in BuildInfo.CHANNELS + [BuildInfo.CHANNEL_NONE]:
		assert_not_null(Platform.for_channel(channel, BuildInfo.EDITION_FULL), "%s のアダプターがある" % channel)

func test_unknown_channel_stops() -> void:
	assert_null(Platform.for_channel("gog", BuildInfo.EDITION_FULL), "知らないチャネルにまとめ枠で答えない")
	assert_push_error("アダプターの無いチャネル")

func test_always_owned_owns_anything() -> void:
	assert_true(AlwaysOwned.new().owns("any_campaign"))

func test_no_stats_accepts_calls() -> void:
	NoStats.new().add("stage_started")
	NoStats.new().add("stage_cleared", 3)
	pass_test("何もせず、エラーも出さない")
