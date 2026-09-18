extends RefCounted
class_name SaveEditorModel
## セーブエディタ（tools/save_editor）の純ロジック。画面は save_editor.gd。
## 仕様 → doc/backlog.md feature-130 / doc/gdd/campaigns.md 名簿 / doc/gdd/chronicle.md 記録の持ち方
##
## - 名簿の候補：ステージから roster_from をさかのぼり、通った各ステージの actor 駒（player の駒と
##   拠点の garrison の両方）を初登場の順に並べる。既定は Lv1・満員。
## - クロニクルの「全部ON」：全スキン・全陣形スキル（初出は空）・物語の記録（マニフェストにある
##   全ステージの開始時／クリア後の在籍と全イベント）を、進捗とクロニクルの両ストアへ書く。

## roster_from の鎖＝root → stage_id の順のマニフェストのステージ項目。stage_id が無ければ空。
## 鎖が輪になっていても止まる（同じステージは一度だけ）。
static func roster_chain(campaign: Dictionary, stage_id: String) -> Array:
	var by_id := {}
	for s in campaign.get("stages", []):
		by_id[String(s["id"])] = s
	var out: Array = []
	var seen := {}
	var cur := stage_id
	while not cur.is_empty() and by_id.has(cur) and not seen.has(cur):
		seen[cur] = true
		out.push_front(by_id[cur])
		cur = String(by_id[cur].get("roster_from", ""))
	return out

## 1ステージ定義の actor 駒（player の駒＋拠点の控え）。{ actor, type, skin } の配列（書かれた順）。
static func actor_pieces(stage_data: Dictionary) -> Array:
	var out: Array = []
	for p in _dicts(stage_data.get("player", [])):
		for u in _dicts(p.get("units", [])):
			_push_piece(out, u)
	for b in _dicts(stage_data.get("bases", [])):
		for g in _dicts(b.get("garrison", [])):
			_push_piece(out, g)
	return out

## 候補＝鎖のステージ定義（root が先）から actor を初登場の順に集め、type/skin を解決して満員値を添える。
## 性能を引けない駒は落とす（実機でも盤に出ない）。返り値 [{ actor, type, skin, max_troops }]
static func candidates(stage_datas: Array, catalog: Dictionary, skins: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for data in stage_datas:
		for piece in actor_pieces(data):
			var actor: String = piece["actor"]
			if seen.has(actor):
				continue
			var type_id: String = piece["type"]
			var skin_id: String = piece["skin"]
			if type_id.is_empty() and not skin_id.is_empty():
				type_id = SkinCatalog.type_of_skin(skins, skin_id)
			var t: UnitType = catalog.get(type_id)
			if t == null:
				push_warning("SaveEditorModel: '%s' は type/skin から性能を引けない＝候補から外す" % actor)
				continue
			seen[actor] = true
			out.append({
				"actor": actor,
				"type": type_id,
				"skin": skin_id if not skin_id.is_empty() else type_id,
				"max_troops": t.max_troops,
			})
	return out

## 冒険譚とステージから候補を作る（ファイルを読む側）。
static func candidates_for(campaign: Dictionary, stage_id: String, catalog: Dictionary, skins: Dictionary) -> Array:
	return candidates(_chain_datas(campaign, stage_id), catalog, skins)

## 名簿の1行＝Unit.to_dict() と同じ形。Lv は 1 以上、兵数は 0〜満員に収める。
static func roster_entry(c: Dictionary, level: int, troops: int) -> Dictionary:
	var max_troops := int(c["max_troops"])
	return {
		"actor": String(c["actor"]),
		"type": String(c["type"]),
		"skin": String(c["skin"]),
		"level": maxi(level, 1),
		"troops": clampi(troops, 0, max_troops),
		"max_troops": max_troops,
	}

## クロニクルの陣形スキルの章が並べる全スキル（shape が solo＝ユニットスキルは除く）。
static func formation_skill_ids() -> Array:
	var out: Array = []
	for skill_id in Formation.SKILLS:
		if String((Formation.SKILLS[skill_id] as Dictionary).get("shape", "")) != "solo":
			out.append(String(skill_id))
	return out

## クロニクルのユニットの章が並べる全スキン（スキン表の行順）。
static func all_skin_ids(skins: Dictionary) -> Array:
	var out: Array = []
	for skin_id in (skins.get(SkinCatalog.BY_ID_KEY, {}) as Dictionary):
		out.append(String(skin_id))
	return out

## 「全部ON」。campaigns＝CampaignCatalog.load_all()、manifests＝ChronicleLoader.load_all()。
## 物語の記録は最後に遊んだ回（進捗）と遊んだ回の累積（クロニクル）の両方に書く。
## 開始時の在籍＝引き継ぎ元までの候補、クリア後の在籍＝そのステージまでの候補。
## 返り値＝書いた数 { skins, skills, stages }。クロニクルの save() は呼び出し側が呼ぶ。
static func all_on(progress: ProgressStore, chronicle: ChronicleStore, campaigns: Array,
		manifests: Dictionary, catalog: Dictionary, skins: Dictionary) -> Dictionary:
	var n_skins := 0
	for skin_id in all_skin_ids(skins):
		if chronicle.record_skin(skin_id):
			n_skins += 1
	var n_skills := 0
	for skill_id in formation_skill_ids():
		if chronicle.record_skill(skill_id, ""):
			n_skills += 1
	var n_stages := 0
	for c in campaigns:
		if bool(c.get("debug", false)):
			continue
		var cid := String(c["id"])
		var story: Array = (manifests.get(cid, {}) as Dictionary).get("story", [])
		for entry in story:
			var sid := String((entry as Dictionary).get("stage", ""))
			var datas := _chain_datas(c, sid)
			if datas.is_empty():
				continue  # 冒険譚に無いステージ＝物語の側が警告する
			var clear_units := _as_units(candidates(datas, catalog, skins))
			var start_units := _as_units(candidates(datas.slice(0, datas.size() - 1), catalog, skins))
			progress.mark_story_start(cid, sid, start_units)
			progress.mark_story_clear(cid, sid, clear_units)
			chronicle.record_story_roster(cid, sid, "start", _names(start_units))
			chronicle.record_story_roster(cid, sid, "clear", _names(clear_units))
			for event_id in (entry as Dictionary).get("events", []):
				progress.mark_story_event(cid, sid, String(event_id))
				chronicle.record_story_event(cid, sid, String(event_id))
			n_stages += 1
	return { "skins": n_skins, "skills": n_skills, "stages": n_stages }

# ---------------------------------------------------------------------------

## 鎖のステージ定義を root から順に読む。
static func _chain_datas(campaign: Dictionary, stage_id: String) -> Array:
	var out: Array = []
	for s in roster_chain(campaign, stage_id):
		out.append(StageLoader.read_stage(String(s["path"])))
	return out

static func _push_piece(out: Array, u: Dictionary) -> void:
	var actor := String(u.get("actor", ""))
	if actor.is_empty():
		return
	out.append({ "actor": actor, "type": String(u.get("type", "")), "skin": String(u.get("skin", "")) })

## 候補を「名簿の形」（actor を持つ辞書）にする＝進捗の記録は名簿から actor を取り出す。
static func _as_units(cands: Array) -> Array:
	var out: Array = []
	for c in cands:
		out.append({ "actor": String(c["actor"]) })
	return out

static func _names(units: Array) -> Array:
	var out: Array = []
	for u in units:
		out.append(String(u["actor"]))
	return out

static func _dicts(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for e in value:
		if typeof(e) == TYPE_DICTIONARY:
			out.append(e)
	return out
