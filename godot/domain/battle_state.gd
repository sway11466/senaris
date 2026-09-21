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

var _units: Array[Unit] = []
var _moved := {}       # handle -> true（攻撃前の移動を1回使った）
var _post_moved := {}  # handle -> true（攻撃後の再移動を1回使った）
var _attacked := {}    # handle -> true（このターンに攻撃済み）
var _done := {}        # handle -> true（コマンドメニューの「待機」等で明示的に行動終了）
var _spent := {}       # handle -> int（このターンに使った移動コスト。move と比較）
var _terrain := {}   # Vector2i(axial) -> terrain_id（未登録は平地）
var _movement := {}  # move_type -> { 地形名: コスト }（空＝全地形コスト1の従来挙動）
var _bases: Array[Base] = []  # 拠点（占領・出撃・回復）。詳細 → doc/gdd/map.md

## 勝利条件リスト（OR＝どれか1つ満たせば勝利）。空＝殲滅のみ（従来挙動）。詳細 → doc/gdd/map.md（勝敗条件）
## 要素は dict。現在対応: { "type": "defeat_unit", "unit_ids": [<String>, …] } ＝ ボス撃破（名指した駒をすべて撃破。駒に unit_id を書いて名指す）
var victory_conditions: Array = []

## 敗北条件リスト（OR＝どれか1つ満たせば敗北）。空＝自軍消滅・本拠地喪失・時間切れの常時ルールのみ。
## 要素は dict。現在対応: { "type": "lose_base", "bases": [{ "col": <int>, "row": <int> }, …] } ＝ 指定拠点を全て敵に奪われる
##                       { "type": "lose_unit", "unit_ids": [<String>, …] } ＝ 護衛対象の喪失
## 本拠地(hq)喪失の常時ルールとは別軸＝あちらは陣営の要、こちらはステージが名指しする守り物。
var defeat_conditions: Array = []

## 部隊(squad)＝特性とパラメーターを共有するユニットの束。敵ユニットは必ずいずれかの部隊に属する。
## 要素は dict: { "name": 表示名, "ai": 特性id, "order": 行動順, ...パラメーターの上書き（sight/stack） }
## 詳細 → doc/gdd/ai.md（部隊）
var squads: Array = []
var _squad_of := {}  # handle -> squads の index（部隊に属さないユニットは未登録）

## handle を部隊 squad_index に所属させる（StageLoader が配線）。
func assign_squad(handle: int, squad_index: int) -> void:
	_squad_of[handle] = squad_index

## handle の所属部隊（dict）。部隊に属さなければ空 dict。
func squad_of(handle: int) -> Dictionary:
	var idx := squad_index_of(handle)
	return squads[idx] if idx >= 0 else {}

## handle の所属部隊 index（部隊に属さなければ -1）。一斉警戒（同部隊判定）に使う。
func squad_index_of(handle: int) -> int:
	var idx: Variant = _squad_of.get(handle)
	if idx == null or int(idx) < 0 or int(idx) >= squads.size():
		return -1
	return int(idx)

# --- AI起動状態（待ち伏せAIの「起きた」フラグ）。詳細 → doc/gdd/ai.md ---

var _engaged := {}  # handle -> true（待ち伏せAIが起動済み。一度起動したら戻らない）

## handle を起動済みにする（AIの起動判定・被弾で立つ）。
func mark_engaged(handle: int) -> void:
	_engaged[handle] = true

## handle が起動済みか。
func is_engaged(handle: int) -> bool:
	return _engaged.has(handle)

var _engaged_squads := {}  # squads の index -> true（拠点の起動フラグ。一度起動したら戻らない）

## 部隊 squad_index を起動済みにする。盤上に駒を持たない部隊（＝拠点そのもの）は駒のフラグを
## 立てられないので部隊の側に焼く。一斉警戒はこのフラグを通って部隊の中を双方向に回る。
func mark_squad_engaged(squad_index: int) -> void:
	if squad_index >= 0:
		_engaged_squads[squad_index] = true

## 部隊 squad_index が起動済みか（拠点が起きたか）。
func is_squad_engaged(squad_index: int) -> bool:
	return squad_index >= 0 and _engaged_squads.has(squad_index)

# --- 状態補正（バフ/デバフ・持続）。詳細 → doc/gdd/combat.md「状態補正」 ---

## 継続ダメージ（毒）で下回らせない残兵数。毒では全滅しない＝倒すのは戦闘の役目。詳細 → doc/gdd/skills.md
const DOT_TROOPS_FLOOR := 1

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

## unit が貫通無効（⑦マジックシールドの結界の中）か。combat の貫通の段が読み、効いていれば
## 攻撃側の貫通を 0 として扱う。詳細 → doc/gdd/formations.md ⑦
func pierce_immune(unit: Unit) -> bool:
	return StatusMod.pierce_immune(_status_mods, unit)

## いま張られている地帯（zone）の一覧＝{hexes, team, fx, skill}。盤が結界の印を重ねるのに読む
## （持続の間ずっと出す＝中か外かが盤で読める）。詳細 → doc/gdd/formations.md ⑦
func status_zones() -> Array:
	var out: Array = []
	for m in _status_mods:
		if String(m.get("scope", "")) != "zone":
			continue
		var center := Vector2i(int(m.get("q", 0)), int(m.get("r", 0)))
		out.append({
			"hexes": Hex.within_range(center, int(m.get("radius", 0))),
			"team": int(m.get("team", -1)),
			"fx": String(m.get("fx", "")),
			"skill": String(m.get("skill", "")),  # 盤が印の絵を規約解決するのに使う
		})
	return out

## unit 1体に効いている弱体（デバフ）の本数。敵AIの stack 条件（doc/gdd/ai.md）が読む。
func debuff_count(unit: Unit) -> int:
	return StatusMod.debuff_count(_status_mods, unit)

## unit 1体に効いている強化（バフ）の本数。敵AIの stack 条件（強化を重ねる上限）が読む。
## 弱体と同じく対象1体に掛かったものだけ＝陣営全体の補正（グレイス）は数えない。
func buff_count(unit: Unit) -> int:
	return StatusMod.buff_count(_status_mods, unit)

## unit に掛かっている弱体（デバフ）を落とす（③ピュリファイ）。落とした件数を返す。
## 落とすのは kind が debuff で対象1体（scope="unit"）のものだけ＝味方から掛かった
## 強化（ピクシーダスト）は残り、陣営全体に掛かった補正を1人のピュリファイで消すこともない。
## 詳細 → doc/gdd/skills.md
func clear_debuffs(unit: Unit) -> int:
	var kept: Array = []
	for m in _status_mods:
		if StatusMod.is_unit_debuff(m, unit):
			continue
		kept.append(m)
	var removed := _status_mods.size() - kept.size()
	_status_mods = kept
	return removed

## 陣営全体に効いていて盤の見た目（fx）を宣言している補正の名前。無ければ空文字。
## 盤全体のエフェクト（グレイスの加護の光）を出すかの判定に presentation が使う。
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

## 継続ダメージ（⑥ポイズンスティング）を、ターンが始まった陣営の駒に適用する（end_turn から呼ぶ）。
## 減るのは対象側のターン開始時＝掛けられた側が自分の手番の頭で気づける（持続の満了判定が
## 発動側ターン開始なのとは別軸）。重ねがけは加算。詳細 → doc/gdd/skills.md
##
## 残兵 DOT_TROOPS_FLOOR を下回らせない＝毒では全滅しない。倒すのは戦闘の役目で、殴らずに毒だけで
## 削る戦法を最適解にしないための線引き。盤の上の駒だけが対象（搭乗中・garrison は減らない）。
func _tick_dots() -> void:
	for u in _units:
		if u.team != current_team:
			continue
		var n := StatusMod.dot_amount(_status_mods, u)
		if n <= 0:
			continue
		# シールドは 0 まで減り、残兵の下限は本体にだけ掛かる＝減らせる量を先に切ってから入口を通す。
		var room := u.shield + maxi(u.troops - DOT_TROOPS_FLOOR, 0)
		u.take_loss(mini(n, room))

