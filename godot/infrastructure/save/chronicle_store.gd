extends RefCounted
class_name ChronicleStore
## クロニクルの読み書き（infrastructure 層）。出会ったユニット（skin_id）と
## 見た陣形スキル（スキル id）を user://chronicle.json に持つ。
## 仕様 → doc/gdd/chronicle.md 記録の持ち方 / doc/tech/gamesystem.md §クロニクル
##
## 他のストアと異なり、record_* は即座に保存しない。盤を離れるとき（決着・中断・
## タイトルへ戻る）に save() を呼んでまとめて書く（gamesystem.md §クロニクル）。
## 壊れていれば空で起動し、遊び直せば埋まるだけ。

const FILE := "chronicle.json"  # 置き場は SavePaths が持つ
const VERSION := 2
const OLDEST_SUPPORTED := 1  # v1＝スキンにも初出の冒険譚を持っていた版

var _path: String
var _skins := {}    # skin_id -> true（出会った id の集合。スキンは初出を持たない）
var _skills := {}   # skill_id -> { "first": campaign_id }
## 経験した会話。campaign_id -> { stage_id: { start: [[actor]], clear: [[actor]], events: [id] } }
## start / clear は「遊んだ回ごとの在籍 actor の並び」を重複なく溜める＝同じ顔ぶれの回は畳む。
## 足していく形にすることで、仲間が「居た回」と「居なかった回」の両方を経験したかが分かる
## （doc/gdd/chronicle.md 分岐の切り替え）。進捗セーブ側は最後に遊んだ回だけを上書きで持つ。
var _stories := {}
var _dirty := false # record_* を呼んでから save() するまでの間だけ true

func _init(path: String = SavePaths.of(FILE)) -> void:
	_path = path
	_load()

## skin_id が記録済みか。
func has_skin(skin_id: String) -> bool:
	return _skins.has(skin_id)

## skill_id が記録済みか。
func has_skill(skill_id: String) -> bool:
	return _skills.has(skill_id)

## 記録済みのスキン一覧（コピー）。出会った skin_id が並ぶだけ。
func skins() -> Array:
	return _skins.keys()

## 記録済みのスキル一覧（コピー）。
func skills() -> Dictionary:
	return _skills.duplicate(true)

## スキンを記録する（メモリのみ。save() を呼ぶまでファイルに書かない）。
## 新規なら true、既知または空なら false を返す。
func record_skin(skin_id: String) -> bool:
	if skin_id.is_empty() or _skins.has(skin_id):
		return false
	_skins[skin_id] = true
	_dirty = true
	return true

## スキルを記録する（メモリのみ）。新規なら true。
func record_skill(skill_id: String, campaign_id: String) -> bool:
	if skill_id.is_empty() or _skills.has(skill_id):
		return false
	_skills[skill_id] = { "first": campaign_id }
	_dirty = true
	return true

## 遊んだ回の在籍 actor を足す。phase は "start"（開始時）か "clear"（クリア後）。
## 同じ顔ぶれが既にあれば何もしない。新しい顔ぶれなら true。
func record_story_roster(campaign_id: String, stage_id: String, phase: String, actors: Array) -> bool:
	if campaign_id.is_empty() or stage_id.is_empty():
		return false
	if phase != "start" and phase != "clear":
		return false
	var names := _sorted_names(actors)
	var list: Array = _story_entry(campaign_id, stage_id)[phase]
	var key := _roster_key(names)
	for known in list:
		if _roster_key(known) == key:
			return false
	list.append(names)
	_dirty = true
	return true

## 起きたイベントを足す（消さない）。新規なら true。
func record_story_event(campaign_id: String, stage_id: String, event_id: String) -> bool:
	if campaign_id.is_empty() or stage_id.is_empty() or event_id.is_empty():
		return false
	var events: Array = _story_entry(campaign_id, stage_id)["events"]
	if events.has(event_id):
		return false
	events.append(event_id)
	_dirty = true
	return true

## そのステージで経験した会話（コピー）。記録が無ければ空の形を返す。
func story(campaign_id: String, stage_id: String) -> Dictionary:
	var stages: Variant = _stories.get(campaign_id, {})
	var entry: Variant = (stages as Dictionary).get(stage_id, {})
	if (entry as Dictionary).is_empty():
		return { "start": [], "clear": [], "events": [] }
	return (entry as Dictionary).duplicate(true)

