extends RefCounted
class_name TerrainType
## 地形の性能カタログ（データ駆動・静的）。詳細 → doc/gdd/combat.md（地形効果）, doc/gdd/movement.md
##
## 地形は **文字列id**（"plain"/"plateau"/"forest"…）で識別。定義は data/terrain/terrain_type.json
## （正本は terrain_type.csv）。地形を増やす＝terrain_type.csv に1行＋movement.csv に1列（コード不変）。
## 戦闘の攻/防係数・ASCII文字を持つ。移動コストは Movement（movement.csv）側。
## 見た目（表示名・タイル画像・回転可否）は分離＝TerrainSkin/TerrainSkinCatalog が担う（refactoring-2・案P）。
## terrain id はそのまま movement 表の地形キー・既定スキンのidになる。

const PATH := "res://data/terrain/terrain_type.json"
const DEFAULT_ID := "plain"  ## 未設定マスの既定地形
const SIGHT_OPAQUE := 1 << 20  ## `x`（完全遮蔽）の視線コスト＝どんな sight でも越えられない大きな値
const SIGHT_DEFAULT := 1       ## 未定義地形の視線コスト（＝開地・距離1相当）

static var _defs := {}         # id -> { atk, def, char }
static var _char_to_id := {}   # ASCII文字 -> id
static var _loaded := false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_error("TerrainType: 読み込めない/空: %s" % PATH)
		return
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("TerrainType: JSON が不正: %s" % PATH)
		return
	for t in data.get("terrains", []):
		var id := String(t["id"])
		_defs[id] = t
		_char_to_id[String(t.get("char", ""))] = id

## 地形(攻)係数（不明idは1.0）。
static func attack_factor(id: String) -> float:
	_ensure()
	return float(_defs.get(id, {}).get("atk", 1.0))

## 地形(防)係数（不明idは1.0）。
static func defense_factor(id: String) -> float:
	_ensure()
	return float(_defs.get(id, {}).get("def", 1.0))

## 地形の視線コスト（索敵レイキャストの積算コスト）。`x`＝完全遮蔽＝SIGHT_OPAQUE。
## 全地形1なら「累積コスト＝ヘックス距離」＝純距離の索敵に一致。詳細 → doc/gdd/movement.md（視線）
static func sight_cost(id: String) -> int:
	_ensure()
	var v: Variant = _defs.get(id, {}).get("sight_cost", SIGHT_DEFAULT)
	if typeof(v) == TYPE_STRING:
		return SIGHT_OPAQUE if String(v).strip_edges() == "x" else SIGHT_DEFAULT
	return int(v)

## { 地形id: 視線コスト } の表（BattleState への注入用＝domain を data 非依存に保つ。movement 表と同型）。
static func sight_cost_table() -> Dictionary:
	_ensure()
	var out := {}
	for id in _defs:
		out[id] = sight_cost(id)
	return out

## ステージのASCII文字 → 地形id（未定義文字は既定地形）。
static func char_to_id(ch: String) -> String:
	_ensure()
	return _char_to_id.get(ch, DEFAULT_ID)

## 定義済みの全地形id。
static func all_ids() -> Array:
	_ensure()
	return _defs.keys()
