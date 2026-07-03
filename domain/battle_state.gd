extends RefCounted
class_name BattleState
## 戦闘全体の状態 ＝ 中断セーブの本体（唯一の真実）。
## Godot ノード非依存（extends RefCounted）。見た目の状態はここに含めない。
## 詳細 → doc/tech/architecture.md, doc/tech/gamesystem.md

var cols: int  ## 矩形フィールドの幅（offset col 数）
var rows: int  ## 矩形フィールドの高さ（offset row 数）

var current_team: int = 0  ## 現在の手番の陣営
var turn_number: int = 1   ## ターン番号（両陣営が1巡で+1）

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
## 要素は dict。現在対応: { "type": "defeat_unit", "unit_id": <int> } ＝ ボス撃破（id はステージJSONで明示採番）
var victory_conditions: Array = []

## 敵チームのAIプリセットラベル（ステージJSONの "ai"。空＝既定の charge）。詳細 → doc/gdd/ai.md
## 部隊(squad)単位の割り当ては未実装＝当面は敵チーム全体に1ラベル。
var enemy_ai: String = ""
var _defeated := {}  # unit_id -> true（撃破で盤から消えた駒の記録。ボス撃破判定に使う）

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

# --- 拠点（占領・出撃・回復）。詳細 → doc/gdd/map.md ---

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
	return _terrain.get(hex, Terrain.DEFAULT_ID)

## hex に地形を設定する。
func set_terrain(hex: Vector2i, terrain_id: String) -> void:
	_terrain[hex] = terrain_id

## 移動コスト表を設定する（move_type -> {地形名: コスト}）。
func set_movement(table: Dictionary) -> void:
	_movement = table

## hex が矩形フィールド内か。
func in_field(hex: Vector2i) -> bool:
	var off := Hex.axial_to_offset(hex)
	return off.x >= 0 and off.x < cols and off.y >= 0 and off.y < rows

