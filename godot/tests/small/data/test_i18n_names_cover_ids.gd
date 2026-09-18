extends GutTest
## データの id が names.csv に表示名キーを持っているか。
## 目的: id 表に行を足したのに names.csv へ足し忘れる漏れを検知する。画面は
##   tr("terrain.{skin_id}.name") のような規約キーで名前を引き、キーが無ければ
##   キー文字列がそのまま出る（未定義キーはキーを返す＝test_i18n.gd）。
## 向き: ここが見るのは「id 表 → names.csv」。逆向き（names.csv → .translation）は
##   test_i18n_translation.gd が見る。2本で id から画面までが繋がる。
## 検査しないこと: id の無い残存キー。キーは追加のみで使い回さない運用のため
##   （→ doc/tech/i18n.md キー命名規約）、古いキーが残っていても害が無い。

const Csv = preload("res://data/csv_util.gd")
const NAMES_CSV := "res://data/i18n/names.csv"

## 表示名キーの系統。prefix.{列の値}.name が names.csv にあることを求める。
## id 表を新設したらここに足す（足さなければ、その表は検査されないまま増える）。
const SOURCES := [
	{ "prefix": "unit", "csv": "res://data/units/unit_skin.csv", "col": "skin_id" },
	{ "prefix": "terrain", "csv": "res://data/terrain/terrain_skin.csv", "col": "skin_id" },
	{ "prefix": "terrain_type", "csv": "res://data/terrain/terrain_type.csv", "col": "id" },
	{ "prefix": "movement", "csv": "res://data/movement/movement.csv", "col": "move_type" },
	{ "prefix": "ai", "csv": "res://data/ai/ai.csv", "col": "ai" },
	# 分類は unit_skin.csv の category 列＝1つの分類を複数のスキンが共有する（値集合で見る）。
	# 味方は兵種（infantry…）・敵は素性（goblin…）だが、画面に出るのはこの列だけなのでキーは1系統。
	# unit_type.csv の category 列は見ない（味方行と一致することは convert が検証する）。
	{ "prefix": "unit_group", "csv": "res://data/units/unit_skin.csv", "col": "category" },
]


## names.csv のキー集合。1行ヘッダ（keys, ja, en）＝データCSVの2行ヘッダとは別の読み方。
func _name_keys() -> Dictionary:
	var f := FileAccess.open(NAMES_CSV, FileAccess.READ)
	assert_not_null(f, "names.csv を開けること")
	if f == null:
		return {}
	f.get_csv_line()  # ヘッダ
	var keys := {}
	while not f.eof_reached():
		var cols := f.get_csv_line()
		if cols.size() == 0 or cols[0] == "":
			continue
		keys[cols[0]] = true
	f.close()
	return keys


func test_names_csv_has_keys() -> void:
	assert_gt(_name_keys().size(), 0, "names.csv にキーがあること")


## 各 id 表の値が prefix.{値}.name を持つこと。欠けていれば、足すべきキーを名指しで落とす。
func test_every_id_has_a_name_key() -> void:
	var keys := _name_keys()
	for src: Dictionary in SOURCES:
		var rows := Csv.read_table(String(src["csv"]))
		assert_gt(rows.size(), 0, "%s に行があること" % src["csv"])
		for id: String in Csv.value_set(rows, String(src["col"])):
			var key := "%s.%s.name" % [src["prefix"], id]
			assert_true(keys.has(key), "%s に %s があること（%s の %s 列）" % [
				NAMES_CSV, key, src["csv"], src["col"]])


## スキルのスキルIDは CSV ではなくコード側の定義が正本（Formation.SKILLS）。
func test_every_skill_has_a_name_key() -> void:
	var keys := _name_keys()
	assert_gt(Formation.SKILLS.size(), 0, "スキルが定義されていること")
	for id: String in Formation.SKILLS.keys():
		var key := "skill.%s.name" % id
		assert_true(keys.has(key), "%s に %s があること（Formation.SKILLS）" % [NAMES_CSV, key])
