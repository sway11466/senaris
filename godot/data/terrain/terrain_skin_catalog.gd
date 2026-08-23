extends RefCounted
class_name TerrainSkinCatalog
## 地形スキン表(JSON) → skin_id 索引。静的・遅延ロード（TerrainType と同じ流儀）。
## 詳細 → doc/gdd/terrain.md
##
## スキンは性能(TerrainType)とは別ファイル(data/terrain/terrain_skin.json)で持つ＝見た目のレイヤー。
## skin→type は1:1。地形には決まった絵（型IDと同名のスキン）があり、それが場面にそぐわないときだけ
## ステージが別スキンを当てる（→ doc/gdd/terrain.md）。
## 書いた名前で引けなければ、黙って別の絵で埋めずにエラーにする。
## 見た目データなので presentation からのみ引く（domain は skin を知らない＝案P）。

const PATH := "res://data/terrain/terrain_skin.json"

static var _by_id := {}          # skin_id -> TerrainSkin
static var _loaded := false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_error("TerrainSkinCatalog: 読み込めない/空: %s" % PATH)
		return
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("TerrainSkinCatalog: JSON が不正: %s" % PATH)
		return
	for d in data.get("skins", []):
		var s := TerrainSkin.from_dict(d)
		if s.skin_id == "":
			continue
		_by_id[s.skin_id] = s

## skin_id からスキンを引く（主キー解決）。無ければ null。
static func skin_by_id(skin_id: String) -> TerrainSkin:
	_ensure()
	return _by_id.get(skin_id, null)

## 収録スキンを全部返す（CSV の順は保証しない）。表全体を舐めたい検査・ツール向け。
static func all_skins() -> Array:
	_ensure()
	return _by_id.values()

## セルの見た目を解決：ステージが別スキンを当てていればそれ、書いていなければ地形の決まった絵（型IDと同名）。
## 代替は出さない。引けなければ null を返し、そのセルは描かれない（データの不備として声を上げる）。
static func resolve(skin_id: String, type_id: String) -> TerrainSkin:
	_ensure()
	var key := skin_id if skin_id != "" else type_id
	var s: TerrainSkin = _by_id.get(key, null)
	if s == null:
		push_error("TerrainSkinCatalog: スキンが無い '%s'（地形 '%s'）" % [key, type_id])
	return s
