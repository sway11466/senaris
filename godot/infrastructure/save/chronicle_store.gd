extends RefCounted
class_name ChronicleStore
## クロニクルの読み書き（infrastructure 層）。出会ったユニット（skin_id）と
## 見た陣形スキル（レシピ id）を user://chronicle.json に持つ。
## 仕様 → doc/gdd/chronicle.md 記録の持ち方 / doc/tech/gamesystem.md §クロニクル
##
## 他のストアと異なり、record_* は即座に保存しない。盤を離れるとき（決着・中断・
## タイトルへ戻る）に save() を呼んでまとめて書く（gamesystem.md §クロニクル）。
## 壊れていれば空で起動し、遊び直せば埋まるだけ。

const DEFAULT_PATH := "user://chronicle.json"
const VERSION := 1

var _path: String
var _skins := {}    # skin_id -> { "first": campaign_id }
var _recipes := {}  # recipe_id -> { "first": campaign_id }
var _dirty := false # record_* を呼んでから save() するまでの間だけ true

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_load()

## skin_id が記録済みか。
func has_skin(skin_id: String) -> bool:
	return _skins.has(skin_id)

## recipe_id が記録済みか。
func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)

## 記録済みのスキン一覧（コピー）。
func skins() -> Dictionary:
	return _skins.duplicate(true)

## 記録済みのレシピ一覧（コピー）。
func recipes() -> Dictionary:
	return _recipes.duplicate(true)

## スキンを記録する（メモリのみ。save() を呼ぶまでファイルに書かない）。
## 新規なら true、既知または空なら false を返す。
func record_skin(skin_id: String, campaign_id: String) -> bool:
	if skin_id.is_empty() or _skins.has(skin_id):
		return false
	_skins[skin_id] = { "first": campaign_id }
	_dirty = true
	return true

## レシピを記録する（メモリのみ）。新規なら true。
func record_recipe(recipe_id: String, campaign_id: String) -> bool:
	if recipe_id.is_empty() or _recipes.has(recipe_id):
		return false
	_recipes[recipe_id] = { "first": campaign_id }
	_dirty = true
	return true

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
	var out := { "version": VERSION, "skins": _skins, "recipes": _recipes }
	f.store_string(JSON.stringify(out, "  "))
	_dirty = false

# ---------------------------------------------------------------------------

func _load() -> void:
	var result := SaveFile.read(_path, VERSION)
	var status := int(result["status"])
	if status != SaveFile.VALID:
		if status != SaveFile.MISSING:
			push_warning("ChronicleStore: ファイルが不正のため空扱い: %s" % _path)
		return
	var data: Dictionary = result["data"]
	_load_map(data.get("skins", {}), _skins)
	_load_map(data.get("recipes", {}), _recipes)

## { id: { "first": campaign_id } } の辞書を型チェックしながら読む（手編集・破損対策）。
func _load_map(raw: Variant, dest: Dictionary) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for k in raw:
		var v: Variant = raw[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		dest[String(k)] = { "first": String((v as Dictionary).get("first", "")) }
