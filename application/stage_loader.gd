extends RefCounted
class_name StageLoader
## ステージデータ（JSON）→ BattleState の組み立て（マッチのセットアップ）。
## data層(json/UnitCatalog)と domain(BattleState/Unit) の両方に依存するため application 層に置く。
## 詳細 → doc/tech/architecture.md, doc/gdd/map.md
##
## マップは「ASCII地形グリッド＋ユニット配置リスト」で記述する（data/stages/*.json）。
## terrain は1行＝盤の1列ぶんの文字絵。文字→地形の対応は TerrainType（terrain_type.csv の char 列）。
## 見た目(skin)は性能とは別レイヤー＝ステージJSON の terrain_skins（座標→skin_id 差分列挙）。
## skin は presentation 専用（案P）＝ここでは BattleState に入れず、parse_terrain_skins/load_terrain_skins で
## 別途 {Vector2i: skin_id} として取り出し、main→hex_board へ渡す（domain は skin を知らない）。
##
## build(dict) はファイルIOを伴わず辞書から組み立てる（テスト対象）。
## load_file(path) はファイルを読んで build に渡す薄いラッパ。
##
## 陣営は JSON では可読な文字列で書く: "player"（自軍）/ "enemy"（敵）/ "neutral"（中立）。
## 内部は int 規約（0=自軍 / 1=敵 / -1=中立）で持つため loader で文字列→int に変換する。

## 陣営表記（ステージJSON）→ 内部 int（0=自軍 / 1=敵 / -1=中立=Base.NEUTRAL）。
const TEAM_NAMES := { "player": 0, "enemy": 1, "neutral": -1 }

## 戦力供給モデル（ステージJSON "roster"）の許容値。既定は fresh（独立）。詳細 → doc/gdd/map.md
const ROSTER_MODES := ["fresh", "carryover"]

## イベント自身のキー。敵の増援ではこれ以外（ai・sight 等）を部隊定義として拾う。
const EVENT_KEYS := ["type", "team", "turn", "label", "units"]

## roster 値を検証して返す。省略（null）・未知の表記は "fresh"（独立＝前ステージを引き継がない）。
static func _parse_roster(value: Variant) -> String:
	if value == null:
		return "fresh"
	var key := String(value)
	if key in ROSTER_MODES:
		return key
	push_warning("StageLoader: 未知の roster '%s'（fresh/carryover のいずれか）＝fresh を使用" % key)
	return "fresh"

## 陣営値を int に解決する。キー省略（null）は default_team、未知の表記は警告して default_team。
static func _parse_team(value: Variant, default_team: int) -> int:
	if value == null:
		return default_team
	var key := String(value)
	if TEAM_NAMES.has(key):
		return TEAM_NAMES[key]
	push_warning("StageLoader: 未知の陣営表記 '%s'（player/enemy/neutral のいずれか）＝既定を使用" % key)
	return default_team

