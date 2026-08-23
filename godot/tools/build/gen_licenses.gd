extends SceneTree
## 配布物に添えるライセンス文（THIRD-PARTY-LICENSES.txt）を組む。仕様 → doc/tech/build.md
##
##   godot --headless --path godot --script res://tools/build/gen_licenses.gd
##
## 集める先は2か所。
##   Godot 本体と、Godot が同梱している第三者 … エンジンのバイナリに埋まっている（3つのAPI）
##   本作が使う素材                          … 素材の隣の <名前>-NOTICE.txt と <名前>-LICENSE.txt
##
## 素材を足すときはスクリプトを触らない。NOTICE と LICENSE を素材の隣に置けば次から拾う。
## 書き出し先は assets/licenses/ で、生成物をコミットする（差分で何が増えたか読めるように）。
## 走らせるのは Godot のバージョンを上げたときと、義務のある素材を足したとき。

const OUT_PATH := "res://assets/licenses/THIRD-PARTY-LICENSES.txt"
const ASSETS_ROOT := "res://assets"
const RULE := "--------------------------------------------------------------------------------"


func _initialize() -> void:
	var out := PackedStringArray()
	out.append_array(_header())
	out.append_array(_godot_sections())
	out.append_array(_asset_sections())

	var text := "\n".join(out)
	var dir := OUT_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("書けない: %s (err %d)" % [OUT_PATH, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("wrote %s (%d bytes)" % [OUT_PATH, text.length()])
	quit()


func _header() -> PackedStringArray:
	var name := String(ProjectSettings.get_setting("application/config/name", "Game"))
	return PackedStringArray([
		"%s — Third-party licenses" % name,
		RULE,
		"",
		"This file lists the third-party software and assets distributed with this game,",
		"together with the license texts they require. It is generated from the engine's",
		"own license data and from the license files stored next to each asset.",
		"",
	])


## Godot 本体の MIT と、Godot が同梱している第三者の一覧・ライセンス全文。
## get_license_text() は本体の分だけで、同梱分は get_copyright_info / get_license_info が持つ。
func _godot_sections() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(_section("Godot Engine", Engine.get_license_text().strip_edges()))

	var used := {}   # ライセンス名 -> true（実際に参照されたものだけ全文を載せる）
	var lines := PackedStringArray()
	for entry in Engine.get_copyright_info():
		var comp := String(entry.get("name", ""))
		if comp.is_empty():
			continue
		var holders := PackedStringArray()
		var licenses := PackedStringArray()
		for part in entry.get("parts", []):
			for c in part.get("copyright", []):
				var line := "Copyright (c) %s" % String(c)
				if not (line in holders):
					holders.append(line)
			var lic := String(part.get("license", ""))
			if not lic.is_empty() and not (lic in licenses):
				licenses.append(lic)
			for token in _license_tokens(lic):
				used[token] = true
		lines.append(comp)
		for h in holders:
			lines.append("    " + h)
		if not licenses.is_empty():
			lines.append("    License: " + ", ".join(licenses))
		lines.append("")
	out.append_array(_section("Components bundled in Godot Engine", "\n".join(lines).strip_edges()))

	var info := Engine.get_license_info()
	var names := used.keys()
	names.sort()
	for n in names:
		if not info.has(n):
			continue
		out.append_array(_section("License text: %s" % n, String(info[n]).strip_edges()))
	return out


## "Expat and Zlib" のような複合表記をライセンス名に割る（get_license_info のキーに合わせる）。
func _license_tokens(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in raw.replace(" and ", ",").replace(" or ", ",").split(","):
		var s := String(t).strip_edges()
		if not s.is_empty():
			out.append(s)
	return out


## 素材の権利ファイル。<名前>-NOTICE.txt を索引にして、対の <名前>-LICENSE.txt を添える。
## NOTICE が索引なのは、著作権表記こそが「誰の成果物か」を示す本体だから
## （Apache 2.0 の全文は著作権者名がテンプレートのままで、単体では誰の物か分からない）。
## 見出しは NOTICE の1行目＝表示名はファイル名ではなく素材側が決める（"Rock Salt" と書ける）。
func _asset_sections() -> PackedStringArray:
	var out := PackedStringArray()
	var notices := _find_notices(ASSETS_ROOT)
	notices.sort()
	for notice_path in notices:
		var base := notice_path.trim_suffix("-NOTICE.txt")
		var notice := _read(notice_path).strip_edges().split("\n", false)
		var title := String(notice[0]).strip_edges() if notice.size() > 0 else base.get_file()
		var body := "\n".join(notice.slice(1)).strip_edges()
		var license_path := base + "-LICENSE.txt"
		if FileAccess.file_exists(license_path):
			body += "\n\n" + _read(license_path).strip_edges()
		else:
			push_warning("gen_licenses: %s に対応する -LICENSE.txt が無い" % notice_path)
		out.append_array(_section(title, body))
	if notices.is_empty():
		push_warning("gen_licenses: assets 以下に -NOTICE.txt が1つも無い")
	return out


## assets 以下を走査して -NOTICE.txt を集める。.gdignore のフォルダ（元素材）は配布物でないので入らない。
func _find_notices(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	if FileAccess.file_exists(root.path_join(".gdignore")):
		return out
	for f in dir.get_files():
		if f.ends_with("-NOTICE.txt"):
			out.append(root.path_join(f))
	for sub in dir.get_directories():
		out.append_array(_find_notices(root.path_join(sub)))
	return out


func _section(title: String, body: String) -> PackedStringArray:
	return PackedStringArray([RULE, title, RULE, "", body, "", ""])


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("読めない: %s" % path)
		return ""
	var s := f.get_as_text()
	f.close()
	return s
