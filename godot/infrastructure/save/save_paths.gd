extends RefCounted
class_name SavePaths
## セーブファイルの置き場。仕様 → doc/tech/gamesystem.md §保存の置き場
## 遊ぶときは user:// の直下で、ここを差し替えるのはテストだけ＝main.tscn を丸ごと立ち上げる
## テストが実セーブに触らずに済む（doc/tech/testing.md 実ファイルを触らない）。
## ファイル名は各ストアが FILE で持つ＝ここが持つのは置き場だけ。

static var dir := "user://"

## 置き場に置くファイルのパス。
static func of(file: String) -> String:
	return dir.path_join(file)
