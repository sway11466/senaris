extends SceneTree
## CSV正本 → コード用JSON の変換（headless）。ユニットデータ一式は data/units/ に同居。
## 共通のCSV読み/JSON書きは CsvUtil。生成JSONは手で触らず、CSVを直して再実行する。
##
## 実行: godot --headless --path . --script res://data/units/convert.gd

const Csv = preload("res://data/csv_util.gd")
const SkinDef = preload("res://data/units/unit_skin.gd")

## 非空で必ず要る性能列（category/memo は任意）。
const TYPE_REQUIRED := [
	"id", "atk_ground", "atk_air", "pierce", "defense", "move", "move_type",
	"range", "move_after_attack", "can_capture", "max_troops", "capacity",
]
## スキンの必須列。combat_lineup は既定値を持たせず必ず書かせる（空＝squad の暗黙既定にすると
## 「書き忘れ」と「squad と決めた」が区別できなくなる）。
const SKIN_REQUIRED := ["skin_id", "name", "side", "type_id", "combat_lineup"]
## side は陣営の2値のみ（convert が skins[tid][side] へ振り分けるため他値はNG）。
const SIDES := ["ally", "enemy"]
## 従者リスト（retainers 列）の区切り。CSV なのでカンマは使えない。
const RETAINER_SEP := "|"
## 従者の上限。戦闘演出の隊列は8スロットで、先頭1つは本人が使う（doc/tech/combat_scene.md）。
const RETAINER_MAX := 7

func _initialize() -> void:
	var type_rows := Csv.read_table("res://data/units/unit_type.csv")
	var skin_rows := Csv.read_table("res://data/units/unit_skin.csv")
	var type_ids := Csv.value_set(type_rows, "id")
	var move_types := Csv.value_set(Csv.read_table("res://data/movement/movement.csv"), "move_type")

	var t := build_unit_type(type_rows, move_types)
	if t["json"] == null:
		_report("unit_type.csv", t["problems"])
	else:
		Csv.write_json("res://data/units/unit_type.json", t["json"])
		print("unit_type.json: %d types" % type_rows.size())

	var s := build_unit_skin(skin_rows, type_ids)
	if s["json"] == null:
		_report("unit_skin.csv", s["problems"])
	else:
		Csv.write_json("res://data/units/unit_skin.json", s["json"])
		print("unit_skin.json: %d types" % s["json"]["skins"].size())
	quit()

## ユニット性能表 → { problems, json }。id重複・必須列・move_type参照を検証。純関数＝IOなし・テスト容易。
## problems が空でなければ json は null（＝壊れた生成物を書かせない契約）。json は { "types": rows } 形。
static func build_unit_type(rows: Array, move_types: Array) -> Dictionary:
	var problems := Csv.missing_required(rows, TYPE_REQUIRED, "id")
	for v in Csv.duplicates(rows, "id"):
		problems.append("id が重複: '%s'（後勝ち上書きになる）" % v)
	problems += Csv.invalid_values(rows, "move_type", move_types, "id")  # movement.csv に無い移動タイプ＝黙ってコスト1の罠
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	return { "problems": problems, "json": { "types": rows } }

## スキン表（1行=1別名: skin_id, side, type_id, name, category, combat_lineup, retainers）→ { problems, json }。純関数。
## 同じ (type_id, side) の行は出現順にエイリアス配列へ。description/images は空（後で拡張）。
## category は管理分類（基準/ゴブリン/…）＝参考データとして JSON にも持つ。
## skin は見た目レイヤー（案P）＝category をゲームロジックから参照しないこと（ツール・図鑑用）。
## combat_lineup は戦闘演出での並べ方（squad/retinue/single）＝スキンごとに人が決める（性能から導かない）。
## retainers は戦闘演出で本人の脇に並べる別スキン（'|' 区切り・retinue のときだけ）。→ doc/tech/combat_scene.md
## side/combat_lineup enum・skin_id重複・type_id参照・retainers参照・必須列を検証。problems があれば json は null。
static func build_unit_skin(rows: Array, type_ids: Array) -> Dictionary:
	var problems := Csv.missing_required(rows, SKIN_REQUIRED, "skin_id")
	problems += Csv.invalid_values(rows, "side", SIDES, "skin_id")
	problems += Csv.invalid_values(rows, "combat_lineup", SkinDef.LINEUPS, "skin_id")
	problems += Csv.invalid_values(rows, "type_id", type_ids, "skin_id")  # unit_type に無い性能への参照切れ
	for v in Csv.duplicates(rows, "skin_id"):
		problems.append("skin_id が重複: '%s'" % v)
	problems += _retainer_problems(rows)
	if not problems.is_empty():
		return { "problems": problems, "json": null }
	var skins := {}
	for r in rows:
		var tid := str(r["type_id"])
		var side := str(r["side"])
		if not skins.has(tid):
			skins[tid] = { "ally": [], "enemy": [] }
		skins[tid][side].append({
			"skin_id": str(r.get("skin_id", "")), "type_id": tid,
			"name": str(r["name"]), "category": str(r.get("category", "")),
			"description": "", "images": {},
			"combat_lineup": str(r.get("combat_lineup", "")), "retainers": parse_retainers(r),
		})
	return { "problems": problems, "json": { "skins": skins } }

## retainers セル → skin_id の配列。空セル・空要素は落とす。純関数。
static func parse_retainers(row: Dictionary) -> Array:
	var out := []
	for part in str(row.get("retainers", "")).split(RETAINER_SEP):
		var id := part.strip_edges()
		if not id.is_empty():
			out.append(id)
	return out

## retainers の検証：実在しない skin_id への参照（＝黙って絵が出ない罠）・隊列に入り切らない数・
## combat_lineup との噛み合わせ（retinue なのに従者が無い／retinue でないのに従者が書いてある＝どちらも
## 意図と表示がずれたまま黙って通る）。
static func _retainer_problems(rows: Array) -> Array:
	var known := Csv.value_set(rows, "skin_id")
	var out := []
	for r in rows:
		var label := str(r.get("skin_id", ""))
		var lineup := str(r.get("combat_lineup", "")).strip_edges()
		var list := parse_retainers(r)
		if lineup == SkinDef.LINEUP_RETINUE and list.is_empty():
			out.append("'%s': combat_lineup が retinue なのに retainers が空（従者を書くか squad にする）" % label)
		if lineup != SkinDef.LINEUP_RETINUE and not list.is_empty():
			out.append("'%s': combat_lineup が '%s' なのに retainers が書いてある（retinue 以外では使わない）" % [label, lineup])
		if list.size() > RETAINER_MAX:
			out.append("'%s': retainers が %d 個（上限 %d＝隊列8のうち先頭は本人）" % [label, list.size(), RETAINER_MAX])
		for id in list:
			if not known.has(id):
				out.append("'%s': retainers が未定義の skin_id を指している: '%s'" % [label, id])
	return out

func _report(name: String, problems: Array) -> void:
	for p in problems:
		push_error("%s: %s" % [name, p])
	push_error("%s: 検証エラー %d 件。JSON は更新しない（CSVを直して再実行）" % [name, problems.size()])
