extends RefCounted
class_name RosterStore
## 名簿（継承 carryover）の読み書き。仕様 → doc/gdd/campaigns.md 名簿 / doc/tech/gamesystem.md セーブ
## ステージをクリアした時点の名簿を、冒険譚ID×ステージIDの控えとして持つ。次のステージはマニフェストの
## roster_from が指すステージの控えを読む＝どの控えを読むかは application 層（CampaignProgress）が決め、
## ここは冒険譚IDとステージIDで引くだけ。前のステージをやり直しても先のステージの控えは変わらない。
## 控えの中身は「パーティの在籍者一覧」の直列化リスト（盤上の生存者リストではない＝兵力ゼロで戦線を
## 離れた駒も troops:0 で残る。盤へ出すのは troops>0 の者だけ）。Unit.to_dict() の配列＝素性・成長・損耗だけ
## （性能は type から再構築・盤依存の状態は持たない）。Unit の復元・配置は application 層。
## 素のJSON＋バージョン・形式チェック（不正・破損は空にフォールバックしクラッシュしない＝ProgressStore と同流儀）。

const FILE := "roster.json"  # 置き場は SavePaths が持つ
## 2: 冒険譚に1冊だった名簿をステージごとの控えにした（rosters[冒険譚ID][ステージID]）。
const VERSION := 2
## 変換を持ついちばん古い版。v1 の1冊はどのステージのクリア後かが分からないので捨てる（doc/gdd/campaigns.md 名簿）。
const OLDEST_SUPPORTED := 1

var _path: String
var _rosters := {}  # 冒険譚ID -> { ステージID: Array[Dictionary]（Unit.to_dict() の配列） }

func _init(path: String = SavePaths.of(FILE)) -> void:
	_path = path
	_load()

## ステージをクリアした時点の名簿（Unit.to_dict() の配列）のコピーを返す。無ければ空配列。
func load_roster(campaign_id: String, stage_id: String) -> Array:
	var stages: Dictionary = _rosters.get(campaign_id, {})
	return (stages.get(stage_id, []) as Array).duplicate(true)

## ステージをクリアした時点の名簿を記録して即保存する。units は Unit.to_dict() の配列（クリア時に呼ぶ）。
func save_roster(campaign_id: String, stage_id: String, units: Array) -> void:
	if not _rosters.has(campaign_id):
		_rosters[campaign_id] = {}
	_rosters[campaign_id][stage_id] = units.duplicate(true)
	_save()

## ステージの控えを破棄して即保存する。冒険譚の控えがすべて無くなれば冒険譚の項も消す。
func clear_roster(campaign_id: String, stage_id: String) -> void:
	if not _rosters.has(campaign_id):
		return
	var stages: Dictionary = _rosters[campaign_id]
	if not stages.erase(stage_id):
		return
	if stages.is_empty():
		_rosters.erase(campaign_id)
	_save()

func _load() -> void:
	# 破損・手編集・版違いの判定と退避は SaveFile が持つ（doc/tech/gamesystem.md §バックアップ）
	var result := SaveFile.read(_path, VERSION, OLDEST_SUPPORTED)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("RosterStore: 名簿が不正のため空扱い: %s" % _path)
		return
	var data: Dictionary = _migrate(result["data"])
	if data.is_empty():
		return
	var rosters: Variant = data.get("rosters", {})
	if typeof(rosters) != TYPE_DICTIONARY:
		return
	for c in rosters:
		var stages: Variant = rosters[c]
		if typeof(stages) != TYPE_DICTIONARY:
			continue  # 辞書でない冒険譚エントリはスキップ（他は生かす）
		var entry := {}
		for s in stages:
			var list: Variant = stages[s]
			if typeof(list) != TYPE_ARRAY:
				continue  # 配列でないステージエントリはスキップ（他は生かす）
			var units: Array = []
			for e in list:
				if typeof(e) == TYPE_DICTIONARY:
					units.append(e)  # 各ユニットの中身の欠損は Unit.from_dict が復元時に耐える
			if not units.is_empty():
				entry[String(s)] = units
		if not entry.is_empty():
			_rosters[String(c)] = entry

## 旧版を現行版の形へ直す（doc/tech/gamesystem.md §版と移行）。読めない版は空 dict＝新規扱い。
static func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	var out := data
	if version == 1:
		out = _v1_to_v2(out)
		version = 2
	if version != VERSION:
		push_warning("RosterStore: 変換を持たない版 %d（SaveFile が弾くはず＝呼び出しのバグ）" % version)
		return {}
	return out

## v1（冒険譚に1冊）→ v2（ステージごとの控え）。1冊がどのステージのクリア後かはファイルから分からない
## ので捨てる＝控え無しで始める。体験版は出回っておらず守る名簿が無い（doc/gdd/campaigns.md 名簿）。
static func _v1_to_v2(_data: Dictionary) -> Dictionary:
	return { "version": 2, "rosters": {} }

func _save() -> void:
	SaveFile.rotate(_path)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("RosterStore: 書き込めない: %s" % _path)
		return
	f.store_string(JSON.stringify({ "version": VERSION, "rosters": _rosters }, "  "))
