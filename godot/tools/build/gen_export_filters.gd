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
## 収録リストの項目は冒険譚 ID か、範囲付きの辞書 { id, through }（「このステージまで」）。
## 範囲付きなら範囲外のステージのファイルも除外に足す。マニフェストの差し替えは書き出しプラグイン
## （tools/build/export_plugin/）の仕事で、ここは「範囲付きがあるのにプラグインが無効」を止めるだけ。
## 切り方の答えは BuildContents が1か所で持つ。
##
## 導出するのは「1つのIDが1つのフォルダ」になっている素材だけ（冒険譚の絵とユニットの絵）。
## フラットに並ぶ素材（地形・BGM・効果音ほか）は丸ごと入れる。地形スキンは名前が互いの接頭辞に
## なっていて（plain / plain_fence / plain_grave1 …）、さらに combat_ground・map_ground・connect_to で
## 別のスキンを指すため、フォルダ単位のような素直な線が引けない。

const CONTENTS_PATH := "res://tools/build/contents.json"
const PRESETS_PATH := "res://export_presets.cfg"
const EXPORT_PLUGIN_CFG := "res://tools/build/export_plugin/plugin.cfg"
const STAGES_ROOT := "res://data/stages"
const CHRONICLE_ROOT := "res://data/chronicle"
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

## Steam のビルドにだけ入れるもの。GodotSteam（Steamworks の再配布ファイルを含む）は
## Steam 以外のチャネルでは使わない＝持ち込まない。仕様 → doc/tech/platform.md 置き場
const STEAM_ONLY := [
	"addons/godotsteam/*",
]


func _initialize() -> void:
	var editions := _load_editions()
	if editions.is_empty():
		quit(1)
		return
	_warn_unlisted(editions)
	if not _ranges_are_valid(editions):
		quit(1)
		return

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
		var entries: Array = editions[edition]
		var excluded := _build_exclusions(entries)
		if not "steam" in features.split(","):
			excluded.append_array(PackedStringArray(STEAM_ONLY))
		presets.set_value(section, "exclude_filter", ", ".join(excluded))
		_report(preset_name, edition, entries, excluded)

	err = presets.save(PRESETS_PATH)
	if err != OK:
		printerr("書けない: %s (err %d)" % [PRESETS_PATH, err])
		quit(1)
		return
	print("updated %s" % PRESETS_PATH)
	quit()


## contents.json → { 版: [{ id, through }] }。項目の形が崩れていれば {}＝止める。
func _load_editions() -> Dictionary:
	var raw := BuildContents.load_editions(CONTENTS_PATH)
	if raw.is_empty():
		return {}
	var out := {}
	for e in raw:
		var entries := BuildContents.parse_entries(raw[e])
		if entries.is_empty():
			printerr("版 '%s' の収録リストが不正: %s" % [e, CONTENTS_PATH])
			return {}
		out[e] = entries
	return out


## 範囲付きの項目を確かめる。through がマニフェストに無い／書き出しプラグインが無効なら止める。
## プラグインが無効のままだと、ステージのファイルだけ落ちてマニフェストに残る＝選べない行が出る。
func _ranges_are_valid(editions: Dictionary) -> bool:
	var has_range := false
	for e in editions:
		for entry in editions[e]:
			var through := String(entry["through"])
			if through.is_empty():
				continue
			has_range = true
			var manifest := BuildContents.load_json("%s/%s/campaign.json" % [STAGES_ROOT, String(entry["id"])])
			if BuildContents.kept_stages(manifest, through).is_empty():
				printerr("版 '%s': 冒険譚 '%s' の through '%s' がマニフェストに無い" % [e, entry["id"], through])
				return false
	if not has_range:
		return true
	var enabled: Variant = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	if not (enabled as PackedStringArray).has(EXPORT_PLUGIN_CFG):
		printerr("範囲付きの冒険譚があるのに書き出しプラグインが無効（project.godot の editor_plugins/enabled に %s）" % EXPORT_PLUGIN_CFG)
		return false
	return true


## data/stages にあるのにどの版にも載っていない冒険譚を警告する。
## 収録リスト方式の穴はここ1つ＝作ったのに載せ忘れる。声を出して塞ぐ。
## デバッグ用（campaign.json の debug が真）は載せない前提なので対象外。
func _warn_unlisted(editions: Dictionary) -> void:
	var listed := {}
	for e in editions:
		for entry in editions[e]:
			listed[String(entry["id"])] = true
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


## 収録する冒険譚（[{ id, through }]）→ 除外フィルタの並び。
func _build_exclusions(entries: Array) -> PackedStringArray:
	var keep_campaigns := BuildContents.ranges_of(entries)  # id → through（"" ＝まるごと）

	var out := PackedStringArray(ALWAYS_EXCLUDED)

	for id in _dirs(STAGES_ROOT):
		if id.begins_with(NON_CAMPAIGN_PREFIX):
			continue
		if keep_campaigns.has(id):
			# 途中まで収録＝範囲外のステージの本体と地形を落とす。マニフェストとクロニクルは
			# 書き出しプラグインが差し替えるので、ここでは落とさない。
			var manifest := BuildContents.load_json("%s/%s/campaign.json" % [STAGES_ROOT, id])
			for f in BuildContents.cut_stage_files(manifest, String(keep_campaigns[id])):
				out.append("data/stages/%s/%s" % [id, f])
			continue
		out.append("data/stages/%s/*" % id)
		# クロニクル専用データは冒険譚フォルダの外（data/chronicle/<id>.json）にある。
		if FileAccess.file_exists("%s/%s.json" % [CHRONICLE_ROOT, id]):
			out.append("data/chronicle/%s.json" % id)

	for id in _dirs(CAMPAIGN_ART_ROOT):
		if not keep_campaigns.has(id):
			out.append("assets/campaign/%s/*" % id)

	var keep_skins := _needed_unit_skins(entries)
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
## 途中まで収録する冒険譚は、マニフェストと範囲内のステージのファイルだけ読む＝範囲外にしか出ない駒の絵は落ちる。
func _needed_unit_skins(entries: Array) -> Dictionary:
	var universe := {}
	for skin in _dirs(UNIT_ART_ROOT):
		universe[skin] = true

	var found := {}
	for entry in entries:
		var dir_path := "%s/%s" % [STAGES_ROOT, String(entry["id"])]
		var d := DirAccess.open(dir_path)
		if d == null:
			push_warning("gen_export_filters: 収録リストの冒険譚が無い: %s" % dir_path)
			continue
		var through := String(entry["through"])
		var files := PackedStringArray()
		if through.is_empty():
			for f in d.get_files():
				if f.ends_with(".json"):
					files.append(f)
		else:
			files.append("campaign.json")
			files.append_array(BuildContents.kept_stage_files(BuildContents.load_json(dir_path.path_join("campaign.json")), through))
		for f in files:
			if not FileAccess.file_exists(dir_path.path_join(f)):
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


func _report(preset_name: String, edition: String, entries: Array, excluded: PackedStringArray) -> void:
	var names := PackedStringArray()
	for entry in entries:
		var through := String(entry["through"])
		names.append(String(entry["id"]) if through.is_empty() else "%s(~%s)" % [entry["id"], through])
	print("[%s] edition=%s campaigns=%s" % [preset_name, edition, ", ".join(names)])
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
