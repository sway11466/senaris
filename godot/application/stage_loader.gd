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

## イベント自身のキー。敵の増援ではこれ以外（ai・sight 等）を部隊定義として拾う。
const EVENT_KEYS := ["id", "type", "team", "turn", "on", "col", "row", "once", "label", "units", "dialogue", "focus"]

## 戦力供給の指定（player の駒の任意キー "supply"）＝名簿とどう突き合わせるか。詳細 → doc/gdd/campaigns.md 配置
const SUPPLY_CARRY := ""          # 省略＝名簿の状態（Lv・troops）のまま持ち越す
const SUPPLY_JOIN := "join"       # 名簿を見ずに配給（初登場）＝Lv も兵数も初期値
const SUPPLY_REFILL := "refill"   # 名簿から出すが兵数は満員へ（Lv は名簿のまま）
const SUPPLY_REVIVE := "revive"   # refill に加えて、兵力ゼロの離脱者も満員で呼び戻す
const SUPPLY_VALUES := [SUPPLY_JOIN, SUPPLY_REFILL, SUPPLY_REVIVE]

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
## enemy は squad の配列で、各 squad が特性(ai)を持つ（敵は必ず squad に属する）。
## catalog = { id: UnitType }。ユニットが "type" を持つときステータスを引く（省略時は素の値）＝性能の唯一の出どころ。
## carried = 継承ユニットの直列化リスト（Unit.to_dict() の配列＝名簿）。
## player の駒のうち actor を持つものだけが名簿と突き合わされる（詳細 → _apply_units）。
## 名簿が空／突き合う actor が無ければ何も起きない＝独立のステージは carried を無視する。
static func build(data: Dictionary, catalog: Dictionary = {}, skin_catalog: Dictionary = {}, carried: Array = []) -> BattleState:
	var cols := int(data.get("cols", 12))
	var rows := int(data.get("rows", 8))
	var state := BattleState.new(cols, rows)
	_apply_terrain(state, data.get("terrain", []), _parse_margin(data))
	var next_id := _apply_units(state, data.get("player", []), catalog, 0, skin_catalog, carried)
	next_id = _apply_squads(state, data.get("enemy", []), catalog, 1, next_id, skin_catalog)
	next_id = _apply_bases(state, data.get("bases", []), catalog, next_id, skin_catalog)
	next_id = _apply_events(state, data.get("events", []), catalog, next_id, skin_catalog)
	# 勝利条件リスト（OR）。例: "victory": [{ "type": "defeat_unit", "actor": "necromancer" }]（ボスの駒に actor）
	var victory: Variant = data.get("victory", [])
	if typeof(victory) == TYPE_ARRAY:
		state.victory_conditions = victory
	# 敗北条件リスト（OR）。例: "defeat": [{ "type": "lose_base", "col": 10, "row": 4 }]
	var defeat: Variant = data.get("defeat", [])
	if typeof(defeat) == TYPE_ARRAY:
		state.defeat_conditions = defeat
	state.turn_limit = int(data.get("turn_limit", 0))  # 0＝無制限。実ステージでの必須チェックは load_file 側
	# 1ターン目の増援はここでは出さない。置き場所の判定に移動コスト表が要るので、
	# set_movement のあと（load_file）で fire_due_events() を呼ぶ。以降のターンは end_turn が拾う。
	return state

## res:// パスの JSON を読み込んで BattleState を返す。失敗時は null。
## ユニット種別は標準ロスター(UnitCatalog)で解決する。
## carried = 継承ユニットの直列化リスト（名簿）。player の actor 付きの駒がここから引かれる。
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
## skin は presentation 専用（案P）＝BattleState には入れない。載らないセルは型IDと同名のスキンで描く
## （足場のみ。オブジェクトは同名が無いので必ず書く → doc/gdd/terrain.md）。
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

