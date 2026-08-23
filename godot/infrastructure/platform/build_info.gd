extends RefCounted
class_name BuildInfo
## このビルドが何者かの唯一の出どころ。仕様 → doc/tech/build.md
## チャネルと版はエクスポートプリセットのカスタム機能タグ、版番号は project.godot の
## application/config/version。刻印の表示もチャネルごとの分岐も、ここから引く。
## 別々に持つとずれるので、OS.has_feature を他所で直接叩かない。

## 判定するチャネル。先に当たったものを採る。プリセットのタグに1つだけ書く前提。
const CHANNELS := ["steam", "itch", "booth"]

## どのチャネルのタグも立っていないとき（エディタ実行・タグを書き忘れたビルド）。
const CHANNEL_NONE := "dev"

const EDITION_DEMO := "demo"
const EDITION_FULL := "full"

## 配布元。エクスポートしたビルドでしかタグは立たない＝エディタ実行では CHANNEL_NONE。
static func channel() -> String:
	for c in CHANNELS:
		if OS.has_feature(c):
			return c
	return CHANNEL_NONE

## 体験版か製品版か。体験版のプリセットだけが demo タグを立てる。
static func edition() -> String:
	return EDITION_DEMO if OS.has_feature(EDITION_DEMO) else EDITION_FULL

## 動作中のOS。自前のタグは持たない＝Godot が標準で答えられる。
static func os_name() -> String:
	return OS.get_name()

static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## 画面に出す刻印（例: windows-itch-demo-0.1.0）。サポートで版を特定するための1行。
## OS は小文字に揃える＝プリセット名と同じ字面になり、報告と手元のビルドを突き合わせやすい。
static func stamp() -> String:
	return "%s-%s-%s-%s" % [os_name().to_lower(), channel(), edition(), version()]
