extends RefCounted
class_name BattleState
## 戦闘全体の状態 ＝ 中断セーブの本体（唯一の真実）。
## Godot ノード非依存（extends RefCounted）。見た目の状態はここに含めない。
## 詳細 → doc/tech/architecture.md, doc/tech/gamesystem.md

var cols: int  ## 矩形フィールドの幅（offset col 数）
var rows: int  ## 矩形フィールドの高さ（offset row 数）

var current_team: int = 0  ## 現在のターンの陣営
var turn_number: int = 1   ## ターン番号（両陣営が1巡で+1）
var turn_limit: int = 0    ## ターン上限（超過でプレイヤー敗北・引き分けなし）。0＝無制限。実ステージJSONでは必須指定。詳細 → doc/gdd/map.md
var roster: String = "fresh"  ## 戦力供給モデル（"fresh"=独立/"carryover"=継承）。ステージJSONの roster から。継承ステージ間の受け渡しに使う。詳細 → doc/gdd/map.md

var _units: Array[Unit] = []
var _moved := {}       # unit_id -> true（攻撃前の移動を1回使った）
var _post_moved := {}  # unit_id -> true（攻撃後の再移動を1回使った）
var _attacked := {}    # unit_id -> true（このターンに攻撃済み）
var _done := {}        # unit_id -> true（コマンドメニューの「待機」等で明示的に行動終了）
var _spent := {}       # unit_id -> int（このターンに使った移動コスト。move と比較）
var _terrain := {}   # Vector2i(axial) -> terrain_id（未登録は平地）
var _movement := {}  # move_type -> { 地形名: コスト }（空＝全地形コスト1の従来挙動）
var _bases: Array[Base] = []  # 拠点（占領・出撃・回復）。詳細 → doc/gdd/map.md

## 勝利条件リスト（OR＝どれか1つ満たせば勝利）。空＝殲滅のみ（従来挙動）。詳細 → doc/gdd/map.md（勝敗条件）
## 要素は dict。現在対応: { "type": "defeat_unit", "actor": <String> } ＝ ボス撃破（駒に actor を書いて名指す）
var victory_conditions: Array = []

## 敗北条件リスト（OR＝どれか1つ満たせば敗北）。空＝自軍消滅・本拠地喪失・時間切れの常時ルールのみ。
## 要素は dict。現在対応: { "type": "lose_base", "col": <int>, "row": <int> } ＝ 指定拠点を敵に奪われる
##                       { "type": "lose_unit", "actors": [<String>, …] } ＝ 護衛対象の喪失
## 本拠地(hq)喪失の常時ルールとは別軸＝あちらは陣営の要、こちらはステージが名指しする守り物。
var defeat_conditions: Array = []

## 敵チーム既定のAIプリセットラベル（ステージJSONの "ai"。空＝charge）。詳細 → doc/gdd/ai.md
## 部隊(squad)に属するユニットは部隊の割り当てが優先。これは部隊外ユニットの既定。
var enemy_ai: String = ""

## 部隊(squad)＝AIプリセットを共有するユニットの束。詳細 → doc/gdd/ai.md
## 要素は dict: { "name": 表示名, "ai": プリセットラベル, ...プリセット値の上書き（sight/retreat/advance 等） }
var squads: Array = []
var _squad_of := {}  # unit_id -> squads の index（部隊に属さないユニットは未登録）

## unit_id を部隊 squad_index に所属させる（StageLoader が配線）。
func assign_squad(unit_id: int, squad_index: int) -> void:
	_squad_of[unit_id] = squad_index

## unit_id の所属部隊（dict）。部隊に属さなければ空 dict。
func squad_of(unit_id: int) -> Dictionary:
	var idx := squad_index_of(unit_id)
	return squads[idx] if idx >= 0 else {}

## unit_id の所属部隊 index（部隊に属さなければ -1）。一斉警戒（同部隊判定）に使う。
func squad_index_of(unit_id: int) -> int:
	var idx: Variant = _squad_of.get(unit_id)
	if idx == null or int(idx) < 0 or int(idx) >= squads.size():
		return -1
	return int(idx)

# --- AI起動状態（待機AIの「起きた」フラグ）。詳細 → doc/gdd/ai.md ---

var _engaged := {}  # unit_id -> true（待機AIが起動済み。一度起動したら戻らない）

## unit_id を起動済みにする（AIの起動判定・被弾で立つ）。
func mark_engaged(unit_id: int) -> void:
	_engaged[unit_id] = true

## unit_id が起動済みか。
func is_engaged(unit_id: int) -> bool:
	return _engaged.has(unit_id)
# --- 状態補正（バフ/デバフ・持続）。詳細 → doc/gdd/combat.md「状態補正」 ---

var _status_mods: Array = []  # エントリ配列 {scope,op,target,value,owner_team,remaining,...}。中断セーブに乗る

## 状態補正エントリを積む（陣形バフ等）。
func add_status_mod(entry: Dictionary) -> void:
	_status_mods.append(entry)

## unit の target（"attack"/"defense"）に効く状態補正の合成 { mul, add }。combat が実効ステに反映。
func status_aggregate(unit: Unit, target: String) -> Dictionary:
	return StatusMod.aggregate(_status_mods, unit, target)

## unit にいま効いている状態補正エントリの一覧（表示用・読み取り専用）。情報パネルが使う。
func status_mods_for(unit: Unit) -> Array:
	return StatusMod.applied(_status_mods, unit)

## unit に掛かっている弱体（デバフ）を落とす（③ピュリファイ）。落とした件数を返す。
## 落とすのは kind が debuff で対象1体（scope="unit"）のものだけ＝味方から掛かった
## 強化（ピクシーダスト）は残り、陣営全体に掛かった補正を1人のピュリファイで消すこともない。
## 詳細 → doc/gdd/skills.md
func clear_debuffs(unit: Unit) -> int:
	var kept: Array = []
	for m in _status_mods:
		var drop := StatusMod.is_debuff(m) \
			and String(m.get("scope", "")) == "unit" \
			and StatusMod.applies_to(m, unit)
		if drop:
			continue
		kept.append(m)
	var removed := _status_mods.size() - kept.size()
	_status_mods = kept
	return removed

## 陣営全体に効いていて盤の見た目（fx）を宣言している補正の名前。無ければ空文字。
## 盤全体のエフェクト（ホーリーアリアの加護の光）を出すかの判定に presentation が使う。
func team_aura_fx() -> String:
	for m in _status_mods:
		if String(m.get("scope", "")) == "team" and not String(m.get("fx", "")).is_empty():
			return String(m.get("fx", ""))
	return ""

## ターン開始時に、始まった陣営の持続を1減らして満了を掃除する（end_turn から呼ぶ）。
## remaining は「残り自軍ターン数」＝発動陣営のターンが始まるたびに減る（跨いだ敵ターンでは減らない）。
func _expire_status_mods() -> void:
	var kept: Array = []
	for m in _status_mods:
		if int(m.get("owner_team", -1)) == current_team:
			var rem := int(m.get("remaining", 0)) - 1
			m["remaining"] = rem
			if rem > 0:
				kept.append(m)
		else:
			kept.append(m)
	_status_mods = kept

var _defeated := {}  # unit_id -> true（撃破で盤から消えた駒の記録）
var _defeated_actors := {}  # actor -> true（名前つきの駒の撃破。ボス撃破・護衛対象の喪失が見る。doc/gdd/map.md）

func _init(p_cols: int = 12, p_rows: int = 8) -> void:
	cols = p_cols
	rows = p_rows

func add_unit(unit: Unit) -> void:
	_units.append(unit)

func units() -> Array[Unit]:
	return _units

func unit_by_id(id: int) -> Unit:
	for u in _units:
		if u.id == id:
			return u
	return null

func unit_at(hex: Vector2i) -> Unit:
	for u in _units:
		if u.pos == hex:
			return u
	return null