# --- チャージ（再使用間隔）。詳細 → doc/gdd/skills.md ---
#
# 駒ごと・スキルごとに整数値を持ち、毎ターン開始時に +1 される。スキルの必要量に達すると
# 発動できる。発動すると 0 に戻る。盤に出た直後は 0＝溜まるまで撃てない。
# 将来、他のスキルでチャージ量を直接加速できる余地を残す（→ doc/gdd/skills.md 共通ルール）。

var _charges := {}  # handle -> { skill_id: int }

## handle の skill_id に対するチャージ量（未登録は 0）。
func get_charge(handle: int, skill_id: String) -> int:
	var per_unit: Variant = _charges.get(handle)
	if per_unit == null or typeof(per_unit) != TYPE_DICTIONARY:
		return 0
	return int((per_unit as Dictionary).get(skill_id, 0))

## handle の skill_id のチャージ量を value にセットする。
func set_charge(handle: int, skill_id: String, value: int) -> void:
	if not _charges.has(handle):
		_charges[handle] = {}
	_charges[handle][skill_id] = value

## ターン開始時に、始まった陣営の駒のチャージ量を +1 する（charge_turns を持つスキルだけ）。
## 盤上の駒だけが対象（搭乗中・garrison はチャージしない）。
func _increment_charges() -> void:
	for u in _units:
		if u.team != current_team:
			continue
		for rid in Formation.SKILLS:
			var r: Dictionary = Formation.SKILLS[rid]
			if int(r.get("charge_turns", 0)) <= 0:
				continue
			if not Formation.can_cast_skin(u, r):
				continue
			var cur := get_charge(u.handle, rid)
			set_charge(u.handle, rid, cur + 1)

var _defeated := {}  # handle -> true（撃破で盤から消えた駒の記録）
## team -> 失った駒の数（累積・兵器は数えない）。戦果票の撃破数が敵側の値を読む。doc/gdd/rank.md
var _losses := {}
var _defeated_unit_ids := {}  # unit_id -> true（名指された駒の撃破。ボス撃破・護衛対象の喪失が見る。doc/gdd/map.md）
## actor -> true（この戦闘に投入された名前つきの駒。初期配置・拠点の控え・搭乗・増援のすべてを含む）。
## クリア後の名簿更新がここを見て「出た者」と「出番の無かった者」を分ける。詳細 → doc/gdd/campaigns.md 名簿の更新
var _fielded_actors := {}

func _init(p_cols: int = 12, p_rows: int = 8) -> void:
	cols = p_cols
	rows = p_rows

func add_unit(unit: Unit) -> void:
	_units.append(unit)
	_mark_fielded(unit)

## 名前つきの駒を「この戦闘に出た」として控える。盤・控え・搭乗の入口すべてから呼ぶ。
func _mark_fielded(u: Unit) -> void:
	if u != null and u.actor != "":
		_fielded_actors[u.actor] = true

## この戦闘に投入された駒か（名簿の更新対象かどうか）。
func has_fielded(actor: String) -> bool:
	return actor != "" and _fielded_actors.has(actor)

func units() -> Array[Unit]:
	return _units

func unit_by_handle(handle: int) -> Unit:
	for u in _units:
		if u.handle == handle:
			return u
	return null

## 盤上に居なくても handle で引く（輸送に乗っている駒も探す）。降車先を決めている間の搭乗駒は
## まだ盤に居ないので、「降車先に居るものとして」見る判定（攻撃・拠点に入る・スキル）はこちらを使う。
## 盤の状態を変える処理（移動・攻撃）は unit_by_handle のまま＝盤外の駒を動かさない。
func unit_any(handle: int) -> Unit:
	var u := unit_by_handle(handle)
	if u != null:
		return u
	for tid in _passengers:
		for p in _passengers[tid]:
			if (p as Unit).handle == handle:
				return p
	return null

func unit_at(hex: Vector2i) -> Unit:
	for u in _units:
		if u.pos == hex:
			return u
	return null

# --- イベント（途中で起きること）。詳細 → doc/gdd/map.md イベント ---
#
# 引き金は turn（Nターン目）か on（盤の出来事＝いまは "capture" ＝拠点の占領）のどちらか。
# 増援＝開始時に盤に存在しない駒が加わること。拠点の控えを出す出撃や、
# 盤に居る敵部隊が動き出す起動（engage）とは別物で、これだけを「増援」と呼ぶ。
# 駒は StageLoader が読み込み時に組んで（catalog 解決込み）ここへ預け、発生時に盤へ出す。

## 未発生のイベント。発生したものは取り除く＝残っているものが未発生。
## 各要素 = { id, turn, on, hex, team, label, once, dialogue, focus, squad,
##            units: [ { unit: Unit, passengers: Array[Unit] } ] }
## id＝イベントの名前（ステージ内で一意）。セーブが未発火のイベントを識別するのに使う。
## on が空＝turn 起点。"capture"＝hex の拠点を team が取った瞬間（turn は見ない）。
## once＝排他の名前。同じ名前を持つイベントはどれか1つだけ起きる。
## 発生時に placed（実際に駒が出た hex の配列）が足される。
var _events: Array[StageEvent] = []

## 発火済み（once の兄弟として捨てたものを含む）のイベント id。中断セーブに乗る
## ＝復元はステージ定義のイベントからこの id を除いた残りを未発火とする。
## 未発火の側を持たないのは、ステージ更新で足したイベントを既存のセーブへ届かせるため。
var _fired_events := {}  # id -> true

## 直近の fire_due_events で起きたイベント（上へ知らせるための控え）。end_turn が内側で発火するので、
## 戻り値だけでは呼び出し側に届かない。保存はしない＝復元直後は空。
var last_fired_events: Array[StageEvent] = []

## イベントを積む（StageLoader が組んで渡す）。
func add_event(e: StageEvent) -> void:
	_events.append(e)

## 未発生のイベント一覧（読み取り専用）。
func pending_events() -> Array[StageEvent]:
	return _events

## いちばん近い未発生の増援の { label, turns }。turns＝あと何ターンで来るか（0＝このターン）。
## label を持たないイベントは予告しない＝ここには出さない。無ければ空。残りターン板が読む
## （→ doc/gdd/uiux.md 残りターン板）。
func next_event() -> Dictionary:
	var out := {}
	var best := -1
	for e in _events:
		if e.is_capture():
			continue  # 盤の出来事が引き金＝あと何ターンかを数えられない
		if e.label.is_empty():
			continue
		if best < 0 or e.turn < best:
			best = e.turn
			out = { "label": e.label, "turns": maxi(e.turn - turn_number, 0) }
	return out

## 発生ターンが来たイベントを起こす。起きたものの配列を返す（演出・ログ用）。
## end_turn の最後と、ステージ開始直後（1ターン目の分）に呼ぶ。指定ターンを過ぎていても
## 取りこぼさないよう「turn 以下」で見る。引き金が盤の出来事のイベントはここでは起きない。
func fire_due_events() -> Array[StageEvent]:
	var fired: Array[StageEvent] = []
	for e in _events.duplicate():  # 発生ぶんを取り除きながら回すので控えを辿る
		if not _is_pending(e):
			continue  # 同じ once の兄弟が先に起きて捨てられた
		if e.is_capture():
			continue
		if e.turn <= turn_number and e.team == current_team:
			_consume_event(e)
			fired.append(e)
	last_fired_events = fired
	return fired

