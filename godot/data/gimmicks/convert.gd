extends SceneTree
## 仕掛けの見た目 CSV正本 → JSON の変換（headless）。
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
## 検証エラーが1件でもあれば JSON は書かない（壊れた生成物を残さない）。
## 種類がコードの定義（GimmickKinds）と一致するかは、data が domain を見られないので
## テスト（test_data_integrity）で突き合わせる。
##
## 実行: godot --headless --path . --script res://data/gimmicks/convert.gd

const Csv = preload("res://data/csv_util.gd")

## 非空で必ず要る列（combat_scale・memo は任意）。
const REQUIRED := ["kind", "name", "map_scale", "foot_z"]

func _initialize() -> void:
	var rows := Csv.read_table("res://data/gimmicks/gimmick_visual.csv")
	var r := build(rows)
	if r["json"] == null:
		_report("gimmick_visual.csv", r["problems"])
	else:
		Csv.write_json("res://data/gimmicks/gimmick_visual.json", r["json"])
		print("gimmick_visual.json: %d kinds" % rows.size())
	quit()

## 見た目の表 → { problems, json }。json は { "gimmicks": rows } 形。純関数＝IOなし・テスト容易。
## 空を既定値に倒さない＝書き忘れが「大きさ0」「寄せ0」に化けて黙って出るのを防ぐ。
static func build(rows: Array) -> Dictionary:
	var problems := Csv.missing_required(rows, REQUIRED, "kind")
	for v in Csv.duplicates(rows, "kind"):
		problems.append("kind が重複: '%s'（後勝ち上書きになる）" % v)
	problems += _invalid_number(rows, "map_scale", true, false)
	problems += _invalid_number(rows, "foot_z", false, false)
	problems += _invalid_number(rows, "combat_scale", true, true)
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	return { "problems": problems, "json": { "gimmicks": rows } }

## col は数値だけ許す。positive なら 0 以下も弾き、そうでなければ負だけ弾く。blank_ok なら空も許す。
static func _invalid_number(rows: Array, col: String, positive: bool, blank_ok: bool) -> Array:
	var problems: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var v: Variant = r.get(col)
		var who := str(r.get("kind", i))
		if blank_ok and (v == null or (typeof(v) == TYPE_STRING and String(v).strip_edges() == "")):
			continue
		var num: bool = typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
		if not num:
			problems.append("行[%s] の %s が数値でない '%s'" % [who, col, str(v)])
		elif positive and float(v) <= 0.0:
			problems.append("行[%s] の %s が不正 '%s'（0より大きい数値）" % [who, col, str(v)])
		elif float(v) < 0.0:
			problems.append("行[%s] の %s が不正 '%s'（0以上の数値）" % [who, col, str(v)])
	return problems

func _report(name: String, problems: Array) -> void:
	for p in problems:
		push_error("%s: %s" % [name, p])
	push_error("%s: 検証エラー %d 件。JSON は更新しない（CSVを直して再実行）" % [name, problems.size()])
