extends SceneTree
## 地形 CSV正本 → JSON（headless）。性能(terrain_type)と見た目(terrain_skin)を別ファイルに分離。
## - terrain_type.csv → terrain_type.json（id/char/atk/def＝combat/movement 用）
## - terrain_skin.csv → terrain_skin.json（skin_id/terrain_type/name/orientable＝描画用・案P）
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
## 検証エラーが1件でもあれば、その JSON は書かない（壊れた生成物を残さない）。
##
## 実行: godot --headless --path . --script res://data/terrain/convert.gd

const Csv = preload("res://data/csv_util.gd")

## 性能で必ず要る列（memo は任意）。name/image は skin へ分離済み。
const TYPE_REQUIRED := ["id", "char", "atk", "def", "sight_cost"]
## スキンで必ず要る列（memo は任意）。
const SKIN_REQUIRED := ["skin_id", "terrain_type", "name"]

func _initialize() -> void:
	var type_rows := Csv.read_table("res://data/terrain/terrain_type.csv")
	var skin_rows := Csv.read_table("res://data/terrain/terrain_skin.csv")
	var type_ids := Csv.value_set(type_rows, "id")

	var t := build_type(type_rows)
	if t["json"] == null:
		_report("terrain_type.csv", t["problems"])
	else:
		Csv.write_json("res://data/terrain/terrain_type.json", t["json"])
		print("terrain_type.json: %d terrains" % type_rows.size())

	var s := build_skin(skin_rows, type_ids)
	if s["json"] == null:
		_report("terrain_skin.csv", s["problems"])
	else:
		Csv.write_json("res://data/terrain/terrain_skin.json", s["json"])
		print("terrain_skin.json: %d skins" % skin_rows.size())
	quit()

## 性能表 → { problems, json }。json は { "terrains": rows } 形。id/char 重複・必須列を検証。純関数。
static func build_type(rows: Array) -> Dictionary:
	var problems := Csv.missing_required(rows, TYPE_REQUIRED, "id")
	for v in Csv.duplicates(rows, "id"):
		problems.append("id が重複: '%s'（後勝ち上書きになる）" % v)
	for v in Csv.duplicates(rows, "char"):
		problems.append("char が重複: '%s'（マップ文字→地形の衝突）" % v)
	problems += _invalid_sight_cost(rows)
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	return { "problems": problems, "json": { "terrains": rows } }

## sight_cost 列は「0以上の整数」または `x`（完全遮蔽）だけ許す。視線減衰＝レイキャストの積算コスト。詳細 → doc/gdd/movement.md
static func _invalid_sight_cost(rows: Array) -> Array:
	var problems: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var v: Variant = r.get("sight_cost")
		var ok: bool = (typeof(v) == TYPE_INT and int(v) >= 0) or (typeof(v) == TYPE_STRING and String(v).strip_edges() == "x")
		if not ok:
			problems.append("行[%s] の sight_cost が不正 '%s'（0以上の整数か 'x'）" % [str(r.get("id", i)), str(v)])
	return problems

## スキン表 → { problems, json }。json は { "skins": rows } 形。純関数。
## skin_id 一意・terrain_type 参照整合・orientable の bool・各 type に既定スキン（1枚以上）を検証。
static func build_skin(rows: Array, type_ids: Array) -> Dictionary:
	var problems := Csv.missing_required(rows, SKIN_REQUIRED, "skin_id")
	for v in Csv.duplicates(rows, "skin_id"):
		problems.append("skin_id が重複: '%s'" % v)
	problems += Csv.invalid_values(rows, "terrain_type", type_ids, "skin_id")  # terrain_type に無い性能への参照切れ
	problems += Csv.invalid_values(rows, "orientable", ["true", "false"], "skin_id")  # bool以外（打ち間違い→黙って true 化）を弾く
	# 各 terrain_type に少なくとも1枚のスキン（＝描画のフォールバック先）があること。
	var covered := Csv.value_set(rows, "terrain_type")
	for tid in type_ids:
		if not (tid in covered):
			problems.append("terrain_type '%s' にスキンが1枚も無い（描画フォールバック先が無い）" % tid)
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	return { "problems": problems, "json": { "skins": rows } }

func _report(name: String, problems: Array) -> void:
	for p in problems:
		push_error("%s: %s" % [name, p])
	push_error("%s: 検証エラー %d 件。JSON は更新しない（CSVを直して再実行）" % [name, problems.size()])
