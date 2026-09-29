extends RefCounted
class_name GimmickKinds
## 仕掛けの種類の定義（状態の一覧・固有の要素・踏んだときの振る舞い）。種類ごとに形が違うので
## コードに持つ（陣形スキルの定義と同じ流儀）。種類を足すときは KINDS に1件と、振る舞いの分岐を足す。
## 詳細 → doc/gdd/gimmicks.md カタログ

## 種類 id → { states: 選べる状態, params: 必須の固有の要素（ステージ JSON のキー）,
## glow: 床を光らせる状態 → 光の色（光らせない種類は空＝隠れている罠は光らせない） }。
## glow はどの状態が「作動している」かという振る舞いなのでここに持つ（doc/gdd/gimmicks.md 絵）。
const KINDS := {
	"production_switch": { "states": ["on", "off"], "params": ["base"],
		"glow": { "on": Color("#C85750") } },  # 箱の正面の紋の赤
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

## 拠点 base_hex の生産を止めているか（生産装置のスイッチが off）。
static func blocks_production(g: Gimmick, base_hex: Vector2i) -> bool:
	if g.kind != "production_switch" or g.state != "off":
		return false
	var b: Variant = g.params.get("base")
	return typeof(b) == TYPE_VECTOR2I and b == base_hex  # 型違いの == は実行時エラー＝先に型を見る
