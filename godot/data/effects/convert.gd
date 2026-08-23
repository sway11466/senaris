extends SceneTree
## 攻撃エフェクト CSV正本 → コード用JSON の変換（headless）。
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
## 検証エラーが1件でもあれば JSON は書かない（壊れた生成物を残さない）。
##
## 実行: godot --headless --path . --script res://data/effects/convert.gd

const Csv = preload("res://data/csv_util.gd")
const EffectDef = preload("res://data/effects/combat_effect.gd")

## 非空で必ず要る列（memo は任意）。
const REQUIRED := ["effect_id", "name", "kind", "scale"]

func _initialize() -> void:
	var rows := Csv.read_table("res://data/effects/combat_effect.csv")
	var r := build(rows)
	if r["json"] == null:
		_report("combat_effect.csv", r["problems"])
	else:
		Csv.write_json("res://data/effects/combat_effect.json", r["json"])
		print("combat_effect.json: %d effects" % rows.size())
	quit()

## エフェクト表 → { problems, json }。json は { "effects": rows } 形。純関数＝IOなし・テスト容易。
## effect_id 重複・必須列・kind の enum・scale の数値を検証。画像パスは規約で解決するので列に持たない。
static func build(rows: Array) -> Dictionary:
	var problems := Csv.missing_required(rows, REQUIRED, "effect_id")
	for v in Csv.duplicates(rows, "effect_id"):
		problems.append("effect_id が重複: '%s'（後勝ち上書きになる）" % v)
	problems += Csv.invalid_values(rows, "kind", EffectDef.KINDS, "effect_id")  # 打ち間違いが黙って impact に化けるのを防ぐ
	problems += _invalid_scale(rows)
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	return { "problems": problems, "json": { "effects": rows } }

## scale は「0より大きい数値」だけ許す。文字列が混じると float() で 0 に化けて絵が消える。
static func _invalid_scale(rows: Array) -> Array:
	var problems: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var v: Variant = r.get("scale")
		var ok: bool = (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) > 0.0
		if not ok:
			problems.append("行[%s] の scale が不正 '%s'（0より大きい数値）" % [str(r.get("effect_id", i)), str(v)])
	return problems

func _report(name: String, problems: Array) -> void:
	for p in problems:
		push_error("%s: %s" % [name, p])
	push_error("%s: 検証エラー %d 件。JSON は更新しない（CSVを直して再実行）" % [name, problems.size()])