## unit_id が「残り移動力」で到達できるヘックス（起点を含む）。盤外・他ユニットは進入不可、地形はコスト。
## 敵ZOC（敵に隣接するマス）に入ると停止＝その先へは進めない（飛行含む全移動タイプ）。
func reachable(unit_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in _reach_map(unit_id):
		result.append(h)
	return result

## reachable の {ヘックス: 到達コスト} 版（残り移動力で計算）。移動コスト消費に使う。
func _reach_map(unit_id: int) -> Dictionary:
	var u := unit_by_id(unit_id)
	if u == null:
		return {}
	var budget := maxi(u.move - int(_spent.get(unit_id, 0)), 0)
	return Hex.flood_reach_cost_map(u.pos, budget, _enter_cost.bind(u), _in_enemy_zoc.bind(u))

## u が hex に進入するコスト。盤外・占有は進入不可（Movement.IMPASSABLE）。それ以外は地形コスト。
func _enter_cost(hex: Vector2i, u: Unit) -> int:
	if not in_field(hex) or unit_at(hex) != null:
		return Movement.IMPASSABLE
	return Movement.cost(_movement, u.move_type, terrain_at(hex))

## hex が u から見た敵ZOC内か（敵ユニットに隣接しているか）。ZOCに入ると移動が止まる。
func _in_enemy_zoc(hex: Vector2i, u: Unit) -> bool:
	for nb in Hex.neighbors(hex):
		var occ := unit_at(nb)
		if occ != null and occ.team != u.team:
			return true
	return false

## unit_id を to へ動かせるか（空きマスかつ残り移動範囲内）。地形のみの判定で手番は見ない。
func can_move(unit_id: int, to: Vector2i) -> bool:
	if unit_at(to) != null:
		return false
	var u := unit_by_id(unit_id)
	if u == null or to == u.pos:
		return false
	return _reach_map(unit_id).has(to)

## 妥当なら移動を適用して true。手番違い・移動権なし・不正先なら false。移動コストを予算から消費。
func move_unit(unit_id: int, to: Vector2i) -> bool:
	if not _can_act_move(unit_id):
		return false
	var rm := _reach_map(unit_id)
	var u := unit_by_id(unit_id)
	if unit_at(to) != null or to == u.pos or not rm.has(to):
		return false
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

## いま移動できるか（手番・移動権・残り予算）。
## 攻撃前: 通常移動を未使用なら可。攻撃後: 再移動可ユニットが再移動を未使用なら可。
func _can_act_move(unit_id: int) -> bool:
	var u := unit_by_id(unit_id)
	if not is_current_unit(u):
		return false
	if int(_spent.get(unit_id, 0)) >= u.move:
		return false  # 予算切れ
	if has_attacked(unit_id):
		return u.move_after_attack and not _post_moved.has(unit_id)
	return not _moved.has(unit_id)

## いま移動できるか（公開）。盤の移動範囲表示などに使う。
func can_still_move(unit_id: int) -> bool:
	return _can_act_move(unit_id)

# --- 出撃（ネクタリス方式・占領済み拠点から1歩で出す） ---

## base_hex の拠点から出撃できる空きhex（拠点に隣接・盤内・空き）。出撃先候補の表示に使う。
func deploy_cells(base_hex: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var b := base_at(base_hex)
	if b == null or b.team != current_team or b.garrison.is_empty():
		return cells
	for nb in Hex.neighbors(base_hex):
		if in_field(nb) and unit_at(nb) == null:
			cells.append(nb)
	return cells

## いま出撃させられるか（自軍拠点・控えあり・出せる空きあり）。
func can_deploy(base_hex: Vector2i) -> bool:
	return not deploy_cells(base_hex).is_empty()

## 拠点の garrison[index] を隣接空き to_hex へ出撃させる。出撃は1歩＝そのターンは行動完了。
## 成否を返す。手番違い・非占領・索引外・隣接でない・占有マスなら false。
func deploy(base_hex: Vector2i, garrison_index: int, to_hex: Vector2i) -> bool:
	var b := base_at(base_hex)
	if b == null or b.team != current_team:
		return false
	if garrison_index < 0 or garrison_index >= b.garrison.size():
		return false
	if not in_field(to_hex) or unit_at(to_hex) != null:
		return false
	if Hex.distance(base_hex, to_hex) != 1:
		return false
	var u: Unit = b.garrison[garrison_index]
	b.garrison.remove_at(garrison_index)
	u.team = current_team
	u.pos = to_hex
	_units.append(u)
	# 出撃した駒はそのターン行動完了（1歩のみ＝移動も再移動も攻撃もこれ以上しない）。
	_moved[u.id] = true
	_post_moved[u.id] = true
	_attacked[u.id] = true
	_spent[u.id] = u.move
	return true

# --- 攻撃 ---

## attacker が target を攻撃できるか（現手番・未攻撃・射程内の敵）。
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
	return Hex.distance(from_hex, t.pos) <= a.attack_range  # 近接=1, 間接=射程内

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
	var melee := a.attack_range <= 1  # 近接なら反撃あり、間接なら反撃なし
	# 反撃は「近接」かつ「防御側が攻撃側を攻撃できる」ときだけ成立。
	# 例: 対空0の地上ユニットが飛行に殴られても反撃できない（→被反撃なし・経験+0）。
	var can_retaliate := melee and t.attack_against(a) > 0
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

## 表示用のユニットスナップショット（戦闘前）。撃破後も値が要るので dict に固める。
func _unit_snapshot(u: Unit) -> Dictionary:
	return {
		"id": u.id, "type_id": u.type_id, "skin_id": u.skin_id, "team": u.team, "level": u.level,
		"troops_before": u.troops, "max": u.max_troops, "terrain": terrain_at(u.pos),
	}

## 撃破された駒を盤から除去し、撃破済みとして記録（勝利条件「ボス撃破」の判定材料）。
func _remove_unit(unit_id: int) -> void:
	_defeated[unit_id] = true
	for i in _units.size():
		if _units[i].id == unit_id:
			_units.remove_at(i)
			return

# --- 勝敗（自軍＝team 0 視点。拠点占領勝利・ターン制限は未実装） ---

enum { ONGOING, PLAYER_WIN, PLAYER_LOSS }

func team_unit_count(team: int) -> int:
	var n := 0
	for u in _units:
		if u.team == team:
			n += 1
	return n

## 決着結果。敗北を優先（自軍全滅／自軍本拠地の喪失）。相討ち全滅も負け。
## 勝利は 殲滅（常に有効）＋ victory_conditions のいずれか（OR）。
func outcome() -> int:
	if team_unit_count(0) == 0:
		return PLAYER_LOSS
	if _own_hq_lost():
		return PLAYER_LOSS  # 味方本拠地を奪われたら敗北（hq を置いたステージだけ効く）
	if team_unit_count(1) == 0:
		return PLAYER_WIN
	for c in victory_conditions:
		if _victory_met(c):
			return PLAYER_WIN
	return ONGOING

## 自軍 native の本拠地（hq）が敵の手に落ちているか。hq が無いステージでは常に false。
func _own_hq_lost() -> bool:
	for b in _bases:
		if b.is_hq() and b.native_team == 0 and b.team != 0:
			return true
	return false

## 勝利条件1件の判定。未知の type は満たさない扱い（前方互換）。
func _victory_met(c: Dictionary) -> bool:
	match String(c.get("type", "")):
		"defeat_unit":  # ボス撃破＝指定IDの駒が撃破済み
			return _defeated.has(int(c.get("unit_id", -1)))
		"capture_hq":   # 本拠地占領＝敵 native の hq をすべて自軍が保持（hq が無ければ不成立）
			return _enemy_hq_all_captured()
	return false

## 敵 native の本拠地（hq）がすべて自軍所属になっているか。該当 hq が1つも無ければ false（空勝ち防止）。
func _enemy_hq_all_captured() -> bool:
	var found := false
	for b in _bases:
		if b.is_hq() and b.native_team == 1:
			found = true
			if b.team != 0:
				return false
	return found

func is_over() -> bool:
	return outcome() != ONGOING

# --- 手番 ---

## この陣営/ユニットが現在の手番か。
func is_current_unit(u: Unit) -> bool:
	return u != null and u.team == current_team

## このターンに（攻撃前の）移動を使ったか。
func has_moved(unit_id: int) -> bool:
	return _moved.has(unit_id)

## このターンに攻撃済みか。
func has_attacked(unit_id: int) -> bool:
	return _attacked.has(unit_id)

## このターンの行動を使い切ったか（もう移動も攻撃もできない／明示的に待機した）。
func is_done(unit_id: int) -> bool:
	if _done.has(unit_id):
		return true  # 「待機」で行動終了済み
	var can_atk := not has_attacked(unit_id) and not attack_targets(unit_id).is_empty()
	var can_mv := _can_act_move(unit_id) and reachable(unit_id).size() > 1  # 自分以外に行ける
	return not can_atk and not can_mv

## 明示的に行動終了させる（コマンドメニューの「待機」）。再選択・再行動を止める。
func set_done(unit_id: int) -> void:
	_done[unit_id] = true

## 選択して操作できる状態か（現手番・まだ行動が残っている）。
func can_select(unit_id: int) -> bool:
	return is_current_unit(unit_by_id(unit_id)) and not is_done(unit_id)

## 手番を次の陣営へ。行動済みフラグを一掃し、0 に戻ったらターン+1。
## 手番開始時に、自軍拠点に乗っている自軍ユニットを兵数 max まで回復（休憩）。
func end_turn() -> void:
	_moved.clear()
	_post_moved.clear()
	_attacked.clear()
	_done.clear()
	_spent.clear()
	current_team = 1 - current_team
	if current_team == 0:
		turn_number += 1
	_heal_on_bases()

## 手番が始まる陣営のユニットのうち、自軍所属の拠点hexに乗っているものを満員へ回復（兵数のみ）。
func _heal_on_bases() -> void:
	for u in _units:
		if u.team != current_team:
			continue
		var b := base_at(u.pos)
		if b != null and b.team == u.team:
			u.troops = u.max_troops
