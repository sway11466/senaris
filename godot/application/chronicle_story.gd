extends RefCounted
class_name ChronicleStory
## クロニクルの「会話／イベント」＝会話の通し読みの並びを組み立てる（application 層）。
## マニフェスト（data/chronicle/<冒険譚>.json の story）の並びを背骨に、進捗の記録で
## 経験した会話だけを残した段（1ステージ＝1段）の列を作る。本文（行）は chapter_talks で解く。
## 仕様 → doc/gdd/chronicle.md 会話／イベント
##
## 出す会話は最後に遊んだ回＝進捗セーブの記録（CampaignProgress.story）。
## 拠点の取得／喪失（once で捨て合うイベントの組）だけは、冒険譚をまたいで溜まる ChronicleStore の
## 記録で両方を経験したかを見て、並べる組（options）を持たせる。
## 仲間の台詞（when: joined:<actor>）は出し分けない＝仲間は居る前提で常に出す。

## 段の盤の絵の置き場。1段＝ステージ id で1枚（<ステージ id>_map.png）。置かれたものだけを拾う。
const MAP_ROOT := "res://assets/chronicle"

## 冒険譚1本ぶんの段の列を読む（ファイルを読む側）。
## story_manifest＝ChronicleLoader が正規化した story（[{ stage, events }]）。
## campaign＝CampaignProgress.campaign() の辞書（stages が id / title / path を持つ）。
## store＝経験したイベントを冒険譚をまたいで溜めた記録（取得／喪失の両方を経験したかを見る）。
static func load(campaign_id: String, story_manifest: Array, campaign: Dictionary,
		progress: CampaignProgress, store: ChronicleStore) -> Array:
	var stages := {}
	for entry in story_manifest:
		var sid := String((entry as Dictionary).get("stage", ""))
		if sid.is_empty() or stages.has(sid):
			continue
		var s := _find_stage(campaign, sid)
		if s.is_empty():
			continue  # 冒険譚に無いステージ＝build が警告する
		var path := String(s["path"])
		var seen: Array = store.story(campaign_id, sid).get("events", []) if store != null else []
		stages[sid] = {
			"title": String(s.get("title", sid)),
			"path": path,
			"cleared": progress.stage_state(campaign_id, sid) == CampaignProgress.CLEARED,
			"record": progress.story(campaign_id, sid),
			"seen_events": seen,
			"event_talks": StageLoader.load_event_talks(path),
		}
	return build(campaign_id, story_manifest, stages)

## 段の列を組み立てる（純ロジック）。
## stages＝{ stage_id: { title, path, cleared, record, seen_events, event_talks } }。
## - 段の並びはマニフェスト順。未クリアのステージまで出してそこで終わる
##   （決着の会話が無い＝物語がそこまで）。
## - 段のなかの会話は 開幕 → イベント（マニフェスト順）→ 決着。記録に在るものだけ。
## - 記録の無いステージ（仕組みより前のクリア）は見出しと盤だけで会話なし。
## - 一度も遊んでいないステージは段ごと出さない＝見ていない出来事の存在を匂わせない。
static func build(campaign_id: String, story_manifest: Array, stages: Dictionary) -> Array:
	var out: Array = []
	for entry in story_manifest:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid := String((entry as Dictionary).get("stage", ""))
		if not stages.has(sid):
			push_warning("ChronicleStory[%s]: story の stage '%s' が冒険譚に無い" % [campaign_id, sid])
			continue
		var info: Dictionary = stages[sid]
		var record: Dictionary = info["record"]
		var cleared: bool = bool(info["cleared"])
		if not cleared and record.is_empty():
			break  # 一度も遊んでいない＝ここから先は物語が無い
		out.append({
			"stage": sid,
			"title": String(info["title"]),
			"path": String(info["path"]),
			"map": map_path(campaign_id, sid),
			"talks": _talks(campaign_id, sid, (entry as Dictionary).get("events", []),
					record, info.get("seen_events", []), info["event_talks"]),
		})
		if not cleared:
			break  # 未クリア＝決着の会話が無い。物語はここまで
	return out

## 段の会話を本文つきで解く。台本は仲間が全員居る前提で組む（when: joined:<actor> の行は全部出す）。
## 本文の無い会話（台本が消えた・全行落ちた）は落とす＝空の会話を出さない。
## 返り値: [{ key, phase, event, lines, options }]（phase＝intro／event／outro）
##   options＝両方を経験した取得／喪失の組 [{ event, captured_by, lines }]（マニフェスト順。組でなければ空）。
##   options があれば画面は lines の代わりに組の両方を並べる。
static func chapter_talks(chapter: Dictionary) -> Array:
	var data := StageLoader.read_stage(String(chapter["path"]))
	var script := StageLoader.parse_dialogue(data, all_joined_roster(data))
	var out: Array = []
	for raw in chapter.get("talks", []):
		var talk: Dictionary = raw
		var lines: Array = script.get(String(talk["key"]), [])
		var options: Array = []
		for opt in talk.get("options", []):
			var opt_lines: Array = script.get(String((opt as Dictionary)["key"]), [])
			if opt_lines.is_empty():
				continue
			options.append({ "event": String(opt["event"]), "captured_by": String(opt["captured_by"]),
					"lines": opt_lines })
		if options.size() < 2:
			options = []
		if lines.is_empty():
			continue
		out.append({
			"key": String(talk["key"]),
			"phase": String(talk.get("phase", "")),
			"event": String(talk["event"]),
			"lines": lines,
			"options": options,
		})
	return out

