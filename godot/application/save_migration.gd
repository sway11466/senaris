extends RefCounted
class_name SaveMigration
## 中断セーブの旧版→現行版の変換（application）。仕様 → doc/tech/gamesystem.md §版と移行
## 版の判定と退避は SaveFile、素の読み書きは SaveStore＝ここは中身の形だけを扱う。
## 変換を持たない版は SaveFile が退避して弾くので、ここへは来ない。

## 体験版 demo-v0.1.0 に同梱したステージの印の表（{ "冒険譚ID/ステージID": 印 }）。
## v2 セーブは印を持たないのでここから引いて埋める。今のステージJSONから計算はしない
## ＝将来そのステージを直したときに通知が黙るため。表に無いステージは印なし＝不明として通知側へ倒す。
const DEMO_DIGESTS_PATH := "res://data/save/demo-v0.1.0_digests.json"

## v3 の state が持つキー（BattleState.to_save_diff）。v2 からはこのうち在るものを写す
## （bases/pending_events は形が違うので別処理）。
const V3_COPIED_KEYS := ["current_team", "turn_number", "units", "status_mods", "passengers",
	"moved", "post_moved", "attacked", "done", "engaged", "engaged_squads",
	"defeated", "defeated_actors", "sortied_actors", "spent", "squad_of", "charges"]

## SaveStore.load の生データ（{ version, meta, state }）→ 現行版の { meta, state }。
## 現行版はそのまま、旧版は変換して返す。変換できない版は空 dict（読まない）。
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version == SaveStore.VERSION:
		return { "meta": data.get("meta", {}), "state": data.get("state", {}) }
	if version == 2:
		return _v2_to_v3(data)
	push_warning("SaveMigration: 変換を持たない版 %d（SaveFile が弾くはず＝呼び出しのバグ）" % version)
	return {}

## v2（盤の丸ごと直列化）→ v3（動的差分）。盤サイズ・地形・勝敗条件・ターン上限・部隊定義は
## ステージJSONから引き直すので落とす。詳細 → doc/backlog.md feature-91・doc/tech/gamesystem.md
static func _v2_to_v3(data: Dictionary) -> Dictionary:
	var old: Dictionary = data.get("state", {})
	var meta: Dictionary = (data.get("meta", {}) as Dictionary).duplicate()
	var state := {}
	for key in V3_COPIED_KEYS:
		if old.has(key):
			state[key] = old[key]
	state["bases"] = _v2_bases(old.get("bases", []))
	state["fired_events"] = _v2_fired_events(old.get("events", []), String(meta.get("stage_path", "")))
	var digest := _demo_digest(meta)
	if digest != "":
		meta["stage_digest"] = digest
	return { "meta": meta, "state": state }

## v2 の拠点（丸ごと）→ v3 の差分形。native/kind/squad_index はステージJSONから引き直すので落とす。
static func _v2_bases(src: Variant) -> Array:
	var out: Array = []
	if typeof(src) != TYPE_ARRAY:
		return out
	for bd in src:
		if typeof(bd) != TYPE_DICTIONARY:
			continue
		out.append({
			"q": int(bd.get("q", 0)), "r": int(bd.get("r", 0)),
			"team": int(bd.get("team", Base.NEUTRAL)),
			"garrison": bd.get("garrison", []),
		})
	return out

## v2 の未発火イベント（丸ごと直列化）→ v3 の発火済み id の一覧。旧セーブは id を持たないので、
## 今のステージJSONのイベントと内容（turn・陣営・引き金・拠点位置・once・label）で突き合わせて
## 未発火を消し込み、残った id ＝発火済みとして記録する。同じ内容が複数あれば書かれた順に消し込む。
## 突き合わないセーブ側イベントは警告して無視する（ステージ更新で消えた・変わったイベント）。
static func _v2_fired_events(saved: Variant, stage_path: String) -> Array:
	var pool := _stage_event_ids_by_identity(stage_path)
	if typeof(saved) == TYPE_ARRAY:
		for ed in saved:
			if typeof(ed) != TYPE_DICTIONARY:
				continue
			var key := _identity_of_saved(ed)
			var ids: Array = pool.get(key, [])
			if ids.is_empty():
				push_warning("SaveMigration: 旧セーブの未発火イベントが今のステージに見当たらない＝無視: %s" % key)
				continue
			ids.pop_front()  # 未発火として消し込む＝発火済みに残らない
	var fired: Array = []
	for key in pool:
		for id in pool[key]:
			fired.append(String(id))
	return fired

## 今のステージJSONのイベントを内容の鍵で索引化（{ 鍵: [id, ...] }）。読めなければ空。
static func _stage_event_ids_by_identity(stage_path: String) -> Dictionary:
	var pool := {}
	var text := FileAccess.get_file_as_string(stage_path)
	if text.is_empty():
		return pool
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return pool
	var events: Variant = (data as Dictionary).get("events", [])
	if typeof(events) != TYPE_ARRAY:
		return pool
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var key := _identity_of_stage(e)
		if not pool.has(key):
			pool[key] = []
		pool[key].append(String(e.get("id", "")))
	return pool

## v2 セーブのイベント（BattleState の旧 _events_to_dicts の形）の内容の鍵。
static func _identity_of_saved(ed: Dictionary) -> String:
	return _identity(int(ed.get("turn", 1)), int(ed.get("team", 0)), String(ed.get("on", "")),
		Vector2i(int(ed.get("hex_q", 0)), int(ed.get("hex_r", 0))),
		String(ed.get("once", "")), String(ed.get("label", "")))

## ステージJSONのイベント記述の内容の鍵。既定値の解釈は StageLoader._apply_events と揃える。
static func _identity_of_stage(e: Dictionary) -> String:
	var on := String(e.get("on", ""))
	var hex := Vector2i.MAX
	if on == "capture" and e.has("col") and e.has("row"):
		hex = Hex.offset_to_axial(int(e["col"]), int(e["row"]))
	var team := 0
	if e.has("team"):
		team = int(StageLoader.TEAM_NAMES.get(String(e["team"]), 0))
	return _identity(int(e.get("turn", 1)), team, on, hex, String(e.get("once", "")), String(e.get("label", "")))

static func _identity(turn: int, team: int, on: String, hex: Vector2i, once: String, label: String) -> String:
	return "%d|%d|%s|%d,%d|%s|%s" % [turn, team, on, hex.x, hex.y, once, label]

## 体験版の印の表から冒険譚ID/ステージIDで引く。無ければ ""（印なし）。
static func _demo_digest(meta: Dictionary) -> String:
	var campaign := String(meta.get("campaign_id", ""))
	var stage := String(meta.get("stage_id", ""))
	if campaign == "" or stage == "":
		return ""
	var text := FileAccess.get_file_as_string(DEMO_DIGESTS_PATH)
	if text.is_empty():
		return ""
	var table: Variant = JSON.parse_string(text)
	if typeof(table) != TYPE_DICTIONARY:
		return ""
	return String((table as Dictionary).get("%s/%s" % [campaign, stage], ""))