# --- イベント（時限発生）。詳細 → doc/gdd/map.md イベント ---
#
# 増援＝開始時に盤に存在しない駒が、指定のターンに加わること。拠点の控えを出す出撃や、
# 盤に居る敵部隊が動き出す起動（engage）とは別物で、これだけを「増援」と呼ぶ。
# 駒は StageLoader が読み込み時に組んで（catalog 解決込み）ここへ預け、発生ターンに盤へ出す。

## 未発生のイベント。発生したものは取り除く＝残っているものが未発生。
## 各要素 = { turn, team, label, squad, units: [ { unit: Unit, passengers: Array[Unit] } ] }
var _events: Array = []

## イベントを積む（StageLoader が組んで渡す）。
func add_event(entry: Dictionary) -> void:
	_events.append(entry)

## 未発生のイベント一覧（読み取り専用）。
func pending_events() -> Array:
	return _events

## いちばん近い未発生の増援の { label, turns }。turns＝あと何ターンで来るか（0＝このターン）。
## label を持たないイベントは予告しない＝ここには出さない。無ければ空。残りターン板が読む
## （→ doc/gdd/uiux.md 残りターン板）。
func next_event() -> Dictionary:
	var out := {}
	var best := -1
	for e in _events:
		var label := String(e.get("label", ""))
		if label.is_empty():
			continue
		var t := int(e.get("turn", 0))
		if best < 0 or t < best:
			best = t
			out = { "label": label, "turns": maxi(t - turn_number, 0) }
	return out

## 発生ターンが来たイベントを起こす。起きたものの配列を返す（演出・ログ用）。
## end_turn の最後と、ステージ開始直後（1ターン目の分）に呼ぶ。指定ターンを過ぎていても
## 取りこぼさないよう「turn 以下」で見る。
func fire_due_events() -> Array:
	var fired: Array = []
	var kept: Array = []
	for e in _events:
		if int(e.get("turn", 0)) <= turn_number and int(e.get("team", -1)) == current_team:
			_place_event_units(e)
			fired.append(e)
		else:
			kept.append(e)
	_events = kept
	return fired

## イベントの駒を盤へ出す。置けなかった駒は出さずに警告1行＝イベント全体は止めない。
func _place_event_units(e: Dictionary) -> void:
	var squad_index := int(e.get("squad", -1))
	for item in e.get("units", []):
		var u: Unit = item.get("unit")
		if u == null:
			continue
		var hex := _free_hex_for(u, u.pos)
		if hex == Vector2i.MAX:
			push_warning("BattleState: 増援を置く空きが無い（この駒は出さない）: id=%d" % u.id)
			continue
		u.pos = hex
		add_unit(u)
		if squad_index >= 0:
			assign_squad(u.id, squad_index)
		for p in item.get("passengers", []):
			put_passenger(u.id, p)

## u を置くヘックス。希望位置が埋まっている／その駒が入れない地形なら最寄りの空きへずらす。
## 見つからなければ Vector2i.MAX。近い順に見るので、ずれても意図した場所の近くに出る。
func _free_hex_for(u: Unit, want: Vector2i) -> Vector2i:
	var seen := { want: true }
	var frontier: Array[Vector2i] = [want]
	while not frontier.is_empty():
		var nxt: Array[Vector2i] = []
		for h in frontier:
			if unit_at(h) == null and _enter_cost(h, u) != Movement.IMPASSABLE:
				return h
			for n in Hex.neighbors(h):
				if seen.has(n) or not in_field(n):
					continue
				seen[n] = true
				nxt.append(n)
		frontier = nxt
	return Vector2i.MAX

# --- 輸送（積載・運搬）。詳細 → doc/gdd/movement.md ---

var _passengers := {}  # transport_id -> Array[Unit]（搭乗中の駒。盤上には居ない＝殲滅カウント外）

## transport_id に搭乗中の駒（無ければ空配列）。
func passengers(transport_id: int) -> Array:
	return _passengers.get(transport_id, [])

## u が transport に乗れるか（同陣営・輸送どうし不可・capacity に空き）。
func can_board(u: Unit, transport: Unit) -> bool:
	if u == null or transport == null or not transport.is_transport():
		return false
	if u.is_transport() or u.team != transport.team:
		return false
	return passengers(transport.id).size() < transport.capacity

## 駒を輸送へ直接積む（初期配置・乗車の内部処理。行動フラグは触らない）。
func put_passenger(transport_id: int, u: Unit) -> void:
	if not _passengers.has(transport_id):
		var list: Array[Unit] = []
		_passengers[transport_id] = list
	_passengers[transport_id].append(u)

## 降車先候補の {hex: コスト}。搭乗駒が「輸送の位置を起点に」自力で動ける空きhex（通常移動と同じ規則）。
## 隣接1マスの特例: 輸送に隣接する進入可能な空きマスは、移動力・地形コストに関係なく常に含める
## （積み降ろしは人手＝移動0の駒も隣へ降ろせる）。進入不可地形（x）は特例でも不可。
## 乗車したターン（行動済み）の駒は降りられない＝空。
func _unload_map(transport_id: int, index: int) -> Dictionary:
	var t := unit_by_id(transport_id)
	var list := passengers(transport_id)
	if t == null or index < 0 or index >= list.size():
		return {}
	var p: Unit = list[index]
	if has_moved(p.id):
		return {}  # 乗車したターンは行動完了＝降りられない（翌ターンから）
	var m := Hex.flood_reach_cost_map(t.pos, p.move, _enter_cost.bind(p), _move_stop.bind(p))
	var cells := {}
	for h in m:
		if h != t.pos and unit_at(h) == null:  # 起点（輸送のマス）と占有マスは降車先にしない
			cells[h] = m[h]
	for nb in Hex.neighbors(t.pos):
		if cells.has(nb) or unit_at(nb) != null:
			continue
		if _enter_cost(nb, p) == Movement.IMPASSABLE:
			continue  # 盤外・進入不可地形（崖など）へは特例でも降ろせない
		cells[nb] = p.move  # 特例の降車は移動予算を使い切る扱い
	return cells

