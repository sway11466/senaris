extends GutTest
## 生成済みJSON（コミット物）のクロスファイル整合性テスト。
## convert 実行を忘れて手編集した/正本がドリフトした場合でも、committed な artifacts が
## 噛み合っていることを担保する（各 convert の生成時チェックを、成果物側からも網掛けする）。
## 詳細 → doc/tech/architecture.md「CSV→データ生成のバリデーション」

func test_unit_move_types_exist_in_movement() -> void:
	# 各ユニット種別の move_type が movement 表に存在する（typo→黙ってコスト1 の罠を封じる）。
	var types := UnitCatalog.load_default()
	var move := Movement.load_default()
	assert_gt(types.size(), 0, "ロスターが読める")
	for id in types:
		var mt: String = types[id].move_type
		assert_true(move.has(mt), "%s の move_type '%s' が movement 表にある" % [id, mt])

func test_skin_type_ids_exist_in_unit_types() -> void:
	# 各スキンの type_id（性能への参照）が unit_type に存在する（参照切れ→素の10/10 に化ける罠を封じる）。
	var types := UnitCatalog.load_default()
	var skins := SkinCatalog.load_standard()
	for key in skins:
		if key == SkinCatalog.BY_ID_KEY:
			continue  # skin_id 索引は type_id ではない
		assert_true(types.has(key), "スキンの type_id '%s' が unit_type にある" % key)

func test_movement_table_covers_all_terrain() -> void:
	# movement は完全表＝各 move_type が全地形のコストを持つ（新地形の入れ忘れ→黙ってコスト1 を封じる）。
	var move := Movement.load_default()
	var terrains := TerrainType.all_ids()
	assert_gt(terrains.size(), 0, "地形が読める")
	for mt in move:
		var costs: Dictionary = move[mt]
		for t in terrains:
			assert_true(costs.has(t), "move_type '%s' に地形 '%s' のコストがある" % [mt, t])

func test_stage_squad_ai_labels_exist() -> void:
	# ステージの squad が参照する特性id が ai.json に実在する（打ち間違い→黙って charge 化 を封じる）。
	var presets := AiCatalog.load_default()
	var files := _all_stage_files("res://data/stages")
	assert_gt(files.size(), 0, "ステージJSONが見つかる")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for squad in data.get("enemy", []):
			if typeof(squad) != TYPE_DICTIONARY:
				continue
			var label := str(squad.get("ai", "")).strip_edges()
			if label.is_empty():
				continue  # 未指定＝charge 既定（正当）
			assert_true(presets.has(label), "%s の squad.ai '%s' が ai.json に実在" % [path, label])

## 駒の直書きを見分ける印。部隊定義には現れず、駒にだけ現れるキー（player は type / enemy は skin）。
const PIECE_KEYS := ["skin", "type", "col", "row"]

func test_stage_player_pieces_all_belong_to_parties() -> void:
	# 味方の駒も必ずいずれかの味方部隊に属する（doc/gdd/map.md 駒の配置）。
	# player の直下に駒を直書きすると、ローダーは「units 無しの部隊」として読み飛ばす
	# ＝盤から駒が黙って消える。
	var files := _all_stage_files("res://data/stages")
	assert_gt(files.size(), 0, "ステージJSONが見つかる")
	for path in files:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for entry in data.get("player", []):
			if typeof(entry) != TYPE_DICTIONARY:
				assert_true(false, "%s の player 要素が部隊(辞書)でない" % path)
				continue
			var party: Dictionary = entry
			assert_true(party.has("units"), "%s の player 要素が units を持つ＝部隊である" % path)
			assert_eq(typeof(party.get("units", [])), TYPE_ARRAY, "%s の units は配列" % path)
			for key in PIECE_KEYS:
				assert_false(party.has(key), "%s の player 直下に駒キーがある（部隊の外に駒を直書きしない）: %s" \
					% [path, key])
			for key in ["ai", "order"]:
				assert_false(party.has(key), "%s の味方部隊には書かないキー（特性も行動順も持たない）: %s" % [path, key])


