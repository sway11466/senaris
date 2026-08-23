extends RefCounted
class_name CombatEffectCatalog
## 攻撃エフェクト表(JSON) → effect_id 索引。静的・遅延ロード（TerrainSkinCatalog と同じ流儀）。
## 見た目データなので presentation からのみ引く（domain はエフェクトを知らない＝案P）。

const PATH := "res://data/effects/combat_effect.json"

static var _by_id := {}  # effect_id -> CombatEffect
static var _loaded := false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_error("CombatEffectCatalog: 読み込めない/空: %s" % PATH)
		return
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("CombatEffectCatalog: JSON が不正: %s" % PATH)
		return
	for d in data.get("effects", []):
		var e := CombatEffect.from_dict(d)
		if e.effect_id != "":
			_by_id[e.effect_id] = e

## effect_id からエフェクトを引く。未定義・空文字なら null（＝演出側は既定のスパーク）。
static func by_id(effect_id: String) -> CombatEffect:
	_ensure()
	if effect_id == "":
		return null
	return _by_id.get(effect_id, null)

## 収録エフェクトを全部返す（表全体を舐めたい検査・ツール向け）。
static func all_effects() -> Array:
	_ensure()
	return _by_id.values()
