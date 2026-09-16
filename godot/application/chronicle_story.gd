extends RefCounted
class_name ChronicleStory
## クロニクルの「物語」＝会話の通し読みの並びを組み立てる（application 層）。
## マニフェスト（data/chronicle/<冒険譚>.json の story）の並びを背骨に、進捗の記録で
## 経験した会話だけを残した章の列を作る。本文（行）は読むときに chapter_talks で解く。
## 仕様 → doc/gdd/chronicle.md 物語
##
## 出す会話は最後に遊んだ回で固定＝進捗セーブの記録（CampaignProgress.story）を見る。
## 冒険譚をまたいで溜まる ChronicleStore の記録は見ない（両方を経験した箇所の切り替えは別件）。

## 章の挿絵の置き場。1章＝ステージ id で1枚。置かれたものだけを拾う。
const ART_ROOT := "res://assets/chronicle"

## 冒険譚1本ぶんの章の列を読む（ファイルを読む側）。
## story_manifest＝ChronicleLoader が正規化した story（[{ stage, events }]）。
## campaign＝CampaignProgress.campaign() の辞書（stages が id / title / path を持つ）。
static func load(campaign_id: String, story_manifest: Array, campaign: Dictionary,
		progress: CampaignProgress) -> Array:
	var stages := {}
	for entry in story_manifest:
		var sid := String((entry as Dictionary).get("stage", ""))
		if sid.is_empty() or stages.has(sid):
			continue
		var s := _find_stage(campaign, sid)
		if s.is_empty():
			continue  # 冒険譚に無いステージ＝build が警告する
		var path := String(s["path"])
		stages[sid] = {
			"title": String(s.get("title", sid)),
			"path": path,
			"cleared": progress.stage_state(campaign_id, sid) == CampaignProgress.CLEARED,
			"record": progress.story(campaign_id, sid),
			"event_talks": StageLoader.load_event_talks(path),
		}
	return build(campaign_id, story_manifest, stages)

## 章の列を組み立てる（純ロジック）。
## stages＝{ stage_id: { title, path, cleared, record, event_talks } }。
## - 章の並びはマニフェスト順。未クリアのステージまで出してそこで終わる
##   （決着の会話が無い＝物語がそこまで）。
## - 章のなかの会話は 開幕 → イベント（マニフェスト順）→ 決着。記録に在るものだけ。
## - 記録の無いステージ（仕組みより前のクリア）は章題だけで会話なし。
## - 一度も遊んでいないステージは章ごと出さない＝見ていない出来事の存在を匂わせない。
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
			"art": art_path(campaign_id, sid),
			"talks": _talks(campaign_id, sid, (entry as Dictionary).get("events", []),
					record, info["event_talks"]),
		})
		if not cleared:
			break  # 未クリア＝決着の会話が無い。物語はここまで
	return out

## 章の会話を本文つきで解く。開幕・イベントは開始時の顔ぶれ、決着はクリア後の顔ぶれで
## 台本を組み直す＝会話の when が見るのは在籍だけ（StoryDirector の読み直しと同じ規約）。
## 本文の無い会話（台本が消えた・when で全行落ちた）は落とす＝空の板を出さない。
## 返り値: [{ key, event, lines }]
static func chapter_talks(chapter: Dictionary) -> Array:
	var scripts := {}  # "start" / "clear" -> 台本（読むのは1章につき最大2回）
	var out: Array = []
	for talk in chapter.get("talks", []):
		var phase := String((talk as Dictionary)["phase"])
		var by := "clear" if phase == "outro" else "start"
		if not scripts.has(by):
			scripts[by] = StageLoader.load_dialogue(String(chapter["path"]),
					_as_roster((talk as Dictionary)["actors"]))
		var lines: Array = (scripts[by] as Dictionary).get(String((talk as Dictionary)["key"]), [])
		if lines.is_empty():
			continue
		out.append({
			"key": String((talk as Dictionary)["key"]),
			"event": String((talk as Dictionary)["event"]),
			"lines": lines,
		})
	return out

## 章の挿絵のパス。置かれていなければ空＝絵の無い章は暗幕だけで読ませる。
static func art_path(campaign_id: String, stage_id: String) -> String:
	var path := "%s/%s/%s.png" % [ART_ROOT, campaign_id, stage_id]
	return path if ResourceLoader.exists(path) else ""

# ---------------------------------------------------------------------------

## 章のなかの会話の並び。開幕（開始の記録が在れば）→ イベント → 決着（クリアの記録が在れば）。
## イベントの順はマニフェスト＝書き手が持つ。記録に在ってマニフェストに無いものは出さない
## （並びを決められないため）＝データの誤りとして警告する。
static func _talks(campaign_id: String, stage_id: String, manifest_events: Variant,
		record: Dictionary, event_talks: Dictionary) -> Array:
	var out: Array = []
	var start: Array = record.get("start", [])
	var clear: Array = record.get("clear", [])
	if record.has("start"):
		out.append({ "key": "intro", "phase": "intro", "event": "", "actors": start })
	var fired: Array = record.get("events", [])
	var listed := {}
	if typeof(manifest_events) == TYPE_ARRAY:
		for raw in manifest_events:
			var event_id := String(raw)
			listed[event_id] = true
			if not fired.has(event_id):
				continue  # 経験していない＝流れに出さない
			var talk: Dictionary = event_talks.get(event_id, {})
			if talk.is_empty():
				push_warning("ChronicleStory[%s/%s]: イベント '%s' の台本が無い"
						% [campaign_id, stage_id, event_id])
				continue
			out.append({
				"key": String(talk["dialogue"]), "phase": "event",
				"event": event_id, "actors": start,
			})
	for event_id in fired:
		if not listed.has(String(event_id)):
			push_warning("ChronicleStory[%s/%s]: 起きたイベント '%s' が story の events に無い"
					% [campaign_id, stage_id, event_id])
	if record.has("clear"):
		out.append({ "key": "outro", "phase": "outro", "event": "", "actors": clear })
	return out

## 記録した actor の並びを、会話の条件（when: joined:<actor>）が見るだけの名簿に仕立てる。
static func _as_roster(actors: Variant) -> Array:
	var out: Array = []
	if typeof(actors) != TYPE_ARRAY:
		return out
	for a in actors:
		out.append({ "actor": String(a) })
	return out

## 冒険譚のステージ表から1件引く（無ければ空）。
static func _find_stage(campaign: Dictionary, stage_id: String) -> Dictionary:
	for s in campaign.get("stages", []):
		if typeof(s) == TYPE_DICTIONARY and String((s as Dictionary).get("id", "")) == stage_id:
			return s
	return {}