## 見た目レイヤー：マスごとの高さ上書き。terrain_skins のエントリに elevation と floor をペアで
## 書くと、そのマスだけスキンの値を差し替える（無視フラグ・行/列の基準の扱いはスキン定義のまま
## → doc/gdd/terrain.md 盤の高さ）。片方だけ・数値でない値は書き間違い＝エラーにして適用しない
## （黙って半分だけ効くと、駒が地形にめり込んで原因が追えなくなる）。
static func parse_height_overrides(data: Dictionary) -> Dictionary:
	var out := {}
	var list: Variant = data.get("terrain_skins", [])
	if typeof(list) != TYPE_ARRAY:
		return out
	for e in list:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var has_e: bool = e.has("elevation")
		var has_f: bool = e.has("floor")
		if not has_e and not has_f:
			continue
		var col := int(e.get("col", 0))
		var row := int(e.get("row", 0))
		if has_e != has_f:
			push_error("stage: terrain_skins (%d, %d) の高さ上書きは elevation と floor をペアで書く" % [col, row])
			continue
		var ev: Variant = e.get("elevation")
		var fl: Variant = e.get("floor")
		if not (typeof(ev) in [TYPE_INT, TYPE_FLOAT]) or not (typeof(fl) in [TYPE_INT, TYPE_FLOAT]):
			push_error("stage: terrain_skins (%d, %d) の elevation / floor が数値でない" % [col, row])
			continue
		out[Hex.offset_to_axial(col, row)] = { "elevation": float(ev), "floor": float(fl) }
	return out

## 見た目レイヤー：盤の基準高さ。ステージ辞書の "height"（{row:[..], col:[..]}）→ { row, col }。
## あるマスの見た目の高さ ＝ 行の基準 ＋ 列の基準 ＋ スキンの elevation（→ doc/gdd/terrain.md 盤の高さ）。
## 移動にも戦闘にも視線にも入らない。書いていなければ平ら。書くなら盤の行数・列数と長さを合わせる
## （足りない/多い配列は黙って0で埋めずに弾く＝どこまで指定したつもりかが分からなくなるため）。
static func parse_board_height(data: Dictionary, cols: int, rows: int) -> Dictionary:
	var out := { "row": [], "col": [] }
	var h: Variant = data.get("height", null)
	if typeof(h) != TYPE_DICTIONARY:
		return out
	out["row"] = _height_axis(h, "row", rows)
	out["col"] = _height_axis(h, "col", cols)
	return out

## height の1軸ぶん。長さが合わなければ空（＝その軸は平ら）に倒し、理由をログに出す。
static func _height_axis(h: Dictionary, key: String, want: int) -> Array:
	var v: Variant = h.get(key, null)
	if typeof(v) != TYPE_ARRAY:
		return []
	var arr: Array = v
	if arr.size() != want:
		push_error("stage: height.%s の長さ %d が盤の %d と違う" % [key, arr.size(), want])
		return []
	var out: Array = []
	for e in arr:
		out.append(float(e) if typeof(e) == TYPE_INT or typeof(e) == TYPE_FLOAT else 0.0)
	return out

## res:// パスの JSON から盤の基準高さを読む（load_file と対＝見た目を presentation へ渡すため）。
static func load_board_height(path: String, cols: int, rows: int) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return { "row": [], "col": [] }
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return { "row": [], "col": [] }
	return parse_board_height(data, cols, rows)

