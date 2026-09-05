extends RefCounted
class_name ProgressStore
## 進捗セーブ（クリア記録）の読み書き。仕様 → doc/gdd/stage_select.md / doc/tech/gamesystem.md
## 素のJSON＋バージョン・形式チェック（不正・破損は新規扱いにフォールバックしクラッシュしない）。
## 課金解放(entitlement)はここに書かない＝セーブ改ざんで課金を突破させない設計規律。

const DEFAULT_PATH := "user://progress.json"
## 2: ステージごとのベストタイム（times＝クリアまでの所要秒）を足した。
## 3: ステージごとに経験した会話（story）を足した。
const VERSION := 3
## 変換を持ついちばん古い版。v1 は所要時間を測っていないので times を持たないまま読む。
const OLDEST_SUPPORTED := 1

var _path: String
var _cleared := {}  # 冒険譚ID -> { ステージID: true }
var _ranks := {}    # 冒険譚ID -> { ステージID: "S"/"A"/"B" }（ベストランク）
var _times := {}    # 冒険譚ID -> { ステージID: 秒 }（ベストタイム＝いちばん短いクリア）
## 経験した会話。冒険譚ID -> { ステージID: { start: [actor], clear: [actor], events: [イベントid] } }
## start＝開始時の在籍 actor・clear＝クリア後の在籍 actor（無ければ未クリア）・events＝起きた順。
## 「ストーリーを確認」が当時の顔ぶれで台本を組み直すのに使う。仕様 → doc/tech/gamesystem.md 経験した会話
var _story := {}

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

## そのステージのベストタイム（秒）。まだ記録が無ければ 0。
func best_time(campaign_id: String, stage_id: String) -> int:
	return int(_times.get(campaign_id, {}).get(stage_id, 0))

## 所要時間を記録して即保存する。前より短いときだけ上書きする（ランクと同じ流儀）。
## 0 以下は測れていない回＝記録しない（doc/tech/gamesystem.md §所要時間）。
func mark_time(campaign_id: String, stage_id: String, seconds: int) -> void:
	if seconds <= 0:
		return
	var current := best_time(campaign_id, stage_id)
	if current > 0 and current <= seconds:
		return
	if not _times.has(campaign_id):
		_times[campaign_id] = {}
	_times[campaign_id][stage_id] = seconds
	_save()

## そのステージで経験した会話の記録（無ければ空）。中身は _story のコメントを参照。
func story(campaign_id: String, stage_id: String) -> Dictionary:
	return _story.get(campaign_id, {}).get(stage_id, {})

## ステージを開始した＝開始時の在籍 actor を書き換える（遊び直すたびに上書き）。
func mark_story_start(campaign_id: String, stage_id: String, actors: Array) -> void:
	_story_entry(campaign_id, stage_id)["start"] = _actor_names(actors)
	_save()

## クリアした＝クリア後の在籍 actor を書き換える。この項目の有無がクリア済みかを表す。
func mark_story_clear(campaign_id: String, stage_id: String, actors: Array) -> void:
	_story_entry(campaign_id, stage_id)["clear"] = _actor_names(actors)
	_save()

## イベントが起きた＝起きた順に足す。同じイベントは1回だけ（遊び直しでも消さない
## ＝前に読み逃した会話を、もう一度起こすまで読めなくしない）。
func mark_story_event(campaign_id: String, stage_id: String, event_id: String) -> void:
	if event_id.is_empty():
		return
	var entry := _story_entry(campaign_id, stage_id)
	var events: Array = entry["events"]
	if events.has(event_id):
		return
	events.append(event_id)
	_save()

## そのステージの記録を作って返す（無ければ空の形で置く）。
func _story_entry(campaign_id: String, stage_id: String) -> Dictionary:
	if not _story.has(campaign_id):
		_story[campaign_id] = {}
	var stages: Dictionary = _story[campaign_id]
	if not stages.has(stage_id):
		# clear は「無い＝未クリア＝決着の会話は読めない」を表す＝mark_story_clear まで置かない。
		stages[stage_id] = { "start": [], "events": [] }
	return stages[stage_id]

