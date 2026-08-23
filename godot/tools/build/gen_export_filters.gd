extends SceneTree
## 収録リスト（tools/build/contents.json）から同梱物を導出し、export_presets.cfg の
## 除外フィルタを書き換える。仕様 → doc/tech/build.md
##
##   godot --headless --path godot --script res://tools/build/gen_export_filters.gd
##
## 人が触るのは contents.json だけ。除外を手で書くと、冒険譚が増えたときに行を足し忘れて
## 未公開のものが黙って出荷される。収録リスト側で管理すると、書き忘れた冒険譚は
## ビルドに出てこないだけで済む（気づける方向に倒れる）。
##
## 導出するのは「1つのIDが1つのフォルダ」になっている素材だけ（冒険譚の絵とユニットの絵）。
## フラットに並ぶ素材（地形・BGM・効果音ほか）は丸ごと入れる。地形スキンは名前が互いの接頭辞に
## なっていて（plain / plain_fence / plain_grave1 …）、さらに combat_ground・map_ground・connect_to で
## 別のスキンを指すため、フォルダ単位のような素直な線が引けない。

const CONTENTS_PATH := "res://tools/build/contents.json"
const PRESETS_PATH := "res://export_presets.cfg"
const STAGES_ROOT := "res://data/stages"
const CAMPAIGN_ART_ROOT := "res://assets/campaign"
const UNIT_ART_ROOT := "res://assets/units"

## 冒険譚ではないステージフォルダの接頭辞（_boot＝盤の外周の下敷き）。収録リストの対象外。
const NON_CAMPAIGN_PREFIX := "_"

## どの版にも共通で外す開発専用のもの。
const ALWAYS_EXCLUDED := [
	"tools/*",
	"tests/*",
	"addons/gut/*",
	".gutconfig.json",
]


func _initialize() -> void:
	var editions := _load_editions()
	if editions.is_empty():
		quit(1)
		return
	_warn_unlisted(editions)

	var presets := ConfigFile.new()
	var err := presets.load(PRESETS_PATH)
	if err != OK:
		printerr("読めない: %s (err %d)" % [PRESETS_PATH, err])
		quit(1)
		return

	for section in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var preset_name := String(presets.get_value(section, "name", section))
		var features := String(presets.get_value(section, "custom_features", ""))
		var edition := "demo" if "demo" in features.split(",") else "full"
		if not editions.has(edition):
			printerr("contents.json に版 '%s' が無い（プリセット %s）" % [edition, preset_name])
			quit(1)
			return
		var campaigns: Array = editions[edition]
		var excluded := _build_exclusions(campaigns)
		presets.set_value(section, "exclude_filter", ", ".join(excluded))
		_report(preset_name, edition, campaigns, excluded)

	err = presets.save(PRESETS_PATH)
	if err != OK:
		printerr("書けない: %s (err %d)" % [PRESETS_PATH, err])
		quit(1)
		return
	print("updated %s" % PRESETS_PATH)
	quit()


func _load_editions() -> Dictionary:
	var text := FileAccess.get_file_as_string(CONTENTS_PATH)
	if text.is_empty():
		printerr("読めない/空: %s" % CONTENTS_PATH)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		printerr("JSON が不正: %s" % CONTENTS_PATH)
		return {}
	var editions: Variant = (data as Dictionary).get("editions", {})
	if typeof(editions) != TYPE_DICTIONARY or (editions as Dictionary).is_empty():
		printerr("editions が無い: %s" % CONTENTS_PATH)
		return {}
	return editions


## data/stages にあるのにどの版にも載っていない冒険譚を警告する。
## 収録リスト方式の穴はここ1つ＝作ったのに載せ忘れる。声を出して塞ぐ。
## デバッグ用（campaign.json の debug が真）は載せない前提なので対象外。
func _warn_unlisted(editions: Dictionary) -> void:
	var listed := {}
	for e in editions:
		for c in editions[e]:
			listed[String(c)] = true
	for id in _dirs(STAGES_ROOT):
		if id.begins_with(NON_CAMPAIGN_PREFIX) or listed.has(id):
			continue
		var manifest := "%s/%s/campaign.json" % [STAGES_ROOT, id]
		if not FileAccess.file_exists(manifest):
			continue
		var c := CampaignCatalog.load_file(manifest)
		if c.is_empty() or c["debug"]:
			continue
		push_warning("gen_export_filters: 冒険譚 '%s' がどの版の収録リストにも無い（contents.json）" % id)


## 収録する冒険譚 → 除外フィルタの並び。
func _build_exclusions(campaigns: Array) -> PackedStringArray:
	var keep_campaigns := {}
	for c in campaigns:
		keep_campaigns[String(c)] = true

	var out := PackedStringArray(ALWAYS_EXCLUDED)

	for id in _dirs(STAGES_ROOT):
		if id.begins_with(NON_CAMPAIGN_PREFIX) or keep_campaigns.has(id):
			continue
		out.append("data/stages/%s/*" % id)

	for id in _dirs(CAMPAIGN_ART_ROOT):
		if not keep_campaigns.has(id):
			out.append("assets/campaign/%s/*" % id)

	var keep_skins := _needed_unit_skins(campaigns)
	for skin in _dirs(UNIT_ART_ROOT):
		if not keep_skins.has(skin):
			out.append("assets/units/%s/*" % skin)
	return out


## 収録する冒険譚が使うユニットのスキンID。
##
## JSON のどの欄に skin が書かれているかを追わず、文字列を全部拾って
## 「実在するスキンIDと一致するもの」だけ残す。欄を1つ見落とすと絵が落ちて実行時に壊れるが、
## この形なら見落としようがなく、外れても余計な絵が1つ残るだけ（安全な側に倒れる）。
## skin を省いた駒は type と同名のスキンで描かれる規約なので、type もこの網に掛かる。
func _needed_unit_skins(campaigns: Array) -> Dictionary:
	var universe := {}
	for skin in _dirs(UNIT_ART_ROOT):
		universe[skin] = true

	var found := {}
	for c in campaigns:
		var dir_path := "%s/%s" % [STAGES_ROOT, String(c)]
		var d := DirAccess.open(dir_path)
		if d == null:
			push_warning("gen_export_filters: 収録リストの冒険譚が無い: %s" % dir_path)
			continue
		for f in d.get_files():
			if not f.ends_with(".json"):
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_path.path_join(f)))
			_collect_strings(data, universe, found)
	return found


## 値を再帰で辿り、universe に載っている文字列だけ found に積む。
func _collect_strings(value: Variant, universe: Dictionary, found: Dictionary) -> void:
	match typeof(value):
		TYPE_STRING:
			var s := String(value)
			if universe.has(s):
				found[s] = true
		TYPE_ARRAY:
			for v in (value as Array):
				_collect_strings(v, universe, found)
		TYPE_DICTIONARY:
			for k in (value as Dictionary):
				_collect_strings(k, universe, found)
				_collect_strings((value as Dictionary)[k], universe, found)


func _report(preset_name: String, edition: String, campaigns: Array, excluded: PackedStringArray) -> void:
	print("[%s] edition=%s campaigns=%s" % [preset_name, edition, ", ".join(PackedStringArray(campaigns))])
	for e in excluded:
		print("    - %s" % e)


func _dirs(root: String) -> PackedStringArray:
	var d := DirAccess.open(root)
	if d == null:
		push_warning("gen_export_filters: 開けない: %s" % root)
		return PackedStringArray()
	var out := PackedStringArray(d.get_directories())
	out.sort()
	return out
