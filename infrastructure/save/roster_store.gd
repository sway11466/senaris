extends RefCounted
class_name RosterStore
## 戦力スナップショット（継承 carryover）の読み書き。仕様 → doc/gdd/map.md / doc/tech/gamesystem.md
## 冒険譚ごとに「次ステージへ持ち越す生存ユニットの直列化リスト」を持つ。中身は Unit.to_dict() の配列＝
## 素性・成長・損耗だけ（性能は type から再構築・盤依存の状態は持たない）。Unit の復元・配置は application 層（Phase 2c/2d）。
## 素のJSON＋バージョン・形式チェック（不正・破損は空にフォールバックしクラッシュしない＝ProgressStore と同流儀）。

const DEFAULT_PATH := "user://roster.json"
const VERSION := 1

var _path: String
var _rosters := {}  # 冒険譚ID -> Array[Dictionary]（Unit.to_dict() の配列）

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_load()

## 冒険譚に持ち越し戦力があるか（＝空でないスナップショットが記録済みか）。
func has_roster(campaign_id: String) -> bool:
	return not (_rosters.get(campaign_id, []) as Array).is_empty()

## 持ち越し戦力（Unit.to_dict() の配列）のコピーを返す。無ければ空配列。
func load_roster(campaign_id: String) -> Array:
	return (_rosters.get(campaign_id, []) as Array).duplicate(true)

## 持ち越し戦力を記録して即保存する。units は Unit.to_dict() の配列（継承ステージ終了時に呼ぶ）。
func save_roster(campaign_id: String, units: Array) -> void:
	_rosters[campaign_id] = units.duplicate(true)
	_save()

## 冒険譚の持ち越しを破棄して即保存する（連戦区間の終わり・最初からやり直し）。
func clear_roster(campaign_id: String) -> void:
	if _rosters.erase(campaign_id):
		_save()

func _load() -> void:
	if not FileAccess.file_exists(_path):
		return
	# 破損・手編集がありうるファイルなので、エンジンエラーを出さない JSON.parse で静かに検証する
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(_path)) == OK else null
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		push_warning("RosterStore: スナップショットが不正のため空扱い: %s" % _path)
		return
	var rosters: Variant = data.get("rosters", {})
	if typeof(rosters) != TYPE_DICTIONARY:
		return
	for c in rosters:
		var list: Variant = rosters[c]
		if typeof(list) != TYPE_ARRAY:
			continue  # 配列でない冒険譚エントリはスキップ（他は生かす）
		var units: Array = []
		for e in list:
			if typeof(e) == TYPE_DICTIONARY:
				units.append(e)  # 各ユニットの中身の欠損は Unit.from_dict が復元時に耐える
		if not units.is_empty():
			_rosters[String(c)] = units

func _save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("RosterStore: 書き込めない: %s" % _path)
		return
	f.store_string(JSON.stringify({ "version": VERSION, "rosters": _rosters }, "  "))