func test_stage_enemy_pieces_all_belong_to_squads() -> void:
	# 敵駒は必ずいずれかの部隊(squad)に属する（doc/gdd/ai.md 部隊）。
	# enemy の直下に駒を直書きすると特性も order も持たない駒ができ、行動順の列から漏れる。
	# ローダーは squad 配列として読むので、直書きは黙って「units 無しの部隊」に化ける＝ここで捕まえる。
	var files := _all_stage_files("res://data/stages")
	assert_gt(files.size(), 0, "ステージJSONが見つかる")
	for path in files:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for entry in data.get("enemy", []):
			if typeof(entry) != TYPE_DICTIONARY:
				assert_true(false, "%s の enemy 要素が部隊(辞書)でない" % path)
				continue
			var squad: Dictionary = entry
			assert_true(squad.has("units"), "%s の enemy 要素 '%s' が units を持つ＝部隊である" \
				% [path, str(squad.get("name", squad.get("ai", "無名")))])
			assert_eq(typeof(squad.get("units", [])), TYPE_ARRAY, "%s の units は配列" % path)
			for key in PIECE_KEYS:
				assert_false(squad.has(key), "%s の enemy 直下に駒キー '%s' が無い（部隊の外に駒を直書きしない）" \
					% [path, key])

func test_stage_rank_has_all_four_thresholds() -> void:
	# rank を書くなら4キーとも書く（doc/gdd/rank.md 判定）。低い方を最終ランクにするので、
	# 片方の軸を空けるとその軸が常に B を返し、もう片方をどれだけ詰めても B に落ちる。
	# 戦果票は空けた軸の基準を出さないので、画面とランクで食い違ったまま気づけない。
	const RANK_KEYS := ["turn_s", "turn_a", "survival_s", "survival_a"]
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("rank"):
			continue  # rank 無し＝ランクを評価しないステージ
		var rank: Variant = data["rank"]
		assert_eq(typeof(rank), TYPE_DICTIONARY, "%s の rank は辞書" % path)
		if typeof(rank) != TYPE_DICTIONARY:
			continue
		for key in RANK_KEYS:
			var v: Variant = (rank as Dictionary).get(key)
			assert_true(typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT,
				"%s の rank に '%s' がある" % [path, key])
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				assert_gt(int(v), 0, "%s の rank '%s' は1以上（0＝基準なしにしない）" % [path, key])

func test_stage_squads_and_ai_bases_have_order() -> void:
	# 行動順 order は全部隊・AI出撃する全拠点に書く（doc/gdd/ai.md 行動順）。
	# 省略はコード側では登録順にフォールバックするので黙って通ってしまう＝ここで抜けを捕まえる。
	# 同一ステージ内で重複していると順番が記述順に落ちるので、一意であることも見る。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var seen := {}
		for squad in data.get("enemy", []):
			if typeof(squad) != TYPE_DICTIONARY:
				continue
			_assert_order(path, squad, "squad '%s'" % str(squad.get("name", "無名")), seen)
		for base in data.get("bases", []):
			if typeof(base) != TYPE_DICTIONARY or not (base as Dictionary).has("ai"):
				continue  # ai 無し＝AI出撃しない拠点は行動順の列に並ばない
			_assert_order(path, base, "base (%s, %s)" % [str(base.get("col")), str(base.get("row"))], seen)
		for event in data.get("events", []):
			# イベントで出す敵の部隊も squads に積まれる＝行動順の列に並ぶ（order は部隊の中に書く）。
			# 自軍の部隊は行動をプレイヤーが選ぶので order を持たない＝enemy セクションだけ見る。
			# 駒を出さないイベント（会話だけ）は部隊を持たない＝order も要らない。
			if typeof(event) != TYPE_DICTIONARY:
				continue
			for squad in event.get("enemy", []):
				if typeof(squad) != TYPE_DICTIONARY:
					continue
				_assert_order(path, squad, "event '%s' squad" % str(event.get("id", "")), seen)

func test_stage_events_name_their_trigger_by_type() -> void:
	# 引き金は type（turn／capture）で書く（doc/gdd/map.md イベント）。既定は無い＝書き忘れは
	# 読み込みで捨てられて黙ってイベントが消えるので、ここで捕まえる。旧い書き方（on／team／
	# reinforce／talk）は読み込みが止めるが、データとしては不備。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for event in data.get("events", []):
			if typeof(event) != TYPE_DICTIONARY:
				continue
			var where := "%s のイベント '%s'" % [path, str(event.get("id", ""))]
			var type_id := str(event.get("type", ""))
			assert_true(type_id in ["turn", "capture"], "%s の type は turn／capture" % where)
			assert_false(event.has("on") or event.has("team") or event.has("name"),
				"%s に on／team／name（廃止）が無い" % where)
			if type_id == "capture":
				assert_true(event.has("col") and event.has("row"), "%s に拠点の col/row がある" % where)
				assert_true(str(event.get("captured_by", "")) in ["player", "enemy"],
					"%s に captured_by（player／enemy）がある" % where)
			else:
				assert_true(event.has("turn"), "%s に turn がある" % where)