## 台本の when に出てくる仲間を全員在籍させた名簿（parse_dialogue に渡す形）。
## 仲間の台詞は出し分けず常に出す（doc/gdd/chronicle.md 分岐の扱い）。
static func all_joined_roster(data: Dictionary) -> Array:
	var actors := {}
	var dlg: Variant = data.get("dialogue", {})
	if typeof(dlg) == TYPE_DICTIONARY:
		for phase in (dlg as Dictionary):
			var lines: Variant = dlg[phase]
			if typeof(lines) != TYPE_ARRAY:
				continue
			for line in lines:
				if typeof(line) != TYPE_DICTIONARY:
					continue
				var cond := String((line as Dictionary).get("when", "")).strip_edges()
				if cond.begins_with("joined:"):
					actors[cond.substr("joined:".length()).strip_edges()] = true
	var out: Array = []
	for a in actors:
		out.append({ "actor": String(a) })
	return out

## 段の盤の絵のパス。置かれていなければ空＝盤の無い段は会話だけ。
static func map_path(campaign_id: String, stage_id: String) -> String:
	var path := "%s/%s/%s_map.png" % [MAP_ROOT, campaign_id, stage_id]
	return path if ResourceLoader.exists(path) else ""

# ---------------------------------------------------------------------------

## 段のなかの会話の並び。開幕（開始の記録が在れば）→ イベント → 決着（クリアの記録が在れば）。
## イベントの順はマニフェスト＝書き手が持つ。記録に在ってマニフェストに無いものは出さない
## （並びを決められないため）＝データの誤りとして警告する。
## 最後に遊んだ回で起きたイベントが once の組なら、組のうち経験したもの（seen_events）を
## 並べる組（options・マニフェスト順）に入れる。
static func _talks(campaign_id: String, stage_id: String, manifest_events: Variant,
		record: Dictionary, seen_events: Array, event_talks: Dictionary) -> Array:
	var out: Array = []
	if record.has("start"):
		out.append({ "key": "intro", "phase": "intro", "event": "", "options": [] })
	var fired: Array = record.get("events", [])
	var listed: Array = []
	if typeof(manifest_events) == TYPE_ARRAY:
		for raw in manifest_events:
			listed.append(String(raw))
	for event_id in listed:
		if not fired.has(event_id):
			continue  # 最後に遊んだ回で起きていない＝流れに出さない（組の相手なら options で出る）
		var talk: Dictionary = event_talks.get(event_id, {})
		if talk.is_empty():
			push_warning("ChronicleStory[%s/%s]: イベント '%s' の台本が無い"
					% [campaign_id, stage_id, event_id])
			continue
		out.append({
			"key": String(talk["dialogue"]), "phase": "event", "event": event_id,
			"options": _options(event_id, listed, seen_events, event_talks),
		})
	for event_id in fired:
		if not listed.has(String(event_id)):
			push_warning("ChronicleStory[%s/%s]: 起きたイベント '%s' が story の events に無い"
					% [campaign_id, stage_id, event_id])
	if record.has("clear"):
		out.append({ "key": "outro", "phase": "outro", "event": "", "options": [] })
	return out

## once の組のうち経験したものを並べる組にする（自分を含む・マニフェスト順）。
## 1つだけ（組でない・相手を経験していない）なら空＝経験したほうだけを出す。
static func _options(event_id: String, listed: Array, seen_events: Array,
		event_talks: Dictionary) -> Array:
	var group := String((event_talks[event_id] as Dictionary).get("once", ""))
	if group.is_empty():
		return []
	var out: Array = []
	for other in listed:
		var talk: Dictionary = event_talks.get(other, {})
		if talk.is_empty() or String(talk.get("once", "")) != group:
			continue
		if other != event_id and not seen_events.has(other):
			continue
		out.append({ "event": other, "key": String(talk["dialogue"]),
				"captured_by": String(talk.get("captured_by", "")) })
	return out if out.size() >= 2 else []

## 冒険譚のステージ表から1件引く（無ければ空）。
static func _find_stage(campaign: Dictionary, stage_id: String) -> Dictionary:
	for s in campaign.get("stages", []):
		if typeof(s) == TYPE_DICTIONARY and String((s as Dictionary).get("id", "")) == stage_id:
			return s
	return {}
