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
##   name: String … 表示名（例: "ホーリーアリア"）。表示専用・省略可（name 無しの旧セーブも読める）
##   kind: "buff" | "debuff" … その補正が掛かった側にとって良いものか悪いものか。省略＝"buff"。
##     ピュリファイが落とす対象と、盤の見た目（強化＝黄緑／弱体＝紫）の出し分けがこれを見る。
##     値の符号からは判断しない＝「攻撃は下がるが防御は上がる」ようなスキルで破綻するため。
##     詳細 → doc/gdd/skills.md

const KIND_BUFF := "buff"
const KIND_DEBUFF := "debuff"

## エントリ m が弱体（デバフ）か。kind を持たないエントリは強化扱い。
## 旧セーブは bool の harmful を持つので、そちらも読む（版を上げずに読み続けられる）。
static func is_debuff(m: Dictionary) -> bool:
	if m.has("kind"):
		return String(m.get("kind", KIND_BUFF)) == KIND_DEBUFF
	return bool(m.get("harmful", false))

## mods のうち unit の target（"attack"/"defense"）に効くものを合成する。
## 戻り: { "mul": 掛け合わせ, "add": 足し合わせ }。該当なしは { 1.0, 0.0 }。
static func aggregate(mods: Array, unit: Unit, target: String) -> Dictionary:
	var mul := 1.0
	var add := 0.0
	for m in mods:
		if not applies_to(m, unit):
			continue
		var t := String(m.get("target", "both"))
		if t != "both" and t != target:
			continue
		if String(m.get("op", "mul")) == "mul":
			mul *= float(m.get("value", 1.0))
		else:
			add += float(m.get("value", 0.0))
	return {"mul": mul, "add": add}

## エントリ m が unit 1体に掛かった弱体か（陣営全体のものは含めない）。
## ピュリファイが落とす範囲（BattleState.clear_debuffs）と、敵AIのデバフ本数の上限判定
## （doc/gdd/ai.md §5b skill_stack）が同じ判定を使う＝落とせるものと数えるものがずれない。
static func is_unit_debuff(m: Dictionary, unit: Unit) -> bool:
	return is_debuff(m) and String(m.get("scope", "")) == "unit" and applies_to(m, unit)

## unit 1体に効いている弱体（デバフ）の本数。敵AIの「もう十分弱っている相手には掛けない」
## 判定が使う。スキルの種類では分けない＝別種のデバフも合算する（doc/gdd/ai.md §5b）。
static func debuff_count(mods: Array, unit: Unit) -> int:
	var n := 0
	for m in mods:
		if is_unit_debuff(m, unit):
			n += 1
	return n

## mods のうち unit に効いているエントリをそのまま返す（表示用）。
## aggregate と同じ scope 判定を使う＝画面に出す一覧と実計算が必ず一致する。
## target での絞り込みはしない（攻/防どちらに効くかは各エントリの target を見て表示側が描き分ける）。
static func applied(mods: Array, unit: Unit) -> Array:
	var out: Array = []
	for m in mods:
		if applies_to(m, unit):
			out.append(m)
	return out

## エントリ m が unit に効くか（scope 判定）。集計と表示だけでなく、ピュリファイが落とす対象の
## 選別（BattleState.clear_debuffs）も同じ判定を使う＝ずれない。
static func applies_to(m: Dictionary, unit: Unit) -> bool:
	match String(m.get("scope", "")):
		"team":
			return int(m.get("team", -99)) == unit.team
		"unit":
			return int(m.get("unit_id", -1)) == unit.id
	return false
