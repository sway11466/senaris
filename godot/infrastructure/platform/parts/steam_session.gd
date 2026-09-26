extends RefCounted
class_name SteamSession
## Steamworks との接続。Steam の部品だけが使う。仕様 → doc/tech/platform.md 置き場・Steam の初期化に失敗したとき
## GodotSteam は Steam のビルドにだけ入る＝itch・BOOTH のビルドには Steam のシングルトンが無い。
## `Steam` を名前で直接書くと、そのビルドでスクリプトの解析に失敗するので、ここで Engine から取る。

const SINGLETON := "Steam"

## Steam のシングルトン。GodotSteam が無ければ null。
static func api() -> Object:
	return Engine.get_singleton(SINGLETON) if Engine.has_singleton(SINGLETON) else null

## Steamworks を初期化する。空文字＝繋がった。それ以外は繋がらなかった理由（ログ用）。
## AppID は Steam が渡す（Steam から起動したとき）か、作業ディレクトリの steam_appid.txt から読まれる。
## コールバックは GodotSteam に回させる（embed）＝毎フレーム run_callbacks を呼ぶ場所を持たない。
static func start() -> String:
	var steam := api()
	if steam == null:
		return "GodotSteam が無い"
	var result: Dictionary = steam.steamInitEx(0, true)
	if int(result.get("status", -1)) != 0:
		return "Steamworks の初期化に失敗: %s" % String(result.get("verbal", ""))
	return ""
