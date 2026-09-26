extends OwnershipCheck
class_name SteamDlcOwnership
## 所有権チェックの部品「Steam DLC」。content_id を DLC の AppID に引いて Steam に問い合わせる。
## 仕様 → doc/tech/platform.md アダプターと部品
## 中身は GodotSteam の導入（doc/backlog.md feature-40）で書く。それまでは呼ばれたら声を出す。

func owns(content_id: String) -> bool:
	push_error("SteamDlcOwnership: 未実装（feature-40）: %s" % content_id)
	return false
