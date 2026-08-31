extends RefCounted
class_name SaveStore
## 中断セーブ（1枠）の読み書き。仕様 → doc/tech/gamesystem.md
## 盤の動的差分 dict（BattleState.to_save_diff）＋文脈メタ（冒険譚/ステージID・パス・ステージ定義の印）を
## version 付きで user://save.json に保存する。
## 中身の解釈（旧版の変換＝SaveMigration・盤の復元＝SaveRestore）は呼び出し側の管轄
## ＝ここは素の永続化に徹する（ProgressStore/RosterStore と同流儀）。破損・手編集は「セーブ無し」にフォールバックしクラッシュしない。

const DEFAULT_PATH := "user://save.json"
## 2: roster を落とし sortied_actors を足した（doc/gdd/campaigns.md 名簿の更新）。旧セーブ(v1)は投入記録を
##    持たず、復元して勝つと在籍者が全員「出番なし」扱いになるため読まない（退避はする）。
## 3: 盤の丸ごと直列化をやめ、ステージJSONから引き直せるものを落として動的差分だけを持つ。
##    meta にステージ定義の印（stage_digest）を足した（doc/tech/gamesystem.md §中断セーブが持つもの）。
const VERSION := 3
## 変換を持ついちばん古い版。v2 は読んで生のまま返し、呼び出し側が SaveMigration で v3 に変換して使う。
const OLDEST_SUPPORTED := 2

var _path: String

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path

## 有効な中断セーブが存在するか（ファイルがあり・バージョン一致・state を持つ）。
func has_save() -> bool:
	return not _read().is_empty()

## 中断セーブを読む。{ "version": int, "meta": Dictionary, "state": Dictionary } を返す。無効/無ければ空 dict。
## state はファイルの生 dict＝呼び出し側が SaveMigration.migrate（版の変換）→ SaveRestore.restore で復元する。
func load() -> Dictionary:
	return _read()

## 盤状態 dict ＋メタを保存する（1枠＝上書き）。state_dict は BattleState.to_save_diff の戻り値。
func save(state_dict: Dictionary, meta: Dictionary = {}) -> void:
	SaveFile.rotate(_path)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveStore: 書き込めない: %s" % _path)
		return
	f.store_string(JSON.stringify({ "version": VERSION, "meta": meta, "state": state_dict }, "  "))

## 中断セーブを消す（再開後・破棄時）。消す前に世代を残す＝取り違えて消しても戻せる。
func clear() -> void:
	if FileAccess.file_exists(_path):
		SaveFile.rotate(_path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))

func _read() -> Dictionary:
	# 破損・手編集・版違いの判定と退避は SaveFile が持つ（doc/tech/gamesystem.md §バックアップ）。
	# 変換を持つ旧版（OLDEST_SUPPORTED 以上）は生のまま通す＝変換は呼び出し側（SaveMigration）。
	var result := SaveFile.read(_path, VERSION, OLDEST_SUPPORTED)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("SaveStore: 中断セーブが不正のため無視: %s" % _path)
		return {}
	var data: Dictionary = result["data"]
	var state: Variant = data.get("state", {})
	if typeof(state) != TYPE_DICTIONARY or state.is_empty():
		return {}  # 盤状態が無い/壊れている＝セーブとして無効
	var meta: Variant = data.get("meta", {})
	return {
		"version": int(data.get("version", 0)),
		"meta": meta if typeof(meta) == TYPE_DICTIONARY else {},
		"state": state,
	}
