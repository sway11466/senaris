extends RefCounted
class_name StoreLink
## 製品版の売り場への導線。体験版で「この先は製品版で」の案内に添えるリンクの出どころ。
## 仕様 → doc/tech/platform.md ストアページへの導線
##
## 1か所に持つ＝ページの URL が決まったとき（Steam の AppID 登録後）ここだけ書き換える。
## 空のうちは案内の紙にボタンが出ない（quest_sheet.open_full_only）。

## Steam のストアページ。AppID の登録後に "https://store.steampowered.com/app/<AppID>/" を書く。
const STEAM_STORE_URL := ""


## 案内に添える URL。チャネルに関わらず Steam のストアページ＝製品版の売り場は Steam（doc/sales/monetization.md）。
## 空＝まだページが無い。
static func url() -> String:
	return STEAM_STORE_URL
