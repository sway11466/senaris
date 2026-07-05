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
	_convert_ai()
	quit()

## ai.csv → { "presets": { label: {engage, sight, retreat, attack, target, advance} } }。
## 全軸そろい検証つき（共有 Csv.missing_required）: 1件でも欠け/空があれば ai.json は更新しない。
func _convert_ai() -> void:
	var rows := Csv.read_table("res://data/ai/ai.csv")
	var problems := Csv.missing_required(rows, REQUIRED_AXES, "label")
	for p in problems:
		push_error("ai.csv: %s（`-`＝該当なし を明示すること）" % p)
	var errors := problems.size()
	for r in rows:
		if str(r.get("label", "")).strip_edges().is_empty():
			push_error("ai.csv: label が空の行がある")
			errors += 1
	if errors > 0:
		push_error("ai.csv: 検証エラー %d 件。ai.json は更新しない（CSVを直して再実行）" % errors)
		return
	var presets := {}
	for r in rows:
		var label := str(r["label"])
		var p := {}
		for key in r:
			if key != "label":
				p[key] = r[key]
		presets[label] = p
	Csv.write_json("res://data/ai/ai.json", { "presets": presets })
	print("ai.json: %d presets" % presets.size())
