extends OwnershipCheck
class_name SteamDlcOwnership
## 所有権チェックの部品「Steam DLC」。content_id を DLC の AppID に引いて Steam に問い合わせる。
## 仕様 → doc/tech/platform.md アダプターと部品
## content_id と AppID の対応はここだけが持つ＝本体は AppID を知らない。

## content_id（冒険譚 ID）→ DLC の AppID。DLC を Steamworks に登録したら足す。
const DLC_APP_IDS := {}

func owns(content_id: String) -> bool:
	if not DLC_APP_IDS.has(content_id):
		push_error("SteamDlcOwnership: AppID の無い追加コンテンツ: %s" % content_id)
		return false
	var steam := SteamSession.api()
	return steam != null and bool(steam.isDLCInstalled(int(DLC_APP_IDS[content_id])))
