extends RefCounted
class_name ProgressStore
## 進捗セーブ（クリア記録）の読み書き。仕様 → doc/gdd/stage_select.md / doc/tech/gamesystem.md
## 素のJSON＋バージョン・形式チェック（不正・破損は新規扱いにフォールバックしクラッシュしない）。
## 課金解放(entitlement)はここに書かない＝セーブ改ざんで課金を突破させない設計規律。

const DEFAULT_PATH := "user://progress.json"
const VERSION := 1

var _path: String
var _cleared := {}  # 冒険譚ID -> { ステージID: true }

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_load()

func is_cleared(campaign_id: String, stage_id: String) -> bool:
	return _cleared.get(campaign_id, {}).get(stage_id, false) == true

## クリアを記録して即保存する。
func mark_cleared(campaign_id: String, stage_id: String) -> void:
	if not _cleared.has(campaign_id):
		_cleared[campaign_id] = {}
	_cleared[campaign_id][stage_id] = true
	_save()

func _load() -> void:
	if not FileAccess.file_exists(_path):
		return
	# 破損・手編集がありうるファイルなので、エンジンエラーを出さない JSON.parse で静かに検証する
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(_path)) == OK else null
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		push_warning("ProgressStore: 進捗ファイルが不正のため新規扱い: %s" % _path)
		return
	var cleared: Variant = data.get("cleared", {})
	if typeof(cleared) != TYPE_DICTIONARY:
		return
	for c in cleared:
		var stages: Variant = cleared[c]
		if typeof(stages) != TYPE_DICTIONARY:
			continue
		var entry := {}
		for s in stages:
			# bool 以外の値と == 比較すると実行時エラーになるため型を先に見る（手編集・破損対策）
			if stages[s] is bool and stages[s]:
				entry[String(s)] = true
		if not entry.is_empty():
			_cleared[String(c)] = entry

func _save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("ProgressStore: 書き込めない: %s" % _path)
		return
	f.store_string(JSON.stringify({ "version": VERSION, "cleared": _cleared }, "  "))
