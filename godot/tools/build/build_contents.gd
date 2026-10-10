extends RefCounted
class_name BuildContents
## 収録リスト（tools/build/contents.json）の読み方と、冒険譚を途中まで収録するときの切り方（純ロジック）。
## 仕様 → doc/tech/build.md 冒険譚の途中まで収録する
##
## 除外フィルタを起こす gen_export_filters.gd と、pck に詰める瞬間にマニフェストを差し替える
## 書き出しプラグイン（export_plugin/）が同じ答えを出すための1か所。ここは Godot の
## ファイルやエディタに触らず、辞書を受けて辞書を返すだけ＝GUT で直接確かめる。

## 範囲外のステージの殻に立てる印。CampaignCatalog が読み、製品版だけの話として扱う。
const FULL_ONLY_KEY := "full_only"
## 収録リストの項目（辞書形）で範囲を書く欄＝「このステージまで」。
const THROUGH_KEY := "through"
## ステージ本体の相棒＝地形ファイルの綴り（StageLoader.TERRAIN_SUFFIX と同じ）。
const TERRAIN_SUFFIX := ".terrain.json"


## 版の項目列（contents.json の editions.<版>）→ [{ id: String, through: String }]。
## 文字列の項目は冒険譚まるごと（through ""）。辞書の項目は id と through を持つ。
## 形の崩れた項目が1つでもあれば push_error して []＝呼び手はビルドを止める（黙って捨てると
## その冒険譚が出荷から落ちるだけで気づけない）。
static func parse_entries(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		push_error("BuildContents: 版の項目列が配列でない")
		return []
	var out: Array = []
	var seen := {}
	for item in (raw as Array):
		var entry := {}
		match typeof(item):
			TYPE_STRING:
				entry = { "id": String(item), "through": "" }
			TYPE_DICTIONARY:
				var d := item as Dictionary
				entry = { "id": String(d.get("id", "")), "through": String(d.get(THROUGH_KEY, "")) }
				if entry["id"].is_empty():
					push_error("BuildContents: 辞書の項目に id が無い: %s" % JSON.stringify(d))
					return []
			_:
				push_error("BuildContents: 項目は文字列か辞書: %s" % str(item))
				return []
		if seen.has(entry["id"]):
			push_error("BuildContents: 冒険譚 '%s' が同じ版に2回ある" % entry["id"])
			return []
		seen[entry["id"]] = true
		out.append(entry)
	return out


## 収録する冒険譚 ID → through の辞書（まるごとは ""）。parse_entries の結果を引きやすい形にしたもの。
static func ranges_of(entries: Array) -> Dictionary:
	var out := {}
	for e in entries:
		out[String(e["id"])] = String(e["through"])
	return out


## マニフェスト（campaign.json の生 JSON 辞書）から、収録するステージ項目をマニフェスト順で返す。
## through ""＝全部。through がマニフェストに無ければ push_error して []（黙って全部入れない）。
static func kept_stages(manifest: Dictionary, through: String) -> Array:
	var raw: Variant = manifest.get("stages", [])
	if typeof(raw) != TYPE_ARRAY:
		push_error("BuildContents[%s]: stages が配列でない" % String(manifest.get("id", "?")))
		return []
	var stages := raw as Array
	if through.is_empty():
		return stages.duplicate()
	var out: Array = []
	for s in stages:
		out.append(s)
		if typeof(s) == TYPE_DICTIONARY and String((s as Dictionary).get("id", "")) == through:
			return out
	push_error("BuildContents[%s]: through '%s' がマニフェストに無い" % [String(manifest.get("id", "?")), through])
	return []


## 収録するステージの ID 列（マニフェスト順）。
static func kept_stage_ids(manifest: Dictionary, through: String) -> Array:
	var out: Array = []
	for s in kept_stages(manifest, through):
		if typeof(s) == TYPE_DICTIONARY:
			out.append(String((s as Dictionary).get("id", "")))
	return out


## 範囲外のステージのファイル名（冒険譚フォルダからの相対）。本体と地形の対。
## through ""（まるごと）や through が無いときは []＝落とすものなし。
static func cut_stage_files(manifest: Dictionary, through: String) -> PackedStringArray:
	var out := PackedStringArray()
	if through.is_empty():
		return out
	var kept := kept_stages(manifest, through)
	if kept.is_empty():
		return out
	# kept はマニフェストの先頭からの範囲＝その後ろが落とす側。
	for s in (manifest["stages"] as Array).slice(kept.size()):
		out.append_array(_stage_files(s))
	return out


## 収録するステージのファイル名（本体と地形の対）。ユニットの絵の導出が読む対象。
static func kept_stage_files(manifest: Dictionary, through: String) -> PackedStringArray:
	var out := PackedStringArray()
	for s in kept_stages(manifest, through):
		out.append_array(_stage_files(s))
	return out


static func _stage_files(stage: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(stage) != TYPE_DICTIONARY:
		return out
	var file := String((stage as Dictionary).get("file", ""))
	if file.is_empty():
		return out
	out.append(file)
	out.append(file.get_basename() + TERRAIN_SUFFIX)
	return out


## 差し替え後の campaign.json 辞書。範囲内のステージはそのまま、範囲外のステージは
## 「id と full_only だけの殻」にする＝話の数は製品版と同じまま、題名・あらすじ・ファイル名・
## 解放条件・名簿の出どころは落ちる。一覧には同じ数の札が並び、殻は常に裏返しで出る。
## through ""＝元のまま。through が無ければ {}＝呼び手は止める。元の辞書は書き換えない。
static func stub_manifest(manifest: Dictionary, through: String) -> Dictionary:
	if through.is_empty():
		return manifest.duplicate(true)
	var kept := kept_stages(manifest, through)
	if kept.is_empty():
		return {}
	var out := manifest.duplicate(true)
	var stages: Array = kept.duplicate(true)
	for s in (manifest["stages"] as Array).slice(kept.size()):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		stages.append({ "id": String((s as Dictionary).get("id", "")), FULL_ONLY_KEY: true })
	out["stages"] = stages
	return out


## 差し替え後のクロニクル辞書（data/chronicle/<冒険譚ID>.json）。
## story＝stage が kept_ids に無い項目を削る（殻の話は物語を持たない）。
## lore＝unlock のどれかが kept_ids に無い stage を指す項目を削る（体験版では永久に開かない節を出さない）。
## stage を指さない条件（campaign_cleared 等）は触らない。
static func trim_chronicle(chronicle: Dictionary, kept_ids: Array) -> Dictionary:
	var out := chronicle.duplicate(true)
	var story: Variant = out.get("story", [])
	if typeof(story) == TYPE_ARRAY:
		var kept_story: Array = []
		for entry in (story as Array):
			if typeof(entry) == TYPE_DICTIONARY and not kept_ids.has(String((entry as Dictionary).get("stage", ""))):
				continue
			kept_story.append(entry)
		out["story"] = kept_story
	var lore: Variant = out.get("lore", [])
	if typeof(lore) == TYPE_ARRAY:
		var kept_lore: Array = []
		for entry in (lore as Array):
			if typeof(entry) == TYPE_DICTIONARY and _refers_cut_stage((entry as Dictionary).get("unlock", []), kept_ids):
				continue
			kept_lore.append(entry)
		out["lore"] = kept_lore
	return out


static func _refers_cut_stage(unlock: Variant, kept_ids: Array) -> bool:
	if typeof(unlock) != TYPE_ARRAY:
		return false
	for cond in (unlock as Array):
		if typeof(cond) != TYPE_DICTIONARY:
			continue
		var ref := String((cond as Dictionary).get("stage", ""))
		if not ref.is_empty() and not kept_ids.has(ref):
			return true
	return false


## contents.json を読んで editions 辞書を返す。失敗は {}（呼び手が止める）。
static func load_editions(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("BuildContents: 読めない/空: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("BuildContents: JSON が不正: %s" % path)
		return {}
	var editions: Variant = (data as Dictionary).get("editions", {})
	if typeof(editions) != TYPE_DICTIONARY or (editions as Dictionary).is_empty():
		push_error("BuildContents: editions が無い: %s" % path)
		return {}
	return editions


## JSON ファイルを辞書として読む。失敗は {}。
static func load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	return data if typeof(data) == TYPE_DICTIONARY else {}
