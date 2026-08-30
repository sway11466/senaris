extends RefCounted
class_name ProgressStore
## 進捗セーブ（クリア記録）の読み書き。仕様 → doc/gdd/stage_select.md / doc/tech/gamesystem.md
## 素のJSON＋バージョン・形式チェック（不正・破損は新規扱いにフォールバックしクラッシュしない）。
## 課金解放(entitlement)はここに書かない＝セーブ改ざんで課金を突破させない設計規律。

const DEFAULT_PATH := "user://progress.json"
const VERSION := 1

var _path: String
var _cleared := {}  # 冒険譚ID -> { ステージID: true }
var _ranks := {}    # 冒険譚ID -> { ステージID: "S"/"A"/"B" }（ベストランク）

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

## ベストランクを返す（未記録なら空文字）。
func best_rank(campaign_id: String, stage_id: String) -> String:
	return String(_ranks.get(campaign_id, {}).get(stage_id, ""))

## ランクを記録して即保存する。既存より上位のときだけ上書きする。
func mark_rank(campaign_id: String, stage_id: String, rank: String) -> void:
	if rank.is_empty():
		return
	var current := best_rank(campaign_id, stage_id)
	if not current.is_empty() and not RankEvaluator.is_better(rank, current):
		return
	if not _ranks.has(campaign_id):
		_ranks[campaign_id] = {}
	_ranks[campaign_id][stage_id] = rank
	_save()

func _load() -> void:
	# 破損・手編集・版違いの判定と退避は SaveFile が持つ（doc/tech/gamesystem.md §バックアップ）
	var result := SaveFile.read(_path, VERSION)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("ProgressStore: 進捗ファイルが不正のため新規扱い: %s" % _path)
		return
	var data: Dictionary = result["data"]
	var cleared: Variant = data.get("cleared", {})
	if typeof(cleared) == TYPE_DICTIONARY:
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
	var ranks: Variant = data.get("ranks", {})
	if typeof(ranks) == TYPE_DICTIONARY:
		for c in ranks:
			var stages: Variant = ranks[c]
			if typeof(stages) != TYPE_DICTIONARY:
				continue
			var entry := {}
			for s in stages:
				var v: Variant = stages[s]
				if v is String and v in ["S", "A", "B"]:
					entry[String(s)] = String(v)
			if not entry.is_empty():
				_ranks[String(c)] = entry

func _save() -> void:
	SaveFile.rotate(_path)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("ProgressStore: 書き込めない: %s" % _path)
		return
	var out := { "version": VERSION, "cleared": _cleared }
	if not _ranks.is_empty():
		out["ranks"] = _ranks
	f.store_string(JSON.stringify(out, "  "))