## ファイルに書き出す。変更がなければ何もしない。
## 盤を離れるとき（決着・中断・タイトルへ戻る）に呼ぶ。
func save() -> void:
	if not _dirty:
		return
	SaveFile.rotate(_path)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("ChronicleStore: 書き込めない: %s" % _path)
		return
	var out := { "version": VERSION, "skins": _skins.keys(), "skills": _skills, "stories": _stories }
	f.store_string(JSON.stringify(out, "  "))
	_dirty = false

# ---------------------------------------------------------------------------

func _load() -> void:
	var result := SaveFile.read(_path, VERSION, OLDEST_SUPPORTED)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("ChronicleStore: ファイルが不正のため空扱い: %s" % _path)
		return
	var data := _migrate(result["data"])
	if data.is_empty():
		return
	_load_ids(data.get("skins", []), _skins)
	_load_map(data.get("skills", {}), _skills)
	_load_stories(data.get("stories", {}))

## 旧版を現行の形に直してから読む（doc/tech/gamesystem.md §版と移行）。
## 版を上げたらここに1段足す。変換を持たない版は空を返す＝無いものとして扱う。
static func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	var out := data
	if version == 1:
		out = _v1_to_v2(out)
		version = 2
	if version != VERSION:
		push_warning("ChronicleStore: 変換を持たない版 %d（SaveFile が弾くはず＝呼び出しのバグ）" % version)
		return {}
	return out

## v1→v2: スキンが持っていた初出の冒険譚を捨て、出会った id の並びだけにする。
## スキル側の初出はそのまま（陣形スキルの章が読む）。
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	var ids: Array = []
	var raw: Variant = data.get("skins", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for k in raw as Dictionary:
			ids.append(String(k))
	out["skins"] = ids
	out["version"] = 2
	return out

## [ id, ... ] の並びを型チェックしながら読む（手編集・破損対策）。
func _load_ids(raw: Variant, dest: Dictionary) -> void:
	if typeof(raw) != TYPE_ARRAY:
		return
	for v in raw as Array:
		if typeof(v) != TYPE_STRING:
			continue
		var id := String(v)
		if not id.is_empty():
			dest[id] = true

## { id: { "first": campaign_id } } の辞書を型チェックしながら読む（手編集・破損対策）。
func _load_map(raw: Variant, dest: Dictionary) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for k in raw:
		var v: Variant = raw[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		dest[String(k)] = { "first": String((v as Dictionary).get("first", "")) }

## 経験した会話を型チェックしながら読む（手編集・破損対策）。読めない枝は捨てる。
func _load_stories(raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for campaign_id in raw:
		var stages: Variant = raw[campaign_id]
		if typeof(stages) != TYPE_DICTIONARY:
			continue
		for stage_id in stages as Dictionary:
			var entry: Variant = (stages as Dictionary)[stage_id]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var dest := _story_entry(String(campaign_id), String(stage_id))
			dest["start"] = _roster_list((entry as Dictionary).get("start", []))
			dest["clear"] = _roster_list((entry as Dictionary).get("clear", []))
			dest["events"] = _string_list((entry as Dictionary).get("events", []))

## 記録の置き場を取る（無ければ作る）。
func _story_entry(campaign_id: String, stage_id: String) -> Dictionary:
	if not _stories.has(campaign_id):
		_stories[campaign_id] = {}
	var stages: Dictionary = _stories[campaign_id]
	if not stages.has(stage_id):
		stages[stage_id] = { "start": [], "clear": [], "events": [] }
	return stages[stage_id]

## 顔ぶれの並び（[[actor]]）を型チェックしながら読む。
static func _roster_list(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for one in raw:
		if typeof(one) != TYPE_ARRAY:
			continue
		out.append(_sorted_names(one))
	return out

## 名前の配列を型チェックしながら読む。
static func _string_list(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for v in raw:
		if typeof(v) != TYPE_STRING:
			continue
		var name := String(v)
		if not name.is_empty() and not out.has(name):
			out.append(name)
	return out

## 顔ぶれを比較できる形にそろえる＝空を除き、重複を除き、名前順に並べる。
static func _sorted_names(actors: Array) -> Array:
	var out: Array = _string_list(actors)
	out.sort()
	return out

## 顔ぶれの照合キー。Array どうしの比較を避けて文字列で見る。
static func _roster_key(names: Array) -> String:
	return ",".join(PackedStringArray(names))