## ステージ辞書から BattleState を組み立てる。
## 期待キー: cols, rows, margin, terrain(配列の文字列), player(駒の配列), enemy(squadの配列), bases(配列の辞書)。
## margin＝terrain を盤より何マス外側まで書いたか（外周）。cols/rows は遊べる盤のままで、
## ずれるのは terrain の読み出し位置だけ＝駒・拠点・terrain_skins の座標は盤の0起点で不変。
## 陣営はセクションで決まる（player→内部0 / enemy→内部1）＝駒に "team" は書かない。
## enemy は squad の配列で、各 squad が AI プリセット(ai)を持つ（敵は必ず squad に属する）。
## catalog = { id: UnitType }。ユニットが "type" を持つときステータスを引く（省略時は素の値）＝性能の唯一の出どころ。
## carried = 継承ユニットの直列化リスト（Unit.to_dict() の配列＝前ステージの生存者）。
## roster:carryover のステージで carryover_slots の位置に順に嵌める（案A）。fresh では未使用。
static func build(data: Dictionary, catalog: Dictionary = {}, skin_catalog: Dictionary = {}, carried: Array = []) -> BattleState:
	var cols := int(data.get("cols", 12))
	var rows := int(data.get("rows", 8))
	var state := BattleState.new(cols, rows)
	_apply_terrain(state, data.get("terrain", []), _parse_margin(data))
	var next_id := _apply_units(state, data.get("player", []), catalog, 0, skin_catalog)
	next_id = _apply_squads(state, data.get("enemy", []), catalog, 1, next_id, skin_catalog)
	next_id = _apply_bases(state, data.get("bases", []), catalog, next_id, skin_catalog)
	next_id = _apply_events(state, data.get("events", []), catalog, next_id, skin_catalog)
	_apply_carryover(state, data.get("carryover_slots", []), carried, catalog, next_id)
	# 勝利条件リスト（OR）。例: "victory": [{ "type": "defeat_unit", "actor": "necromancer" }]（ボスの駒に actor）
	var victory: Variant = data.get("victory", [])
	if typeof(victory) == TYPE_ARRAY:
		state.victory_conditions = victory
	# 敗北条件リスト（OR）。例: "defeat": [{ "type": "lose_base", "col": 10, "row": 4 }]
	var defeat: Variant = data.get("defeat", [])
	if typeof(defeat) == TYPE_ARRAY:
		state.defeat_conditions = defeat
	state.enemy_ai = String(data.get("ai", ""))  # squad 外ユニット用の内部フォールバック（新スキーマでは通常未使用）
	state.turn_limit = int(data.get("turn_limit", 0))  # 0＝無制限。実ステージでの必須チェックは load_file 側
	state.roster = _parse_roster(data.get("roster"))  # fresh（既定）/carryover。受け渡しは main が RosterStore 経由で配線
	# 1ターン目の増援はここでは出さない。置き場所の判定に移動コスト表が要るので、
	# set_movement のあと（load_file）で fire_due_events() を呼ぶ。以降のターンは end_turn が拾う。
	return state

