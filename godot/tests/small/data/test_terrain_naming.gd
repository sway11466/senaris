extends GutTest
## 地形の命名規約を守っているか（→ doc/gdd/terrain.md スキンの命名・doc/art/terrain.md §3.4）。
## 目的: スキンIDを変えたのに元絵フォルダが旧名のまま残る、といった追随漏れを検知する。
##   元絵は .gdignore で Godot が読まない置き場なので、誰も開かないまま何か月も残りうる。
##
## 規約:
##   footing スキン = {型ID} または {型ID}_{持ち味}{連番}
##   object スキン  = {足場スキンID}_{元絵フォルダ名}（フォルダ名は {型ID} または {型ID}_{バリエーション名}）
##   元絵フォルダ   = assets/terrain-src/{フォルダ名}/、中のファイルはフォルダ名で始まる
##
## 検査しないこと: スキンに対応する元絵フォルダが在るか。絵は後から描くので、
##   無いことは欠陥ではない。

const Csv = preload("res://data/csv_util.gd")
const TYPE_CSV := "res://data/terrain/terrain_type.csv"
const SKIN_CSV := "res://data/terrain/terrain_skin.csv"
const SRC_ROOT := "res://assets/terrain-src"

## 通常の項目ではない置き場（アンダースコア始まり）は検査から外す。
const NOT_A_SOURCE_PREFIX := "_"


## 型ID -> layer（footing / object）。
func _layers() -> Dictionary:
	var out := {}
	for r: Dictionary in Csv.read_table(TYPE_CSV):
		out[String(r.get("id", ""))] = String(r.get("layer", ""))
	return out


## スキンID -> 型ID。
func _skins() -> Dictionary:
	var out := {}
	for r: Dictionary in Csv.read_table(SKIN_CSV):
		out[String(r.get("skin_id", ""))] = String(r.get("terrain_type", ""))
	return out


## 足場のスキンIDだけを集める（object スキンの前半に立てる資格があるもの）。
func _footing_ids(skins: Dictionary, layers: Dictionary) -> Array:
	var out: Array = []
	for id: String in skins:
		if layers.get(skins[id], "") == "footing":
			out.append(id)
	return out


## footing スキンは 型ID そのものか、型ID_ で始まること。
func test_footing_skin_id_starts_with_its_type() -> void:
	var layers := _layers()
	var skins := _skins()
	for id: String in skins:
		var t: String = skins[id]
		if layers.get(t, "") != "footing":
			continue
		assert_true(id == t or id.begins_with(t + "_"),
			"footing スキン '%s' は型ID '%s' で始まること" % [id, t])


## object スキンは {実在する足場スキンID}_{自分の型ID}… の形であること。
func test_object_skin_id_is_footing_plus_type() -> void:
	var layers := _layers()
	var skins := _skins()
	var footings := _footing_ids(skins, layers)
	for id: String in skins:
		var t: String = skins[id]
		if layers.get(t, "") != "object":
			continue
		var ok := false
		for f: String in footings:
			if id.begins_with(f + "_" + t):
				ok = true
				break
		assert_true(ok, "object スキン '%s' は {足場スキンID}_%s… の形であること" % [id, t])


## 元絵フォルダ名は、足場スキンIDそのものか、{足場スキンID}_{フォルダ名} が実在する
## object スキンになること。「型IDで始まる」だけでは、足場名を抱えた旧名も通ってしまう。
func test_source_folder_names_follow_the_rule() -> void:
	var layers := _layers()
	var skins := _skins()
	var footings := _footing_ids(skins, layers)
	var d := DirAccess.open(SRC_ROOT)
	assert_not_null(d, "%s を開けること" % SRC_ROOT)
	if d == null:
		return
	var dirs := d.get_directories()
	assert_gt(dirs.size(), 0, "元絵フォルダがあること")
	for name: String in dirs:
		if name.begins_with(NOT_A_SOURCE_PREFIX):
			continue
		var ok: bool = footings.has(name)
		if not ok:
			for f: String in footings:
				var head := f + "_" + name
				for id: String in skins:
					if id == head or id.begins_with(head + "_"):
						ok = true
						break
				if ok:
					break
		assert_true(ok, "元絵フォルダ '%s' は足場スキンIDか、{足場スキンID}_%s のスキンに対応すること" % [name, name])


## フォルダの中のファイルはフォルダ名で始まること（→ doc/art/terrain.md §3.4 の3点セット）。
func test_source_files_are_prefixed_with_their_folder() -> void:
	var d := DirAccess.open(SRC_ROOT)
	assert_not_null(d, "%s を開けること" % SRC_ROOT)
	if d == null:
		return
	for name: String in d.get_directories():
		if name.begins_with(NOT_A_SOURCE_PREFIX):
			continue
		var sub := DirAccess.open("%s/%s" % [SRC_ROOT, name])
		assert_not_null(sub, "%s を開けること" % name)
		if sub == null:
			continue
		for f: String in sub.get_files():
			assert_true(f.begins_with(name + "_"),
				"'%s/%s' はフォルダ名で始まること" % [name, f])