## hex の拠点の所属が team へ変わったときに起こすイベント（引き金＝占領）。起きたものを返す。
## 占領そのものは _try_capture が静かに書き換えるだけなので、前後の所属を見比べている
## 呼び出し側（MatchController）から呼ぶ。last_fired_events は触らない＝そちらは end_turn 用。
func fire_capture_events(hex: Vector2i, team: int) -> Array[StageEvent]:
	var fired: Array[StageEvent] = []
	for e in _events.duplicate():
		if not _is_pending(e):
			continue  # 同じ once の兄弟が先に起きて捨てられた
		if not e.is_capture():
			continue
		if e.hex != hex or e.team != team:
			continue
		_consume_event(e)
		fired.append(e)
	return fired

## デバッグ: 未発生イベント e を引き金を問わず起こす（起こせたら true）。引き金の成否を見ないので
## 引き金の種類が増えてもここは変わらない。盤は動かさない＝占領起点でも拠点の所属はそのまま
## （会話と増援だけが流れる）。last_fired_events は触らない＝そちらは end_turn 用。
## 呼ぶのはデバッグメニューだけ。詳細 → doc/gdd/uiux.md デバッグメニュー
func fire_event(e: StageEvent) -> bool:
	if not _is_pending(e):
		return false
	_consume_event(e)
	return true

## まだ未発生か（控えに残っているか）。同じイベントそのものを探す＝中身の一致では見ない。
func _is_pending(e: StageEvent) -> bool:
	return e in _events

## イベントを1件起こす＝駒を盤へ出し、未発生の控えから取り除く。
## once に名前があれば、同じ名前の未発生イベントもまとめて捨てる＝どれか1つだけが起きる
## （中立拠点を味方が解放したときと敵に取られたときで、先に起きたほうだけを流す）。
func _consume_event(e: StageEvent) -> void:
	_place_event_units(e)
	var kept: Array[StageEvent] = []
	for other in _events:
		if other == e:
			_fired_events[other.id] = true
			continue
		if not e.once.is_empty() and other.once == e.once:
			_fired_events[other.id] = true  # 捨てた兄弟も済み＝復元で蘇らせない
			continue
		kept.append(other)
	_events = kept

## イベントの駒を盤へ出す。置けなかった駒は出さずに警告1行＝イベント全体は止めない。
## 実際に出た hex は placed に控える＝ずれて出ても、上（カメラ・演出）が本当の場所を見られる。
func _place_event_units(e: StageEvent) -> void:
	e.placed.clear()
	e.placed_ids.clear()
	for item in e.units:
		var u := item.unit
		if u == null:
			continue
		var hex := _free_hex_for(u, u.pos)
		if hex == Vector2i.MAX:
			push_warning("BattleState: 増援を置く空きが無い（この駒は出さない）: id=%d" % u.handle)
			continue
		u.pos = hex
		e.placed.append(hex)
		e.placed_ids.append(u.handle)
		add_unit(u)
		if item.squad_index >= 0:
			assign_squad(u.handle, item.squad_index)
		for p in item.passengers:
			put_passenger(u.handle, p)

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
	return passengers(transport.handle).size() < transport.capacity

## 駒を輸送へ直接積む（初期配置・乗車の内部処理。行動フラグは触らない）。
func put_passenger(transport_id: int, u: Unit) -> void:
	if not _passengers.has(transport_id):
		var list: Array[Unit] = []
		_passengers[transport_id] = list
	_passengers[transport_id].append(u)
	_mark_fielded(u)

## 降車先候補の {hex: コスト}。搭乗駒が「輸送の位置を起点に」自力で動ける空きhex（通常移動と同じ規則）。
## 隣接1マスの特例: 輸送に隣接する進入可能な空きマスは、移動力・地形コストに関係なく常に含める
## （積み降ろしは人手＝移動0の駒も隣へ降ろせる）。進入不可地形（x）は特例でも不可。
## 乗車したターン（行動済み）の駒は降りられない＝空。
func _unload_map(transport_id: int, index: int) -> Dictionary:
	var t := unit_by_handle(transport_id)
	var list := passengers(transport_id)
	if t == null or index < 0 or index >= list.size():
		return {}
	var p: Unit = list[index]
	if has_moved(p.handle):
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
	_moved[p.handle] = true
	_spent[p.handle] = int(m[to])
	_try_capture(p)
	return true

# --- 拠点（占領・出撃・回復）。詳細 → doc/gdd/map.md ---

## 占領成功で占領兵が得るレベル。占領兵は戦闘機会が少ないぶんを1回で補う。詳細 → doc/gdd/combat.md
const CAPTURE_LEVEL_GAIN := 10

func add_base(base: Base) -> void:
	_bases.append(base)
	for gu in base.garrison:
		_mark_fielded(gu as Unit)  # 控えも参戦済み（出撃しなくてもこの盤に居る）

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

## u が hex の地形に入れるか（駒の有無は見ない＝地形だけの判定）。
## 盤外・進入不可地形（move_type の x）が false。AIが降車先を見積もるのに使う。
func can_enter_terrain(u: Unit, hex: Vector2i) -> bool:
	if u == null or not in_field(hex):
		return false
	return Movement.cost(_movement, u.move_type, terrain_at(hex)) != Movement.IMPASSABLE

## hex に地形を設定する。
func set_terrain(hex: Vector2i, terrain_id: String) -> void:
	_terrain[hex] = terrain_id
	_travel_cache.clear()
	_sight_cache.clear()

## 移動コスト表を設定する（move_type -> {地形名: コスト}）。
func set_movement(table: Dictionary) -> void:
	_movement = table
	_travel_cache.clear()

## いま使っている移動コスト表（読み取り用の写し）。情報パネルが地形のコスト一覧を出すのに使う。
func movement_table() -> Dictionary:
	return _movement.duplicate()

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
## ignore_ids＝「居ないもの」として測る駒のid（AIの経路上の敵＝どければ道が良くなるかを測る）。
## budget＝流す上限コスト。これを超えるマスは表に載らない（載る範囲の値は上限に依らず同じ）。
func travel_cost_field_avoiding_units(goal: Vector2i, move_type: String, budget: int,
		max_step_cost: int = 0, from_hex: Vector2i = Vector2i(1 << 30, 1 << 30),
		ignore_ids: Dictionary = {}) -> Dictionary:
	if not in_field(goal):
		return {}
	var cost_fn := func(hex: Vector2i) -> int:
		if not in_field(hex):
			return Movement.IMPASSABLE
		var occ := unit_at(hex)
		if hex != goal and hex != from_hex and occ != null and not ignore_ids.has(occ.handle):
			return Movement.IMPASSABLE  # 標的以外の駒は壁
		var c := Movement.cost(_movement, move_type, terrain_at(hex))
		if max_step_cost > 0 and c > max_step_cost:
			return Movement.IMPASSABLE
		return c
	return Hex.flood_reach_cost_map(goal, budget, cost_fn)

## travel_cost_field のメモ（地形・移動コスト表が変わるまで有効）。
## 盤ごと・移動タイプごとに1枚で、駒が動いても作り直さない＝AIが毎ターン全員ぶん流し直さない。
## 直列化しない（to_dict に載せない）＝復元後に作り直せる導出物。
var _travel_cache := {}

# --- 視線（索敵の遮蔽・減衰）。詳細 → doc/gdd/movement.md（視線）, doc/gdd/ai.md（起動） ---

var _sight_cost := {}  # 地形id -> 視線コスト（空＝全地形1＝純距離の索敵と一致）。TerrainType から注入

## visible_hexes のメモ（位置と sight ごと。地形・視線コスト表が変わるまで有効）。
## 見張りは起きるまで動かず、地形は戦闘中に変わらないので、1体につき実質1回の計算で済む。
## 地形を1マスでも書き換えたら全部捨てる（set_terrain / set_sight_cost）＝部分的に消す仕組みは持たない。
## 直列化しない（to_dict に載せない）＝復元後に作り直せる導出物。返る辞書は共有＝呼び出し側で書き換えない。
var _sight_cache := {}  # Vector3i(from.x, from.y, budget) -> { hex: true }