## res:// パスの JSON を読み込んで BattleState を返す。失敗時は null。
## ユニット種別は標準ロスター(UnitCatalog)で解決する。
## carried = 継承ユニットの直列化リスト（roster:carryover のステージで carryover_slots に嵌める）。fresh では無視される。
static func load_file(path: String, carried: Array = []) -> BattleState:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("StageLoader: 読み込めない/空: %s" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("StageLoader: JSON が不正: %s" % path)
		return null
	if not data.has("turn_limit") or int(data.get("turn_limit", 0)) <= 0:
		push_error("StageLoader: turn_limit（>0）は必須です（指定なし＝データのバグ）: %s" % path)  # doc/gdd/map.md
	var state := build(data, UnitCatalog.load_default(), SkinCatalog.load_standard(), carried)
	state.set_movement(Movement.load_default())  # 地形ごとの移動コストを有効化
	state.set_sight_cost(TerrainType.sight_cost_table())  # 地形ごとの視線コスト（索敵の遮蔽・減衰）を有効化
	state.fire_due_events()  # 1ターン目に指定された増援を出す（移動コスト表が要るのでここ）
	return state

## 外周（ステージJSON "margin"）の厚み。0＝外周なし。負値は0に丸める。詳細 → doc/gdd/map.md
static func _parse_margin(data: Dictionary) -> int:
	return maxi(int(data.get("margin", 0)), 0)

## 地形グリッド（文字列の配列）を盤に反映。row=行index, col=文字index → offset(col,row)。
## margin（外周）があるグリッドは盤より1周ぶん大きく書かれているので、読み出しを margin ずらす。
## 外周そのものは盤に入れない＝BattleState は cols×rows のまま（駒も入らない・描かれもしない）。
static func _apply_terrain(state: BattleState, grid: Variant, margin: int = 0) -> void:
	if typeof(grid) != TYPE_ARRAY:
		return
	var lines: Array = grid
	for i in lines.size():
		var row := i - margin
		if row < 0 or row >= state.rows:
			continue
		var line := String(lines[i])
		for j in line.length():
			var col := j - margin
			if col < 0 or col >= state.cols:
				continue
			var tid := TerrainType.char_to_id(line[j])
			if tid != TerrainType.DEFAULT_ID:  # 既定地形は明示設定不要
				state.set_terrain(Hex.offset_to_axial(col, row), tid)

## 外周（margin）の地形 → { axial: terrain_id }。盤の外側のセルだけを、既定地形も含めて全て載せる。
## 用途は接続タイル（柵・道）の向き決めだけ＝「盤の外に何があるか」を作者が描いたもの。
## presentation 専用（案P＝terrain_skins と同じ渡し方）で BattleState には入れない。
## 空＝外周なし。空でないことが「作者が描いた」の合図で、盤側はこれがある時だけ縁の推測をやめる。
static func parse_margin_terrain(data: Dictionary) -> Dictionary:
	var out := {}
	var margin := _parse_margin(data)
	if margin <= 0:
		return out
	var grid: Variant = data.get("terrain", [])
	if typeof(grid) != TYPE_ARRAY:
		return out
	var cols := int(data.get("cols", 12))
	var rows := int(data.get("rows", 8))
	var lines: Array = grid
	for i in lines.size():
		var row := i - margin
		var line := String(lines[i])
		for j in line.length():
			var col := j - margin
			if col >= 0 and col < cols and row >= 0 and row < rows:
				continue  # 盤の中は BattleState が持つ＝ここは外周だけ
			out[Hex.offset_to_axial(col, row)] = TerrainType.char_to_id(line[j])
	return out

## res:// パスの JSON から外周の地形を読む（load_terrain_skins と対＝盤の縁の判定を presentation へ）。
static func load_margin_terrain(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return parse_margin_terrain(data)

## 見た目レイヤー：ステージ辞書の "terrain_skins"（[{col,row,skin}]）→ { Vector2i: skin_id }。
## skin は presentation 専用（案P）＝BattleState には入れない。載らないセルは呼び出し側で type 既定にフォールバック。
static func parse_terrain_skins(data: Dictionary) -> Dictionary:
	var out := {}
	var list: Variant = data.get("terrain_skins", [])
	if typeof(list) != TYPE_ARRAY:
		return out
	for e in list:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var hex := Hex.offset_to_axial(int(e.get("col", 0)), int(e.get("row", 0)))
		out[hex] = String(e.get("skin", ""))
	return out

## res:// パスの JSON から terrain_skins を読む（load_file と対＝skin を presentation へ渡すため）。
static func load_terrain_skins(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return parse_terrain_skins(data)

## 会話（シナリオ）：ステージ辞書の "dialogue"（{ intro:[...], outro:[...] }）を取り出す。
## presentation 専用（案P と同じ＝BattleState には入れない）。各行 { speaker, skin, text } ＋任意 when。
## text/speaker は翻訳キー＝表示時に tr() で解決する（i18n。正本 data/i18n/dialogue.csv）。
## roster（名簿＝Unit.to_dict() の配列）を渡すと when 条件を評価して行を絞る。詳細 → doc/campaign/authoring.md
static func parse_dialogue(data: Dictionary, roster: Array = []) -> Dictionary:
	var out := { "intro": [], "outro": [] }
	var dlg: Variant = data.get("dialogue", {})
	if typeof(dlg) != TYPE_DICTIONARY:
		return out
	var joined := _roster_actors(roster)
	for phase in ["intro", "outro"]:
		var lines: Variant = dlg.get(phase, [])
		if typeof(lines) != TYPE_ARRAY:
			continue
		var kept: Array = []
		for line in lines:
			if typeof(line) != TYPE_DICTIONARY or _when_holds(line.get("when"), joined):
				kept.append(line)
		out[phase] = kept
	return out

## 名簿に在籍している actor の集合（兵力ゼロの離脱者も在籍＝会話には出る）。
static func _roster_actors(roster: Array) -> Dictionary:
	var set := {}
	for e in roster:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var a := String(e.get("actor", ""))
		if a != "":
			set[a] = true
	return set

## 会話行の when 条件が成り立つか。未指定（null）は常に真＝条件のない行は必ず出る。
## 対応する表記は "joined:<actor>"（在籍）と、先頭 "!" による否定。未知の表記は真（行を落とさない）。
static func _when_holds(cond: Variant, joined: Dictionary) -> bool:
	if cond == null:
		return true
	var s := String(cond).strip_edges()
	if s == "":
		return true
	var negate := s.begins_with("!")
	if negate:
		s = s.substr(1).strip_edges()
	if not s.begins_with("joined:"):
		push_warning("StageLoader: 未知の会話条件 '%s'＝この行は常に表示" % cond)
		return true
	var actor := s.substr("joined:".length()).strip_edges()
	var has: bool = joined.has(actor)
	return not has if negate else has

## res:// パスの JSON から dialogue を読む（load_file と対＝会話を presentation へ渡すため）。
## roster を渡すと when 条件で行を絞る（省略＝条件つきの行は在籍なしとして扱われる）。
static func load_dialogue(path: String, roster: Array = []) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return { "intro": [], "outro": [] }
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return { "intro": [], "outro": [] }
	return parse_dialogue(data, roster)

## BGM：ステージ辞書の "bgm"（{ main, crisis }）を取り出す。値はトラックID（assets/bgm/{id}.ogg）。
## 会話(skin)と同じく presentation/application 側の関心＝BattleState には入れない。
## 空スロットの穴埋め（冒険譚既定・全体既定）は application/bgm_director.gd。詳細 → doc/audio/bgm.md
static func parse_bgm(data: Dictionary) -> Dictionary:
	return BgmCatalog.parse_slots(data.get("bgm", {}))

## res:// パスの JSON から bgm を読む（load_file と対＝曲の決定を BgmDirector へ渡すため）。
static func load_bgm(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return parse_bgm(data)

## 駒配置リスト（player セクション）を盤に追加。id 省略時は出現順に1始まりで採番。次の採番値を返す。
## team は陣営（呼び出し側が固定＝駒から読まない）。
## "type" があれば catalog からステータスを引く（性能の上書きは不可）。駒が書けるのは troops/level だけ。
## "type" が無ければ素の値（既定: move3・troops8・atk10・def10・level1）。
static func _apply_units(state: BattleState, units: Variant, catalog: Dictionary, team: int, skin_catalog: Dictionary = {}) -> int:
	if typeof(units) != TYPE_ARRAY:
		return 1
	var auto_id := 1
	for u in units:
		var unit := _make_unit(u, catalog, auto_id, team, skin_catalog)
		state.add_unit(unit)
		auto_id += 1
		auto_id = _apply_initial_passengers(state, unit, u.get("passengers", []), catalog, auto_id, skin_catalog)
	return auto_id

## 輸送ユニットの初期搭乗（"passengers": [...]）。各要素は通常のユニット記法（col/row 不要）。
static func _apply_initial_passengers(state: BattleState, transport: Unit, list: Variant, catalog: Dictionary, start_id: int, skin_catalog: Dictionary = {}) -> int:
	if typeof(list) != TYPE_ARRAY or list.is_empty():
		return start_id
	if not transport.is_transport():
		push_warning("StageLoader: capacity 0 のユニットに passengers 指定: id=%d" % transport.id)
		return start_id
	var auto_id := start_id
	for pd in list:
		var p := _make_unit(pd, catalog, auto_id, transport.team, skin_catalog)  # 搭乗は同陣営
		state.put_passenger(transport.id, p)
		auto_id += 1
	return auto_id

## enemy セクション（部隊(squad)の配列）を盤に追加。各部隊は { name?, ai: プリセットラベル, ...上書き, units: [...] }。
## team は陣営（呼び出し側が固定＝敵=1）。敵は必ず squad に属する（バラ配置は無い）。
## units は通常の駒記法（型/スキン/troops・level）と同じで、採番も player の続きから連続する。
## 部隊定義には行動順 order も入る（順番の解決は NearestAttackerBrain＝doc/gdd/ai.md 行動順）。
## 部隊メンバーは BattleState に「unit→部隊」の対応が登録され、AIが部隊のプリセットで振る舞う。
static func _apply_squads(state: BattleState, squads: Variant, catalog: Dictionary, team: int, start_id: int, skin_catalog: Dictionary = {}) -> int:
	if typeof(squads) != TYPE_ARRAY:
		return start_id
	var auto_id := start_id
	for sq in squads:
		var squad := {}
		for key in sq:
			if key != "units":  # units 以外（name/ai/上書きパラメーター）が部隊定義
				squad[key] = sq[key]
		var idx: int = state.squads.size()
		state.squads.append(squad)
		for u in sq.get("units", []):
			var unit := _make_unit(u, catalog, int(u.get("id", auto_id)), team, skin_catalog)
			state.add_unit(unit)
			state.assign_squad(unit.id, idx)
			auto_id += 1
			auto_id = _apply_initial_passengers(state, unit, u.get("passengers", []), catalog, auto_id, skin_catalog)
	return auto_id

## events（時限発生）を読む。いまは増援（type: "reinforce"）だけを扱う。詳細 → doc/gdd/map.md イベント
## 駒はここで組んで（catalog 解決込み）BattleState へ預け、発生ターンに盤へ出す＝domain は JSON を知らない。
## team:"enemy" の増援は1つの部隊として登録し、その index をイベントに持たせる（発生時に assign_squad）。
## 採番は他のセクションの続き。搭載駒（passengers）も同じ列で採番する。
static func _apply_events(state: BattleState, events: Variant, catalog: Dictionary, start_id: int, skin_catalog: Dictionary = {}) -> int:
	if typeof(events) != TYPE_ARRAY:
		return start_id
	var auto_id := start_id
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var type_id := String(e.get("type", "reinforce"))
		if type_id != "reinforce":
			push_warning("StageLoader: 未知のイベント type '%s'（無視）" % type_id)
			continue
		var team := _parse_team(e.get("team"), 0)
		var squad_index := -1
		if team == 1:  # 敵の増援＝1部隊。AIプリセット等の上書きはイベント直下に書く（部隊定義と同じ流儀）
			var squad := {}
			for key in e:
				if not (key in EVENT_KEYS):
					squad[key] = e[key]
			squad_index = state.squads.size()
			state.squads.append(squad)
		var units: Array = []
		for ud in e.get("units", []):
			if typeof(ud) != TYPE_DICTIONARY:
				continue
			var unit := _make_unit(ud, catalog, auto_id, team, skin_catalog)
			auto_id += 1
			var ps: Array = []
			var plist: Variant = ud.get("passengers", [])
			if typeof(plist) == TYPE_ARRAY and not plist.is_empty():
				if unit.is_transport():
					for pd in plist:
						ps.append(_make_unit(pd, catalog, auto_id, team, skin_catalog))  # 搭乗は同陣営
						auto_id += 1
				else:
					push_warning("StageLoader: capacity 0 の増援に passengers 指定: id=%d" % unit.id)
			units.append({ "unit": unit, "passengers": ps })
		state.add_event({
			"turn": int(e.get("turn", 1)), "team": team,
			"label": String(e.get("label", "")), "squad": squad_index,
			"units": units,
		})
	return auto_id

## 拠点リストを盤に追加。各拠点は位置(col/row)・所属(team, 既定は中立)・kind("fort"/"hq", 既定fort)・garrison(控えユニット)を持つ。
## garrison の各要素は { type, count } ＋ 個体の状態（troops 省略＝満員 / level 省略＝1）。
## garrison ユニットは盤上未登場（出撃時に team/pos が決まる）＝採番だけ済ませて Base に積む。
## garrison の生来陣営（native）は拠点の初期所属が既定（中立拠点の駒＝中立＝取った側に寝返る）。
static func _apply_bases(state: BattleState, bases: Variant, catalog: Dictionary, start_id: int, skin_catalog: Dictionary = {}) -> int:
	if typeof(bases) != TYPE_ARRAY:
		return start_id
	var auto_id := start_id
	for b in bases:
		var hex := Hex.offset_to_axial(int(b["col"]), int(b["row"]))
		var base := Base.new(hex, _parse_team(b.get("team"), Base.NEUTRAL), String(b.get("kind", "fort")))
		if b.has("ai"):  # 拠点=1squad（garrison を出す preset）。ai 未指定の拠点はAI出撃しない。ai.md §7
			var squad := {}
			for key in b:
				if not (key in ["col", "row", "team", "kind", "garrison", "native"]):
					squad[key] = b[key]  # ai＋上書き（sight/engage/…）＋行動順 order を部隊定義に
			base.squad_index = state.squads.size()
			state.squads.append(squad)
		for g in b.get("garrison", []):
			for _i in maxi(int(g.get("count", 1)), 1):
				var gu := _make_unit(g, catalog, auto_id, 0, skin_catalog)  # team は出撃時に決まる（deploy で captor 陣営へ）
				gu.set_native_team(_parse_team(g.get("native"), base.native_team))  # 帰属先も揃う（中立＝未確定）
				base.garrison.append(gu)
				auto_id += 1
		state.add_base(base)
	return auto_id  # garrison も id を消費するので次の採番を継ぐ（継承ユニットの配置に使う）

## 継承ユニット（carried＝名簿＝Unit.to_dict() の配列）を carryover_slots に嵌める。詳細 → doc/gdd/map.md
## slots は [{col,row, actor?}]。actor を書いたスロットはその仲間を名指しで置き、指名のないスロットに
## 残りを名簿順で詰める。名指しの相手が名簿に居なければ（未加入）そのスロットは空のまま＝作者の配置が崩れない。
## 盤に出すのは troops > 0 の者だけ＝兵力ゼロの離脱者は名簿に在籍したまま出撃しない（会話には出る）。
## 性能は type から再構築（Unit.from_dict）。出撃できる者がスロット数を超えれば余剰は出撃せず警告。
static func _apply_carryover(state: BattleState, slots: Variant, carried: Array, catalog: Dictionary, start_id: int) -> int:
	if typeof(slots) != TYPE_ARRAY or carried.is_empty():
		return start_id
	# 出撃できるのは在籍者のうち兵力が残っている者だけ（名簿順を保つ）
	var deployable: Array = []
	for e in carried:
		if typeof(e) == TYPE_DICTIONARY and int(e.get("troops", 0)) > 0:
			deployable.append(e)
	var used := {}  # deployable の index -> true（名指しで消費済み）
	var by_actor := {}  # actor -> deployable の index（先勝ち＝名簿順で最初の1体）
	for i in deployable.size():
		var a := String((deployable[i] as Dictionary).get("actor", ""))
		if a != "" and not by_actor.has(a):
			by_actor[a] = i
	# 第1巡: actor 指名のスロットを埋める（該当者が居なければ空のまま）
	var assigned := {}  # slot index -> deployable index
	for si in slots.size():
		if typeof(slots[si]) != TYPE_DICTIONARY:
			continue
		var want := String((slots[si] as Dictionary).get("actor", ""))
		if want == "":
			continue
		if by_actor.has(want):
			assigned[si] = by_actor[want]
			used[by_actor[want]] = true
		else:
			assigned[si] = -1  # 未加入＝このスロットは他の駒に回さず空けておく
	# 第2巡: 指名のないスロットへ残りを名簿順で詰める
	var rest: Array = []
	for i in deployable.size():
		if not used.has(i):
			rest.append(i)
	var next_rest := 0
	for si in slots.size():
		if assigned.has(si) or typeof(slots[si]) != TYPE_DICTIONARY:
			continue
		if next_rest >= rest.size():
			break
		assigned[si] = rest[next_rest]
		next_rest += 1
	# 配置
	var auto_id := start_id
	for si in slots.size():
		var di: int = assigned.get(si, -1)
		if di < 0:
			continue
		var slot: Dictionary = slots[si]
		var snap: Dictionary = deployable[di]
		var type_id := String(snap.get("type", ""))
		var t: UnitType = catalog.get(type_id)
		if t == null and type_id != "":
			push_warning("StageLoader: 継承ユニットの未知 type '%s'＝既定性能で配置" % type_id)
		var unit := Unit.from_dict(snap, t)
		unit.id = auto_id
		unit.team = 0  # 継承は自軍
		unit.set_native_team(0)  # 帰属は確定済み（名簿に載っている＝仲間）
		unit.pos = Hex.offset_to_axial(int(slot.get("col", 0)), int(slot.get("row", 0)))
		state.add_unit(unit)
		auto_id += 1
	var left := rest.size() - next_rest
	if left > 0:
		push_warning("StageLoader: 出撃できる継承 %d 体に対しスロットが足りず %d 体は今回出撃しない" % [deployable.size(), left])
	return auto_id

## ユニット辞書 → Unit。team は陣営（呼び出し側がセクションで固定＝駒から "team" は読まない）。
## 性能（攻撃/防御/移動/射程…）は type が唯一の出どころ＝ステージ側から上書きできない。
## 駒が書けるのは個体の状態だけ: "troops"（損耗・省略＝満員）と "level"（成長・省略＝1）。
## col/row 省略は (0,0)（garrison は出撃時に pos を決めるので無視される）。
static func _make_unit(u: Dictionary, catalog: Dictionary, id: int, team: int, skin_catalog: Dictionary = {}) -> Unit:
	var pos := Hex.offset_to_axial(int(u.get("col", 0)), int(u.get("row", 0)))
	# 見た目(skin)と性能(type)の解決。skin→type は1:1なので、どちらか一方の指定で両方決まる。
	var skin_id := String(u.get("skin", ""))
	var type_id := String(u.get("type", ""))
	if skin_id == "" and type_id != "":
		skin_id = type_id  # type 指定 → 同名スキンを使う
	if type_id == "" and skin_id != "" and not skin_catalog.is_empty():
		type_id = SkinCatalog.type_of_skin(skin_catalog, skin_id)  # skin 指定 → 性能を逆引き
	var t: UnitType = null
	if type_id != "":
		t = catalog.get(type_id)
		if t == null:
			push_warning("StageLoader: 未知のユニット種別: %s" % type_id)
	# 未知 type の保険として無難な既定で作り、type があれば性能を丸ごと写す（数値を焼かない）。
	var unit := Unit.new(id, team, pos, 3, 8, 10, 10, int(u.get("level", 1)), type_id)
	unit.move_type = "ground"
	if t != null:
		unit.apply_type(t)
	unit.troops = int(u.get("troops", unit.max_troops))  # 損耗（省略＝満員）。満員値は type のまま＝回復は type の上限まで戻る
	unit.skin_id = skin_id
	unit.set_native_team(_parse_team(u.get("native"), unit.team))  # 生来の陣営＋帰属先（既定=初期team。garrison は呼び出し側が上書き）
	unit.actor = String(u.get("actor", ""))  # 名前つきの駒（名簿・会話分岐の同一性）。詳細 → doc/gdd/map.md
	return unit  # 飛行判定は Unit.is_aerial()＝move_type=="flight" で行う
