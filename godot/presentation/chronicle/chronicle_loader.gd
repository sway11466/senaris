extends RefCounted
class_name ChronicleLoader
## クロニクル専用データの読み込み。
## ゲーム進行（campaign.json / CampaignCatalog）とは分離し、クロニクル画面だけが使う。
## res://data/chronicle/<冒険譚 id>.json に、設定集（lore）と物語（story）のマニフェストを持つ。

const CHRONICLE_ROOT := "res://data/chronicle"

## 全冒険譚のクロニクルデータをまとめて読む。
## 返り値: { campaign_id: { lore: [{ id, unlock }], story: [{ stage, events }] } }
## campaign_id はファイル名（campaign.json の id と一致する規約）。
static func load_all(root: String = CHRONICLE_ROOT) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var campaign_id := file_name.get_basename()
		var data := _load_json("%s/%s" % [root, file_name])
		if data.is_empty():
			continue
		out[campaign_id] = _parse(data)
	return out

## 1冒険譚ぶんのクロニクルデータを読む。無ければ空のデフォルトを返す。
static func load_for(campaign_id: String, root: String = CHRONICLE_ROOT) -> Dictionary:
	var path := "%s/%s.json" % [root, campaign_id]
	if not FileAccess.file_exists(path):
		return { "lore": [], "story": [] }
	var data := _load_json(path)
	if data.is_empty():
		return { "lore": [], "story": [] }
	return _parse(data)

static func _parse(data: Dictionary) -> Dictionary:
	return {
		"lore": _parse_lore(data.get("lore", [])),
		"story": _parse_story(data.get("story", [])),
	}

## 設定集の節リストを正規化。各エントリは { id, unlock: Array }。
static func _parse_lore(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := String(entry.get("id", ""))
		if id.is_empty():
			continue
		var unlock: Variant = entry.get("unlock", [])
		out.append({
			"id": id,
			"unlock": unlock if typeof(unlock) == TYPE_ARRAY else [],
		})
	return out

## 物語のステージリストを正規化。各エントリは { stage, events: Array }。
static func _parse_story(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var stage := String(entry.get("stage", ""))
		if stage.is_empty():
			continue
		var events: Variant = entry.get("events", [])
		out.append({
			"stage": stage,
			"events": events if typeof(events) == TYPE_ARRAY else [],
		})
	return out

static func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data