## 名簿（Unit の直列化）から actor の名前だけを取り出す。会話の when が見るのは在籍だけ
## （doc/campaign/authoring.md 会話の分岐）＝素性も損耗も持たない。
static func _actor_names(units: Array) -> Array:
	var out: Array = []
	for u in units:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var a := String((u as Dictionary).get("actor", ""))
		if a != "" and not out.has(a):
			out.append(a)
	return out

func _load() -> void:
	# 破損・手編集・版違いの判定と退避は SaveFile が持つ（doc/tech/gamesystem.md §バックアップ）
	var result := SaveFile.read(_path, VERSION, OLDEST_SUPPORTED)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("ProgressStore: 進捗ファイルが不正のため新規扱い: %s" % _path)
		return
	var data: Dictionary = _migrate(result["data"])
	if data.is_empty():
		return
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
	var story: Variant = data.get("story", {})
	if typeof(story) == TYPE_DICTIONARY:
		for c in story:
			var stages: Variant = story[c]
			if typeof(stages) != TYPE_DICTIONARY:
				continue
			var entry := {}
			for s in stages:
				var rec: Variant = stages[s]
				if typeof(rec) != TYPE_DICTIONARY:
					continue
				var one := { "start": _string_list(rec.get("start")), "events": _string_list(rec.get("events")) }
				# clear は「無い＝未クリア」を表すので、書かれていないときは足さない（空配列と区別する）。
				if (rec as Dictionary).has("clear"):
					one["clear"] = _string_list(rec.get("clear"))
				entry[String(s)] = one
			if not entry.is_empty():
				_story[String(c)] = entry
	var times: Variant = data.get("times", {})
	if typeof(times) == TYPE_DICTIONARY:
		for c in times:
			var stages: Variant = times[c]
			if typeof(stages) != TYPE_DICTIONARY:
				continue
			var entry := {}
			for s in stages:
				# 手編集・破損対策。JSON の数値は float で来るので型を見てから丸める
				var v: Variant = stages[s]
				if (v is int or v is float) and int(v) > 0:
					entry[String(s)] = int(v)
			if not entry.is_empty():
				_times[String(c)] = entry

## JSON から文字列の配列だけを取り出す（手編集・破損対策）。文字列でない要素は落とす。
static func _string_list(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for e in v:
		if e is String and not out.has(e):
			out.append(String(e))
	return out

## 旧版を現行版の形へ直す（doc/tech/gamesystem.md §版と移行）。読めない版は空 dict＝新規扱い。
static func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	var out := data
	if version == 1:
		out = _v1_to_v2(out)
		version = 2
	if version == 2:
		out = _v2_to_v3(out)
		version = 3
	if version != VERSION:
		push_warning("ProgressStore: 変換を持たない版 %d（SaveFile が弾くはず＝呼び出しのバグ）" % version)
		return {}
	return out

## v1（クリア記録とベストランク）→ v2（ベストタイムを足した）。v1 は所要時間を測っていないので
## times は空のまま＝次にクリアした回から埋まる。
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var out := data.duplicate()
	out["version"] = 2
	out.erase("times")
	return out

## v2（ベストタイムまで）→ v3（経験した会話を足した）。v2 は会話を覚えていないので story は空のまま
## ＝この仕組みより前にクリアしたステージは「ストーリーを確認」に出ない（遊び直せば埋まる）。
static func _v2_to_v3(data: Dictionary) -> Dictionary:
	var out := data.duplicate()
	out["version"] = 3
	out.erase("story")
	return out

func _save() -> void:
	SaveFile.rotate(_path)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("ProgressStore: 書き込めない: %s" % _path)
		return
	var out := { "version": VERSION, "cleared": _cleared }
	if not _ranks.is_empty():
		out["ranks"] = _ranks
	if not _times.is_empty():
		out["times"] = _times
	if not _story.is_empty():
		out["story"] = _story
	f.store_string(JSON.stringify(out, "  "))
