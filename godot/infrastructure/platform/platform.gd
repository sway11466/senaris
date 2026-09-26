extends RefCounted
class_name Platform
## 販売チャネルごとの機能を束ねたもの。本体が見る口はこの3つだけ。仕様 → doc/tech/platform.md
## どのアダプターで組むかは for_build() の1か所で決める＝本体は BuildInfo.channel() を見て機能を分岐させない。

var ownership: OwnershipCheck  ## 所有権チェック（owns）
var achievements: AchievementVault  ## 実績の保管庫（unlock / is_unlocked / unlocked_ids）
var stats: StatsSink  ## Stats（add）

func _init(p_ownership: OwnershipCheck, p_achievements: AchievementVault, p_stats: StatsSink) -> void:
	ownership = p_ownership
	achievements = p_achievements
	stats = p_stats

## このビルドのチャネルと版からアダプターを選んで組む。起動時に main が1回呼ぶ。
static func for_build() -> Platform:
	return for_channel(BuildInfo.channel(), BuildInfo.edition())

## チャネルと版からアダプターを選ぶ。知らないチャネルは null＝呼び手が起動を止める。
## 「その他」のまとめ枠は作らない＝アダプターの足し忘れが黙って別の振る舞いにならない。
static func for_channel(channel: String, edition: String) -> Platform:
	match channel:
		"steam":
			return SteamDemoAdapter.build() if edition == BuildInfo.EDITION_DEMO else SteamAdapter.build()
		"itch":
			return ItchAdapter.build()
		"booth":
			return BoothAdapter.build()
		BuildInfo.CHANNEL_NONE:
			return DevAdapter.build()
	push_error("Platform: アダプターの無いチャネル: %s" % channel)
	return null