## 降車先候補（表示用）。
func unload_cells(transport_id: int, index: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for h in _unload_map(transport_id, index):
		cells.append(h)
	return cells

## 搭乗駒 index が from_hex に降りたと仮定したときの攻撃対象（降車確認メニューの「攻撃」可否）。
func unload_attack_targets(transport_id: int, index: int, from_hex: Vector2i) -> Array[int]:
	var list := passengers(transport_id)
	var ids: Array[int] = []
	if index < 0 or index >= list.size():
		return ids
	var p: Unit = list[index]
	for u in _units:
		if _can_attack_from(p, u, from_hex):
			ids.append(u.id)
	return ids

## 搭乗駒 index を to へ降ろす。降車＝その駒の通常移動（コスト消費・以後攻撃は可能）。
## 占領可ユニットが拠点hexへ降りれば即占領（移動と同じ扱い）。
func unload(transport_id: int, index: int, to: Vector2i) -> bool:
	var m := _unload_map(transport_id, index)
	if not m.has(to):
		return false
	var p: Unit = passengers(transport_id)[index]
	_passengers[transport_id].remove_at(index)
	p.pos = to
	_units.append(p)
	_moved[p.id] = true
	_spent[p.id] = int(m[to])
	_try_capture(p)
	return true

# --- 拠点（占領・出撃・回復）。詳細 → doc/gdd/map.md ---

## 占領成功で占領兵が得る経験（＝レベル）。占領兵は戦闘機会が少ないぶんを1回で補う。詳細 → doc/gdd/combat.md
const CAPTURE_EXPERIENCE := 10

func add_base(base: Base) -> void:
	_bases.append(base)

func bases() -> Array[Base]:
	return _bases

## hex にある拠点（無ければ null）。
func base_at(hex: Vector2i) -> Base:
	for b in _bases:
		if b.hex == hex:
			return b
	return null

## hex の地形id（未設定は既定地形 "plain"）。
func terrain_at(hex: Vector2i) -> String:
	return _terrain.get(hex, TerrainType.DEFAULT_ID)

## hex に地形を設定する。
func set_terrain(hex: Vector2i, terrain_id: String) -> void:
	_terrain[hex] = terrain_id
	_travel_cache.clear()

## 移動コスト表を設定する（move_type -> {地形名: コスト}）。
func set_movement(table: Dictionary) -> void:
	_movement = table
	_travel_cache.clear()

## hex が矩形フィールド内か。
func in_field(hex: Vector2i) -> bool:
	var off := Hex.axial_to_offset(hex)
	return off.x >= 0 and off.x < cols and off.y >= 0 and off.y < rows

## goal から盤全体へ、move_type の地形コストで測った道のり表 { ヘックス: コスト }。
## 何ターンかければ届くか、を測る道具＝1ターンの移動力の予算では切らない。届かないヘックスは載らない。
## 駒の配置・ZOC は見ない＝地形だけの道のり。見ると味方で塞がった瞬間に道が消えて、
## 「行き先なし＝その場で停止」に戻ってしまう（AIの前進が直線距離で止まっていた問題と同じ形）。
##
## max_step_cost（＝その駒の移動力。0＝上限なし）を渡すと、1マスの進入コストがそれを超える
## ヘックスを通行不能として流す。ターンを重ねても入れないマス（移動2の駒にとっての柵＝コスト3）は
## その駒の道ではない。最短路に含めると勾配がそこを指し、実際に踏めるマスが全部「上り」になって、
## 前進先が現在地のまま＝永久に動かない駒ができる。
## 用途はAIの前進＝直線距離ではなくこの値が縮むマスへ寄る。詳細 → doc/gdd/ai.md（前進）
func travel_cost_field(goal: Vector2i, move_type: String, max_step_cost: int = 0) -> Dictionary:
	if not in_field(goal):
		return {}
	var key := "%d,%d|%s|%d" % [goal.x, goal.y, move_type, max_step_cost]
	if _travel_cache.has(key):
		return _travel_cache[key]
	var cost_fn := func(hex: Vector2i) -> int:
		if not in_field(hex):
			return Movement.IMPASSABLE
		var c := Movement.cost(_movement, move_type, terrain_at(hex))
		if max_step_cost > 0 and c > max_step_cost:
			return Movement.IMPASSABLE  # 何ターンかけても入れない＝この駒には壁
		return c
	var field := Hex.flood_reach_cost_map(goal, 1 << 24, cost_fn)
	_travel_cache[key] = field
	return field

## 駒を避けた道のり表＝標的(goal)以外の駒が立つヘックスを壁として流す（敵味方を問わない）。
## 味方の上は通過できても止まれない＝止まれるマスだけを繋いだ「実際に歩けるルート」がこれで出る。
## from_hex（測る側の駒がいま立っているマス）は壁にしない＝自分自身で道を塞がない。
## 駒は1手ごとに動くのでメモしない（地形だけの travel_cost_field と違って使い捨て）。
## 標的が完全に囲まれていると道が消える＝呼び出し側は地形だけの表へ退避する（AIの前進）。
func travel_cost_field_avoiding_units(goal: Vector2i, move_type: String,
		max_step_cost: int = 0, from_hex: Vector2i = Vector2i(1 << 30, 1 << 30)) -> Dictionary:
	if not in_field(goal):
		return {}
	var cost_fn := func(hex: Vector2i) -> int:
		if not in_field(hex):
			return Movement.IMPASSABLE
		if hex != goal and hex != from_hex and unit_at(hex) != null:
			return Movement.IMPASSABLE  # 標的以外の駒は壁
		var c := Movement.cost(_movement, move_type, terrain_at(hex))
		if max_step_cost > 0 and c > max_step_cost:
			return Movement.IMPASSABLE
		return c
	return Hex.flood_reach_cost_map(goal, 1 << 24, cost_fn)

## travel_cost_field のメモ（地形・移動コスト表が変わるまで有効）。
## 盤ごと・移動タイプごとに1枚で、駒が動いても作り直さない＝AIが毎ターン全員ぶん流し直さない。
## 直列化しない（to_dict に載せない）＝復元後に作り直せる導出物。
var _travel_cache := {}

# --- 視線（索敵の遮蔽・減衰）。詳細 → doc/gdd/movement.md（視線）, doc/gdd/ai.md（起動） ---

var _sight_cost := {}  # 地形id -> 視線コスト（空＝全地形1＝純距離の索敵と一致）。TerrainType から注入

## 視線コスト表を注入する（movement 表と同型＝domain を data 非依存に保つ）。
func set_sight_cost(table: Dictionary) -> void:
	_sight_cost = table

## hex の視線コスト（未登録は1＝開地相当）。壁など `x` は TerrainType.SIGHT_OPAQUE の大きな値。
func sight_cost_at(hex: Vector2i) -> int:
	return int(_sight_cost.get(terrain_at(hex), 1))

## 視線の規則計算は Sight（static ヘルパー）が持つ＝ここは表の持ち主として口だけ残す。
func sight_reaches(from: Vector2i, to: Vector2i, budget: int) -> bool:
	return Sight.reaches(self, from, to, budget)

func visible_hexes(from: Vector2i, budget: int) -> Dictionary:
	return Sight.visible_hexes(self, from, budget)

## unit_id が「残り移動力」で到達できるヘックス（起点を含む）。盤外・敵は進入不可、地形はコスト。
## 味方のマスは通過できるが停止できない（到達候補には含めない）。
## 敵ZOC（敵に隣接するマス）に入ると停止＝その先へは進めない（飛行含む全移動タイプ）。
func reachable(unit_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in _reach_map(unit_id):
		result.append(h)
	return result

## unit_id が to へ移動するときに通るヘックス列（起点 u.pos で始まり to で終わる）。
## 移動できない to には空配列。盤の状態は変えない（見た目＝移動アニメの経路に使う）。
## move_unit より前に呼ぶこと: 移動後は u.pos と _spent が変わり、同じ経路は復元できない。
func path_to(unit_id: int, to: Vector2i) -> Array[Vector2i]:
	var u := unit_by_id(unit_id)
	if u == null or to == u.pos or not _reach_map(unit_id).has(to):
		return []
	var budget := maxi(u.move - int(_spent.get(unit_id, 0)), 0)
	var prev := Hex.flood_reach_prev_map(u.pos, budget, _enter_cost.bind(u), _move_stop.bind(u))
	if not prev.has(to):
		# 隣接1マスの特例（乗れる輸送）は探索の外＝経路を持たない。隣接なので直進で足りる。
		var direct: Array[Vector2i] = []
		if Hex.distance(u.pos, to) == 1:
			direct = [u.pos, to]
		return direct
	var path: Array[Vector2i] = [to]
	var cur := to
	while cur != u.pos:
		cur = prev[cur]  # prev は確定済みノードだけを指す＝閉路にならず必ず start へ着く
		path.append(cur)
	path.reverse()
	return path

## reachable の {ヘックス: 到達コスト} 版（残り移動力で計算）。移動コスト消費に使う。
## 隣接1マスの特例: 隣接する乗れる輸送のマスは、移動力・地形コストに関係なく常に含める
## （積み降ろしは人手＝移動0の駒も隣の輸送には乗れる）。詳細 → doc/gdd/movement.md（輸送）
func _reach_map(unit_id: int) -> Dictionary:
	var u := unit_by_id(unit_id)
	if u == null:
		return {}
	var budget := maxi(u.move - int(_spent.get(unit_id, 0)), 0)
	var m := Hex.flood_reach_cost_map(u.pos, budget, _enter_cost.bind(u), _move_stop.bind(u))
	# 味方のマスは通過できるが停止できない＝到達候補から除外（起点・乗れる輸送は残す）。
	var result := {}
	for h in m:
		var occ := unit_at(h)
		if h == u.pos or occ == null or can_board(u, occ):
			result[h] = m[h]
	for h in _adjacent_boardable(u):
		if not result.has(h):
			result[h] = 0  # コスト値は未使用（乗車は move_unit が予算を使い切る扱いにする）
	return result

## u に隣接する「乗れる輸送」のマス一覧（隣接1マスの特例の対象）。
func _adjacent_boardable(u: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for nb in Hex.neighbors(u.pos):
		if in_field(nb) and can_board(u, unit_at(nb)):
			cells.append(nb)
	return cells

## u が hex に進入するコスト。盤外・敵ユニットのマスは進入不可（Movement.IMPASSABLE）。
## 味方のマスは通過できる（地形コスト）が停止はできない（到達候補からは _reach_map で除外）。
## 乗れる味方輸送のマスへは進入できる（＝移動先に選ぶと乗車）。それ以外は地形コスト。
func _enter_cost(hex: Vector2i, u: Unit) -> int:
	if not in_field(hex):
		return Movement.IMPASSABLE
	var occ := unit_at(hex)
	if occ != null and occ.team != u.team:
		return Movement.IMPASSABLE  # 敵の上は通れない（味方は通過可）
	return Movement.cost(_movement, u.move_type, terrain_at(hex))

## hex で移動が止まるか（その先へ展開しない）。敵ZOC＝停止／乗れる輸送＝乗車先なので通過不可。
## 味方のマスでは止まらず先へ展開する（通過はできるが停止はできない＝到達候補にはならない）。
func _move_stop(hex: Vector2i, u: Unit) -> bool:
	var occ := unit_at(hex)
	if occ != null and can_board(u, occ):
		return true  # 乗れる輸送のマス（終点としてのみ有効）
	return _in_enemy_zoc(hex, u)

## hex が u から見た敵ZOC内か（敵ユニットに隣接しているか）。ZOCに入ると移動が止まる。
func _in_enemy_zoc(hex: Vector2i, u: Unit) -> bool:
	for nb in Hex.neighbors(hex):
		var occ := unit_at(nb)
		if occ != null and occ.team != u.team:
			return true
	return false

## 妥当なら移動を適用して true。ターン違い・移動権なし・不正先なら false。移動コストを予算から消費。
## 移動先が「乗れる味方輸送」のマスなら乗車＝盤から降りて搭乗し、その駒は行動完了になる。
func move_unit(unit_id: int, to: Vector2i) -> bool:
	if not _can_act_move(unit_id):
		return false
	var rm := _reach_map(unit_id)
	var u := unit_by_id(unit_id)
	if to == u.pos or not rm.has(to):
		return false
	var occ := unit_at(to)
	if occ != null:
		if not can_board(u, occ):
			return false
		_take_off_board(unit_id)  # 乗車: 盤から外して輸送へ（撃破記録は付かない）
		put_passenger(occ.id, u)
		_moved[unit_id] = true    # 乗った駒は行動完了（doc/gdd/movement.md）
		_post_moved[unit_id] = true
		_attacked[unit_id] = true
		_spent[unit_id] = u.move
		return true
	u.pos = to
	_spent[unit_id] = int(_spent.get(unit_id, 0)) + int(rm[to])
	# 攻撃前なら通常移動、攻撃後なら再移動として消費（どちらも1回）。
	if has_attacked(unit_id):
		_post_moved[unit_id] = true
	else:
		_moved[unit_id] = true
	_try_capture(u)  # 占領可ユニットが敵/中立拠点に入ったら即占領
	return true

## u が今いる拠点を占領できるなら所属を u の陣営へ移す（占領＝即時・進入した瞬間）。
func _try_capture(u: Unit) -> void:
	if not u.can_capture:
		return
	var b := base_at(u.pos)
	if b != null and b.team != u.team:
		b.team = u.team
		u.add_experience(CAPTURE_EXPERIENCE)

## いま移動できるか（ターン・移動権・残り予算）。
## 攻撃前: 通常移動を未使用なら可。攻撃後: 再移動可ユニットが再移動を未使用なら可。
func _can_act_move(unit_id: int) -> bool:
	var u := unit_by_id(unit_id)
	if not is_current_unit(u):
		return false
	if int(_spent.get(unit_id, 0)) >= u.move and _adjacent_boardable(u).is_empty():
		return false  # 予算切れ（隣接に乗れる輸送があれば特例で乗車だけはできる）
	if has_attacked(unit_id):
		return u.move_after_attack and not _post_moved.has(unit_id)
	return not _moved.has(unit_id)

## いま移動できるか（公開）。盤の移動範囲表示などに使う。
func can_still_move(unit_id: int) -> bool:
	return _can_act_move(unit_id)

# --- 出撃（ネクタリス方式・占領済み拠点から1歩で出す） ---

## base_hex の拠点から出撃できるhex（拠点に隣接・盤内の空き＋乗れる味方輸送のマス）。出撃先候補の表示に使う。
## garrison_index を渡すとその駒が乗れる輸送だけ含める（省略＝控えのどれかが乗れる輸送を含める）。
func deploy_cells(base_hex: Vector2i, garrison_index := -1) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var b := base_at(base_hex)
	if b == null or b.team != current_team or b.garrison.is_empty():
		return cells
	for nb in Hex.neighbors(base_hex):
		if not in_field(nb):
			continue
		var occ := unit_at(nb)
		if occ == null:
			if _deploy_enterable(b, garrison_index, nb):
				cells.append(nb)
		elif _deploy_boardable(b, garrison_index, occ):
			cells.append(nb)  # 出撃＝そのまま搭乗（隣接1マスの特例の拠点版）
	return cells

## 拠点 b の控え（index 指定 or いずれか）が nb の地形に立てるか。
## その移動タイプで進入不可の地形（壁・瓦礫など）へは出せない＝出た瞬間に動かせない駒を作らない。
## index 省略のときは「誰か1体でも入れるなら候補」＝誰を出すかは後で決まるため。
func _deploy_enterable(b: Base, garrison_index: int, nb: Vector2i) -> bool:
	var terrain := terrain_at(nb)
	if garrison_index >= 0:
		if garrison_index >= b.garrison.size():
			return false
		return _enterable_terrain((b.garrison[garrison_index] as Unit).move_type, terrain)
	for gu in b.garrison:
		if _enterable_terrain((gu as Unit).move_type, terrain):
			return true
	return false

func _enterable_terrain(move_type: String, terrain: String) -> bool:
	return Movement.cost(_movement, move_type, terrain) != Movement.IMPASSABLE

## 拠点 b の控え（index 指定 or いずれか）が輸送 occ に出撃で直接乗れるか。
## can_board 相当だが、控えの team は出撃時に確定するため拠点の所属で判定する。
func _deploy_boardable(b: Base, garrison_index: int, occ: Unit) -> bool:
	if not occ.is_transport() or occ.team != b.team:
		return false
	if passengers(occ.id).size() >= occ.capacity:
		return false
	if garrison_index >= 0:
		return garrison_index < b.garrison.size() and not (b.garrison[garrison_index] as Unit).is_transport()
	for gu in b.garrison:
		if not (gu as Unit).is_transport():
			return true  # 輸送でない控えが1体でも居れば候補（輸送は輸送に乗れない）
	return false

## garrison[index] を出撃させられるか（帰属ルール）。帰属未確定（中立でまだ解放されていない）は
## 誰の拠点からでも出せる＝出した側の戦力になる。確定済みは「拠点の現所有者＝帰属先」のときだけ
## ＝奪われた拠点の駒は閉じ込め（一度解放した駒は奪われても寝返らない）。詳細 → doc/gdd/map.md
func can_deploy_garrison(base_hex: Vector2i, index: int) -> bool:
	var b := base_at(base_hex)
	if b == null or index < 0 or index >= b.garrison.size():
		return false
	var u: Unit = b.garrison[index]
	# このターン行動を終えた駒は出せない＝「入る」で収容した駒の往復を止める。判定は明示的な
	# 行動終了フラグだけを見る（is_done は「動ける先が無い」も完了とするので盤外の駒は常に真＝
	# 初期配置の控えまで出せなくなる）。フラグは end_turn で一掃される＝次の自軍ターンから出せる。
	if _done.has(u.id):
		return false
	return u.is_unclaimed() or u.recruited_team == b.team

## 拠点の garrison[index] を隣接 to_hex へ出撃させる。出撃は1歩＝そのターンは行動完了。
## to_hex が「乗れる味方輸送」のマスなら出撃＝そのまま搭乗（盤上には出ない）。
## 成否を返す。ターン違い・非占領・索引外・native不一致（閉じ込め）・隣接でない・乗れない占有マスなら false。
func deploy(base_hex: Vector2i, garrison_index: int, to_hex: Vector2i) -> bool:
	var b := base_at(base_hex)
	if b == null or b.team != current_team:
		return false
	if not can_deploy_garrison(base_hex, garrison_index):
		return false
	if not in_field(to_hex):
		return false
	if Hex.distance(base_hex, to_hex) != 1:
		return false
	var occ := unit_at(to_hex)
	if occ != null and not _deploy_boardable(b, garrison_index, occ):
		return false
	if occ == null and not _deploy_enterable(b, garrison_index, to_hex):
		return false  # 進入不可の地形へは出せない（deploy_cells と同じ規則）
	var u: Unit = b.garrison[garrison_index]
	b.garrison.remove_at(garrison_index)
	u.team = current_team
	if u.is_unclaimed():
		u.recruited_team = current_team  # 解放＝帰属確定。以後は拠点を奪われても寝返らず捕虜になる
	if occ != null:
		put_passenger(occ.id, u)  # 出撃先が輸送＝直接乗車（盤上には出ない）
	else:
		u.pos = to_hex
		_units.append(u)
	if b.squad_index >= 0:
		assign_squad(u.id, b.squad_index)  # 拠点=squad の駒として振る舞う（敵AIの拠点出撃。ai.md §7）
	# 出撃した駒はそのターン行動完了（1歩のみ＝移動も再移動も攻撃も降車もこれ以上しない）。
	_moved[u.id] = true
	_post_moved[u.id] = true
	_attacked[u.id] = true
	_spent[u.id] = u.move
	return true

## 自軍所有の拠点に「入る」（駐留）。拠点hexに立っている駒を garrison へ移す＝盤上から消える。
## 中でターン開始ごとに回復（_heal_garrisons）。出るのは出撃（deploy）＝1歩・行動完了。
func can_enter_base(unit_id: int) -> bool:
	var u := unit_by_id(unit_id)
	return u != null and can_enter_base_at(unit_id, u.pos)

## dest_hex（自軍拠点）へ移動して「入る」が許されるか。メニュー表示は移動前に先読みするため、
## 現在位置ではなく移動先を仮定して判定する（実行時は dest_hex＝現在位置で同じ規則になる）。
## 案B: 盤上最後の1体でも、入った直後に復帰手段が残るなら入れる（即敗北を防ぐ）。
func can_enter_base_at(unit_id: int, dest_hex: Vector2i) -> bool:
	var u := unit_by_id(unit_id)
	if not is_current_unit(u):
		return false
	var b := base_at(dest_hex)
	if b == null or b.team != u.team:
		return false
	if team_unit_count(u.team) > 1:
		return true  # 入っても盤上に他の駒が残る
	# 盤上最後の1体：入った駒自身が b の出せる控えになる＝b に空き隣接があれば復帰可。
	# 他拠点で既に復帰可能でもよい（＝入った瞬間に「盤上0かつ復帰なし」の敗北にならない）。
	return _base_has_open_neighbor(b) or has_reinforcement(u.team)

func enter_base(unit_id: int) -> bool:
	if not can_enter_base(unit_id):
		return false
	var u := unit_by_id(unit_id)
	var b := base_at(u.pos)
	_take_off_board(unit_id)
	set_done(unit_id)  # 入るのも1手＝行動終了。これがそのターンの出撃を止める（往復させない）
	b.garrison.append(u)
	return true

# --- 攻撃 ---

## attacker が target を攻撃できるか（現ターン・未攻撃・射程内の敵）。
func can_attack(attacker_id: int, target_id: int) -> bool:
	var a := unit_by_id(attacker_id)
	if a == null:
		return false
	return _can_attack_from(a, unit_by_id(target_id), a.pos)

## from_hex に attacker が居ると仮定したときの攻撃可否。仮移動でメニューを出す（移動確定前）ために使う。
func _can_attack_from(a: Unit, t: Unit, from_hex: Vector2i) -> bool:
	if a == null or t == null:
		return false
	if not is_current_unit(a) or has_attacked(a.id):
		return false
	if t.team == a.team:
		return false
	if a.attack_against(t) <= 0:
		return false  # 対空0の駒は飛行を狙えない（攻撃力が無い相手は対象外）
	return a.can_reach(Hex.distance(from_hex, t.pos))  # 下限min_range〜上限attack_range

## attacker が今いる位置から攻撃できる敵ユニットIDの一覧。
func attack_targets(attacker_id: int) -> Array[int]:
	var a := unit_by_id(attacker_id)
	return attack_targets_from(attacker_id, a.pos) if a != null else []

## from_hex に居ると仮定して攻撃できる敵ID一覧（移動を確定せずコマンドメニューを出すため）。
func attack_targets_from(attacker_id: int, from_hex: Vector2i) -> Array[int]:
	var a := unit_by_id(attacker_id)
	var ids: Array[int] = []
	if a == null:
		return ids
	for u in _units:
		if _can_attack_from(a, u, from_hex):
			ids.append(u.id)
	return ids

## 攻撃を解決。両軍同時攻撃（防御側は反撃する）。
## 成功なら {damage, killed, retaliation, attacker_killed, target_troops, attacker_troops}、不正なら空。
func attack(attacker_id: int, target_id: int) -> Dictionary:
	if not can_attack(attacker_id, target_id):
		return {}
	var a := unit_by_id(attacker_id)
	var t := unit_by_id(target_id)
	var melee := Hex.distance(a.pos, t.pos) <= 1  # 距離1の攻撃＝近接（反撃あり）、距離≥2＝遠隔（反撃なし）
	# 反撃は「近接（距離1）」かつ「防御側が距離1を狙えて、攻撃側を攻撃できる」ときだけ成立。
	# 例: 対空0の地上ユニットが飛行に殴られても反撃できない／砲兵(min_range≥2)は懐の敵に反撃できない（→被反撃なし・経験+0）。
	var can_retaliate := melee and t.can_reach(1) and t.attack_against(a) > 0
	# 同時攻撃: 戦闘前の状態で内訳ごと確定してから適用（決定的）。表示はこの内訳をそのまま使う。
	var fwd := Combat.hit_detail(self, a, t, melee)
	var ret: Variant = Combat.hit_detail(self, t, a, melee) if can_retaliate else null
	# 戦闘前スナップショット（撃破で盤から消えても結果表示できるよう値を固める）。
	var a_snap := _unit_snapshot(a)
	var t_snap := _unit_snapshot(t)
	var dmg_to_target: int = fwd["loss"]
	var dmg_to_attacker: int = (ret["loss"] if ret != null else 0)
	t.troops -= dmg_to_target
	a.troops -= dmg_to_attacker
	var target_killed := t.troops <= 0
	var attacker_killed := a.troops <= 0
	a_snap["troops_after"] = maxi(a.troops, 0)
	t_snap["troops_after"] = maxi(t.troops, 0)
	# 経験値: 戦ったら+1・倒したらさらに+1。攻撃側は常に参加。
	# 防御側は反撃が成立したときだけ+1（間接で撃たれた側／対空なしで飛行に撃たれた側は+0）。
	a.add_experience(1 + (1 if target_killed else 0))
	if can_retaliate:
		t.add_experience(1 + (1 if attacker_killed else 0))
	if target_killed:
		_remove_unit(target_id)
	if attacker_killed:
		_remove_unit(attacker_id)
	_attacked[attacker_id] = true  # 移動可否は move_after_attack で判定（再移動）
	# 被ダメは待機AIの確定起動トリガー（攻撃した側も当然起動済み）。詳細 → doc/gdd/ai.md
	mark_engaged(attacker_id)
	mark_engaged(target_id)
	return {
		"damage": dmg_to_target,
		"killed": target_killed,
		"retaliation": dmg_to_attacker,
		"attacker_killed": attacker_killed,
		"target_troops": maxi(t.troops, 0),
		"attacker_troops": maxi(a.troops, 0),
		"detail": {  # 戦闘結果ビュー用（式は Combat.hit_detail の1か所＝盤の兵数と一致）
			"attacker": a_snap,
			"defender": t_snap,
			"to_defender": fwd,
			"to_attacker": ret,
			"melee": melee,
		},
	}

## 陣形スキルを解決して盤に適用する。option＝Formation.available_for の1要素。
## target＝着弾中心（buff では無視）。参加ユニットは行動完了。詳細 → doc/gdd/formations.md
## 成功なら {recipe, results:[{target_id, loss, killed, detail}...]}、不正（ターン違い・行動済み・射程外）なら空。
func resolve_formation(option: Dictionary, target: Vector2i) -> Dictionary:
	# 妥当性: 参加者が現ターン・未行動・生存していること、target が射程内であること。
	# 移動後でも撃てるレシピ（ユニットスキル）は「行動を使い切っていないか」で見る。
	# 陣形は従来どおり盤の行動終了判定に従う（配置が変わる＝動いたら成立しない）。
	var after_move := bool(option.get("after_move", false))
	for pid in option["participants"]:
		var p := unit_by_id(int(pid))
		if p == null or p.team != current_team:
			return {}
		if not (has_action_left(int(pid)) if after_move else not is_done(int(pid))):
			return {}
	if not Formation.can_target(self, option, target):
		return {}
	# 効果対象が1体のユニットスキルは演出シーンに乗る（→ doc/tech/combat_scene.md）。
	# 兵数が動かない＝着弾も撃破も起きないので、内訳は results ではなく専用の1件で渡す。
	# 発動前に撮る＝戦闘の detail（戦闘前スナップショット）と同じ流儀。
	var skill_scope := String(option.get("buff_scope", "")) == "unit"
	var skill_detail := _skill_snapshot(option, target) if skill_scope else {}
	# バフ系（②ホーリーアリア）は着弾ではなく状態補正エントリを積む（ダメージ処理は空回り＝results空）。
	if String(option["effect"]) == "buff":
		var entry := _buff_entry(option, target)
		add_status_mod(entry)
		if skill_scope:
			skill_detail["op"] = String(entry.get("op", "mul"))
			skill_detail["value"] = float(entry.get("value", 0.0))
			skill_detail["buff_target"] = String(entry.get("target", "both"))
			skill_detail["kind"] = String(entry.get("kind", StatusMod.KIND_BUFF))
	# ピュリファイ（③）は積むのではなく落とす。同じく着弾は起きない＝results空。
	elif String(option["effect"]) == "cleanse":
		var cleansed := unit_at(target)  # can_target が味方の存在を保証済み
		if cleansed != null:
			var dropped := clear_debuffs(cleansed)
			if skill_scope:
				skill_detail["cleansed"] = dropped
	# 着弾内訳は戦闘前の盤で確定（決定的＝attack と同じ流儀）。
	var pv := Formation.preview(self, option, target)
	var results: Array = []
	for hit in pv["hits"]:
		var victim := unit_by_id(int(hit["target_id"]))
		if victim == null:
			continue
		var loss := int(hit["loss"])
		victim.troops -= loss
		var killed := victim.troops <= 0
		mark_engaged(victim.id)  # 被弾＝起動トリガー（待機AIが立つ）
		if killed:
			_remove_unit(victim.id)
		results.append({"target_id": victim.id, "loss": loss, "killed": killed, "detail": hit})
	# 経験値: attack と同じ「戦ったら+1・倒したらさらに+1」を陣形1発の単位で（面で複数撃破でも+2止まり）。
	# 対象に1体も当たらなかった空撃ちは0（戦っていない＝経験を稼げない）。
	var any_killed := false
	for r in results:
		if bool(r["killed"]):
			any_killed = true
			break
	var exp_gain := 0
	if not results.is_empty():
		exp_gain = 1 + (1 if any_killed else 0)
	elif skill_scope:
		# ユニットスキルは撃破が起きないので前半（戦ったら+1）だけが乗る。詳細 → doc/gdd/skills.md
		exp_gain = 1
	# 参加者は行動完了（1体は1ターンに1つの陣形スキルにのみ参加）＋経験値加算。
	for pid in option["participants"]:
		var p := unit_by_id(int(pid))
		if p != null:
			p.add_experience(exp_gain)
		set_done(int(pid))
		mark_engaged(int(pid))
	var out := {"recipe": option["recipe"], "results": results}
	if skill_scope:
		out["skill"] = skill_detail
	return out

## 効果対象が1体のユニットスキルの演出用内訳（発動前に撮る）。発動者と対象のスナップショットに、
## レシピの情報（表示名・エフェクトID）を添える。乗った補正の値は呼び出し側が足す。
## 兵数は動かないので troops_after は troops_before と同じ＝戦闘の detail と器を揃える。
## 詳細 → doc/tech/combat_scene.md ユニットスキルの演出
func _skill_snapshot(option: Dictionary, target: Vector2i) -> Dictionary:
	var caster := unit_by_id(int(option.get("leader_id", -1)))
	var victim := unit_at(target)
	var c_snap := _unit_snapshot(caster) if caster != null else {}
	var t_snap := _unit_snapshot(victim) if victim != null else {}
	if not c_snap.is_empty():
		c_snap["troops_after"] = int(c_snap["troops_before"])
	if not t_snap.is_empty():
		t_snap["troops_after"] = int(t_snap["troops_before"])
	return {
		"recipe": String(option.get("recipe", "")),
		"name": String(option.get("name", "")),
		"effect": String(option.get("effect", "")),
		"combat_effect": String(option.get("combat_effect", "")),
		"caster": c_snap,
		"target": t_snap,
	}

## バフ系レシピの状態補正エントリを組む。陣営全体（②ホーリーアリア）と、対象1体
## （ユニットスキル＝buff_scope "unit"・target のhexに居る駒。味方＝ピクシーダスト／敵＝ドレッドタッチ）の両方を作る。
## 詳細 → doc/gdd/formations.md, doc/gdd/skills.md
func _buff_entry(option: Dictionary, target: Vector2i) -> Dictionary:
	# 発動者の兵1人あたりで効くレシピ（ピクシーダスト・ドレッドタッチ）は、発動時の残兵数を掛けて
	# 値を焼き込む。以後は発動者と切り離される＝掛けた側が損耗しても倒されても補正は変わらない。
	# 弱体は負値（ドレッドタッチ＝-10/兵）なので、0 以外かどうかで判定する。
	var value := float(option.get("buff_value", 1.0))
	var per_troop := float(option.get("buff_value_per_troop", 0.0))
	if not is_zero_approx(per_troop):
		var caster := unit_by_id(int(option.get("leader_id", -1)))
		value = per_troop * float(caster.troops if caster != null else 0)
	var e := {
		"owner_team": current_team,
		"op": String(option.get("buff_op", "mul")),
		"target": String(option.get("buff_target", "both")),
		"value": value,
		"remaining": int(option.get("duration_turns", 1)),
		"name": String(option.get("name", "")),  # 戦闘レポートの表示用（レシピ表示名）
		"fx": String(option.get("buff_fx", "")),  # 盤の見た目（presentation が読む。空＝見た目なし）
		# 強化か弱体か。ピュリファイが落とす対象と盤の見た目をこれで決める＝値の符号から推測しない。
		"kind": String(option.get("buff_kind", StatusMod.KIND_BUFF)),
	}
	if String(option.get("buff_scope", "team")) == "unit":
		var u := unit_at(target)  # can_target が対象の存在と陣営を保証済み
		e["scope"] = "unit"
		e["unit_id"] = u.id if u != null else -1
	else:
		e["scope"] = "team"
		e["team"] = current_team
	return e

## 表示用のユニットスナップショット（戦闘前）。撃破後も値が要るので dict に固める。
## statuses＝この時点で効いている状態補正エントリの一覧（戦闘レポートのバフ表示用）。
## pos は演出シーンが地面を組むのに要る（terrain＝性能IDだけでは平地/雪原の別＝スキンが決まらない）。
func _unit_snapshot(u: Unit) -> Dictionary:
	return {
		"id": u.id, "type_id": u.type_id, "skin_id": u.skin_id, "team": u.team, "level": u.level,
		"troops_before": u.troops, "max": u.max_troops, "terrain": terrain_at(u.pos), "pos": u.pos,
		"statuses": StatusMod.applied(_status_mods, u),
	}

## 撃破された駒を盤から除去し、撃破済みとして記録（勝利条件「ボス撃破」の判定材料）。
## 輸送が撃破された場合、搭乗中の駒も失われる（ネクタリス準拠）。
func _remove_unit(unit_id: int) -> void:
	_defeated[unit_id] = true
	_mark_actor_defeated(unit_by_id(unit_id))
	for p in passengers(unit_id):
		_defeated[p.id] = true  # 巻き添え（盤上には居ないのでリストから消すだけ）
		_mark_actor_defeated(p)
	_passengers.erase(unit_id)
	_take_off_board(unit_id)

## 名前つきの駒（actor）の撃破を記録する。名前の無い駒は素通し。
func _mark_actor_defeated(u: Unit) -> void:
	if u != null and u.actor != "":
		_defeated_actors[u.actor] = true

## 駒を盤上リストから外す（撃破記録は付けない。乗車・撃破処理の内部用）。
func _take_off_board(unit_id: int) -> void:
	for i in _units.size():
		if _units[i].id == unit_id:
			_units.remove_at(i)
			return

# --- 勝敗（自軍＝team 0 視点） ---

enum { ONGOING, PLAYER_WIN, PLAYER_LOSS }

func team_unit_count(team: int) -> int:
	var n := 0
	for u in _units:
		if u.team == team:
			n += 1
	return n

## team が「復帰手段」を持つか＝所有拠点に、実際に盤上へ出せる控えが1体でもいる（案B）。
## 盤上0でもこれが真なら、その陣営はまだ消滅していない＝敗北/勝利にしない。
## 勝敗判定（Victory）と駐留の可否（can_enter_base_at）の両方が使う＝state 側に置く。
func has_reinforcement(team: int) -> bool:
	for b in _bases:
		if b.team == team and _base_has_deployable_garrison(b) and _base_has_open_neighbor(b):
			return true
	return false

## 拠点 b の控えに、帰属ルールで出撃できる駒が1体でもいるか（未確定、または所有者と同じ帰属先）。
func _base_has_deployable_garrison(b: Base) -> bool:
	for gu in b.garrison:
		var u := gu as Unit
		if u.is_unclaimed() or u.recruited_team == b.team:
			return true
	return false

## 拠点 b の周囲に、盤上へ出せる空きマスが1つでもあるか（＝盤上復帰の余地）。
## 盤上0の判定用なので味方輸送は考慮不要（盤上に味方が居ない＝味方輸送も盤上に無い）。
func _base_has_open_neighbor(b: Base) -> bool:
	for nb in Hex.neighbors(b.hex):
		if in_field(nb) and unit_at(nb) == null:
			return true
	return false

## 撃破済みの駒か。盤から消えた駒は unit_by_id では引けないので記録を見る。
func is_defeated(unit_id: int) -> bool:
	return _defeated.has(unit_id)

## 名指しした駒（actor）が撃破済みか。ボス撃破・護衛対象の喪失が見る。詳細 → doc/gdd/map.md
func is_actor_defeated(actor: String) -> bool:
	return actor != "" and _defeated_actors.has(actor)

## 駒を1体、戦闘を経ずに盤から除去する（撃破扱い＝ボス撃破の勝利条件にも効く）。
## 戦闘の結果ではない除去の入口＝デバッグメニューの「敵を殲滅」が使う。詳細 → doc/gdd/uiux.md
## 盤に居ない駒（既に撃破・搭乗中）を指したら false。
func remove_unit(unit_id: int) -> bool:
	if unit_by_id(unit_id) == null:
		return false
	_remove_unit(unit_id)
	return true

## 決着結果。判定規則は Victory（static ヘルパー）が持つ＝勝利条件タイプが増えても state は太らない。
func outcome() -> int:
	return Victory.outcome(self)

func is_over() -> bool:
	return Victory.is_over(self)

# --- ターン ---

## この陣営/ユニットが現在のターンか。
func is_current_unit(u: Unit) -> bool:
	return u != null and u.team == current_team

## このターンに（攻撃前の）移動を使ったか。
func has_moved(unit_id: int) -> bool:
	return _moved.has(unit_id)

## このターンに攻撃済みか。
func has_attacked(unit_id: int) -> bool:
	return _attacked.has(unit_id)

## このターンの行動を使い切ったか（もう移動も攻撃もできない／明示的に待機した）。
## 降車は「搭乗駒の行動」＝輸送自身が行動完了（待機・攻撃済み）でも、降ろせる駒が居る限り
## 選択可能にする（未行動の搭乗駒はいつでも降ろせる）。詳細 → doc/gdd/movement.md
func is_done(unit_id: int) -> bool:
	if _has_unloadable_passenger(unit_id):
		return false  # 「待機」済みでも降車のために選択できる
	if _done.has(unit_id):
		return true  # 「待機」で行動終了済み
	var can_atk := not has_attacked(unit_id) and not attack_targets(unit_id).is_empty()
	var can_mv := _can_act_move(unit_id) and reachable(unit_id).size() > 1  # 自分以外に行ける
	return not can_atk and not can_mv

## このターンの行動をまだ使っていないか（「待機」で終えておらず、攻撃もしていない）。
## is_done と違い「行ける先が無い／撃てる相手が居ない」を終了扱いにしない。移動してから
## 撃てるユニットスキルは、移動後この判定で発動可否を決める。詳細 → doc/gdd/skills.md
func has_action_left(unit_id: int) -> bool:
	return not _done.has(unit_id) and not has_attacked(unit_id)

## 降ろせる搭乗駒（このターン未行動）が居るか。
func _has_unloadable_passenger(unit_id: int) -> bool:
	for p in passengers(unit_id):
		if not has_moved(p.id):
			return true
	return false

## 明示的に行動終了させる（コマンドメニューの「待機」）。再選択・再行動を止める。
func set_done(unit_id: int) -> void:
	_done[unit_id] = true

## 選択して操作できる状態か（現ターン・まだ行動が残っている）。
func can_select(unit_id: int) -> bool:
	return is_current_unit(unit_by_id(unit_id)) and not is_done(unit_id)

## ターンを次の陣営へ。行動済みフラグを一掃し、0 に戻ったらターン+1。
## ターン開始時に、拠点に駐留中（garrison）の駒を回復（休憩＝中に入るモデル）。
func end_turn() -> void:
	_moved.clear()
	_post_moved.clear()
	_attacked.clear()
	_done.clear()
	_spent.clear()
	current_team = 1 - current_team
	if current_team == 0:
		turn_number += 1
	_expire_status_mods()  # 始まった陣営の持続バフ/デバフを1減らして満了を掃除
	_heal_garrisons()
	fire_due_events()  # 発生ターンが来た増援を盤へ出す（→ doc/gdd/map.md イベント）

## ターンが始まる陣営の「拠点に駐留中の駒」を満員へ回復（兵数のみ・経験Lvは据え置き）。
## 回復できるのは native が自陣営/中立の拠点だけ＝奪った敵 native 拠点は出撃拠点にはなるが回復しない。
## 閉じ込め駒（帰属先≠所有者）も回復しない。hexの上に立っている駒は回復しない（中に入るモデル）。
func _heal_garrisons() -> void:
	for b in _bases:
		if b.team != current_team:
			continue
		if b.native_team != current_team and b.native_team != Base.NEUTRAL:
			continue  # 敵 native の拠点では回復しない
		for u in b.garrison:
			if u.recruited_team == current_team or u.is_unclaimed():
				u.troops = u.max_troops

# --- 中断セーブ（状態の丸ごと直列化）。バージョン枠・ファイルIOは infrastructure/save 側。詳細 → doc/tech/gamesystem.md ---

## 盤の状態をすべて素データ（JSON化可能）に直列化する。見た目・movement 表（静的コンフィグ）は含めない
## ＝復元後に呼び出し側が set_movement(Movement.load_default()) を再適用する（load_file と同じ流儀）。
func to_dict() -> Dictionary:
	var units_out: Array = []
	for u in _units:
		units_out.append(u.to_full_dict())
	var terrain_out: Array = []
	for h in _terrain:
		terrain_out.append({ "q": h.x, "r": h.y, "t": _terrain[h] })
	var bases_out: Array = []
	for b in _bases:
		bases_out.append(b.to_dict())
	var pass_out := {}
	for tid in _passengers:
		var arr: Array = []
		for p in _passengers[tid]:
			arr.append(p.to_full_dict())
		pass_out[str(tid)] = arr
	return {
		"cols": cols, "rows": rows,
		"current_team": current_team, "turn_number": turn_number,
		"turn_limit": turn_limit, "roster": roster, "enemy_ai": enemy_ai,
		"units": units_out,
		"terrain": terrain_out,
		"bases": bases_out,
		"victory_conditions": victory_conditions,
		"defeat_conditions": defeat_conditions,
		"squads": squads,
		"status_mods": _status_mods,
		"passengers": pass_out,
		"moved": _moved.keys(), "post_moved": _post_moved.keys(),
		"attacked": _attacked.keys(), "done": _done.keys(),
		"engaged": _engaged.keys(), "defeated": _defeated.keys(),
		"defeated_actors": _defeated_actors.keys(),
		"spent": _int_keyed_to_str(_spent), "squad_of": _int_keyed_to_str(_squad_of),
		"events": _events_to_dicts(),
	}

## 素データ1件 → イベント（駒を復元）。to_dict の逆。
static func _event_from_dict(ed: Dictionary, catalog: Dictionary) -> Dictionary:
	var units: Array = []
	for item in ed.get("units", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var ud: Variant = item.get("unit")
		if typeof(ud) != TYPE_DICTIONARY:
			continue
		var ps: Array = []
		for pd in item.get("passengers", []):
			if typeof(pd) == TYPE_DICTIONARY:
				ps.append(Unit.from_full_dict(pd, catalog.get(String(pd.get("type", "")))))
		units.append({
			"unit": Unit.from_full_dict(ud, catalog.get(String(ud.get("type", "")))),
			"passengers": ps,
		})
	return {
		"turn": int(ed.get("turn", 0)), "team": int(ed.get("team", -1)),
		"label": String(ed.get("label", "")), "squad": int(ed.get("squad", -1)),
		"units": units,
	}

## 未発生イベントを素データへ（駒は to_full_dict）。発生済みは配列から消えているので出ない。
func _events_to_dicts() -> Array:
	var out: Array = []
	for e in _events:
		var units_out: Array = []
		for item in e.get("units", []):
			var u: Unit = item.get("unit")
			if u == null:
				continue
			var ps: Array = []
			for p in item.get("passengers", []):
				ps.append((p as Unit).to_full_dict())
			units_out.append({ "unit": u.to_full_dict(), "passengers": ps })
		out.append({
			"turn": int(e.get("turn", 0)), "team": int(e.get("team", -1)),
			"label": String(e.get("label", "")), "squad": int(e.get("squad", -1)),
			"units": units_out,
		})
	return out

## to_dict からの復元。ユニット/拠点の性能は catalog（{id: UnitType}）から再構築する。
## movement 表は復元しない＝呼び出し側が set_movement で再適用する（doc の "見た目・コンフィグはセーブに含めない"）。
static func from_dict(data: Dictionary, catalog: Dictionary = {}) -> BattleState:
	var s := BattleState.new(int(data.get("cols", 12)), int(data.get("rows", 8)))
	s.current_team = int(data.get("current_team", 0))
	s.turn_number = int(data.get("turn_number", 1))
	s.turn_limit = int(data.get("turn_limit", 0))
	s.roster = String(data.get("roster", "fresh"))
	s.enemy_ai = String(data.get("enemy_ai", ""))
	for ud in data.get("units", []):
		if typeof(ud) == TYPE_DICTIONARY:
			s._units.append(Unit.from_full_dict(ud, catalog.get(String(ud.get("type", "")))))
	for td in data.get("terrain", []):
		if typeof(td) == TYPE_DICTIONARY:
			s._terrain[Vector2i(int(td.get("q", 0)), int(td.get("r", 0)))] = String(td.get("t", ""))
	for bd in data.get("bases", []):
		if typeof(bd) == TYPE_DICTIONARY:
			s._bases.append(Base.from_dict(bd, catalog))
	var vc: Variant = data.get("victory_conditions", [])
	s.victory_conditions = vc if typeof(vc) == TYPE_ARRAY else []
	var dc: Variant = data.get("defeat_conditions", [])
	s.defeat_conditions = dc if typeof(dc) == TYPE_ARRAY else []
	var sq: Variant = data.get("squads", [])
	s.squads = sq if typeof(sq) == TYPE_ARRAY else []
	var sm: Variant = data.get("status_mods", [])
	s._status_mods = sm if typeof(sm) == TYPE_ARRAY else []
	for tid in _as_dict(data.get("passengers", {})):
		var arr: Array[Unit] = []
		for pd in data["passengers"][tid]:
			if typeof(pd) == TYPE_DICTIONARY:
				arr.append(Unit.from_full_dict(pd, catalog.get(String(pd.get("type", "")))))
		s._passengers[int(tid)] = arr
	for ed in data.get("events", []):
		if typeof(ed) == TYPE_DICTIONARY:
			s._events.append(_event_from_dict(ed, catalog))
	s._moved = _ids_to_set(data.get("moved", []))
	s._post_moved = _ids_to_set(data.get("post_moved", []))
	s._attacked = _ids_to_set(data.get("attacked", []))
	s._done = _ids_to_set(data.get("done", []))
	s._engaged = _ids_to_set(data.get("engaged", []))
	s._defeated = _ids_to_set(data.get("defeated", []))
	var actors: Variant = data.get("defeated_actors", [])
	if typeof(actors) == TYPE_ARRAY:
		for a in actors:
			s._defeated_actors[String(a)] = true
	s._spent = _str_keyed_to_int(data.get("spent", {}))
	s._squad_of = _str_keyed_to_int(data.get("squad_of", {}))
	return s

## int キーの dict → 文字列キーの dict（JSON はキーを文字列化するので保存時に明示変換）。
static func _int_keyed_to_str(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out

## 文字列キー（JSON復元後）の dict → int キー・int 値の dict（_spent / _squad_of 用）。
static func _str_keyed_to_int(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) == TYPE_DICTIONARY:
		for k in src:
			out[int(k)] = int(src[k])
	return out

## id の配列 → { id(int): true } の集合 dict（_moved 等の行動フラグ復元）。
static func _ids_to_set(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) == TYPE_ARRAY:
		for id in src:
			out[int(id)] = true
	return out

static func _as_dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}
