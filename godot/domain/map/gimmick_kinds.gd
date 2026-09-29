extends RefCounted
class_name GimmickKinds
## 仕掛けの種類の定義（状態の一覧・固有の要素・踏んだときの振る舞い）。種類ごとに形が違うので
## コードに持つ（陣形スキルの定義と同じ流儀）。種類を足すときは KINDS に1件と、振る舞いの分岐を足す。
## 詳細 → doc/gdd/gimmicks.md カタログ

# --- 罠 ---
# 状態は 隠れている（絵なし）→ 見つかった（全種類で1枚の印）→ 種類ごとの発動後。
# 撃つ側は兵数 TRAP_TROOPS・補正なし、受ける側はふだんどおり（Combat.trap_hit_detail）。

const HIDDEN := "hidden"  ## 隠れている＝何も描かない
const FOUND := "found"    ## 見つかった＝印を描く
const SPENT := "spent"    ## 撃ち終えた（一度きりの罠）＝もう撃たない・何も描かない
const TRAP_TROOPS := 8    ## 罠の一撃の兵数（罠は兵数を持たない＝満員として計算する）

## 種類 id → { states: 選べる状態, params: 必須の固有の要素（ステージ JSON のキー）,
## glow: 床を光らせる状態 → 光の色（光らせない種類は空＝隠れている罠は光らせない） }。
## glow はどの状態が「作動している」かという振る舞いなのでここに持つ（doc/gdd/gimmicks.md 絵）。
## 罠は trap を持つ＝踏んだときに撃つ一撃の値（上記 罠）。
const KINDS := {
	"production_switch": { "states": ["on", "off"], "params": ["base"],
		"glow": { "on": Color("#C85750") } },  # 箱の正面の紋の赤
	# ダメージの罠（doc/gdd/gimmicks.md 罠・カタログ）。値は仮（調整は実プレイで）。
	"thunder_sigil": { "states": [HIDDEN, FOUND], "params": [], "glow": {},  # 雷の紋＝魔法・踏むたびに撃つ
		"trap": { "atk_ground": 40, "atk_air": 40, "pierce": 0.5, "radius": 0, "after": FOUND } },
	"landmine": { "states": [HIDDEN, FOUND, SPENT], "params": [], "glow": {},  # 地雷＝機械・隣まで・一度きり
		"trap": { "atk_ground": 40, "atk_air": 20, "pierce": 0.0, "radius": 1, "after": SPENT } },
}

## 種類が定義されているか。
static func has_kind(kind: String) -> bool:
	return KINDS.has(kind)

## 種類の選べる状態。未知の種類は空。
static func states(kind: String) -> Array:
	return (KINDS.get(kind, {}) as Dictionary).get("states", [])

## 種類が必須とする固有の要素のキー。未知の種類は空。
static func params(kind: String) -> Array:
	return (KINDS.get(kind, {}) as Dictionary).get("params", [])

## g の今の状態で床を光らせる色。光らせない状態なら null。
static func glow_color(g: Gimmick) -> Variant:
	var glow: Dictionary = (KINDS.get(g.kind, {}) as Dictionary)["glow"]
	return glow.get(g.state, null)

## team の駒が g を踏んだら、次にどの状態になるか。変わらなければ ""。状態は変えない
## ＝コマンドメニューの言い換え（「スイッチ停止」）と、実際に踏んだときの両方がこれを引く。
static func state_after_step(g: Gimmick, team: int) -> String:
	match g.kind:
		"production_switch":  # 味方が踏むと止め、敵が踏むと再開する（doc/gdd/gimmicks.md 生産装置のスイッチ）
			if team == 0 and g.state == "on":
				return "off"
			if team == 1 and g.state == "off":
				return "on"
	return ""

## 種類が罠か（踏むと撃つ）。
static func is_trap(kind: String) -> bool:
	return (KINDS.get(kind, {}) as Dictionary).has("trap")

## 罠の一撃の値 { atk_ground, atk_air, pierce, radius, after }。罠でなければ空。
static func trap_spec(kind: String) -> Dictionary:
	return (KINDS.get(kind, {}) as Dictionary).get("trap", {})

## g が今踏まれたら撃つか（罠で、撃ち終えていない）。
static func trap_armed(g: Gimmick) -> bool:
	return is_trap(g.kind) and g.state != SPENT

## 撃った後の状態（雷の紋＝見つかった扱い、地雷＝撃ち終えた）。
static func state_after_trap(g: Gimmick) -> String:
	return String(trap_spec(g.kind)["after"])

## 盤に描く絵の名前（assets/gimmicks/{これ}.png）。見つかった罠は種類によらず1枚の印を使う。
## 隠れている罠は名前を返すが絵を置かない＝何も描かない（doc/gdd/gimmicks.md 見え方）。
static func art_stem(g: Gimmick) -> String:
	if is_trap(g.kind) and g.state == FOUND:
		return "trap_found"
	return "%s_%s" % [g.kind, g.state]

## 拠点 base_hex の生産を止めているか（生産装置のスイッチが off）。
static func blocks_production(g: Gimmick, base_hex: Vector2i) -> bool:
	if g.kind != "production_switch" or g.state != "off":
		return false
	var b: Variant = g.params.get("base")
	return typeof(b) == TYPE_VECTOR2I and b == base_hex  # 型違いの == は実行時エラー＝先に型を見る
