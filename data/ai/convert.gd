extends SceneTree
## AI思考プリセット CSV正本 → ai.json（headless）。詳細 → doc/gdd/ai.md
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
##
## 実行: godot --headless --path . --script res://data/ai/convert.gd

const Csv = preload("res://data/csv_util.gd")

## 各プリセットが非空で必ず持つべき思考の軸（doc/gdd/ai.md「既定と省略のポリシー」）。
## CSVは省略不可＝`-`（該当なし）も値として埋める。欠け/空セルはデータのバグとして生成を止める。
const REQUIRED_AXES := ["engage", "sight", "retreat", "attack", "target", "advance"]

func _initialize() -> void:
	var rows := Csv.read_table("res://data/ai/ai.csv")
	var result := build_presets(rows)
	if result["json"] == null:
		for p in result["problems"]:
			push_error("ai.csv: %s" % p)
		push_error("ai.csv: 検証エラー %d 件。ai.json は更新しない（CSVを直して再実行）" % result["problems"].size())
	else:
		Csv.write_json("res://data/ai/ai.json", result["json"])
		print("ai.json: %d presets" % result["json"]["presets"].size())
	quit()

## ai.csv 行 → { problems, json }。json は { "presets": { label: {engage, sight, retreat, attack, target, advance} } }。
## 全軸そろい検証つき（共有 Csv.missing_required）＋ label 空行の検出: 1件でも欠け/空があれば json は null。純関数。
static func build_presets(rows: Array) -> Dictionary:
	var problems := []
	for p in Csv.missing_required(rows, REQUIRED_AXES, "label"):
		problems.append("%s（`-`＝該当なし を明示すること）" % p)
	for i in rows.size():
		if str(rows[i].get("label", "")).strip_edges().is_empty():
			problems.append("行[%d] の label が空" % i)
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	var presets := {}
	for r in rows:
		var label := str(r["label"])
		var p := {}
		for key in r:
			if key != "label":
				p[key] = r[key]
		presets[label] = p
	return { "problems": problems, "json": { "presets": presets } }
