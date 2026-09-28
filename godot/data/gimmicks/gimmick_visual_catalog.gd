extends RefCounted
class_name GimmickVisualCatalog
## 仕掛けの見た目の表(JSON) → 種類の索引。静的・遅延ロード（CombatEffectCatalog と同じ流儀）。
## 見た目データなので presentation からのみ引く。

const PATH := "res://data/gimmicks/gimmick_visual.json"

static var _by_kind := {}  # kind -> GimmickVisual
static var _loaded := false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_error("GimmickVisualCatalog: 読み込めない/空: %s" % PATH)
		return
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GimmickVisualCatalog: JSON が不正: %s" % PATH)
		return
	for d in data.get("gimmicks", []):
		var v := GimmickVisual.from_dict(d)
		if v.kind != "":
			_by_kind[v.kind] = v

## 種類から見た目を引く。表に無い種類は null（描く側は描かない＝既定の値に倒さない）。
static func by_kind(kind: String) -> GimmickVisual:
	_ensure()
	return _by_kind.get(kind, null)

## 表の種類を全部返す（表とコードの種類の突き合わせ・ツール向け）。
static func all_kinds() -> Array:
	_ensure()
	return _by_kind.keys()
