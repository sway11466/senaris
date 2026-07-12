extends SceneTree
## 移動タイプ×地形コスト表 CSV正本 → movement.json（headless）。
## CSVは「行=移動タイプ／列=地形コスト」の完全表（差分なし）。x=進入不可。
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
##
## 実行: godot --headless --path . --script res://data/movement/convert.gd

const Csv = preload("res://data/csv_util.gd")

const REQUIRED := ["move_type", "name"]

func _initialize() -> void:
	var rows := Csv.read_table("res://data/movement/movement.csv")
	var terrain_ids := Csv.value_set(Csv.read_table("res://data/terrain/terrain_type.csv"), "id")
	var result := build(rows, terrain_ids)
	if result["json"] == null:
		for p in result["problems"]:
			push_error("movement.csv: %s" % p)
		push_error("movement.csv: 検証エラー %d 件。movement.json は更新しない（CSVを直して再実行）" % result["problems"].size())
	else:
		Csv.write_json("res://data/movement/movement.json", result["json"])
		print("movement.json: %d move types" % result["json"]["movement_types"].size())
	quit()

## movement.csv 行 → { problems, json }。純関数＝IOなし・テスト容易。
## json は { "movement_types": { move_type: { 地形: コスト } }, "move_type_names": { move_type: 表示名 } }。
## コスト表は地形キーだけの純辞書に保ち（Movement.cost の走査を汚さない）、表示名は別辞書で持つ。
## 必須列・move_type重複・列の過不足（完全表）・コスト値（int/x）を検証。問題があれば json は null。
static func build(rows: Array, terrain_ids: Array) -> Dictionary:
	var problems := Csv.missing_required(rows, REQUIRED, "move_type")
	for v in Csv.duplicates(rows, "move_type"):
		problems.append("move_type が重複: '%s'" % v)
	problems += _check_terrain_columns(rows, terrain_ids)
	problems += _check_costs(rows, terrain_ids)
	if not problems.is_empty():
		return { "problems": problems, "json": null }

	var types := {}
	var names := {}
	for r in rows:
		var id := str(r["move_type"])
		names[id] = str(r["name"])  # 表示名（歩行/飛行…）は別辞書へ
		var costs := {}
		for key in r:
			if key != "move_type" and key != "name":  # 識別列は地形コストではない
				costs[key] = r[key]  # int か "x"
		types[id] = costs
	return { "problems": problems, "json": { "movement_types": types, "move_type_names": names } }

## コスト列（move_type/name 以外）が terrain の id と過不足なく一致するか（完全表の担保）。
## 「terrain に無い列」「terrain にあるのに列が無い（新地形の入れ忘れ＝黙ってコスト1になる罠）」を両方拾う。
static func _check_terrain_columns(rows: Array, terrain_ids: Array) -> Array:
	if rows.is_empty():
		return ["行が無い（空表）"]
	var cols := {}
	for k in rows[0]:
		if k != "move_type" and k != "name":
			cols[k] = true
	var problems: Array = []
	for c in cols:
		if not (c in terrain_ids):
			problems.append("コスト列 '%s' が terrain に無い地形" % c)
	for t in terrain_ids:
		if not cols.has(t):
			problems.append("地形 '%s' のコスト列が無い（完全表であるべき）" % t)
	return problems

## 各コストセルが int か "x"（進入不可）のみか。空セル・"y" などの誤記を拾う。
static func _check_costs(rows: Array, terrain_ids: Array) -> Array:
	var problems: Array = []
	for r in rows:
		var mt := str(r.get("move_type", ""))
		for c in terrain_ids:
			if not r.has(c):
				continue  # 列欠落は _check_terrain_columns の担当
			var v: Variant = r[c]
			var okv: bool = typeof(v) == TYPE_INT or (typeof(v) == TYPE_STRING and str(v) == "x")
			if not okv:
				problems.append("[%s] の '%s' コストが不正 '%s'（int か x のみ）" % [mt, c, v])
	return problems
