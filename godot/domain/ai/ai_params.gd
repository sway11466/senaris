extends RefCounted
class_name AiParams
## 敵AIのパラメーター解決（純ロジック・Node非依存）。
## 駒（部隊）や拠点の特性idと、sight / stack / retreat の値を「部隊の上書き ＞ 特性の既定」の順で引き、
## ai.json の混ざった型（int と "*"・"-" の String）を数に読み替える。読み替えの規則はここだけが知る。
## 詳細 → doc/gdd/ai.md（特性の書き方・データ構成）

## 部隊が未知の値・特性なしのときに使う特性id（常時起動・前へ出る）。
const DEFAULT_TRAIT := "charge"

## sight `*`（上限なし）の視線予算。盤のどの距離にも届き、かつ壁（TerrainType.SIGHT_OPAQUE＝1<<20）
## 1枚で必ず遮られる大きさ。「上限なし・ただし壁は遮る」を1つの数で表す（doc/gdd/ai.md データ構成）。
const SIGHT_UNLIMITED := 1 << 16

## stack `-`（上限なし）。強化・弱体では常に成立し、解除では1本以上あれば成立する。
const NO_LIMIT := -1

## retreat `-`（使わない）＝損耗率がこの値に届くことはない。
const RETREAT_NEVER := 101

## 特性表（特性id -> { name, sight, stack }＝AiCatalog.load_default()）。特性の既定値の出どころ。
var presets := {}

## 実装済みの特性id（TraitBrain が持つ特性の一覧）。部隊の ai がここに無ければ DEFAULT_TRAIT。
var known_traits: Array[String] = []

func _init(p_known_traits: Array[String]) -> void:
	known_traits = p_known_traits

# --- 駒（部隊）のパラメーター ---

## u の特性id。部隊に属さない駒・未知の特性は DEFAULT_TRAIT。
func trait_id_of(state: BattleState, u: Unit) -> String:
	return _resolve_trait(String(state.squad_of(u.handle).get("ai", "")))

## u のパラメーター（解決順＝部隊の上書き ＞ 特性の既定）。どちらにも無ければ "-"（該当なし）。
func param(state: BattleState, u: Unit, key: String) -> Variant:
	var squad := state.squad_of(u.handle)
	if squad.has(key):
		return squad[key]
	return preset_param(trait_id_of(state, u), key)

## 特性の既定パラメーター。特性表に無ければ "-"。
func preset_param(trait_id: String, key: String) -> Variant:
	var p: Dictionary = presets.get(trait_id, {})
	return p.get(key, "-")

## u の視線予算（sight）。
func sight_of(state: BattleState, u: Unit) -> int:
	return sight_budget(param(state, u, "sight"))

## u の stack 上限（本数）。NO_LIMIT＝上限なし。
func stack_limit_of(state: BattleState, u: Unit) -> int:
	return stack_limit(param(state, u, "stack"))

## u の退く損耗率の閾値（retreat）。RETREAT_NEVER＝使わない。
func retreat_percent_of(state: BattleState, u: Unit) -> int:
	return retreat_percent(param(state, u, "retreat"))

# --- 拠点のパラメーター（部隊の ai を拠点hex基準で使う。doc/gdd/ai.md 拠点出撃） ---

## 拠点の特性id（部隊の ai）。未設定・未知は DEFAULT_TRAIT。
func base_trait_id(state: BattleState, b: Base) -> String:
	if b.squad_index < 0 or b.squad_index >= state.squads.size():
		return DEFAULT_TRAIT
	return _resolve_trait(String((state.squads[b.squad_index] as Dictionary).get("ai", "")))

## 拠点のパラメーター解決: 部隊の上書き ＞ 特性の既定。部隊未設定は "-"。
func base_param(state: BattleState, b: Base, key: String) -> Variant:
	if b.squad_index < 0 or b.squad_index >= state.squads.size():
		return "-"
	var squad: Dictionary = state.squads[b.squad_index]
	if squad.has(key):
		return squad[key]
	return preset_param(base_trait_id(state, b), key)

## 拠点の視線予算（sight）。
func base_sight_of(state: BattleState, b: Base) -> int:
	return sight_budget(base_param(state, b, "sight"))

# --- 値の読み替え（ai.json は型が混ざるので typeof で分ける） ---

## 視線の予算に読み替える。数値はそのまま／"*"＝上限なし／それ以外（"-"＝その特性は使わない）は0。
static func sight_budget(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return maxi(int(v), 0)
	return SIGHT_UNLIMITED if String(v) == "*" else 0

## stack の本数に読み替える。数値はそのまま／それ以外（"-"）は NO_LIMIT＝上限なし。
static func stack_limit(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return maxi(int(v), 0)
	return NO_LIMIT

## retreat を損耗率の閾値に読み替える。数値はそのまま（0〜100）、"-"＝使わない＝RETREAT_NEVER。
static func retreat_percent(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return clampi(int(v), 0, 100)
	return RETREAT_NEVER

func _resolve_trait(id: String) -> String:
	return id if id in known_traits else DEFAULT_TRAIT
