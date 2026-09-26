extends RefCounted
class_name Platform
## 販売チャネルごとの機能を束ねたもの。本体が見る口はこの3つだけ。仕様 → doc/tech/platform.md
## どのアダプターで組むかは for_build() の1か所で決める＝本体は BuildInfo.channel() を見て機能を分岐させない。

var ownership: OwnershipCheck  ## 所有権チェック（owns）
var achievements: AchievementVault  ## 実績の保管庫（unlock / is_unlocked / unlocked_ids）
var stats: StatsSink  ## Stats（add）

var _starter := Callable()  # 起動時の接続（Steam など）。無ければ何もしない

func _init(p_ownership: OwnershipCheck, p_achievements: AchievementVault, p_stats: StatsSink) -> void:
	ownership = p_ownership
	achievements = p_achievements
	stats = p_stats

## 起動時に要る接続を登録する（アダプターが使う）。返り値は start() と同じ。
func set_starter(fn: Callable) -> void:
	_starter = fn

## 外界に繋ぐ。起動時に main が1回呼ぶ。空文字＝使える。それ以外は起動を止める理由（ログ用）。
## 選ぶ（for_build）と繋ぐ（start）を分ける＝アダプターの選択を、繋がずにテストできる。
func start() -> String:
	return String(_starter.call()) if _starter.is_valid() else ""

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
