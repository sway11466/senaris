extends SceneTree
## 地形 CSV正本 → JSON（headless）。性能(terrain_type)と見た目(terrain_skin)を別ファイルに分離。
## - terrain_type.csv → terrain_type.json（id/char/atk/def＝combat/movement 用）
## - terrain_skin.csv → terrain_skin.json（skin_id/terrain_type/name/orientable＝描画用・案P）
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
## 検証エラーが1件でもあれば、その JSON は書かない（壊れた生成物を残さない）。
##
## 実行: godot --headless --path . --script res://data/terrain/convert.gd

const Csv = preload("res://data/csv_util.gd")
## 値の正解集合（ORIENTS ほか）はモデル側が正本。ここで文字列を二重に持たない。
const SkinDef = preload("res://data/terrain/terrain_skin.gd")

## 性能で必ず要る列（memo は任意）。name/image は skin へ分離済み。
const TYPE_REQUIRED := ["id", "name", "layer", "char", "atk", "def", "sight_cost"]
## 地形の層（→ doc/gdd/terrain.md）。足場＝面や線で敷くもの／オブジェクト＝点として置くもの。
const LAYERS := ["footing", "object"]
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

	var s := build_skin(skin_rows, type_rows)
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
	problems += Csv.invalid_values(rows, "layer", LAYERS, "id")
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
## skin_id 一意・terrain_type 参照整合・列の値域・オブジェクトの足場指定を検証。
static func build_skin(rows: Array, type_rows: Array) -> Dictionary:
	var type_ids := Csv.value_set(type_rows, "id")
	var problems := Csv.missing_required(rows, SKIN_REQUIRED, "skin_id")
	for v in Csv.duplicates(rows, "skin_id"):
		problems.append("skin_id が重複: '%s'" % v)
	problems += Csv.invalid_values(rows, "terrain_type", type_ids, "skin_id")  # terrain_type に無い性能への参照切れ
	# orientable は多値: none(散らさない) / flip(左右反転だけ) / full(回転＋反転)。旧データの
	# true/false は「回してよいか」しか言えず flip と区別できないので弾く（→ TerrainSkin.ORIENTS）。
	problems += Csv.invalid_values(rows, "orientable", SkinDef.ORIENTS, "skin_id")
	# connect は多値: line(柵＝線) / area(道＝面) / false(繋がらない)。旧データの true は曖昧なので弾く。
	problems += Csv.invalid_values(rows, "connect", ["line", "area", "false"], "skin_id")
	problems += Csv.invalid_values(rows, "grid", ["true", "false"], "skin_id")
	problems += _invalid_amount(rows, "elevation")   # 打ち間違いが「高さ0」に化けて黙って平らになるのを防ぐ
	problems += _invalid_amount(rows, "sprite_sink")
	# 戦闘演出の地面（→ doc/tech/combat_scene.md）。下地は実在スキンだけ・置き方は既知の語だけ。
	# 盤の重ね（map_ground＝下地 / map_overlay＝絵を借りる先）はどちらも skin_id への参照。
	problems += Csv.invalid_values(rows, "map_ground", Csv.value_set(rows, "skin_id"), "skin_id")
	problems += Csv.invalid_values(rows, "map_overlay", Csv.value_set(rows, "skin_id"), "skin_id")
	problems += Csv.invalid_values(rows, "combat_ground", Csv.value_set(rows, "skin_id"), "skin_id")
	problems += Csv.invalid_values(rows, "combat_layout", ["fill", "line", "center"], "skin_id")
	# オブジェクトは足場の上に置く＝下に敷く足場（map_ground）を必ず書く。空を許すと
	# 「足場の書いていないオブジェクト」ができ、描く側が既定を勝手に決めることになる。
	problems += _object_without_ground(rows, type_rows)
	# 足場は型IDと同名のスキンを1枚持つ（ステージが指定しないセルはこれを引く）。
	# オブジェクトは足場を名前に含む＝同名は存在しないので、ステージが必ず指定する。
	problems += _footing_without_same_name_skin(rows, type_rows)
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	return { "problems": problems, "json": { "skins": rows } }

## layer が object の地形タイプに属するスキンで、map_ground（下に敷く足場）が空の行。
static func _object_without_ground(rows: Array, type_rows: Array) -> Array:
	var layer_of := {}
	for t in type_rows:
		layer_of[String(t.get("id", ""))] = String(t.get("layer", ""))
	var problems: Array = []
	for r in rows:
		if layer_of.get(String(r.get("terrain_type", "")), "") != "object":
			continue
		if String(r.get("map_ground", "")).strip_edges() == "":
			problems.append("行[%s] は object なのに map_ground（下に敷く足場）が空" % String(r.get("skin_id", "")))
	return problems

## layer が footing の地形タイプで、型IDと同名のスキンが無いもの。
static func _footing_without_same_name_skin(rows: Array, type_rows: Array) -> Array:
	var skin_ids := Csv.value_set(rows, "skin_id")
	var problems: Array = []
	for t in type_rows:
		var id := String(t.get("id", ""))
		if String(t.get("layer", "")) != "footing":
			continue
		if not (id in skin_ids):
			problems.append("足場 '%s' に同名のスキンが無い（指定なしのセルが引けない）" % id)
	return problems

## 見た目の量（elevation / sprite_sink）は「0以上の数値」だけ許す。文字列が混じると float() で 0 に化けて黙って平らになる。
static func _invalid_amount(rows: Array, col: String) -> Array:
	var problems: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var v: Variant = r.get(col)
		var ok: bool = (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) >= 0.0
		if not ok:
			problems.append("行[%s] の %s が不正 '%s'（0以上の数値）" % [str(r.get("skin_id", i)), col, str(v)])
	return problems

func _report(name: String, problems: Array) -> void:
	for p in problems:
		push_error("%s: %s" % [name, p])
	push_error("%s: 検証エラー %d 件。JSON は更新しない（CSVを直して再実行）" % [name, problems.size()])