## 視線コスト表を注入する（movement 表と同型＝domain を data 非依存に保つ）。
func set_sight_cost(table: Dictionary) -> void:
	_sight_cost = table
	_sight_cache.clear()

## hex の視線コスト（未登録は1＝開地相当）。壁など `x` は TerrainType.SIGHT_OPAQUE の大きな値。
func sight_cost_at(hex: Vector2i) -> int:
	return int(_sight_cost.get(terrain_at(hex), 1))

## 視線の規則計算は Sight（static ヘルパー）が持つ＝ここは表と記憶の持ち主。
## from から視線が to に届くか＝from の検知域に to が入っているか。
func sight_reaches(from: Vector2i, to: Vector2i, budget: int) -> bool:
	return visible_hexes(from, budget).has(to)

## from の検知域（budget 以内で見える盤内ヘックス。from 含む）。位置と budget ごとに記憶する。
func visible_hexes(from: Vector2i, budget: int) -> Dictionary:
	var key := Vector3i(from.x, from.y, budget)
	if _sight_cache.has(key):
		return _sight_cache[key]
	var vis := Sight.visible_hexes(self, from, budget)
	_sight_cache[key] = vis
	return vis

## handle が「残り移動力」で到達できるヘックス（起点を含む）。盤外・敵は進入不可、地形はコスト。
## 味方のマスは通過できるが停止できない（到達候補には含めない）。
## 敵ZOC（敵に隣接するマス）に入ると停止＝その先へは進めない（飛行含む全移動タイプ）。
func reachable(handle: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in _reach_map(handle):
		result.append(h)
	return result

## handle が to へ移動するときに通るヘックス列（起点 u.pos で始まり to で終わる）。
## 移動できない to には空配列。盤の状態は変えない（見た目＝移動アニメの経路に使う）。
## move_unit より前に呼ぶこと: 移動後は u.pos と _spent が変わり、同じ経路は復元できない。
func path_to(handle: int, to: Vector2i) -> Array[Vector2i]:
	var u := unit_by_handle(handle)
	if u == null or to == u.pos or not _reach_map(handle).has(to):
		return []
	var budget := maxi(u.move - int(_spent.get(handle, 0)), 0)
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

## 入口 from から handle がいま立っているヘックスまでの通り道（見た目だけの経路）。
## 移動力の予算・敵ZOC・ほかの駒は見ない＝地形の進入可否だけをたどる（駒どうしはすり抜ける）。
## 1マスの進入コストがその駒の移動力を超えるヘックスは通さない＝何ターンかけても入れないマスは
## その駒の道ではない（移動2の駒にとっての柵。travel_cost_field と同じ線引き）。
## 移動力0の駒（据え置き）は上限を課さない＝運び込まれた体で歩かせる。
## 増援の登場の演出が使う。たどり着けなければ空配列＝呼んだ側はその駒をその場に出す。
## 詳細 → doc/gdd/map.md イベント（entry／from）・doc/gdd/uiux.md 移動の見せ方
func entry_path(handle: int, from: Vector2i) -> Array[Vector2i]:
	var u := unit_by_handle(handle)
	if u == null or not in_field(from) or from == u.pos:
		return []
	var max_step := u.move
	var cost_fn := func(hex: Vector2i) -> int:
		if not in_field(hex):
			return Movement.IMPASSABLE
		var c := Movement.cost(_movement, u.move_type, terrain_at(hex))
		if max_step > 0 and c > max_step:
			return Movement.IMPASSABLE
		return c
	var prev := Hex.flood_reach_prev_map(from, 1 << 24, cost_fn)
	if not prev.has(u.pos):
		return []
	var path: Array[Vector2i] = [u.pos]
	var cur := u.pos
	while cur != from:
		cur = prev[cur]
		path.append(cur)
	path.reverse()
	return path

## reachable の {ヘックス: 到達コスト} 版（残り移動力で計算）。移動コスト消費に使う。
## 隣接1マスの特例: 隣接する乗れる輸送のマスは、移動力・地形コストに関係なく常に含める
## （積み降ろしは人手＝移動0の駒も隣の輸送には乗れる）。詳細 → doc/gdd/movement.md（輸送）
func _reach_map(handle: int) -> Dictionary:
	var u := unit_by_handle(handle)
	if u == null:
		return {}
	var budget := maxi(u.move - int(_spent.get(handle, 0)), 0)
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
## 乗れる味方輸送のマスへも同じく進入できる（そこで止まれば乗車・通り抜けてもよい）。
func _enter_cost(hex: Vector2i, u: Unit) -> int:
	if not in_field(hex):
		return Movement.IMPASSABLE
	var occ := unit_at(hex)
	if occ != null and occ.team != u.team:
		return Movement.IMPASSABLE  # 敵の上は通れない（味方は通過可）
	return Movement.cost(_movement, u.move_type, terrain_at(hex))

## hex で移動が止まるか（その先へ展開しない）。止まるのは敵ZOCだけ。
## 味方のマスでは止まらず先へ展開する（通過はできるが停止はできない＝到達候補にはならない）。
## 輸送も味方のマスと同じ＝すり抜けて先へ行ける（乗車先としても選べる。doc/gdd/movement.md）。
func _move_stop(hex: Vector2i, u: Unit) -> bool:
	return in_enemy_zoc(hex, u)

## hex が u から見た敵ZOC内か（敵ユニットに隣接しているか）。ZOCに入ると移動が止まる。
## ignore_id＝ZOCを数えない敵（-1＝全員数える）。AIの迂回距離（AiDistance）が狙う標的だけを外すのに使う。
func in_enemy_zoc(hex: Vector2i, u: Unit, ignore_id: int = -1, ignore_ids: Dictionary = {}) -> bool:
	for nb in Hex.neighbors(hex):
		var occ := unit_at(nb)
		if occ != null and occ.team != u.team and occ.handle != ignore_id and not ignore_ids.has(occ.handle):
			return true
	return false

## 妥当なら移動を適用して true。ターン違い・移動権なし・不正先なら false。移動コストを予算から消費。
## 移動先が「乗れる味方輸送」のマスなら乗車＝盤から降りて搭乗し、その駒は行動完了になる。
func move_unit(handle: int, to: Vector2i) -> bool:
	if not _can_act_move(handle):
		return false
	var rm := _reach_map(handle)
	var u := unit_by_handle(handle)
	if to == u.pos or not rm.has(to):
		return false
	var occ := unit_at(to)
	if occ != null:
		if not can_board(u, occ):
			return false
		_take_off_board(handle)  # 乗車: 盤から外して輸送へ（撃破記録は付かない）
		put_passenger(occ.handle, u)
		_moved[handle] = true    # 乗った駒は行動完了（doc/gdd/movement.md）
		_post_moved[handle] = true
		_attacked[handle] = true
		_spent[handle] = u.move
		return true
	u.pos = to
	_spent[handle] = int(_spent.get(handle, 0)) + int(rm[to])
	# 攻撃前なら通常移動、攻撃後なら再移動として消費（どちらも1回）。
	if has_attacked(handle):
		_post_moved[handle] = true
	else:
		_moved[handle] = true
	_try_capture(u)  # 占領可ユニットが敵/中立拠点に入ったら即占領
	return true

## u が今いる拠点を占領できるなら所属を u の陣営へ移す（占領＝即時・進入した瞬間）。
func _try_capture(u: Unit) -> void:
	if not u.can_capture:
		return
	var b := base_at(u.pos)
	if b != null and b.team != u.team:
		b.team = u.team
		u.gain_level(CAPTURE_LEVEL_GAIN)

## いま移動できるか（ターン・移動権・残り予算）。
## 攻撃前: 通常移動を未使用なら可。攻撃後: 再移動可ユニットが再移動を未使用なら可。
func _can_act_move(handle: int) -> bool:
	var u := unit_by_handle(handle)
	if not is_current_unit(u):
		return false
	if int(_spent.get(handle, 0)) >= u.move and _adjacent_boardable(u).is_empty():
		return false  # 予算切れ（隣接に乗れる輸送があれば特例で乗車だけはできる）
	if has_attacked(handle):
		return u.move_after_attack and not _post_moved.has(handle)
	return not _moved.has(handle)

## いま移動できるか（公開）。盤の移動範囲表示などに使う。
func can_still_move(handle: int) -> bool:
	return _can_act_move(handle)

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
	if passengers(occ.handle).size() >= occ.capacity:
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
	# 行動終了フラグだけを見る（盤外の駒に is_done / is_stuck の盤面判定は当てられない）。
	# フラグは end_turn で一掃される＝次の自軍ターンから出せる。
	if _done.has(u.handle):
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
		put_passenger(occ.handle, u)  # 出撃先が輸送＝直接乗車（盤上には出ない）
	else:
		u.pos = to_hex
		_units.append(u)
	if b.squad_index >= 0:
		assign_squad(u.handle, b.squad_index)  # 拠点=部隊の駒として振る舞う（敵AIの拠点出撃。ai.md 拠点出撃）
	# 出撃した駒はそのターン行動完了（1歩のみ＝移動も再移動も攻撃も降車もこれ以上しない）。
	_moved[u.handle] = true
	_post_moved[u.handle] = true
	_attacked[u.handle] = true
	_spent[u.handle] = u.move
	return true

## 自軍所有の拠点に「入る」（駐留）。拠点hexに立っている駒を garrison へ移す＝盤上から消える。
## 中でターン開始ごとに回復（_heal_garrisons）。出るのは出撃（deploy）＝1歩・行動完了。
func can_enter_base(handle: int) -> bool:
	var u := unit_by_handle(handle)
	return u != null and can_enter_base_at(handle, u.pos)

## dest_hex（自軍拠点）へ移動して「入る」が許されるか。メニュー表示は移動前に先読みするため、
## 現在位置ではなく移動先を仮定して判定する（実行時は dest_hex＝現在位置で同じ規則になる）。
## 案B: 盤上最後の1体でも、入った直後に復帰手段が残るなら入れる（即敗北を防ぐ）。
func can_enter_base_at(handle: int, dest_hex: Vector2i) -> bool:
	var u := unit_any(handle)  # 降車先が自軍拠点なら、降りた駒はそのまま入れる
	if not is_current_unit(u):
		return false
	var b := base_at(dest_hex)
	if b == null or b.team != u.team:
		return false
	if not b.can_rest(u.team):
		return false  # 休めない拠点には入れない（rest → doc/gdd/map.md 回復）
	if team_unit_count(u.team) > 1:
		return true  # 入っても盤上に他の駒が残る
	# 盤上最後の1体：入った駒自身が b の出せる控えになる＝b に空き隣接があれば復帰可。
	# 他拠点で既に復帰可能でもよい（＝入った瞬間に「盤上0かつ復帰なし」の敗北にならない）。
	return _base_has_open_neighbor(b) or has_reinforcement(u.team)

## 輸送が入ったときは積載を空にし、搭乗駒も garrison へ移す＝拠点の中に「積んだままの馬車」を
## 残さない（中では降ろせないので、そのままだと搭乗駒が回復も出撃もできない）。搭乗駒にも行動終了を
## 付ける＝乗せて入ってその場でバラまく再配置を止める（輸送自身の往復を止めるのと同じ理由）。
func enter_base(handle: int) -> bool:
	if not can_enter_base(handle):
		return false
	var u := unit_by_handle(handle)
	var b := base_at(u.pos)
	_take_off_board(handle)
	set_done(handle)  # 入るのも1手＝行動終了。これがそのターンの出撃を止める（往復させない）
	b.garrison.append(u)
	for p in passengers(handle):
		set_done(p.handle)
		b.garrison.append(p)
	_passengers.erase(handle)
	return true

# --- 攻撃 ---

## attacker が target を攻撃できるか（現ターン・未攻撃・射程内の敵）。
func can_attack(attacker_id: int, target_id: int) -> bool:
	var a := unit_by_handle(attacker_id)
	if a == null:
		return false
	return _can_attack_from(a, unit_by_handle(target_id), a.pos)

## from_hex に attacker が居ると仮定したときの攻撃可否。仮移動でメニューを出す（移動確定前）ために使う。
func _can_attack_from(a: Unit, t: Unit, from_hex: Vector2i) -> bool:
	if a == null:
		return false
	if not is_current_unit(a) or has_attacked(a.handle):
		return false
	return _can_hit(a, t, from_hex)

## a が from_hex から t に攻撃を届かせられるか＝盤の形だけの判定（ターンの状態は見ない）。
## 陣営・対空/対地・射程の3つ。AIの距離（攻撃可能なマス）はターンの外から測るのでこちらを使う
## ＝手番でない駒からも距離が読める。攻撃そのものの可否は _can_attack_from（ターン判定つき）。
func _can_hit(a: Unit, t: Unit, from_hex: Vector2i) -> bool:
	if a == null or t == null:
		return false
	if t.team == a.team:
		return false
	if a.attack_against(t) <= 0:
		return false  # 対空0の駒は飛行を狙えない（攻撃力が無い相手は対象外）
	return a.can_reach(Hex.distance(from_hex, t.pos))  # 下限min_range〜上限attack_range

## attacker が今いる位置から攻撃できる敵ユニットIDの一覧。
func attack_targets(attacker_id: int) -> Array[int]:
	var a := unit_by_handle(attacker_id)
	return attack_targets_from(attacker_id, a.pos) if a != null else []

## from_hex に居ると仮定して攻撃できる敵ID一覧（移動を確定せずコマンドメニューを出すため）。
func attack_targets_from(attacker_id: int, from_hex: Vector2i) -> Array[int]:
	var a := unit_any(attacker_id)  # 降車先を決めている搭乗駒も「そこに居るものとして」測る
	var ids: Array[int] = []
	if a == null:
		return ids
	for u in _units:
		if _can_attack_from(a, u, from_hex):
			ids.append(u.handle)
	return ids

## 攻撃を解決。両軍同時攻撃（防御側は反撃する）。
## 成功なら AttackResult（損害・撃破はスナップショットと打撃の内訳から導く）、不正なら null。
func attack(attacker_id: int, target_id: int) -> AttackResult:
	if not can_attack(attacker_id, target_id):
		return null
	var a := unit_by_handle(attacker_id)
	var t := unit_by_handle(target_id)
	var melee := Hex.distance(a.pos, t.pos) <= 1  # 距離1の攻撃＝近接（反撃あり）、距離≥2＝遠隔（反撃なし）
	# melee が効くのはここ＝反撃の成立だけ。包囲・支援・地形・レベルは距離によらず乗る（doc/gdd/combat.md）。
	# 反撃は「近接（距離1）」かつ「防御側が距離1を狙えて、攻撃側を攻撃できる」ときだけ成立。
	# 例: 対空0の地上ユニットが飛行に殴られても反撃できない／砲兵(min_range≥2)は懐の敵に反撃できない（→被反撃なし・Lv+0）。
	var can_retaliate := melee and t.can_reach(1) and t.attack_against(a) > 0
	# 同時攻撃: 戦闘前の状態で内訳ごと確定してから適用（決定的）。表示はこの内訳をそのまま使う。
	var fwd := Combat.hit_detail(self, a, t)
	var ret: HitDetail = Combat.hit_detail(self, t, a) if can_retaliate else null
	# 戦闘前スナップショット（撃破で盤から消えても結果表示できるよう値を固める）。
	var a_snap := unit_snapshot(a)
	var t_snap := unit_snapshot(t)
	var dmg_to_target := fwd.loss
	var dmg_to_attacker := ret.loss if ret != null else 0
	t.take_loss(dmg_to_target)  # シールドから先に減る（兵数が減る唯一の入口）。詳細 → doc/gdd/combat.md
	a.take_loss(dmg_to_attacker)
	var target_killed := t.troops <= 0
	var attacker_killed := a.troops <= 0
	a_snap.troops_after = a.troops
	t_snap.troops_after = t.troops
	a_snap.shield_after = a.shield
	t_snap.shield_after = t.shield
	# レベル: 戦ったら+1・倒したらさらに+1。攻撃側は常に参加。
	# 防御側は反撃が成立したときだけ+1（間接で撃たれた側／対空なしで飛行に撃たれた側は+0）。
	a.gain_level(1 + (1 if target_killed else 0))
	if can_retaliate:
		t.gain_level(1 + (1 if attacker_killed else 0))
	if target_killed:
		_remove_unit(target_id)
	if attacker_killed:
		_remove_unit(attacker_id)
	_attacked[attacker_id] = true  # 移動可否は move_after_attack で判定（再移動）
	# 被ダメは待ち伏せAIの確定起動トリガー（攻撃した側も当然起動済み）。詳細 → doc/gdd/ai.md
	mark_engaged(attacker_id)
	mark_engaged(target_id)
	var out := AttackResult.new()
	out.attacker = a_snap
	out.defender = t_snap
	out.to_defender = fwd
	out.to_attacker = ret  # 戦闘結果ビュー用（式は Combat.hit_detail の1か所＝盤の兵数と一致）
	out.melee = melee
	return out

# --- AIの距離の材料（測れない番兵・攻撃可能なマス）。距離そのものは AiDistance。詳細 → doc/gdd/ai.md（用語 > 距離） ---

## 距離が「測れない」ことを表す番兵。除外したマスを避けて標的へ辿り着けないときの値で、
## そのまま比較できる（＝どの標的よりも遠い）。行き先が無くなったあとどう振る舞うかは
## 特性ごとの行動ルールが決める。
const UNREACHABLE := 1 << 30

## 標的 target_id に攻撃可能なマスの集合＝handle の駒がそこに立てば攻撃が届くマス。
## 射程（min_range〜attack_range）だけでなく、その標的を攻撃できるか（対空・対地）まで見る
## ＝対空攻撃力の無い駒にとって飛行の標的は1マスも持たない＝距離が測れない。
## 空きも地形も見ない: 駒で埋まったマスは移動距離の側で壁として落ち、地形距離では逆に数える
## （地形距離は駒を壁にしない）。ここで絞ると2つの距離の使い分けが潰れる。
func attack_cells(handle: int, target_id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var a := unit_by_handle(handle)
	var t := unit_by_handle(target_id)
	if a == null or t == null:
		return cells
	for hex in Hex.within_range(t.pos, a.attack_range):
		if in_field(hex) and _can_hit(a, t, hex):
			cells.append(hex)
	return cells

## 盤上＋搭乗＋garrison の全駒から最大の unit id を返す。分裂で新駒を作るときの採番に使う。
func _max_unit_id() -> int:
	var m := 0
	for u in _units:
		if u.handle > m:
			m = u.handle
	for list in _passengers.values():
		for u in list:
			if u.handle > m:
				m = u.handle
	for b in _bases:
		for u in b.garrison:
			if u.handle > m:
				m = u.handle
	return m

## 分裂スキル（⑤スライムスプリット）の実行。発動者の隣接する空きマスへ複製を1体置く。
## 空きマスが無ければ null を返す（発動失敗）。呼ぶのは FormationResolver。詳細 → doc/gdd/skills.md
func spawn_unit(caster_id: int) -> Unit:
	var caster := unit_by_handle(caster_id)
	if caster == null:
		return null
	# 隣接する空きマス（盤内かつ駒が居ない）を探す
	var candidates: Array[Vector2i] = []
	for nb in Hex.neighbors(caster.pos):
		if in_field(nb) and unit_at(nb) == null:
			candidates.append(nb)
	if candidates.is_empty():
		return null
	# 先頭を選ぶ（Hex.neighbors は方向0から時計回りの固定順＝決定的）
	var spawn_hex := candidates[0]
	var new_id := _max_unit_id() + 1
	var spawned := Unit.new(new_id, caster.team, spawn_hex, caster.move,
		caster.troops, caster.unit_attack, caster.unit_defense, 1, caster.type_id)
	spawned.max_troops = caster.max_troops
	spawned.max_shield = caster.max_shield
	spawned.shield = caster.shield  # 兵数と同じく現在の損耗ごと写す
	spawned.skin_id = caster.skin_id
	spawned.move_type = caster.move_type
	spawned.atk_air = caster.atk_air
	spawned.pierce = caster.pierce
	spawned.min_range = caster.min_range
	spawned.attack_range = caster.attack_range
	spawned.move_after_attack = caster.move_after_attack
	spawned.can_capture = caster.can_capture
	spawned.capacity = caster.capacity
	add_unit(spawned)
	set_done(new_id)  # 生まれたターンは行動済み
	return spawned

## 表示用のユニットスナップショット（戦闘前）。撃破後も値が要るので UnitSnapshot に固める。attack と FormationResolver が撮る。
## statuses＝この時点で効いている状態補正エントリの一覧（戦闘レポートのバフ表示用）。
## pos は演出シーンが地面を組むのに要る（terrain＝性能IDだけでは平地/雪原の別＝スキンが決まらない）。
## troops_after は troops_before と同じ値で返す＝兵数が動く呼び手が上書きする。
func unit_snapshot(u: Unit) -> UnitSnapshot:
	var s := UnitSnapshot.new()
	s.handle = u.handle
	s.type_id = u.type_id
	s.skin_id = u.skin_id
	s.actor = u.actor
	s.team = u.team
	s.level = u.level
	s.troops_before = u.troops
	s.troops_after = u.troops
	s.max_troops = u.max_troops
	s.shield_before = u.shield
	s.shield_after = u.shield
	s.max_shield = u.max_shield
	s.terrain = terrain_at(u.pos)
	s.pos = u.pos
	s.statuses = StatusMod.applied(_status_mods, u)
	return s

## 撃破された駒を盤から除去し、撃破済みとして記録（勝利条件「ボス撃破」の判定材料）。
## 輸送が撃破された場合、搭乗中の駒も失われる（ネクタリス準拠）。
func _remove_unit(handle: int) -> void:
	_defeated[handle] = true
	var lost := unit_by_handle(handle)
	_mark_unit_id_defeated(lost)
	_count_loss(lost)
	for p in passengers(handle):
		_defeated[p.handle] = true  # 巻き添え（盤上には居ないのでリストから消すだけ）
		_mark_unit_id_defeated(p)
		_count_loss(p)
	_passengers.erase(handle)
	_take_off_board(handle)

## 失った駒を陣営ごとに数える。兵器は数えない（→ doc/gdd/rank.md）＝敵の兵器を壊しても撃破に乗らない。
func _count_loss(u: Unit) -> void:
	if u == null or u.is_emplacement():
		return
	_losses[u.team] = int(_losses.get(u.team, 0)) + 1

## 名指された駒（unit_id）の撃破を記録する。名前の無い駒は素通し。
func _mark_unit_id_defeated(u: Unit) -> void:
	if u != null and u.unit_id != "":
		_defeated_unit_ids[u.unit_id] = true

## 駒を盤上リストから外す（撃破記録は付けない。乗車・撃破処理の内部用）。
func _take_off_board(handle: int) -> void:
	for i in _units.size():
		if _units[i].handle == handle:
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

## 自軍の生き残り数＝盤上＋輸送の中＋拠点の中。失われた駒だけが数から落ちる。
## 勝敗（盤上0で判定）とは別の数え方＝評価ランクの生存が読む（詳細 → doc/gdd/rank.md）。
## 拠点の控えは出撃まで team が決まらないので帰属先（recruited_team）で見る。まだ解放されて
## いない中立の控えも自軍に数える＝取りに行かなくても損はせず、敵に取られたときだけ落ちる。
## 中立を敵側で数えることはしない（両陣営に重複して数えないため）＝敵の頭数はここで数えない。
## まだ発火していない自軍の増援も数える＝来ていないだけで失われてはいない（早く勝つほど
## 生存率が落ちる、を避ける）。発火済みの増援は盤上に居るので二重には数えない。
## 兵器は数えない（置いて壊させる駒で、移動0だから退避もできない）＝頭数を数える
## team_unit_count とは別物になったので、盤上のぶんもここで数え直す。
func ally_survivor_count() -> int:
	var n := 0
	for u in _units:
		if u.team == 0 and not u.is_emplacement():
			n += 1
	for list in _passengers.values():
		for u in list:
			if (u as Unit).team == 0 and not (u as Unit).is_emplacement():
				n += 1
	for b in _bases:
		for gu in b.garrison:
			var g := gu as Unit
			if g.is_emplacement():
				continue
			if g.recruited_team == 0 or g.is_unclaimed():
				n += 1
	for e in _events:
		if e.team != 0:
			continue
		for item in e.units:
			if item.unit != null and not item.unit.is_emplacement():
				n += 1
			for p in item.passengers:
				if not p.is_emplacement():
					n += 1
	return n

## team が失った駒の数（累積）。戦果票の撃破数＝敵陣営の損失（詳細 → doc/gdd/rank.md）。
func losses(team: int) -> int:
	return int(_losses.get(team, 0))

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
	return b.has_deployable_garrison()

## 拠点 b の周囲に、盤上へ出せる空きマスが1つでもあるか（＝盤上復帰の余地）。
## 盤上0の判定用なので味方輸送は考慮不要（盤上に味方が居ない＝味方輸送も盤上に無い）。
func _base_has_open_neighbor(b: Base) -> bool:
	for nb in Hex.neighbors(b.hex):
		if in_field(nb) and unit_at(nb) == null:
			return true
	return false

## 撃破済みの駒か。盤から消えた駒は unit_by_handle では引けないので記録を見る。
func is_defeated(handle: int) -> bool:
	return _defeated.has(handle)

## 名指しした駒（unit_id）が撃破済みか。ボス撃破・護衛対象の喪失が見る。詳細 → doc/gdd/map.md
func is_unit_id_defeated(unit_id: String) -> bool:
	return unit_id != "" and _defeated_unit_ids.has(unit_id)

## 駒を1体、戦闘を経ずに盤から除去する（撃破扱い＝ボス撃破の勝利条件にも効く）。
## 戦闘の結果ではない除去の入口＝デバッグメニューの「敵を殲滅」が使う。詳細 → doc/gdd/uiux.md
## 盤に居ない駒（既に撃破・搭乗中）を指したら false。
func remove_unit(handle: int) -> bool:
	if unit_by_handle(handle) == null:
		return false
	_remove_unit(handle)
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
func has_moved(handle: int) -> bool:
	return _moved.has(handle)

## このターンに攻撃済みか。
func has_attacked(handle: int) -> bool:
	return _attacked.has(handle)

## このターンの行動を終えたか（明示的に待機した／このターン動くか撃つかして、もう手が残っていない）。
## このターンまだ何もしていない駒は、瓦礫や味方に囲まれて行ける先が無くても終わりにしない
## ＝暗く落とさず、選択も陣形への参加もできる（そちらは is_stuck で見る）。
## 降車は「搭乗駒の行動」＝輸送自身が行動完了（待機・攻撃済み）でも、降ろせる駒が居る限り
## 選択可能にする（未行動の搭乗駒はいつでも降ろせる）。詳細 → doc/gdd/movement.md
func is_done(handle: int) -> bool:
	if _has_unloadable_passenger(handle):
		return false  # 「待機」済みでも降車のために選択できる
	if _done.has(handle):
		return true  # 「待機」で行動終了済み
	if not has_moved(handle) and not has_attacked(handle):
		return false  # このターンまだ何も使っていない＝手詰まりでも「終えた」ではない
	return is_stuck(handle)

## 打つ手が無いか（行ける先も撃てる相手も無い）。行動を使ったかどうかとは別＝ターン開始から
## 手詰まりの駒もありうる（瓦礫に囲まれる・味方で塞がれる・敵ZOCで出口が終端になる）。
## 手詰まりでも陣形スキルには参加できるので、盤の表示・選択可否はこれではなく is_done を見る。
func is_stuck(handle: int) -> bool:
	var can_atk := not has_attacked(handle) and not attack_targets(handle).is_empty()
	var can_mv := _can_act_move(handle) and reachable(handle).size() > 1  # 自分以外に行ける
	return not can_atk and not can_mv

## このターンの行動をまだ使っていないか（「待機」で終えておらず、攻撃もしていない）。
## is_done と違い「行ける先が無い／撃てる相手が居ない」を終了扱いにしない。移動してから
## 撃てるユニットスキルは、移動後この判定で発動可否を決める。詳細 → doc/gdd/skills.md
func has_action_left(handle: int) -> bool:
	return not _done.has(handle) and not has_attacked(handle)

## 降ろせる搭乗駒（このターン未行動）が居るか。
func _has_unloadable_passenger(handle: int) -> bool:
	for p in passengers(handle):
		if not has_moved(p.handle):
			return true
	return false

## 明示的に行動終了させる（コマンドメニューの「待機」）。再選択・再行動を止める。
func set_done(handle: int) -> void:
	_done[handle] = true

## 選択して操作できる状態か（現ターン・まだ行動が残っている）。
func can_select(handle: int) -> bool:
	return is_current_unit(unit_by_handle(handle)) and not is_done(handle)

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
	_tick_dots()           # 始まった陣営の駒に継続ダメージ（毒）を入れる（→ doc/gdd/skills.md）
	_increment_charges()   # 始まった陣営の駒のチャージ量を +1（→ doc/gdd/skills.md）
	_heal_garrisons()
	fire_due_events()  # 発生ターンが来た増援を盤へ出す（→ doc/gdd/map.md イベント）

## ターンが始まる陣営の「拠点に駐留中の駒」を満員へ回復（兵数のみ・Lvは据え置き）。
## 回復できるのは rest がその陣営を含む拠点だけ＝奪っても休めない拠点（rest:"enemy" の納骨堂など）は
## 出撃拠点にはなるが回復しない。閉じ込め駒（帰属先≠所有者）も回復しない。
## hexの上に立っている駒は回復しない（中に入るモデル）。
func _heal_garrisons() -> void:
	for b in _bases:
		if b.team != current_team:
			continue
		if not b.can_rest(current_team):
			continue  # この陣営が休めない拠点
		for u in b.garrison:
			if u.recruited_team == current_team or u.is_unclaimed():
				u.troops = u.max_troops

# --- 中断セーブ（動的差分の直列化）。バージョン枠・ファイルIOは infrastructure/save 側。詳細 → doc/tech/gamesystem.md ---

## 盤の動的差分を素データ（JSON化可能）に直列化する。ステージJSONから引き直せるもの
## （盤の広さ・地形・勝敗条件・ターン上限・部隊定義・増援の中身）は含めない＝復元は
## ステージJSONで盤を組んでから apply_save_diff で被せる。見た目・movement 表（静的コンフィグ）も
## 含めない（load_file と同じ流儀）。
func to_save_diff() -> Dictionary:
	var units_out: Array = []
	for u in _units:
		units_out.append(u.to_full_dict())
	var bases_out: Array = []
	for b in _bases:
		bases_out.append(b.to_save_diff())
	var pass_out := {}
	for tid in _passengers:
		var arr: Array = []
		for p in _passengers[tid]:
			arr.append(p.to_full_dict())
		pass_out[str(tid)] = arr
	return {
		"current_team": current_team, "turn_number": turn_number,
		"units": units_out,
		"bases": bases_out,
		"status_mods": _status_mods,
		"passengers": pass_out,
		"fired_events": _fired_events.keys(),
		"moved": _moved.keys(), "post_moved": _post_moved.keys(),
		"attacked": _attacked.keys(), "done": _done.keys(),
		"engaged": _engaged.keys(), "engaged_squads": _engaged_squads.keys(),
		"defeated": _defeated.keys(),
		"losses": _int_keyed_to_str(_losses),
		"defeated_unit_ids": _defeated_unit_ids.keys(),
		"fielded_actors": _fielded_actors.keys(),
		"spent": _int_keyed_to_str(_spent), "squad_of": _int_keyed_to_str(_squad_of),
		"charges": _charges_to_dict(),
	}

## ステージJSONで組み立てた盤に、中断セーブの動的差分を被せる。ユニットの性能は catalog
## （{id: UnitType}）から再構築する。呼び出し順は StageLoader.build → set_movement/set_sight_cost
## → ここ（盤に立てない駒の判定に移動コスト表が要る）。fire_due_events は呼ばない＝発火済みの
## イベントはセーブの fired_events で除かれる。ステージ定義がセーブ後に変わっていても
## 差分はそのまま適用する（→ doc/tech/gamesystem.md §ステージ更新の検出）。
func apply_save_diff(diff: Dictionary, catalog: Dictionary = {}) -> void:
	current_team = int(diff.get("current_team", 0))
	turn_number = int(diff.get("turn_number", 1))
	_apply_diff_events(diff)
	_apply_diff_units(diff, catalog)
	var fresh_bases := _apply_diff_bases(diff, catalog)
	var sm: Variant = diff.get("status_mods", [])
	_status_mods = sm if typeof(sm) == TYPE_ARRAY else []
	_moved = _ids_to_set(diff.get("moved", []))
	_post_moved = _ids_to_set(diff.get("post_moved", []))
	_attacked = _ids_to_set(diff.get("attacked", []))
	_done = _ids_to_set(diff.get("done", []))
	_engaged = _ids_to_set(diff.get("engaged", []))
	_engaged_squads = _ids_to_set(diff.get("engaged_squads", []))
	_defeated = _ids_to_set(diff.get("defeated", []))
	_losses = _str_keyed_to_int(diff.get("losses", {}))
	_defeated_unit_ids = _names_to_set(diff.get("defeated_unit_ids", []))
	_fielded_actors = _names_to_set(diff.get("fielded_actors", []))
	for b in fresh_bases:  # ステージ更新で足された拠点の控えは今この盤に出た＝投入記録を立て直す
		for gu in b.garrison:
			_mark_fielded(gu as Unit)
	_spent = _str_keyed_to_int(diff.get("spent", {}))
	_squad_of = _str_keyed_to_int(diff.get("squad_of", {}))
	_charges = _charges_from_dict(diff.get("charges", {}))
	_renumber_stage_units(fresh_bases)

## 増援・会話イベントはステージ定義を正本に、セーブの「発火済み（once で捨てた兄弟を含む）の id」
## を除いた残りを未発火とする＝ステージ更新で足したイベントも既存のセーブで発火する
## （増援の増減は盤に効く変更として届く）。
func _apply_diff_events(diff: Dictionary) -> void:
	_fired_events = _names_to_set(diff.get("fired_events", []))
	var kept: Array[StageEvent] = []
	for e in _events:
		if not _fired_events.has(e.id):
			kept.append(e)
	_events = kept

## 盤上の駒と搭乗をセーブの顔ぶれへ置き換える（ステージ組み立てで出た駒は捨てる＝駒はセーブが正本）。
## 盤に居られない駒（盤外・その移動タイプで進入できない地形）は盤へ出さず、近くへ寄せない
## （→ doc/tech/gamesystem.md §復元して居場所を失った駒）。落とした輸送の搭乗者も出さない。
func _apply_diff_units(diff: Dictionary, catalog: Dictionary) -> void:
	_units.clear()
	_passengers.clear()
	for ud in diff.get("units", []):
		if typeof(ud) != TYPE_DICTIONARY:
			continue
		var u := Unit.from_full_dict(ud, catalog.get(String(ud.get("type", ""))))
		if not in_field(u.pos) or not can_enter_terrain(u, u.pos):
			continue
		_units.append(u)
	for tid in _as_dict(diff.get("passengers", {})):
		if unit_by_handle(int(tid)) == null:
			continue  # 輸送ごと盤から落ちた＝搭乗者も出さない
		var arr: Array[Unit] = []
		for pd in diff["passengers"][tid]:
			if typeof(pd) == TYPE_DICTIONARY:
				arr.append(Unit.from_full_dict(pd, catalog.get(String(pd.get("type", "")))))
		_passengers[int(tid)] = arr

## 拠点は位置・種別・本来の帰属をステージ定義から、現在の帰属と駐留兵をセーブから（位置で突き合わせ）。
## セーブ側にあってステージから消えた拠点は駐留兵ごと出さない。ステージ更新で足された拠点は
## ステージ定義のまま出る。戻り値＝セーブに無かった（足された）拠点の一覧。
func _apply_diff_bases(diff: Dictionary, catalog: Dictionary) -> Array:
	var overlaid := {}
	for bd in diff.get("bases", []):
		if typeof(bd) != TYPE_DICTIONARY:
			continue
		var b := base_at(Vector2i(int(bd.get("q", 0)), int(bd.get("r", 0))))
		if b == null:
			continue  # 拠点が消えた＝この駐留兵は盤へ出さない
		b.team = int(bd.get("team", b.team))
		var g: Array[Unit] = []
		for gd in bd.get("garrison", []):
			if typeof(gd) == TYPE_DICTIONARY:
				g.append(Unit.from_full_dict(gd, catalog.get(String(gd.get("type", "")))))
		b.garrison = g
		overlaid[b.hex] = true
	var fresh: Array = []
	for b in _bases:
		if not overlaid.has(b.hex):
			fresh.append(b)
	return fresh

## ステージ組み立て由来で盤に残った駒（未発火イベントの駒・足された拠点の駐留兵）の id を、
## セーブの駒より上へ振り直す。ステージ更新で採番がずれてもセーブの駒と id が衝突しないため。
## セーブ由来の id は行動記録・チャージが参照しているので動かさない。
func _renumber_stage_units(fresh_bases: Array) -> void:
	var next_id := 1
	for u in _units:
		next_id = maxi(next_id, u.handle + 1)
	for tid in _passengers:
		for p in _passengers[tid]:
			next_id = maxi(next_id, (p as Unit).handle + 1)
	for b in _bases:
		if b in fresh_bases:
			continue
		for gu in b.garrison:
			next_id = maxi(next_id, (gu as Unit).handle + 1)
	for b in fresh_bases:
		for gu in b.garrison:
			(gu as Unit).handle = next_id
			next_id += 1
	for e in _events:
		for item in e.units:
			if item.unit != null:
				item.unit.handle = next_id
				next_id += 1
			for p in item.passengers:
				p.handle = next_id
				next_id += 1

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

## 文字列の配列 → { 名前: true } の集合 dict（actor の記録・未発火イベント id の復元）。
static func _names_to_set(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) == TYPE_ARRAY:
		for name in src:
			out[String(name)] = true
	return out

static func _as_dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

## _charges を JSON 化可能な dict に変換（キーを文字列化）。
## { handle(int): { skill_id: int } } → { "handle": { skill_id: int } }
func _charges_to_dict() -> Dictionary:
	var out := {}
	for uid in _charges:
		var inner: Dictionary = _charges[uid]
		if not inner.is_empty():
			out[str(uid)] = inner.duplicate()
	return out

## JSON 復元後の dict → _charges（文字列キーを int に戻す）。
static func _charges_from_dict(src: Variant) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for uid_str in src:
		var inner: Variant = src[uid_str]
		if typeof(inner) == TYPE_DICTIONARY:
			var restored := {}
			for rid in inner:
				restored[String(rid)] = int(inner[rid])
			out[int(uid_str)] = restored
	return out
