extends AchievementVault
class_name AchievementFile
## 実績の保管庫の部品「実績ファイル」（user://achievements.json）。仕様 → doc/tech/platform.md 実績ファイル
## Steam 以外に実績を置くチャネル（steam-demo・itch・booth・dev）が使う。進捗セーブとは別のファイル
## ＝セーブを消しても実績は残り、体験版から製品版へは実績だけを渡せる。
## 形式は { "version", "unlocked": [id, …] }（解除した順）。解除した時刻は持たない。

const FILE := "achievements.json"  # 置き場は SavePaths が持つ
const VERSION := 1

var _path: String
var _unlocked := PackedStringArray()

func _init(path: String = SavePaths.of(FILE)) -> void:
	_path = path
	_load()

func unlock(id: String) -> void:
	if _unlocked.has(id):
		return
	_unlocked.append(id)
	# エディタ実行でも解除が見えるように、ログに1行残す（doc/tech/platform.md 狙い）
	print("Achievement unlocked: %s" % id)
	_save()

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)

func unlocked_ids() -> PackedStringArray:
	return _unlocked.duplicate()

func _load() -> void:
	# 破損・手編集・版違いの判定と退避は SaveFile が持つ（doc/tech/gamesystem.md §バックアップ）
	var result := SaveFile.read(_path, VERSION)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("AchievementFile: 実績ファイルが不正のため解除なしで起動: %s" % _path)
		return
	var list: Variant = result["data"].get("unlocked", null)
	if not list is Array:
		return
	for v in list:
		# 文字列でないもの・重複は手編集の名残＝黙って捨てる
		if v is String and not _unlocked.has(v):
			_unlocked.append(String(v))

func _save() -> void:
	SaveFile.rotate(_path)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("AchievementFile: 書き込めない: %s" % _path)
		return
	f.store_string(JSON.stringify({ "version": VERSION, "unlocked": Array(_unlocked) }, "  "))
