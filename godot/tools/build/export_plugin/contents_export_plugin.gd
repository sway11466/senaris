@tool
extends EditorExportPlugin
## 冒険譚を途中まで収録する版のために、pck に詰める瞬間にマニフェストを差し替える。
## 仕様 → doc/tech/build.md 冒険譚の途中まで収録する
##
## 差し替えるのは2つ。どちらも手元のファイルは書き換えない（skip して同じパスに別の中身を add_file）。
##   data/stages/<冒険譚ID>/campaign.json   … 範囲外のステージを「id と full_only だけの殻」にする
##   data/chronicle/<冒険譚ID>.json         … 範囲外のステージの story と、それを条件に持つ lore を削る
## 範囲外のステージのファイル自体は除外フィルタが落とす（gen_export_filters.gd）。
## 切り方の答えは BuildContents が1か所で持ち、ここは Godot の書き出しに繋ぐだけ。

const CONTENTS_PATH := "res://tools/build/contents.json"
const STAGES_ROOT := "res://data/stages"
const CHRONICLE_ROOT := "res://data/chronicle"

## この書き出しで範囲を持つ冒険譚 → through（ステージID）。_export_begin で埋め、_export_end で空にする。
var _ranges := {}


func _get_name() -> String:
	return "SenarisBuildContents"


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_ranges = {}
	var edition := "demo" if features.has("demo") else "full"
	var editions := BuildContents.load_editions(CONTENTS_PATH)
	if editions.is_empty():
		push_error("ContentsExportPlugin: 収録リストが読めない＝差し替えなしで進む: %s" % CONTENTS_PATH)
		return
	var ranges := BuildContents.ranges_of(BuildContents.parse_entries(editions.get(edition, [])))
	for id in ranges:
		if not String(ranges[id]).is_empty():
			_ranges[id] = String(ranges[id])
	if _ranges.is_empty():
		return
	print("[export_plugin] edition=%s 途中まで収録する冒険譚: %s" % [edition, JSON.stringify(_ranges)])


func _export_end() -> void:
	_ranges = {}


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _ranges.is_empty():
		return
	if path.begins_with(STAGES_ROOT + "/") and path.get_file() == "campaign.json":
		var id := path.get_base_dir().get_file()
		if _ranges.has(id):
			_replace_manifest(path, id, String(_ranges[id]))
	elif path.begins_with(CHRONICLE_ROOT + "/") and path.ends_with(".json"):
		var id := path.get_file().get_basename()
		if _ranges.has(id):
			_replace_chronicle(path, id, String(_ranges[id]))


func _replace_manifest(path: String, id: String, through: String) -> void:
	var manifest := BuildContents.load_json(path)
	var stubbed := BuildContents.stub_manifest(manifest, through)
	if stubbed.is_empty():
		# through が無い等。gen_export_filters.gd が先に止めているはずだが、ここでも黙って元のまま入れない。
		push_error("ContentsExportPlugin[%s]: マニフェストを切れない（through '%s'）＝元のまま入れる" % [id, through])
		return
	_swap(path, stubbed)
	var total := (manifest.get("stages", []) as Array).size()
	var kept := BuildContents.kept_stage_ids(manifest, through).size()
	print("[export_plugin] %s: stages %d（%s まで）＋ 製品版だけの殻 %d" % [path, kept, through, total - kept])


func _replace_chronicle(path: String, id: String, through: String) -> void:
	var manifest := BuildContents.load_json("%s/%s/campaign.json" % [STAGES_ROOT, id])
	var kept_ids := BuildContents.kept_stage_ids(manifest, through)
	if kept_ids.is_empty():
		push_error("ContentsExportPlugin[%s]: クロニクルを切れない（through '%s'）＝元のまま入れる" % [id, through])
		return
	var chronicle := BuildContents.load_json(path)
	var trimmed := BuildContents.trim_chronicle(chronicle, kept_ids)
	_swap(path, trimmed)
	print("[export_plugin] %s: story %d → %d・lore %d → %d" % [path,
			(chronicle.get("story", []) as Array).size(), (trimmed.get("story", []) as Array).size(),
			(chronicle.get("lore", []) as Array).size(), (trimmed.get("lore", []) as Array).size()])


## 元のファイルを飛ばし、同じパスに差し替えた中身を詰める。
func _swap(path: String, content: Dictionary) -> void:
	skip()
	add_file(path, JSON.stringify(content, "  ").to_utf8_buffer(), false)
