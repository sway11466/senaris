extends RefCounted
class_name AiCatalog
## AI思考プリセット表(JSON) → { label: プリセット辞書 } の読み込み。詳細 → doc/gdd/ai.md
## data層＝純データのみ（Brain の組立は domain/ai 側＝NearestAttackerBrain.from_preset）。

const AI_PATH := "res://data/ai/ai.json"

## プリセット辞書（{ "presets": { label: {...} } }）→ { label: Dictionary }。
static func build(data: Dictionary) -> Dictionary:
	var presets: Variant = data.get("presets", {})
	return presets if typeof(presets) == TYPE_DICTIONARY else {}

## res:// パスの JSON を読み込んで { label: Dictionary } を返す。失敗時は空。
static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("AiCatalog: 読み込めない/空: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("AiCatalog: JSON が不正: %s" % path)
		return {}
	return build(data)

## 既定のプリセット表（ai.json）を読み込む。
static func load_default() -> Dictionary:
	return load_file(AI_PATH)
