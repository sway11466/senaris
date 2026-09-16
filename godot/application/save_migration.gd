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
## 現行版はそのまま、旧版は1段ずつ上げて返す。変換できない版は空 dict（読まない）。
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	data = _renamed_path(data)
	var record := { "meta": data.get("meta", {}), "state": data.get("state", {}) }
	if version == 2:
		record = _v2_to_v3(data)
		version = 3
	if version == 3:
		record = _v3_to_v4(record)
		version = 4
	if version == 4:
		record = _v4_to_v5(record)
		version = 5
	if version == 5:
		record = _v5_to_v6(record)
		version = 6
	if version != SaveStore.VERSION:
		push_warning("SaveMigration: 変換を持たない版 %d（SaveFile が弾くはず＝呼び出しのバグ）" % version)
		return {}
	record["meta"] = StageRenames.meta(record.get("meta", {}))
	return record

## 改名前のステージを指すセーブの stage_path を新しいファイル名へ（StageRenames）。版に関わらず
## 通す＝現行版のセーブも旧名で書かれている。v2 の変換がこのパスでステージJSONを開く（イベントの
## 同定）ので、どの変換よりも前に直す。ステージIDと翻訳キーは逆に最後＝印を引いた後に読み替える。
static func _renamed_path(data: Dictionary) -> Dictionary:
	var meta: Dictionary = (data.get("meta", {}) as Dictionary).duplicate()
	if not meta.has("stage_path"):
		return data
	meta["stage_path"] = StageRenames.path(String(meta["stage_path"]))
	var out := data.duplicate()
	out["meta"] = meta
	return out

## v3 → v4（meta に開始時刻を足した）。旧セーブは測っていないので 0＝不明を入れる。
## 不明のまま勝った回は戦果票に所要時間を出さず、ベストタイムも記録しない
## （doc/tech/gamesystem.md §所要時間）。測っていない時間を 0 秒として記録に混ぜないため。
## v4（味方は部隊に属さない）→ v5（味方も部隊に属する）。部隊の所属は state.squads の並び順で
## 持つので、味方部隊が先に積まれたぶん既存の所属（＝すべて敵か拠点）を後ろへずらす。
## 駒を指す語彙を分けた版（doc/gdd/map.md 駒を指す名前）。実行時のハンドルのキーが "id" から
## "handle" になり、勝敗条件が見る名前が actor から unit_id になった。
## actor を持つ駒には unit_id = actor を無条件で複製する＝旧セーブでは同じ値が両方の役目を
## 兼ねていたので、これで再開後もボス撃破・護衛対象の判定が続く。ステージJSONは読まない
## （そのステージが改名・削除されていても漏れない）。余分な unit_id は誰も参照しないので害がない。
static func _v5_to_v6(record: Dictionary) -> Dictionary:
	var state: Dictionary = (record.get("state", {}) as Dictionary).duplicate()
	for u in _as_dicts(state.get("units", [])):
		_v6_unit(u)
	for tid in (state.get("passengers", {}) as Dictionary):
		for p in _as_dicts((state["passengers"] as Dictionary)[tid]):
			_v6_unit(p)
	for b in _as_dicts(state.get("bases", [])):
		for g in _as_dicts(b.get("garrison", [])):
			_v6_unit(g)
	for m in _as_dicts(state.get("status_mods", [])):
		if m.has("unit_id"):  # 駒のハンドル（int）を指していたキー＝String の unit_id とは別物
			m["handle"] = m["unit_id"]
			m.erase("unit_id")
	if state.has("defeated_actors"):
		state["defeated_unit_ids"] = state["defeated_actors"]
		state.erase("defeated_actors")
	return { "meta": record.get("meta", {}), "state": state }

## 駒1体を v6 の形へ（ハンドルのキー名と、名指しの複製）。
static func _v6_unit(u: Dictionary) -> void:
	if u.has("id"):
		u["handle"] = u["id"]
		u.erase("id")
	var actor := String(u.get("actor", ""))
	if actor != "" and not u.has("unit_id"):
		u["unit_id"] = actor

## 味方の駒は、どの部隊に居たかを v4 セーブが持たない＝全員そのステージの最初の味方部隊に入れる
## （doc/tech/gamesystem.md §版と移行）。所属は見出しの表示にしか効かない。
static func _v4_to_v5(record: Dictionary) -> Dictionary:
	var state: Dictionary = (record.get("state", {}) as Dictionary).duplicate()
	var shift := _player_party_count(String((record.get("meta", {}) as Dictionary).get("stage_path", "")))
	var squad_of := {}
	for key in (state.get("squad_of", {}) as Dictionary):
		squad_of[key] = int((state["squad_of"] as Dictionary)[key]) + shift
	var engaged: Array = []
	for i in (state.get("engaged_squads", []) as Array):
		engaged.append(int(i) + shift)
	if shift > 0:
		for u in _as_dicts(state.get("units", [])):
			if int(u.get("team", 0)) == 0:
				squad_of[str(int(u.get("id", 0)))] = 0  # 味方は最初の部隊へ
	state["squad_of"] = squad_of
	state["engaged_squads"] = engaged
	return { "meta": record.get("meta", {}), "state": state }

## そのステージの味方部隊の数（ずらし幅）。読めないステージは 0＝所属をいじらない。
static func _player_party_count(stage_path: String) -> int:
	if stage_path.is_empty():
		return 0
	var data := StageLoader.read_stage(stage_path)
	var parties: Variant = data.get("player", [])
	return (parties as Array).size() if typeof(parties) == TYPE_ARRAY else 0

## Variant を辞書の配列として読む（旧版セーブの中身を数えるときの入口）。
static func _as_dicts(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for e in v:
		if typeof(e) == TYPE_DICTIONARY:
			out.append(e)
	return out

static func _v3_to_v4(record: Dictionary) -> Dictionary:
	var meta: Dictionary = (record.get("meta", {}) as Dictionary).duplicate()
	meta["started_at"] = 0
	return { "meta": meta, "state": record.get("state", {}) }

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
	# 陣営は増援なら駒を書いたセクション、会話だけなら "team"（引き金の条件）。
	var team := 0
	if typeof(e.get("enemy")) == TYPE_ARRAY:
		team = 1
	elif typeof(e.get("player")) != TYPE_ARRAY and e.has("team"):
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