## 翻訳CSV（1行ヘッダ keys, ja, en）のキー集合。
func _i18n_keys(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s を開けること" % path)
	if f == null:
		return {}
	f.get_csv_line()  # ヘッダ
	var keys := {}
	while not f.eof_reached():
		var cols := f.get_csv_line()
		if cols.size() > 0 and cols[0] != "":
			keys[cols[0]] = true
	f.close()
	return keys

func test_stage_events_with_dialogue_have_a_name_translation() -> void:
	# 会話つきのイベントは「ストーリーを確認」の目次に並ぶ。見出しは JSON に書かず、
	# ステージ id とイベント id からの規約キー（StageLoader.event_name_key）で campaigns.csv から引く
	# （doc/gdd/map.md イベント）。キーが無ければキー文字列がそのまま画面に出る＝ここで捕まえる。
	var keys := _i18n_keys("res://data/i18n/campaigns.csv")
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var stage_id := str(data.get("name", ""))
		for event in data.get("events", []):
			if typeof(event) != TYPE_DICTIONARY or str(event.get("dialogue", "")).is_empty():
				continue
			assert_false(stage_id.is_empty(), "%s に name（ステージ id）がある" % path)
			var key := StageLoader.event_name_key(stage_id, str(event.get("id", "")))
			assert_true(keys.has(key), "campaigns.csv に %s がある（%s のイベント名）" % [key, path])

func test_stage_events_have_unique_ids() -> void:
	# イベントの id は必須・ステージ内で一意（doc/gdd/map.md イベント）。
	# セーブが未発火のイベントを id で覚えるので、欠落・重複は復元先を見失う。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var seen := {}
		for event in data.get("events", []):
			if typeof(event) != TYPE_DICTIONARY:
				continue
			var v: Variant = event.get("id")
			if typeof(v) != TYPE_STRING or String(v).is_empty():
				assert_true(false, "%s のイベントに id（非空の文字列）がある" % path)
				continue
			assert_false(seen.has(v), "%s のイベント id '%s' が他と重複しない" % [path, v])
			seen[v] = true

func test_stage_unit_ids_are_unique_and_referenced() -> void:
	# 駒の名前(unit_id)はステージ内で一意、勝敗条件が指す先は盤に居る（doc/gdd/map.md 駒を指す名前）。
	# 綴り違いを黙って通すと「書き忘れ」と「名指さない」が区別できなくなる。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var problems := StageLoader.unit_id_problems(data)
		assert_eq(problems, [], "%s の unit_id: %s" % [path, ", ".join(PackedStringArray(problems))])

func test_stage_enter_lines_are_consistent() -> void:
	# 会話の途中の登場（intro の enter 行）が指す部隊 name／unit_id が陣営セクションに居て、
	# 同じ駒を2度指さず、enter 行が intro 以外に無く、entry／from の書き分けが増援と同じ規則に
	# 従う（doc/gdd/map.md 会話の途中の登場）。指す先の綴り違いは実機では黙って何も出ない。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var problems := StageLoader.enter_problems(data)
		assert_eq(problems, [], "%s の enter 行: %s" % [path, ", ".join(PackedStringArray(problems))])

func test_stage_events_declare_entry_and_from() -> void:
	# 駒を出すイベントは登場の仕方（entry）を必ず持ち、歩いてくる登場だけが入口（from）を持つ
	# （doc/gdd/map.md イベント）。既定を置かない決まりなので、書き忘れは
	# 「所定位置にポンと現れる」に黙って戻る＝遊んでみるまで気づけない。
	var files := _all_stage_files("res://data/stages")
	assert_gt(files.size(), 0, "ステージJSONが見つかる")
	for path in files:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for event in (data as Dictionary).get("events", []):
			if typeof(event) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = event
			var units: Variant = e.get("units", [])
			if typeof(units) != TYPE_ARRAY or (units as Array).is_empty():
				continue
			var id := String(e.get("id", ""))
			var entry := String(e.get("entry", ""))
			assert_true(StageEvent.ENTRY_IDS.has(entry),
				"%s のイベント '%s' に entry（march／scatter／fade）がある" % [path, id])
			var from: Variant = e.get("from")
			if entry == "march" or entry == "scatter":
				assert_true(typeof(from) == TYPE_DICTIONARY
						and (from as Dictionary).has("col") and (from as Dictionary).has("row"),
					"%s のイベント '%s' に入口 from（col/row）がある" % [path, id])
			else:
				assert_null(from, "%s のイベント '%s' は入口 from を持たない" % [path, id])

func test_walking_entries_can_reach_their_places() -> void:
	# 歩いてくる登場は、入口から所定位置まで地形をたどれること（doc/gdd/map.md イベント）。
	# たどり着けない駒は歩かずその場に出る＝「入口から出てくる」が黙って崩れる。
	# 読み込むのは歩いてくる登場を持つステージだけ＝全ステージを組み立てない。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var walks := false
		for event in (data as Dictionary).get("events", []):
			if typeof(event) == TYPE_DICTIONARY 					and String((event as Dictionary).get("entry", "")) in ["march", "scatter"]:
				walks = true
		if not walks:
			continue
		var state := StageLoader.load_file(path)
		assert_not_null(state, "%s が読める" % path)
		if state == null:
			continue
		for e in state.pending_events().duplicate():
			if not e.walks_in():
				continue
			state.fire_event(e)  # 引き金を待たずに出す＝並びも座標も本番と同じ
			for uid in e.placed_ids:
				assert_false(state.entry_path(uid, e.from).is_empty(),
					"%s のイベント '%s' の駒 id=%d が入口から歩いてこられる" % [path, e.id, uid])

func test_walking_enter_lines_can_reach_their_places() -> void:
	# 会話の途中の登場（intro の enter 行）で歩いてくる駒も、入口から所定位置まで地形をたどれること
	# （doc/gdd/map.md 会話の途中の登場）。増援と同じく、たどり着けない駒は歩かずその場に出る。
	# 名簿から出す駒（actor だけの駒）は名簿なしでは盤に乗らない＝その行は空で通る。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var intro: Variant = ((data as Dictionary).get("dialogue", {}) as Dictionary).get("intro", [])
		if typeof(intro) != TYPE_ARRAY:
			continue
		var walks := false
		for line in intro:
			if typeof(line) != TYPE_DICTIONARY:
				continue
			for t in (line as Dictionary).get("enter", []):
				if typeof(t) == TYPE_DICTIONARY and String((t as Dictionary).get("entry", "")) in ["march", "scatter"]:
					walks = true
		if not walks:
			continue
		var state := StageLoader.load_file(path)
		assert_not_null(state, "%s が読める" % path)
		if state == null:
			continue
		for line in intro:
			if typeof(line) != TYPE_DICTIONARY:
				continue
			for info in StageLoader.resolve_enter(state, line):
				var from: Vector2i = info["from"]
				if from == Vector2i.MAX:
					continue
				for uid in info["units"]:
					assert_false(state.entry_path(int(uid), from).is_empty(),
						"%s の enter 行の駒 handle=%d が入口 %s から歩いてこられる" % [path, int(uid), from])

func _assert_order(path: String, holder: Dictionary, label: String, seen: Dictionary) -> void:
	var v: Variant = holder.get("order")
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		assert_true(false, "%s の %s に order がある" % [path, label])
		return
	var n := int(v)
	assert_false(seen.has(n), "%s の %s の order %d が他と重複しない" % [path, label, n])
	seen[n] = true

func test_stage_bases_use_hq_rest_and_garrison_native() -> void:
	# 拠点の kind/native は廃止（hq/rest に置き換え）。控えの native は駒ごとに必須＝既定に頼らない
	# （doc/gdd/map.md 拠点の値・帰属）。書き忘れは読み込みで倒されるが、データとしては不備。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var bases: Variant = (data as Dictionary).get("bases", [])
		if typeof(bases) != TYPE_ARRAY:
			continue
		for b in bases:
			if typeof(b) != TYPE_DICTIONARY:
				continue
			var where := "%s の拠点(%s,%s)" % [path, str(b.get("col")), str(b.get("row"))]
			assert_false(b.has("kind") or b.has("native"), "%s: kind/native は廃止＝hq/rest に書き換える" % where)
			if b.has("hq"):
				assert_true(String(b["hq"]) in ["player", "enemy"], "%s: hq は player/enemy" % where)
			if b.has("rest"):
				assert_true(String(b["rest"]) in ["player", "enemy", "both"], "%s: rest は player/enemy/both" % where)
			for g in b.get("garrison", []):
				if typeof(g) != TYPE_DICTIONARY:
					continue
				assert_true(String(g.get("native", "")) in ["player", "enemy", "neutral"],
					"%s: 控え %s に native（player/enemy/neutral）が要る" % [where, str(g.get("skin", g.get("type", "?")))])

## data/stages 以下を再帰し、ステージJSON（campaign.json マニフェストは除く）のパス配列を返す。
func test_every_stage_has_a_terrain_file() -> void:
	# 地形は相棒のファイル（<ステージ>.terrain.json）が正本＝無ければ盤の広さも決まらない。
	for path in _all_stage_files("res://data/stages"):
		assert_true(FileAccess.file_exists(StageLoader.terrain_path(path)),
			"%s の地形ファイルがある" % path)

func test_stage_body_does_not_keep_terrain_keys() -> void:
	# 本体に書いても読まれない＝二重に書けば食い違う。分割の取りこぼしをここで塞ぐ。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for key in StageLoader.TERRAIN_KEYS + ["cols", "rows"]:
			assert_false((data as Dictionary).has(key),
				"%s の本体に \"%s\" は書かない" % [path, key])

func test_stages_declare_haze() -> void:
	# 靄は必須＝書き忘れると戦闘演出で push_error になり 0 に倒れる（doc/tech/combat_scene.md）。
	for path in _all_stage_files("res://data/stages"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var v: Variant = (data as Dictionary).get("haze") if typeof(data) == TYPE_DICTIONARY else null
		assert_true(typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT,
			"%s に haze（0〜1 の数値）がある" % path)

func _all_stage_files(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := "%s/%s" % [root, name]
		if dir.current_is_dir():
			if not name.begins_with("."):
				out += _all_stage_files(full)
		elif name.ends_with(".json") and name != "campaign.json" \
				and not name.ends_with(StageLoader.TERRAIN_SUFFIX):  # 地形ファイルはステージではない
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out

func test_stages_inheriting_actors_declare_roster_from() -> void:
	# 名簿から出す駒（join 以外の actor 駒）を置くステージは、マニフェストに名簿の引き継ぎ元
	# roster_from を書く（doc/gdd/stage_select.md 冒険譚マニフェスト）。無ければ空の名簿で始まり、
	# その駒は黙って盤に出ない。
	for c in CampaignCatalog.load_all():
		for s in c["stages"]:
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(s["path"]))
			if typeof(data) != TYPE_DICTIONARY:
				continue
			var inherits := false
			for party in data.get("player", []):
				if typeof(party) != TYPE_DICTIONARY:
					continue
				for u in party.get("units", []):
					if typeof(u) == TYPE_DICTIONARY and u.has("actor") and String(u.get("supply", "")) != "join":
						inherits = true
			if inherits:
				assert_false(String(s["roster_from"]).is_empty(),
					"%s/%s は名簿から出す駒があるので roster_from を書く" % [c["id"], s["id"]])

func test_every_stage_has_synopsis() -> void:
	# あらすじは全ステージに書く（デバッグ冒険譚も1文）＝一覧から入り直した人が、依頼書で
	# 話の続きを思い出せるようにする（doc/gdd/stage_select.md あらすじ）。
	for c in CampaignCatalog.load_all():
		for s in c["stages"]:
			assert_false(String(s["synopsis"]).is_empty(),
				"%s/%s に synopsis（あらすじ）を書く" % [c["id"], s["id"]])

func test_stage_interlude_matches_supply() -> void:
	# 幕間の印（マニフェストの interlude）は見せ方、兵が戻るかは駒の supply。2か所に書くので
	# 食い違いをここで拾う（doc/gdd/stage_select.md 冒険譚マニフェスト）。線引き＝
	#   onward  → 連戦。refill／revive の駒が1体も無い
	#   refill  → 新入り（join）以外の名簿の駒は全部 refill
	#   revive  → 同じく全部 revive
	# 継承の冒険譚（名簿を引き継ぐ話がある）の2話目以降は、この3値のどれかを必ず書く＝「書いて
	# いない」と「連戦」が同じ意味になると書き忘れを拾えない。1話目と独立の冒険譚には幕間その
	# ものが無いので書かない。デバッグ冒険譚は機能見本で refill と revive を1盤に混ぜるので対象外。
	for c in CampaignCatalog.load_all():
		if c["debug"]:
			continue
		var carryover := false
		for s in c["stages"]:
			if not String(s["roster_from"]).is_empty():
				carryover = true
		for i in c["stages"].size():
			var s: Dictionary = c["stages"][i]
			var interlude: String = s["interlude"]
			var where := "%s/%s" % [c["id"], s["id"]]
			if i == 0 or not carryover:
				assert_true(interlude.is_empty(), "%s: 幕間の無い話（1話目・独立）に interlude は書かない" % where)
			else:
				assert_true(CampaignCatalog.INTERLUDES.has(interlude),
					"%s: 継承の2話目以降は interlude を %s のどれかで書く（今は '%s'）"
						% [where, str(CampaignCatalog.INTERLUDES), interlude])
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(s["path"]))
			if typeof(data) != TYPE_DICTIONARY:
				continue
			for party in data.get("player", []):
				if typeof(party) != TYPE_DICTIONARY:
					continue
				for u in party.get("units", []):
					if typeof(u) != TYPE_DICTIONARY or not u.has("actor"):
						continue
					var supply := String(u.get("supply", ""))
					if supply == "join":
						continue
					var label := "%s の駒 %s（supply='%s'）" % [where, String(u["actor"]), supply]
					match interlude:
						"refill":
							assert_eq(supply, "refill", "%s: 休息の話は名簿の駒を refill で出す" % label)
						"revive":
							assert_eq(supply, "revive", "%s: 復帰の話は名簿の駒を revive で出す" % label)
						_:
							assert_false(supply in ["refill", "revive"],
								"%s: 兵を戻す駒があるなら interlude は refill／revive" % label)

## 歩兵のレシピ（シールドウォール・カウンター）が、味方の歩兵スキンを取りこぼしていない。
## 新しい味方歩兵を unit_skin.csv に足したのにレシピへ書き足し忘れると、その駒だけ列に加われない
## ＝盤の上では「なぜか組めない」としか見えないバグになるので、データ側から網掛けする。
## 対象の見分けは「顔ぶれに fighter が入っているレシピ」＝歩兵のレシピが増えても一覧の追記は要らない。
## ノービスは見習いのため対象外（doc/gdd/formations.md 表A）。
func test_infantry_recipes_cover_every_ally_infantry_skin() -> void:
	var by_id: Dictionary = SkinCatalog.load_standard()[SkinCatalog.BY_ID_KEY]
	var wanted: Array[String] = []
	for skin in by_id.values():
		if skin.side == "ally" and skin.category == "infantry" and skin.skin_id != "novice":
			wanted.append(skin.skin_id)
	assert_gt(wanted.size(), 0, "味方の歩兵スキンが読める")
	var checked := 0
	for rid in Formation.SKILLS:
		var r: Dictionary = Formation.SKILLS[rid]
		if not ("fighter" in r.get("caster_skins", [])):
			continue  # 歩兵のレシピではない
		checked += 1
		for sid in wanted:
			assert_true(sid in r["caster_skins"],
				"%s の caster_skins に味方歩兵 '%s' がある" % [rid, sid])
			assert_true(sid in r["member_skins"],
				"%s の member_skins に味方歩兵 '%s' がある" % [rid, sid])
		assert_false("novice" in r["caster_skins"], "%s はノービスを含まない" % rid)
		assert_false("novice" in r["member_skins"], "%s はノービスを含まない" % rid)
	assert_gt(checked, 0, "歩兵のレシピが1つ以上ある")

## 拠点のマスは地形グリッドで砦（fort）であること。拠点の見た目は地形の側から出る＝`bases` に
## 書いただけでは盤に何も描かれず、遊べてしまうぶん気づけない（2026-09-22 に debug-map/transport
## で踏んだ）。地形は `*.terrain.json` の `O`。詳細 → doc/gdd/terrain.md・doc/gdd/map.md
func test_stage_bases_sit_on_fort_terrain() -> void:
	var files := _all_stage_files("res://data/stages")
	assert_gt(files.size(), 0, "ステージJSONが見つかる")
	var checked := 0
	for path in files:
		var data := StageLoader.read_stage(path)
		var grid: Variant = data.get("terrain", [])
		if typeof(grid) != TYPE_ARRAY:
			continue
		var margin := int(data.get("margin", 0))
		for b in data.get("bases", []):
			if typeof(b) != TYPE_DICTIONARY:
				continue
			checked += 1
			var col := int(b.get("col", -1)) + margin
			var row := int(b.get("row", -1)) + margin
			var line := String(grid[row]) if row >= 0 and row < grid.size() else ""
			var ch := line[col] if col >= 0 and col < line.length() else ""
			assert_eq(TerrainType.char_to_id(ch), "fort",
				"%s の拠点 (col %d, row %d) が砦の上にある" % [path, int(b.get("col", -1)), int(b.get("row", -1))])
	assert_gt(checked, 0, "拠点が1つ以上ある")
