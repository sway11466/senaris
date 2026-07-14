extends RefCounted
class_name StatusMod
## 状態補正（バフ/デバフ）の集計＝純ロジック・Node非依存・すべて static。
## バフもデバフも1つの器で扱う。詳細 → doc/gdd/combat.md「状態補正（バフ/デバフ・持続）」
##
## 1エントリ ＝ Dictionary:
##   scope: "team" | "unit"（将来 "tile"/"area"）… どのユニットに効くか
##   team:  int（scope=="team" のとき対象陣営）
##   unit_id: int（scope=="unit" のとき対象ユニット）
##   op: "mul" | "add" … 乗算（実効ステータスに係数）／加算（支援と同じ位置）
##   target: "attack" | "defense" | "both"
##   value: float … 1.3=バフ／0.7 等=デバフ（不利な値を入れるだけ）
##   owner_team / remaining: 持続管理（残り自軍ターン数。BattleState.end_turn が減算）

## mods のうち unit の target（"attack"/"defense"）に効くものを合成する。
## 戻り: { "mul": 掛け合わせ, "add": 足し合わせ }。該当なしは { 1.0, 0.0 }。
static func aggregate(mods: Array, unit: Unit, target: String) -> Dictionary:
	var mul := 1.0
	var add := 0.0
	for m in mods:
		if not _applies(m, unit):
			continue
		var t := String(m.get("target", "both"))
		if t != "both" and t != target:
			continue
		if String(m.get("op", "mul")) == "mul":
			mul *= float(m.get("value", 1.0))
		else:
			add += float(m.get("value", 0.0))
	return {"mul": mul, "add": add}

## エントリ m が unit に効くか（scope 判定）。
static func _applies(m: Dictionary, unit: Unit) -> bool:
	match String(m.get("scope", "")):
		"team":
			return int(m.get("team", -99)) == unit.team
		"unit":
			return int(m.get("unit_id", -1)) == unit.id
	return false
