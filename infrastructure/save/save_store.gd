extends RefCounted
class_name SaveStore
## 中断セーブ（1枠）の読み書き。仕様 → doc/tech/gamesystem.md
## 盤の状態 dict（BattleState.to_dict）＋文脈メタ（冒険譚/ステージID・パス）を version 付きで user://save.json に保存する。
## 状態 dict の解釈（BattleState.from_dict＝catalog で性能再構築・movement 再適用）は呼び出し側（application）の管轄
## ＝ここは素の永続化に徹する（ProgressStore/RosterStore と同流儀）。破損・手編集は「セーブ無し」にフォールバックしクラッシュしない。

const DEFAULT_PATH := "user://save.json"
const VERSION := 1

var _path: String

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path

## 有効な中断セーブが存在するか（ファイルがあり・バージョン一致・state を持つ）。
func has_save() -> bool:
	return not _read().is_empty()

## 中断セーブを読む。{ "meta": Dictionary, "state": Dictionary } を返す。無効/無ければ空 dict。
## state は BattleState.to_dict の生 dict＝呼び出し側が BattleState.from_dict で復元する。
func load() -> Dictionary:
	return _read()

## 盤状態 dict ＋メタを保存する（1枠＝上書き）。state_dict は BattleState.to_dict の戻り値。
func save(state_dict: Dictionary, meta: Dictionary = {}) -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveStore: 書き込めない: %s" % _path)
		return
	f.store_string(JSON.stringify({ "version": VERSION, "meta": meta, "state": state_dict }, "  "))

## 中断セーブを消す（再開後・破棄時）。
func clear() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))

func _read() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	# 破損・手編集がありうるので、エンジンエラーを出さない JSON.parse で静かに検証する
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(_path)) == OK else null
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		push_warning("SaveStore: 中断セーブが不正のため無視: %s" % _path)
		return {}
	var state: Variant = data.get("state", {})
	if typeof(state) != TYPE_DICTIONARY or state.is_empty():
		return {}  # 盤状態が無い/壊れている＝セーブとして無効
	var meta: Variant = data.get("meta", {})
	return { "meta": meta if typeof(meta) == TYPE_DICTIONARY else {}, "state": state }