## res:// パスの JSON から terrain_skins を読む（load_file と対＝skin を presentation へ渡すため）。
static func load_terrain_skins(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return parse_terrain_skins(data)

## res:// パスの JSON からマスごとの高さ上書きを読む（load_terrain_skins と対）。
static func load_height_overrides(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return parse_height_overrides(data)

## 会話（シナリオ）：ステージ辞書の "dialogue" を台本ごとに取り出す。intro/outro は戦闘前後、
## それ以外のキーは events の "dialogue" が名指しする戦闘中の会話（doc/gdd/map.md イベント）。
## presentation 専用（案P と同じ＝BattleState には入れない）。各行 { speaker, skin, text } ＋任意 when。
## text/speaker は翻訳キー＝表示時に tr() で解決する（i18n。正本 data/i18n/dialogue.csv）。
## roster（名簿＝Unit.to_dict() の配列）を渡すと when 条件を評価して行を絞る。詳細 → doc/campaign/authoring.md
static func parse_dialogue(data: Dictionary, roster: Array = []) -> Dictionary:
	var out := { "intro": [], "outro": [] }  # 前後は台本が無くても空で返す（呼び出し側が素通りできる）
	var dlg: Variant = data.get("dialogue", {})
	if typeof(dlg) != TYPE_DICTIONARY:
		return out
	var joined := _roster_actors(roster)
	for phase in (dlg as Dictionary):
		var lines: Variant = dlg[phase]
		if typeof(lines) != TYPE_ARRAY:
			continue
		var kept: Array = []
		for line in lines:
			if typeof(line) != TYPE_DICTIONARY or _when_holds(line.get("when"), joined):
				kept.append(line)
		out[String(phase)] = kept
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

## BGM：ステージ辞書の "bgm"（{ main }）を取り出す。値はトラックID（assets/bgm/{id}.ogg）。
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

## 奥の背景：ステージ辞書の "backdrop" を取り出す。値は絵のID（assets/backdrop/{id}.png）。
## 戦闘窓の水平線から上に敷く1枚で、空とは限らない（洞窟なら岩壁）。書かなければ空文字＝
## 水平線を引かず地面が窓の上端まで続く。見た目の関心なので BattleState には入れない。
## 詳細 → doc/tech/combat_scene.md
static func parse_backdrop(data: Dictionary) -> String:
	return String(data.get("backdrop", ""))

## res:// パスの JSON から backdrop を読む（load_file と対＝戦闘演出へ渡すため）。
static func load_backdrop(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ""
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	return parse_backdrop(data)

## 靄：ステージ辞書の "haze" を取り出す。値は戦闘窓の奥（水平線）での靄の濃さ（0〜1）。
## 必須＝書いていなければデータのバグ（省略時の既定は持たない）。見た目の関心なので BattleState には入れない。
## 詳細 → doc/tech/combat_scene.md
static func parse_haze(data: Dictionary, path: String) -> float:
	var v: Variant = data.get("haze")
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		push_error("StageLoader: haze（0〜1 の数値）は必須です（指定なし＝データのバグ）: %s" % path)
		return 0.0
	return clampf(float(v), 0.0, 1.0)

## res:// パスの JSON から haze を読む（load_file と対＝戦闘演出へ渡すため）。
static func load_haze(path: String) -> float:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return 0.0
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return 0.0
	return parse_haze(data, path)

## res:// パスの JSON から rank（評価ランクの閾値）を読む（load_file と対＝評価を main へ渡すため）。
## rank が無いステージでは空辞書を返す＝ランクを評価・表示しない。
static func load_rank(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var rank: Variant = data.get("rank", {})
	if typeof(rank) != TYPE_DICTIONARY:
		return {}
	return rank

## 戦果の分母＝ステージ開始時の自軍戦力（→ doc/gdd/rank.md 生存）。数えるのは生来の陣営が
## 自軍か中立の駒と、自軍の増援イベントの駒（未発火も含む）。兵器は数えない。
## 盤の現況ではなくステージ定義から導出する＝中断セーブから再開しても同じ値になる。
## 名簿で出撃が決まる駒（actor 持ち）は state.has_sortied で見る＝未加入・離脱者は数えない。
static func count_start_allies(data: Dictionary, state: BattleState, catalog: Dictionary,
		skin_catalog: Dictionary = {}) -> int:
	var n := 0
	for u in _as_dicts(data.get("player", [])):
		if not _starts_in_force(u, state):
			continue
		n += _force_size(u, catalog, skin_catalog)
	for b in _as_dicts(data.get("bases", [])):
		var base_team := _parse_team(b.get("team"), Base.NEUTRAL)  # native 書き忘れの保険＝_apply_bases と同じ倒し方
		for g in _as_dicts(b.get("garrison", [])):
			if _parse_team(g.get("native"), base_team) == 1:
				continue  # 敵 native の控えは自軍の戦力ではない
			n += maxi(int(g.get("count", 1)), 1) * _force_size(g, catalog, skin_catalog)
	for e in _as_dicts(data.get("events", [])):
		if String(e.get("type", "reinforce")) != "reinforce":
			continue
		if _parse_team(e.get("team"), 0) != 0:
			continue
		for u in _as_dicts(e.get("units", [])):
			n += _force_size(u, catalog, skin_catalog)
	return n

## res:// パスから戦果の分母を数える（load_rank と対＝main は state と path だけで呼べる）。
static func count_start_allies_at(path: String, state: BattleState) -> int:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return 0
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return 0
	return count_start_allies(data, state, UnitCatalog.load_default(), SkinCatalog.load_standard())

## その駒はこの戦いで盤に出たか（_resolve_player_unit と同じ判定を数える側から見たもの）。
static func _starts_in_force(u: Dictionary, state: BattleState) -> bool:
	var actor := String(u.get("actor", ""))
	if actor == "" or _parse_supply(u) == SUPPLY_JOIN:
		return true  # 配給＝名簿を見ずに必ず出る
	return state.has_sortied(actor)

## 駒1つぶんの戦力の数＝本体（兵器なら0）＋搭乗している駒。
static func _force_size(u: Dictionary, catalog: Dictionary, skin_catalog: Dictionary) -> int:
	var n := 0 if _is_emplacement_data(u, catalog, skin_catalog) else 1
	for p in _as_dicts(u.get("passengers", [])):
		n += _force_size(p, catalog, skin_catalog)
	return n

## 駒の記法（type / skin）から兵器かどうかを引く。未知の type は兵器でないものとして扱う。
static func _is_emplacement_data(u: Dictionary, catalog: Dictionary, skin_catalog: Dictionary) -> bool:
	var type_id := String(u.get("type", ""))
	if type_id == "":
		var skin_id := String(u.get("skin", ""))
		if skin_id == "" or skin_catalog.is_empty():
			return false
		type_id = SkinCatalog.type_of_skin(skin_catalog, skin_id)
	var t: UnitType = catalog.get(type_id)
	return t != null and t.move_type == "stationary"

## Variant を辞書の配列として読む（ステージJSONを数えるときの共通の入口）。
static func _as_dicts(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for e in value:
		if typeof(e) == TYPE_DICTIONARY:
			out.append(e)
	return out

## 依頼書（出撃確認の紙 → doc/gdd/stage_select.md 依頼書）に載せるステージ情報。
## { "party": 出撃する顔ぶれ, "carryover": 戦力を持ち越すステージか }
static func parse_briefing(data: Dictionary, catalog: Dictionary = {}, skin_catalog: Dictionary = {},
		carried: Array = []) -> Dictionary:
	return {
		"party": preview_player_units(data, catalog, skin_catalog, carried),
		"carryover": is_carryover_stage(data),
	}

## res:// パスの JSON から依頼書の情報を読む（load_file と対＝セレクトへ渡すため）。
static func load_briefing(path: String, carried: Array = []) -> Dictionary:
	var empty := { "party": [], "carryover": false }
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return empty
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return empty
	return parse_briefing(data, UnitCatalog.load_default(), SkinCatalog.load_standard(), carried)

## 出撃前に見せる自軍の顔ぶれ。盤を組むのと同じ駒解決を通し、player の記述順で返す。
## 輸送の passengers も出撃する戦力なので続けて並べる。増援（events）は見ない＝盤で出会うものを先に見せない。
## 各要素: { "skin_id": 見た目のID, "available": 出撃できるか, "carried": 名簿に載る駒か }
##   available=false … 名簿に居るが兵力ゼロで出撃しない（紙では沈めて並べる）
##   carried=true    … actor を持つ＝この戦いのあと名簿に残る（紙では引き継ぐ隊として分ける）
## 名簿に居ない駒（未加入）は返さない＝盤に出ないものは紙にも出ない。
static func preview_player_units(data: Dictionary, catalog: Dictionary = {}, skin_catalog: Dictionary = {},
		carried: Array = []) -> Array:
	var out: Array = []
	var units: Variant = data.get("player", [])
	if typeof(units) != TYPE_ARRAY:
		return out
	var by_actor := _roster_by_actor(carried)
	for u in units:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var unit := _resolve_player_unit(u, catalog, 1, 0, skin_catalog, by_actor)
		if unit != null:
			out.append({ "skin_id": unit.skin_id, "available": true, "carried": unit.actor != "" })
			_append_preview_passengers(out, u.get("passengers", []), catalog, skin_catalog)
			continue
		# 盤に出ない駒のうち、名簿に居るもの＝兵力ゼロの離脱者。居ないものは未加入なので並べない。
		var actor := String(u.get("actor", ""))
		if actor == "" or not by_actor.has(actor):
			continue
		var left := _make_carried_unit(u, by_actor[actor], catalog, 1, skin_catalog, false)
		out.append({ "skin_id": left.skin_id, "available": false, "carried": true })
	return out

## 輸送に初めから乗っている駒を顔ぶれに足す（配給のみ＝名簿とは突き合わせない＝引き継がない）。
static func _append_preview_passengers(out: Array, list: Variant, catalog: Dictionary, skin_catalog: Dictionary) -> void:
	if typeof(list) != TYPE_ARRAY:
		return
	for pd in list:
		if typeof(pd) != TYPE_DICTIONARY:
			continue
		var p := _make_unit(pd, catalog, 1, 0, skin_catalog)
		out.append({ "skin_id": p.skin_id, "available": true, "carried": false })

## 戦力を持ち越すステージか（継承／独立 → doc/gdd/campaigns.md 戦力供給モデル）。
## 名簿に載る駒（actor 持ち）が1つでもあれば継承＝この戦いの生き残りが次へ渡る。
static func is_carryover_stage(data: Dictionary) -> bool:
	var units: Variant = data.get("player", [])
	if typeof(units) != TYPE_ARRAY:
		return false
	for u in units:
		if typeof(u) == TYPE_DICTIONARY and String(u.get("actor", "")) != "":
			return true
	return false

## 駒配置リスト（player セクション）を盤に追加。出現順に1始まりで採番し、次の採番値を返す。
## team は陣営（呼び出し側が固定＝駒から読まない）。
## "type" があれば catalog からステータスを引く（性能の上書きは不可）。駒が書けるのは troops/level だけ。
## "type" が無ければ素の値（既定: move3・troops8・atk10・def10・level1）。
##
## carried（名簿）との突き合わせ＝戦力供給モデル。詳細 → doc/gdd/campaigns.md 配置
##   actor なし              → 配給。そのステージ限りの駒（名簿に載らない）
##   actor だけ              → 名簿から引く。居ない／兵力ゼロなら盤に出さない（その位置は空のまま）
##   supply:"join"           → 配給。名簿は見ない＝初登場（クリア時に名簿へ載る）
##   supply:"refill"         → 名簿から引き、兵数だけ満員へ（Lv は名簿のまま）。離脱者は出さない
##   supply:"revive"         → refill に加えて兵力ゼロの離脱者も満員で出す
## 出さなかった駒は id を消費しない（採番は盤に乗った駒の順）。
static func _apply_units(state: BattleState, units: Variant, catalog: Dictionary, team: int, skin_catalog: Dictionary = {}, carried: Array = []) -> int:
	if typeof(units) != TYPE_ARRAY:
		return 1
	var by_actor := _roster_by_actor(carried)
	var auto_id := 1
	for u in units:
		var unit := _resolve_player_unit(u, catalog, auto_id, team, skin_catalog, by_actor)
		if unit == null:
			continue  # 名簿に居ない／離脱者＝この駒は今回出撃しない
		state.add_unit(unit)
		auto_id += 1
		auto_id = _apply_initial_passengers(state, unit, u.get("passengers", []), catalog, auto_id, skin_catalog)
	return auto_id

## 名簿を actor で引く索引。同じ actor が重複していれば名簿順で最初の1体が勝つ。
static func _roster_by_actor(carried: Array) -> Dictionary:
	var by_actor := {}
	for e in carried:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var a := String(e.get("actor", ""))
		if a != "" and not by_actor.has(a):
			by_actor[a] = e
	return by_actor

## player の駒を1つ解決する（配給するか、名簿から引くか、出さないか）。null＝盤に出さない。
static func _resolve_player_unit(u: Dictionary, catalog: Dictionary, id: int, team: int,
		skin_catalog: Dictionary, by_actor: Dictionary) -> Unit:
	var actor := String(u.get("actor", ""))
	var supply := _parse_supply(u)
	if actor == "" or supply == SUPPLY_JOIN:
		return _make_unit(u, catalog, id, team, skin_catalog)  # 配給（ステージが戦力を用意する）
	if not by_actor.has(actor):
		return null  # 未加入／まだ登場していない＝勝手に湧かせない
	var snap: Dictionary = by_actor[actor]
	if int(snap.get("troops", 0)) <= 0 and supply != SUPPLY_REVIVE:
		return null  # 兵力ゼロの離脱者は名簿に在籍したまま出撃しない（会話には出る）
	return _make_carried_unit(u, snap, catalog, id, skin_catalog, supply != SUPPLY_CARRY)

## 駒の "supply" を解決する。未知の値は警告して省略扱い（名簿のまま持ち越す）。
static func _parse_supply(u: Dictionary) -> String:
	if u.has("join"):  # 旧キー。黙って無視すると駒が盤から消えて気づけない
		push_warning("StageLoader: 'join' は廃止＝\"supply\": \"join\" に書き換える（doc/gdd/campaigns.md 配置）")
	var supply := String(u.get("supply", SUPPLY_CARRY))
	if supply == SUPPLY_CARRY or SUPPLY_VALUES.has(supply):
		return supply
	push_warning("StageLoader: 未知の supply '%s'（join/refill/revive のいずれか）＝名簿のまま出す" % supply)
	return SUPPLY_CARRY

## 名簿のスナップショットから継承の駒を作る。性能（type/skin）はステージJSONが優先で、省けば名簿から引く。
## 個体の状態（level/troops/max_troops）は名簿が持つ＝ステージ側に数値を書いても効かない。
## 名簿はプレイヤーの手元にあるセーブなので、性能の出どころはステージ側に置く。
## refill＝兵数だけ満員へ戻す（supply: refill/revive）。Lv は名簿のまま＝成長は消えない。
static func _make_carried_unit(u: Dictionary, snap: Dictionary, catalog: Dictionary, id: int,
		skin_catalog: Dictionary, refill: bool = false) -> Unit:
	if u.has("troops") or u.has("level"):
		push_warning("StageLoader: 継承の駒 '%s' の troops/level はステージ側では効かない（名簿が持つ）"
			% String(snap.get("actor", "")))
	var merged := snap.duplicate()
	var type_id := String(u.get("type", ""))
	var skin_id := String(u.get("skin", ""))
	if type_id == "" and skin_id != "" and not skin_catalog.is_empty():
		type_id = SkinCatalog.type_of_skin(skin_catalog, skin_id)  # skin 指定 → 性能を逆引き
	if type_id != "":
		merged["type"] = type_id
		merged["skin"] = skin_id if skin_id != "" else type_id
	elif skin_id != "":
		merged["skin"] = skin_id  # 見た目だけ差し替え（性能は名簿のまま）
	var final_type := String(merged.get("type", ""))
	var t: UnitType = catalog.get(final_type)
	if t == null:
		push_warning("StageLoader: 継承ユニットの未知 type '%s'＝既定性能で配置" % final_type)
	elif final_type != String(snap.get("type", "")):
		merged["max_troops"] = t.max_troops  # 型が変われば満員値も新しい型のもの（損耗 troops は名簿のまま）
	if refill:
		merged["troops"] = int(merged.get("max_troops", 8))  # 幕間の補充・離脱者の復帰＝満員で出す
	var unit := Unit.from_dict(merged, t)
	unit.id = id
	unit.team = 0  # 継承は自軍
	unit.set_native_team(0)  # 帰属は確定済み（名簿に載っている＝仲間）
	unit.pos = Hex.offset_to_axial(int(u.get("col", 0)), int(u.get("row", 0)))
	return unit

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

## enemy セクション（部隊(squad)の配列）を盤に追加。各部隊は { name?, ai: 特性id, ...上書き, units: [...] }。
## team は陣営（呼び出し側が固定＝敵=1）。敵は必ず squad に属する（バラ配置は無い）。
## units は通常の駒記法（型/スキン/troops・level）と同じで、採番も player の続きから連続する。
## 部隊定義には行動順 order も入る（順番の解決は TraitBrain＝doc/gdd/ai.md 行動順）。
## 部隊メンバーは BattleState に「unit→部隊」の対応が登録され、AIが部隊の特性で振る舞う。
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

## events（途中で起きること）を読む。詳細 → doc/gdd/map.md イベント
## 引き金は turn（Nターン目）か on（盤の出来事＝いまは "capture"＝拠点の占領・col/row で拠点を指す）。
## 中身は type＝増援（"reinforce"）か会話だけ（"talk"）。
## 駒はここで組んで（catalog 解決込み）BattleState へ預け、発生時に盤へ出す＝domain は JSON を知らない。
## team:"enemy" の増援は1つの部隊として登録し、その index をイベントに持たせる（発生時に assign_squad）。
## 部隊定義（ai・パラメーターの上書き・行動順 order）はイベント直下に書く＝EVENT_KEYS 以外を拾う。
## order は敵の増援にも要る（湧いた部隊も行動順の列に並ぶ）＝抜けは test_data_integrity が捕まえる。
## id はイベントの名前（必須・ステージ内で一意）＝セーブが未発火のイベントを識別するのに使う。
## 欠落・重複は push_error（turn_limit と同じ扱い）＝ test_data_integrity も同じ検査を持つ。
## 採番は他のセクションの続き。搭載駒（passengers）も同じ列で採番する。
static func _apply_events(state: BattleState, events: Variant, catalog: Dictionary, start_id: int, skin_catalog: Dictionary = {}) -> int:
	if typeof(events) != TYPE_ARRAY:
		return start_id
	var auto_id := start_id
	var seen_ids := {}
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var event_id := String(e.get("id", ""))
		if event_id.is_empty():
			push_error("StageLoader: イベントの id（文字列）は必須です（指定なし＝データのバグ）")
		elif seen_ids.has(event_id):
			push_error("StageLoader: イベントの id '%s' がステージ内で重複（＝データのバグ）" % event_id)
		else:
			seen_ids[event_id] = true
		var type_id := String(e.get("type", "reinforce"))
		if type_id != "reinforce" and type_id != "talk":
			push_warning("StageLoader: 未知のイベント type '%s'（無視）" % type_id)
			continue
		var on := String(e.get("on", ""))
		if on != "" and on != "capture":
			push_warning("StageLoader: 未知のイベント引き金 on '%s'（無視）" % on)
			continue
		var hex := Vector2i.MAX
		if on == "capture":
			if not (e.has("col") and e.has("row")):
				push_warning("StageLoader: on:\"capture\" のイベントに拠点の col/row が無い（無視）")
				continue
			hex = Hex.offset_to_axial(int(e["col"]), int(e["row"]))
		var team := _parse_team(e.get("team"), 0)
		var squad_index := -1
		if team == 1 and type_id == "reinforce":  # 敵の増援＝1部隊。AIプリセット等の上書きはイベント直下に書く（部隊定義と同じ流儀）
			var squad := {}
			for key in e:
				if not (key in EVENT_KEYS):
					squad[key] = e[key]
			squad_index = state.squads.size()
			state.squads.append(squad)
		var units: Array = []
		var raw_units: Variant = e.get("units", [])
		var has_units := typeof(raw_units) == TYPE_ARRAY and not (raw_units as Array).is_empty()
		if type_id == "talk":
			if has_units:
				push_warning("StageLoader: type:\"talk\" のイベントに units 指定（駒は出ない）")
		elif has_units:
			for ud in raw_units:
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
		var dialogue := String(e.get("dialogue", ""))
		if dialogue != "" and on == "" and team != 0:
			# turn 起点の敵イベントは敵の手番が始まる時点で起きる＝AI が動き出す前に盤を止められない。
			# 占領（on:"capture"）は敵の1手の切れ目で起きるので、敵側でも会話を流せる。
			push_warning("StageLoader: turn 起点の dialogue は team:\"player\" のイベントで使う（この会話は流れない）: %s" % dialogue)
		state.add_event({
			"id": event_id,
			"turn": int(e.get("turn", 1)), "team": team,
			"on": on, "hex": hex, "once": String(e.get("once", "")),
			"label": String(e.get("label", "")), "squad": squad_index,
			"dialogue": dialogue, "focus": bool(e.get("focus", false)), "units": units,
		})
	return auto_id

## 拠点リストを盤に追加。各拠点は位置(col/row)・開始時の所有者(team, 既定は中立)・
## 誰が休めるか(rest: "player"/"enemy"/"both", 既定 both)・本拠地の印(hq: "player"/"enemy", 無ければ普通の砦)・
## garrison(控えユニット)を持つ。hq≠team＝開始時点で奪われている本拠地。
## garrison の各要素は { type, count, native } ＋ 個体の状態（troops 省略＝満員 / level 省略＝1）。
## garrison ユニットは盤上未登場（出撃時に team/pos が決まる）＝採番だけ済ませて Base に積む。
## garrison の生来陣営（native）は必須＝拠点からの既定は無い。書き忘れは警告し、開始時の所有者に倒す
## （中立拠点なら中立＝取った側に寝返る）。詳細 → doc/gdd/map.md（拠点の値・帰属）。
static func _apply_bases(state: BattleState, bases: Variant, catalog: Dictionary, start_id: int, skin_catalog: Dictionary = {}) -> int:
	if typeof(bases) != TYPE_ARRAY:
		return start_id
	var auto_id := start_id
	for b in bases:
		var hex := Hex.offset_to_axial(int(b["col"]), int(b["row"]))
		var base := Base.new(hex, _parse_team(b.get("team"), Base.NEUTRAL),
			_parse_team(b.get("hq"), Base.NO_HQ), String(b.get("rest", Base.REST_BOTH)))
		if b.has("rest") and not Base.REST_VALUES.has(String(b["rest"])):
			push_warning("StageLoader: 拠点(%d,%d) の rest が不正: %s（both 扱い）" % [int(b["col"]), int(b["row"]), str(b["rest"])])
		if b.has("kind") or b.has("native"):
			push_warning("StageLoader: 拠点(%d,%d) の kind/native は廃止＝hq/rest に書き換える（doc/gdd/map.md）" % [int(b["col"]), int(b["row"])])
		if b.has("ai"):  # 拠点そのものが1部隊（garrison を出す）。ai 未指定の拠点はAI出撃しない
			var squad := {}
			for key in b:
				if not (key in ["col", "row", "team", "hq", "rest", "garrison", "kind", "native"]):
					squad[key] = b[key]  # ai＋パラメーターの上書き（sight/stack）＋行動順 order を部隊定義に
			base.squad_index = state.squads.size()
			state.squads.append(squad)
		for g in b.get("garrison", []):
			if not g.has("native"):
				push_warning("StageLoader: 拠点(%d,%d) の控え %s に native が無い（開始時の所有者に倒す）"
					% [int(b["col"]), int(b["row"]), String(g.get("skin", g.get("type", "?")))])
			for _i in maxi(int(g.get("count", 1)), 1):
				var gu := _make_unit(g, catalog, auto_id, 0, skin_catalog)  # team は出撃時に決まる（deploy で captor 陣営へ）
				gu.set_native_team(_parse_team(g.get("native"), base.team))  # 帰属先も揃う（中立＝未確定）
				base.garrison.append(gu)
				auto_id += 1
		state.add_base(base)
	return auto_id  # garrison も id を消費するので次の採番を継ぐ

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
	unit.move_type = "foot"
	if t != null:
		unit.apply_type(t)
	unit.troops = int(u.get("troops", unit.max_troops))  # 損耗（省略＝満員）。満員値は type のまま＝回復は type の上限まで戻る
	unit.skin_id = skin_id
	unit.set_native_team(_parse_team(u.get("native"), unit.team))  # 生来の陣営＋帰属先（既定=初期team。garrison は呼び出し側が上書き）
	unit.actor = String(u.get("actor", ""))  # 名前つきの駒（名簿・会話分岐の同一性）。詳細 → doc/gdd/map.md
	return unit  # 飛行判定は Unit.is_aerial()＝move_type=="flight" で行う
