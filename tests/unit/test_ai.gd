extends GutTest
## domain/ai/trait_brain.gd の思考テスト（純ロジック・ツリー不要）。
## 特性ごとに「どの行が成立するか」を見る。仕様の正本は doc/gdd/ai.md（特性詳細）。
##
## 敵ユニットは必ず部隊(squad)に属する形で組む＝実データに部隊外の敵は無い。
## 距離そのもの（測れる／測れない・どのマスを数えるか）は test_ai_distance.gd の受け持ち。
##
## 盤は flat-top / odd-q。offset の「行」は axial の直線ではないので横方向は最短路が扇状に
## 広がり、敵1体のZOCでは迂回距離が伸びないことがある（同じ長さの別ルートが残る）。
## 回り込みの効きを見るテストは壁で抜け道を絞った盤で書く。

const PLAIN_WALL := { "ground": { "plain": 1, "wall": "x" } }

var _brain: TraitBrain

func before_each() -> void:
	_brain = TraitBrain.new()
	_brain.presets = AiCatalog.load_default()  # 特性の既定は ai.csv 由来の実データを使う

# --- 盤の組み立て ---

## 敵(team 1)の部隊を作って index を返す。overrides＝部隊ごとのパラメーター上書き。
func _squad(s: BattleState, ai: String, overrides := {}) -> int:
	var squad := { "ai": ai, "order": s.squads.size() + 1 }
	for k in overrides:
		squad[k] = overrides[k]
	s.squads.append(squad)
	return s.squads.size() - 1

## 地上の駒を1体作る（座標は offset で指定）。
func _u(id: int, team: int, col: int, row: int, move := 3, troops := 8,
		atk := 20, def := 10) -> Unit:
	var u := Unit.new(id, team, Hex.offset_to_axial(col, row), move, troops, atk, def)
	u.move_type = "ground"
	return u

## 敵AIの駒（team 1）を部隊に入れて盤へ置く。
func _ai(s: BattleState, squad_index: int, id: int, col: int, row: int, move := 3) -> Unit:
	var u := _u(id, 1, col, row, move)
	s.add_unit(u)
	s.assign_squad(u.id, squad_index)
	return u

## プレイヤーの駒（team 0）を盤へ置く。
func _pc(s: BattleState, id: int, col: int, row: int, def := 10) -> Unit:
	var u := _u(id, 0, col, row, 3, 8, 20, def)
	s.add_unit(u)
	return u

## 損耗させる（満員兵数は変えない＝損耗は割合で見る）。
func _hurt(u: Unit, troops: int) -> Unit:
	u.troops = troops
	return u

func _skin(u: Unit, skin: String) -> Unit:
	u.skin_id = skin
	return u

## 対象1体に掛かった補正を1本積む。
func _mod(s: BattleState, u: Unit, kind: String) -> void:
	s.add_status_mod({
		"scope": "unit", "unit_id": u.id, "op": "add", "target": "both",
		"value": 10.0 if kind == StatusMod.KIND_BUFF else -10.0,
		"kind": kind, "owner_team": 1, "remaining": 3,
	})

func _col(hex: Vector2i) -> int:
	return Hex.axial_to_offset(hex).x

func _row(hex: Vector2i) -> int:
	return Hex.axial_to_offset(hex).y

# --- charge（突撃） ---

func test_charge_attacks_the_nearest_enemy_not_the_weakest() -> void:
	# 攻撃対象は盤上距離が最小の敵。旧実装の既定は兵数最小だったのでここが変わる。
	# 移動0＝最大間合いの行を素通りさせて攻撃の行だけを見る。どちらも距離2以上＝反撃されない。
	var s := BattleState.new(9, 9)
	s.current_team = 1
	var si := _squad(s, "charge")
	var archer := _ai(s, si, 10, 4, 4, 0)
	archer.attack_range = 3
	var near := _pc(s, 1, 4, 2)             # 盤上距離2・満員
	_hurt(_pc(s, 2, 4, 1), 2)               # 盤上距離3・兵数2（旧実装ならこちらを狙った）
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, near.id, "兵数ではなく盤上距離が最小の敵")

func test_charge_backs_off_to_the_range_edge_before_shooting() -> void:
	# #3 間接攻撃できる駒は、撃てる敵から最大間合いを取ってから撃つ。
	# 隣接のまま撃つと近接扱い＝反撃を受ける（doc/gdd/combat.md 用語）。
	var s := BattleState.new(9, 3)
	s.current_team = 1
	var si := _squad(s, "charge")
	var archer := _ai(s, si, 10, 4, 1)
	archer.attack_range = 2
	var e := _pc(s, 1, 3, 1)                # 隣接＝このままだと反撃を受ける
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "撃つ前に下がる")
	assert_eq(Hex.distance(a.to, e.pos), 2, "射程上限まで間合いを取る")
	assert_true(s.move_unit(a.unit_id, a.to), "前提: 下がる移動は妥当")
	var b := _brain.next_action(s, 1)
	assert_eq(b.kind, AiAction.Kind.ATTACK, "移動後に同じ手番で撃つ")
	assert_eq(b.target_id, e.id)

func test_charge_stops_at_the_range_edge_while_closing_in() -> void:
	# #3 の標的は「移動範囲のどこかから撃てる敵」＝射程の外から詰めるときも外縁で止まる。
	# 移動4・距離5＝隣接まで届くが、届くからといって踏み込まない。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "charge")
	var archer := _ai(s, si, 10, 0, 1, 4)
	archer.attack_range = 2
	var e := _pc(s, 1, 5, 1)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(Hex.distance(a.to, e.pos), 2, "射程上限のマスで止まる")

func test_charge_does_not_shuffle_when_already_at_the_range_edge() -> void:
	# 最大間合いは同値なら現在地優先＝すでに射程上限にいる駒は動かずに撃つ。
	var s := BattleState.new(9, 3)
	s.current_team = 1
	var si := _squad(s, "charge")
	var archer := _ai(s, si, 10, 4, 1)
	archer.attack_range = 2
	var e := _pc(s, 1, 2, 1)                # 盤上距離2＝すでに最大間合い
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "横のマスへ動き直さない")
	assert_eq(a.target_id, e.id)

func test_charge_melee_piece_attacks_without_repositioning() -> void:
	# 近接しかできない駒は撃てるマスがどれも距離1＝最大間合いが現在地と同じ＝この行では動かない。
	var s := BattleState.new(9, 3)
	s.current_team = 1
	var e := _pc(s, 1, 3, 1)
	_ai(s, _squad(s, "charge"), 10, 4, 1)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, e.id)

func test_charge_shoots_the_enemy_that_cannot_retaliate() -> void:
	# #4 隣に敵がいても、距離2で撃てる相手がいればそちらを撃つ（間接＝反撃なし）。
	# 移動0＝下がれない駒にして、攻撃の行の対象選びだけを見る。
	var s := BattleState.new(9, 9)
	s.current_team = 1
	var si := _squad(s, "charge")
	var archer := _ai(s, si, 10, 4, 4, 0)
	archer.attack_range = 2
	_pc(s, 1, 4, 3)                         # 隣接＝殴れば反撃される
	var far := _pc(s, 2, 4, 2)              # 盤上距離2＝反撃されない
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, far.id, "反撃されない敵を優先する")

func test_charge_melees_when_it_cannot_avoid_retaliation() -> void:
	# 反撃されない敵が1体もいなければ、これまで通り盤上距離が最小の敵を殴る。
	var s := BattleState.new(9, 9)
	s.current_team = 1
	var si := _squad(s, "charge")
	_ai(s, si, 10, 4, 4, 0)                 # 近接・移動0＝下がる先も遠い相手も無い
	var e := _pc(s, 1, 4, 3)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, e.id)

func test_charge_captures_before_attacking() -> void:
	# #1 占領兵で移動範囲に自陣営以外の拠点があれば、殴れる敵がいても取りに行く。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var si := _squad(s, "charge")
	var u := _ai(s, si, 10, 3, 3)
	u.can_capture = true
	_pc(s, 1, 3, 2)                          # 隣接＝殴れる
	var base_hex := Hex.offset_to_axial(3, 5)
	s.add_base(Base.new(base_hex, 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "占領は攻撃より上の行")
	assert_eq(a.to, base_hex, "拠点hexへ進入＝占領")

func test_charge_ignores_its_own_base() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var si := _squad(s, "charge")
	var u := _ai(s, si, 10, 3, 3)
	u.can_capture = true
	var e := _pc(s, 1, 3, 2)
	s.add_base(Base.new(Hex.offset_to_axial(3, 5), 1))  # 自陣営の拠点
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "自陣営の拠点は占領の対象外")
	assert_eq(a.target_id, e.id)

func test_charge_advances_by_move_distance() -> void:
	# #4 移動距離が測れる敵へ最大前進＝開けた盤では移動力ぶん詰める。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "charge")
	var u := _ai(s, si, 10, 0, 1)
	var e := _pc(s, 1, 10, 1)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(Hex.distance(a.to, e.pos), Hex.distance(u.pos, e.pos) - 3, "移動力ぶん縮む")

func test_charge_uses_terrain_distance_when_pieces_block_the_way() -> void:
	# #5 標的が駒に囲まれて移動距離が測れないとき、地形距離で詰めておく（駒はいずれ動く）。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var si := _squad(s, "charge")
	var u := _ai(s, si, 10, 1, 2)
	var e := _pc(s, 1, 6, 2)
	var id := 20
	for nb in Hex.neighbors(e.pos):
		var o := Hex.axial_to_offset(nb)
		var blocker := _ai(s, si, id, o.x, o.y)
		s.set_done(blocker.id)  # もう動かない駒＝行動順で飛ばされる
		id += 1
	assert_eq(s.move_distance(10, s.attack_cells(10, 1)), BattleState.UNREACHABLE,
		"前提: 攻撃可能なマスが全部埋まっている＝移動距離は測れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "地形距離で詰める")
	assert_lt(Hex.distance(a.to, e.pos), Hex.distance(u.pos, e.pos), "標的へ近づく")

func test_charge_closes_in_a_straight_line_when_walled_off() -> void:
	# #6 どの道のりも測れないとき＝壁の向こうの敵へ、壁際まで詰めて止まる。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	s.set_movement(PLAIN_WALL)
	for row in 5:
		s.set_terrain(Hex.offset_to_axial(4, row), "wall")
	var si := _squad(s, "charge")
	var u := _ai(s, si, 10, 1, 2)
	_pc(s, 1, 7, 2)
	assert_eq(s.move_distance(10, s.attack_cells(10, 1)), BattleState.UNREACHABLE, "前提: 道が無い")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(_col(a.to), 3, "壁の手前まで詰める")
	assert_eq(u.pos, Hex.offset_to_axial(1, 2), "返すのは1手＝盤はまだ動かない")

func test_charge_skips_the_advance_rows_after_spending_its_move() -> void:
	# 移動を使い切った駒は、移動を伴う行（占領・前進）を飛ばす＝残る行が無ければ待機。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "charge")
	_ai(s, si, 10, 0, 1)
	_pc(s, 1, 10, 1)
	var a := _brain.next_action(s, 1)
	assert_true(s.move_unit(a.unit_id, a.to), "前提: 1手目は前進")
	assert_null(_brain.next_action(s, 1), "移動を使い切ったので待機")

func test_charge_waits_without_enemies() -> void:
	var s := BattleState.new(8, 8)
	s.current_team = 1
	_ai(s, _squad(s, "charge"), 10, 3, 3)
	assert_null(_brain.next_action(s, 1), "標的にできる敵がいなければ末尾の行も成立しない")
	assert_true(s.is_engaged(10), "行動開始条件は常時＝起きてはいる")

func test_charge_reaches_the_enemy_over_several_actions() -> void:
	# 1手ずつ返す＝寄って殴るまでを呼び出し側が回す。
	var s := BattleState.new(12, 3)
	var si := _squad(s, "charge")
	_ai(s, si, 10, 0, 1, 4)
	var enemy_pos := Hex.offset_to_axial(5, 1)
	var e := _pc(s, 1, 5, 1)
	e.unit_attack = 1  # 反撃は微弱＝AIは落ちない
	_run_turn(s, 1)
	var ai := s.unit_by_id(10)
	assert_not_null(ai, "AIユニットは生存")
	assert_eq(Hex.distance(ai.pos, enemy_pos), 1, "敵に隣接するまで前進する")
	assert_lt(s.unit_by_id(1).troops, 8, "前進後に攻撃して兵数を削る")

## 行動が尽きるまで AI を実際に適用する（安全のため上限付き）。
func _run_turn(s: BattleState, team: int) -> void:
	s.current_team = team
	var guard := 0
	while guard < 100:
		guard += 1
		var a := _brain.next_action(s, team)
		if a == null:
			return
		match a.kind:
			AiAction.Kind.MOVE:
				assert_true(s.move_unit(a.unit_id, a.to), "AIの移動は妥当であるべき")
			AiAction.Kind.ATTACK:
				assert_false(s.attack(a.unit_id, a.target_id).is_empty(), "AIの攻撃は妥当であるべき")
			AiAction.Kind.SKILL:
				assert_false(s.resolve_formation(a.option, a.to).is_empty(), "AIのスキルは妥当であるべき")
			AiAction.Kind.DEPLOY:
				assert_true(s.deploy(a.base_hex, a.garrison_index, a.to), "AIの出撃は妥当であるべき")
	fail_test("AIのターンが終了しなかった（無限ループの疑い）")

# --- ambush（待ち伏せ） ---

func test_ambush_sleeps_until_an_enemy_enters_its_sight() -> void:
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "ambush")  # 既定 sight 3
	_ai(s, si, 10, 1, 1)
	var e := _pc(s, 1, 8, 1)
	assert_null(_brain.next_action(s, 1), "視線距離が sight の外なら動かない")
	assert_false(s.is_engaged(10))
	e.pos = Hex.offset_to_axial(4, 1)
	assert_not_null(_brain.next_action(s, 1), "sight に入れば動き出す")
	assert_true(s.is_engaged(10))

func test_ambush_keeps_going_after_the_enemy_backs_off() -> void:
	# 行動開始条件は一度成立したら以後判定しない＝離れても止まらない。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "ambush")
	_ai(s, si, 10, 1, 1)
	var e := _pc(s, 1, 4, 1)
	assert_not_null(_brain.next_action(s, 1), "前提: sight 内で起きる")
	e.pos = Hex.offset_to_axial(11, 1)
	assert_not_null(_brain.next_action(s, 1), "離れても止まらない")

func test_ambush_wakes_when_a_squadmate_is_engaged() -> void:
	# 一斉警戒＝部隊の誰かが行動開始済みなら自分も起きる。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "ambush")
	var near := _ai(s, si, 10, 1, 1)
	var far := _ai(s, si, 11, 0, 0)  # 敵まで視線距離4＝自分では気づかない
	_pc(s, 1, 4, 1)
	s.mark_engaged(near.id)
	s.set_done(near.id)  # 先に動き終えた扱い
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.unit_id, far.id, "部隊ごと起きる")

func test_ambush_wakes_when_shot_from_outside_its_sight() -> void:
	# 攻撃を受けた駒は特性と行動開始条件によらず、その時点で行動開始する。
	var s := BattleState.new(12, 3)
	var si := _squad(s, "ambush")
	_ai(s, si, 10, 5, 1)
	var shooter := _pc(s, 1, 1, 1)
	shooter.attack_range = 4  # 視線3の外から届く
	s.current_team = 0
	assert_false(s.attack(shooter.id, 10).is_empty(), "前提: sight の外から撃てる")
	s.current_team = 1
	assert_true(s.is_engaged(10), "撃たれたら起きる")
	assert_not_null(_brain.next_action(s, 1))

func test_ambush_stays_asleep_with_an_enemy_in_attack_range() -> void:
	# 旧実装にあった自衛（撃たれていないが攻撃射程内に敵が入ったら起きる）は廃止した。
	var s := BattleState.new(8, 8)
	s.current_team = 1
	var si := _squad(s, "ambush", { "sight": "-" })  # 索敵では起きない待ち伏せ
	_ai(s, si, 10, 3, 3)
	_pc(s, 1, 3, 2)  # 隣接＝射程内
	assert_null(_brain.next_action(s, 1), "射程内に来ただけでは起きない")
	assert_false(s.is_engaged(10))

func test_ambush_acts_like_charge_once_awake() -> void:
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "ambush")
	_ai(s, si, 10, 1, 1)
	var e := _pc(s, 1, 3, 1)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "起きたあとは突撃と同じ行")
	assert_lt(Hex.distance(a.to, e.pos), Hex.distance(Hex.offset_to_axial(1, 1), e.pos))

func test_detection_radius_only_for_a_sleeping_ambusher() -> void:
	var s := BattleState.new(12, 3)
	var si := _squad(s, "ambush")
	var g := _ai(s, si, 10, 1, 1)
	var c := _ai(s, _squad(s, "charge"), 11, 2, 1)
	assert_eq(_brain.detection_radius(s, g), 3, "寝ている見張り＝sight 半径")
	assert_eq(_brain.detection_radius(s, c), 0, "常時の特性に検知域は無い")
	s.mark_engaged(g.id)
	assert_eq(_brain.detection_radius(s, g), 0, "起動済みは0")

func test_detection_radius_covers_weak_and_skips_swarm() -> void:
	# weak も行動開始条件が視線で決まる＝寝ている間は検知域を描く（sight `*` は上限なしの予算）。
	# swarm は sight を持つが行動開始条件は常時＝寝ている状態が無いので描かない。
	var s := BattleState.new(12, 3)
	var w := _ai(s, _squad(s, "weak"), 10, 1, 1)
	var sw := _ai(s, _squad(s, "swarm"), 11, 2, 1)
	assert_eq(_brain.detection_radius(s, w), TraitBrain.SIGHT_UNLIMITED, "寝ている弱者狙い＝上限なしの予算")
	assert_eq(_brain.detection_radius(s, sw), 0, "群れは常時起動＝検知域なし")
	assert_eq(_brain.detection_radius(s, _ai(s, _squad(s, "weak", { "sight": 4 }), 12, 3, 1)), 4,
		"部隊の上書きがそのまま半径になる")
	s.mark_engaged(w.id)
	assert_eq(_brain.detection_radius(s, w), 0, "獲物を見つけたあとは0")

# --- raid（拠点攻略） ---

func test_raid_heads_for_the_base_instead_of_the_enemy() -> void:
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "raid")
	_ai(s, si, 10, 5, 1)
	_pc(s, 1, 2, 1)  # 敵は西に3（射程外）
	s.add_base(Base.new(Hex.offset_to_axial(9, 1), 0))  # 拠点は東に4
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_gt(_col(a.to), 5, "敵ではなく拠点へ向かう")

func test_raid_waits_when_no_base_is_left() -> void:
	# 敵を追わない＝拠点を全部取られたあとは動かなくなる（突撃との差）。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "raid")
	_ai(s, si, 10, 5, 1)
	_pc(s, 1, 2, 1)
	s.add_base(Base.new(Hex.offset_to_axial(9, 1), 1))  # 自陣営の拠点は向かう先ではない
	assert_null(_brain.next_action(s, 1), "向かう拠点が盤上に無ければ待機")
	assert_true(s.is_engaged(10), "行動開始条件は常時")

func test_raid_ignores_an_enemy_that_is_not_in_the_way() -> void:
	# 経路上でない敵は殴らない＝目の前の敵を無視して素通りしていくのが raid の圧。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "raid")
	_ai(s, si, 10, 5, 1)
	_pc(s, 1, 5, 0)  # 隣接だが拠点への道は塞いでいない
	s.add_base(Base.new(Hex.offset_to_axial(9, 1), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "殴らずに拠点へ歩く")
	assert_gt(_col(a.to), 5)

## 壁で通路を1本だけ残した盤（開いている row だけが道）。
func _corridor(s: BattleState, open_rows: Array) -> void:
	s.set_movement(PLAIN_WALL)
	for col in s.cols:
		for row in s.rows:
			if not (row in open_rows):
				s.set_terrain(Hex.offset_to_axial(col, row), "wall")

func test_raid_attacks_an_enemy_blocking_the_corridor() -> void:
	# 体で道を塞いでいる＝どければ移動距離が測れるようになる。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	_corridor(s, [2])
	var si := _squad(s, "raid")
	_ai(s, si, 10, 4, 2)
	var e := _pc(s, 1, 5, 2)
	s.add_base(Base.new(Hex.offset_to_axial(9, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "通路を塞ぐ敵は殴る")
	assert_eq(a.target_id, e.id)

func test_raid_does_not_back_off_from_the_enemy_in_its_way() -> void:
	# raid は最大間合いの行を持たない＝間合いを取る移動は拠点から遠ざかるため。
	# 間接攻撃できる駒も、塞がれた位置からそのまま殴る。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	_corridor(s, [2])
	var si := _squad(s, "raid")
	var archer := _ai(s, si, 10, 4, 2)
	archer.attack_range = 2
	var e := _pc(s, 1, 5, 2)
	s.add_base(Base.new(Hex.offset_to_axial(9, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "下がらずに殴る")
	assert_eq(a.target_id, e.id)

func test_raid_attacks_when_two_enemies_block_together() -> void:
	# 幅2の通路を2体で塞ぐ形。1体ずつ試すとどちらを外しても道が開かず、
	# 両方とも経路上ではないと読まれてしまう＝まとめてどけて測る。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	_corridor(s, [2, 3])
	var si := _squad(s, "raid")
	_ai(s, si, 10, 4, 3)
	_pc(s, 1, 5, 2)
	_pc(s, 2, 5, 3)
	s.add_base(Base.new(Hex.offset_to_axial(9, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "2体で塞がれていても殴る")
	assert_eq(a.target_id, 1, "一番前＝拠点への地形距離が最小の駒を殴る")

func test_raid_attacks_an_enemy_that_pins_it_with_zoc() -> void:
	# 体では塞いでいないが、ZOCで通路が消えている＝迂回距離が測れなくなっている。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	_corridor(s, [2, 3])
	var si := _squad(s, "raid")
	_ai(s, si, 10, 4, 3)
	var e := _pc(s, 1, 5, 3)
	s.add_base(Base.new(Hex.offset_to_axial(9, 2), 0))
	assert_lt(s.min_cost_in(s.move_cost_field(10, s.unit_by_id(10).pos),
		[Hex.offset_to_axial(9, 2)]), BattleState.UNREACHABLE, "体では塞がれていない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "ZOCで足を止めている敵は殴る")
	assert_eq(a.target_id, e.id)

func test_raid_takes_the_nearest_base_including_neutral() -> void:
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "raid")
	_ai(s, si, 10, 5, 2)
	s.add_base(Base.new(Hex.offset_to_axial(7, 2), Base.NEUTRAL))  # 中立も向かう先
	s.add_base(Base.new(Hex.offset_to_axial(0, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_gt(_col(a.to), 5, "近いほうの拠点（中立）へ向かう")

# --- weak（弱者狙い） ---

func test_weak_sleeps_until_prey_is_in_sight() -> void:
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "weak", { "sight": 2 })
	_ai(s, si, 10, 1, 1)
	var e := _pc(s, 1, 6, 1)
	assert_null(_brain.next_action(s, 1), "sight の外の獲物では起きない")
	e.pos = Hex.offset_to_axial(3, 1)
	assert_not_null(_brain.next_action(s, 1), "獲物が視線に入れば起きる")

func test_weak_walks_past_the_hard_front_line() -> void:
	# 獲物の上限は盤全体の敵から計算する。射程内の敵から計算し直すと、硬い前衛しか射程に
	# 入っていないターンにその前衛が獲物になり、弱者狙いが硬い相手と殴り合いはじめる。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "weak")
	var u := _ai(s, si, 10, 4, 2)
	_pc(s, 1, 4, 1, 80)               # 硬い前衛（防御80）＝隣接
	var soft := _pc(s, 2, 7, 2, 10)   # 柔らかい後衛（防御10）
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "硬い前衛とは殴り合わない")
	assert_lt(Hex.distance(a.to, soft.pos), Hex.distance(u.pos, soft.pos), "獲物へ寄る")

func test_weak_attacks_the_prey_it_can_reduce_most() -> void:
	# #4 攻撃射程内に獲物 → 攻撃後の残兵が最小となる獲物を攻撃する。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var si := _squad(s, "weak")
	var u := _ai(s, si, 10, 4, 2)
	u.attack_range = 2
	_pc(s, 1, 4, 1, 10)                        # 隣接・満員
	var hurt := _hurt(_pc(s, 2, 4, 0, 10), 1)  # 距離2・残り1
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, hurt.id, "攻撃後の残兵が最小になる相手")

func test_weak_finishes_a_hard_enemy_it_can_kill_in_one_hit() -> void:
	# #5 獲物でなくても、一撃で倒せる相手なら殴る。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var si := _squad(s, "weak")
	var u := _ai(s, si, 10, 4, 2)
	var tough := _hurt(_pc(s, 1, 4, 1, 80), 1)  # 硬いが残り1
	_pc(s, 2, 8, 2, 10)                         # 獲物は遠い
	assert_true(Combat.casualties(s, u, tough, true) >= tough.troops, "前提: 一撃で倒せる")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, tough.id, "獲物でなくても倒しきれるなら殴る")

func test_weak_backs_off_before_shooting_the_prey() -> void:
	# #3 間接攻撃できる駒は、狙う獲物から最大間合いを取ってから撃つ。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var si := _squad(s, "weak")
	var archer := _ai(s, si, 10, 4, 2)
	archer.attack_range = 2
	var prey := _pc(s, 1, 4, 1, 10)             # 隣接・満員＝一撃では倒せない
	assert_lt(Combat.casualties(s, archer, prey, true), prey.troops, "前提: 一撃では倒せない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "撃つ前に下がる")
	assert_eq(Hex.distance(a.to, prey.pos), 2, "射程上限まで間合いを取る")
	assert_true(s.move_unit(a.unit_id, a.to), "前提: 下がる移動は妥当")
	var b := _brain.next_action(s, 1)
	assert_eq(b.kind, AiAction.Kind.ATTACK, "移動後に同じ手番で撃つ")
	assert_eq(b.target_id, prey.id)

func test_weak_does_not_back_off_from_a_finishing_blow() -> void:
	# #3 は「いまの位置から一撃で倒せる敵がいない」ときだけ成立＝倒しきれる相手からは下がらない。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "weak")
	var archer := _ai(s, si, 10, 4, 2)
	archer.attack_range = 2
	var tough := _hurt(_pc(s, 1, 4, 1, 80), 1)  # 硬いが残り1＝一撃で倒せる
	_pc(s, 2, 10, 2, 10)                        # 獲物は遠い＝硬い相手は獲物にならない
	assert_true(Combat.casualties(s, archer, tough, true) >= tough.troops, "前提: 一撃で倒せる")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "倒しきれる相手からは下がらない")
	assert_eq(a.target_id, tough.id)

func test_weak_finishes_the_enemy_that_cannot_retaliate() -> void:
	# #5 どちらも倒せるなら反撃を受けない相手から倒す。移動0＝下がる余地を消して行だけを見る。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "weak")
	var archer := _ai(s, si, 10, 4, 2, 0)
	archer.attack_range = 2
	_hurt(_pc(s, 1, 4, 1, 80), 1)               # 隣接＝殴れば反撃される
	var far := _hurt(_pc(s, 2, 4, 0, 80), 1)    # 盤上距離2＝反撃されない
	_pc(s, 3, 10, 2, 10)                        # 獲物は遠い＝硬い2体は獲物にならない
	assert_true(Combat.casualties(s, archer, far, false) >= far.troops, "前提: 距離2でも倒せる")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, far.id, "反撃されない敵から倒す")

func test_weak_flanks_around_the_zoc_band() -> void:
	# #6 回り込み＝敵ZOCを避けて獲物へ近づく。壁で抜け道を絞らないと同じ長さの別ルートが
	# 残って迂回距離が伸びない（flat-top / odd-q は横に扇状へ広がる）。
	var s := BattleState.new(9, 7)
	s.current_team = 1
	s.set_movement(PLAIN_WALL)
	for row in [0, 2, 3, 4, 5]:
		s.set_terrain(Hex.offset_to_axial(4, row), "wall")  # 抜け道は row 1 と row 6
	var si := _squad(s, "weak")
	var u := _ai(s, si, 10, 1, 0)
	var blocker := _pc(s, 1, 3, 1, 80)  # 近い抜け道の脇＝ZOCで蓋をする硬い駒
	var prey := _pc(s, 2, 7, 0, 10)
	assert_lt(s.detour_distance_to(10, prey.id), BattleState.UNREACHABLE,
		"前提: 遠い抜け道があるので迂回距離は測れる")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_gt(Hex.distance(a.to, blocker.pos), 1, "ZOCの帯に触れない")
	assert_gt(_row(a.to), _row(u.pos), "遠い抜け道の側へ回る")

func test_weak_stops_advancing_when_the_prey_leaves_sight() -> void:
	# 行動開始は一度きりの判定、#6〜#9 の sight は毎ターンの判定＝視線から消えたら前進だけ止まる。
	var s := BattleState.new(12, 3)
	s.current_team = 1
	var si := _squad(s, "weak", { "sight": 2 })
	_ai(s, si, 10, 1, 1)
	var prey := _pc(s, 1, 3, 1)
	assert_not_null(_brain.next_action(s, 1), "前提: sight 内なら前進する")
	prey.pos = Hex.offset_to_axial(9, 1)
	assert_null(_brain.next_action(s, 1), "獲物が視線から消えたら前進を止める")
	assert_true(s.is_engaged(10), "行動開始そのものは戻らない")

# --- swarm（群れ） ---

func test_swarm_bites_a_wounded_enemy_alone() -> void:
	# #2 だけ包囲を条件にしない＝手負いには単独でも噛みつく。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var si := _squad(s, "swarm")
	_ai(s, si, 10, 4, 2)
	var wounded := _hurt(_pc(s, 1, 4, 1), 3)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, wounded.id)

func test_swarm_backs_off_before_shooting_the_wounded() -> void:
	# #1 間接攻撃できる駒は手負いから最大間合いを取ってから撃つ（囲むのは近接の駒に任せる）。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var si := _squad(s, "swarm")
	var archer := _ai(s, si, 10, 4, 2)
	archer.attack_range = 2
	var wounded := _hurt(_pc(s, 1, 4, 1), 3)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "撃つ前に下がる")
	assert_eq(Hex.distance(a.to, wounded.pos), 2, "射程上限まで間合いを取る")
	assert_true(s.move_unit(a.unit_id, a.to), "前提: 下がる移動は妥当")
	var b := _brain.next_action(s, 1)
	assert_eq(b.kind, AiAction.Kind.ATTACK, "移動後に同じ手番で撃つ")
	assert_eq(b.target_id, wounded.id)

func test_swarm_leaves_a_healthy_enemy_and_goes_for_the_wounded() -> void:
	# 無傷の敵には頭数が揃うまで手を出さない。手負いは盤全体から1体選ぶ。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "swarm")
	var u := _ai(s, si, 10, 4, 2)
	_pc(s, 1, 4, 1)                            # 無傷・隣接
	var wounded := _hurt(_pc(s, 2, 9, 2), 2)   # 手負い・遠い
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "単独では無傷の敵に手を出さない")
	assert_lt(Hex.distance(a.to, wounded.pos), Hex.distance(u.pos, wounded.pos), "手負いへ寄る")

func test_swarm_attacks_a_healthy_enemy_once_the_numbers_are_there() -> void:
	# #5 包囲可能な敵は殴る（行動ユニット自身も数に入る）。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "swarm")
	_ai(s, si, 10, 4, 2)
	_ai(s, si, 11, 4, 0)                  # 同じ敵に隣接する2体目＝包囲可能
	var healthy := _pc(s, 1, 4, 1)
	_hurt(_pc(s, 2, 9, 2), 2)             # 手負いは遠い＝#2 は成立しない
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "頭数が揃えば無傷の敵にも手を出す")
	assert_eq(a.target_id, healthy.id)

func test_swarm_does_not_take_bases() -> void:
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "swarm")
	var u := _ai(s, si, 10, 4, 2)
	u.can_capture = true
	var base_hex := Hex.offset_to_axial(4, 4)  # 移動範囲内の敵拠点
	s.add_base(Base.new(base_hex, 0))
	_pc(s, 1, 9, 2)
	var a := _brain.next_action(s, 1)
	assert_ne(a.to, base_hex, "占領兵を混ぜても拠点へは向かわない")

func test_swarm_switches_from_the_skill_to_attacking_when_stacked() -> void:
	# #2 は #3 の裏返し＝効き切った相手に重ねる価値はないので殴りに切り替わる。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "swarm")  # 既定 stack 1
	_skin(_ai(s, si, 10, 4, 2), "ghost")
	_ai(s, si, 11, 4, 4)                       # 今ターン隣へ寄れる2体目＝包囲可能（先に動くのはゴースト）
	var healthy := _pc(s, 1, 4, 1)
	_hurt(_pc(s, 2, 9, 2), 2)                  # 手負いは遠い＝#1 は成立しない
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.SKILL, "前提: まだ刺さっていなければ掛ける")
	_mod(s, healthy, StatusMod.KIND_DEBUFF)
	a = _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "stack に達した相手は殴る")
	assert_eq(a.target_id, healthy.id)

# --- stack 条件（全特性のパラメーター） ---

func test_stack_caps_buffs_on_the_same_ally() -> void:
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "charge", { "stack": 1 })
	var pixie := _skin(_ai(s, si, 10, 6, 2), "pixie")
	var ally := _ai(s, si, 11, 5, 2)
	_pc(s, 1, 8, 2)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.SKILL, "前提: まだ掛かっていなければ放つ")
	_mod(s, ally, StatusMod.KIND_BUFF)
	_mod(s, pixie, StatusMod.KIND_BUFF)  # 自分にも掛けられるので両方埋める
	a = _brain.next_action(s, 1)
	assert_ne(a.kind, AiAction.Kind.SKILL, "強化は上限＝stack 本未満のときだけ掛ける")

func test_stack_does_not_count_buffs_cast_on_the_whole_team() -> void:
	# 数えるのは対象1体に掛かった補正だけ（陣営全体のホーリーアリアは数えない）。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "charge", { "stack": 1 })
	_skin(_ai(s, si, 10, 6, 2), "pixie")
	_ai(s, si, 11, 5, 2)
	_pc(s, 1, 8, 2)
	s.add_status_mod({
		"scope": "team", "team": 1, "op": "mul", "target": "both", "value": 1.3,
		"kind": StatusMod.KIND_BUFF, "owner_team": 1, "remaining": 1,
	})
	assert_eq(_brain.next_action(s, 1).kind, AiAction.Kind.SKILL, "陣営全体の補正は本数に入らない")

func test_stack_caps_debuffs_on_the_same_enemy() -> void:
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "charge", { "stack": 1 })
	_skin(_ai(s, si, 10, 6, 2), "ghost")
	var victim := _pc(s, 1, 6, 1)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.SKILL, "前提: 1本も刺さっていなければ掛ける")
	_mod(s, victim, StatusMod.KIND_DEBUFF)
	a = _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "上限に達したら殴りに回る")

func test_stack_is_a_floor_for_cleansing() -> void:
	# 解除だけ向きが逆＝何本刺さったら動くかの閾値になる。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "charge", { "stack": 2 })
	_skin(_ai(s, si, 10, 6, 2), "cleric")
	var ally := _ai(s, si, 11, 5, 2)
	_pc(s, 1, 8, 2)
	_mod(s, ally, StatusMod.KIND_DEBUFF)
	assert_ne(_brain.next_action(s, 1).kind, AiAction.Kind.SKILL, "1本では動かない（下限2本）")
	_mod(s, ally, StatusMod.KIND_DEBUFF)
	assert_eq(_brain.next_action(s, 1).kind, AiAction.Kind.SKILL, "2本刺さったら落としに動く")

# --- 行動順（部隊は order 順・部隊の中は前線から） ---

func test_squads_act_in_order_not_in_registration_order() -> void:
	# 部隊は order（1から昇順）の小さいほうから動く。登録順でも敵への近さでもない。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var late := _squad(s, "charge", { "order": 2 })  # 先に登録するが order は後
	var early := _squad(s, "charge", { "order": 1 })
	_ai(s, late, 10, 6, 2)  # 敵に近い＝距離で決めるならこちらが先になる
	var far := _ai(s, early, 11, 8, 2)
	_pc(s, 1, 1, 2)
	assert_eq(_brain.next_action(s, 1).unit_id, far.id, "order 1 の部隊から動く")

func test_squad_members_move_from_the_front_line() -> void:
	# 部隊の中は盤上距離で最寄りの敵に近い駒から。後ろの駒が先に動くと前の駒に塞がれるため。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "charge")
	var back := _ai(s, si, 10, 9, 2)
	var front := _ai(s, si, 11, 7, 2)
	_pc(s, 1, 1, 2)
	assert_eq(_brain.next_action(s, 1).unit_id, front.id, "最寄りの敵に近い駒から動く")
	# 駒が動けば距離も変わる＝毎ターン計算し直すので前後が入れ替われば順番も入れ替わる
	back.pos = Hex.offset_to_axial(4, 2)
	assert_eq(_brain.next_action(s, 1).unit_id, back.id, "前に出た駒が先頭になる")

func test_the_base_deploys_after_the_pieces_of_its_squad() -> void:
	# 出撃を行うのは、その部隊の盤上の駒を動かし終えたあと。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "charge")
	var u := _ai(s, si, 10, 6, 2)
	_base_with_garrison(s, si, 4, 2)
	_pc(s, 1, 11, 2)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "盤上の駒が先")
	assert_eq(a.unit_id, u.id)
	s.set_done(u.id)
	assert_eq(_brain.next_action(s, 1).kind, AiAction.Kind.DEPLOY, "駒を捌いてから出撃")

# --- 拠点出撃（行動開始条件を拠点hex基準で見る） ---

## 控えを count 体持つ team1 の拠点を置く（控えの id は 20 から連番＝garrison の記述順）。
func _base_with_garrison(s: BattleState, squad_index: int, col: int, row: int, count := 1) -> Base:
	var b := Base.new(Hex.offset_to_axial(col, row), 1)
	b.squad_index = squad_index
	for i in count:
		b.garrison.append(_u(20 + i, 1, col, row))
	s.add_base(b)
	return b

## 次の1手を出撃として実行し、その AiAction を返す（出す手が無ければ null）。
func _run_deploy(s: BattleState) -> AiAction:
	var a := _brain.next_action(s, 1)
	if a == null:
		return null
	assert_eq(a.kind, AiAction.Kind.DEPLOY, "この盤で出るのは出撃だけ")
	assert_true(s.deploy(a.base_hex, a.garrison_index, a.to), "AIの出撃は妥当であるべき")
	return a

func test_base_deploys_at_once_when_its_squad_is_charge() -> void:
	var s := BattleState.new(9, 5)
	s.current_team = 1
	_base_with_garrison(s, _squad(s, "charge"), 4, 2)
	_pc(s, 1, 8, 2)
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.DEPLOY, "常時の特性は初手から出す")

func test_ambush_base_waits_until_an_enemy_is_in_sight() -> void:
	var s := BattleState.new(12, 5)
	s.current_team = 1
	_base_with_garrison(s, _squad(s, "ambush"), 4, 2)
	var e := _pc(s, 1, 11, 2)
	assert_null(_brain.next_action(s, 1), "拠点hexから sight の外なら出さない")
	e.pos = Hex.offset_to_axial(6, 2)
	assert_eq(_brain.next_action(s, 1).kind, AiAction.Kind.DEPLOY, "索敵に入れば出す")

func test_ambush_base_stays_awake_after_the_enemy_backs_off() -> void:
	# 拠点の行動開始条件も一度成立したら以後は判定しない＝眠り直さない。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	_base_with_garrison(s, _squad(s, "ambush"), 4, 2)
	var e := _pc(s, 1, 6, 2)
	assert_eq(_brain.next_action(s, 1).kind, AiAction.Kind.DEPLOY, "前提: 索敵に入って起きる")
	e.pos = Hex.offset_to_axial(11, 2)
	assert_eq(_brain.next_action(s, 1).kind, AiAction.Kind.DEPLOY, "離れても止まらない")

func test_base_wakes_when_a_squadmate_is_engaged() -> void:
	# 一斉警戒は部隊の中で向きを問わない＝部隊の駒が起きれば拠点も起きる。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "ambush")  # 既定 sight 3
	var scout := _ai(s, si, 10, 8, 2)
	_base_with_garrison(s, si, 4, 2)
	_pc(s, 1, 11, 2)  # 拠点hexからは視線距離7＝拠点だけでは気づかない
	assert_eq(_brain.next_action(s, 1).unit_id, scout.id, "前提: 索敵に入った駒が先に起きる")
	s.set_done(scout.id)
	assert_eq(_brain.next_action(s, 1).kind, AiAction.Kind.DEPLOY, "部隊の駒が起きたら拠点も起きる")

func test_a_piece_wakes_when_its_base_is_engaged() -> void:
	# 逆向きも同じ。出撃は「敵を見つけたから出した」動きなので、出てきた駒が自分の sight では
	# 敵を捉えられずに拠点の真横で止まる、という壊れ方をさせない。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var si := _squad(s, "ambush")
	var far := _ai(s, si, 10, 0, 0)  # 敵まで視線距離6＝自分では気づかない
	_base_with_garrison(s, si, 4, 2)
	_pc(s, 1, 6, 2)
	assert_not_null(_run_deploy(s), "前提: 拠点は索敵に反応して出撃する")
	var a := _brain.next_action(s, 1)
	assert_not_null(a, "拠点が起きたら同じ部隊の駒も起きる")
	assert_eq(a.unit_id, far.id)

func test_base_ignores_another_squads_alarm() -> void:
	# 一斉警戒はその部隊の中で閉じる＝盤上の別部隊が行動開始しても拠点は起きない。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	var other := _squad(s, "charge")
	var runner := _ai(s, other, 10, 8, 2)
	_base_with_garrison(s, _squad(s, "ambush"), 4, 2)
	_pc(s, 1, 11, 2)  # 拠点hexからは sight の外
	s.mark_engaged(runner.id)
	s.set_done(runner.id)  # 先に動き終えた扱い
	assert_null(_brain.next_action(s, 1), "別部隊の起動では拠点は起きない")

func test_base_deploys_until_the_open_neighbors_are_full() -> void:
	# 行動開始したあとは、空き隣接が埋まるまで出す。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var b := _base_with_garrison(s, _squad(s, "charge"), 4, 2, 8)
	var deployed := 0
	for _i in 20:
		if _run_deploy(s) == null:
			break
		deployed += 1
	assert_eq(deployed, 6, "隣接6マスが埋まるまで出す")
	assert_eq(b.garrison.size(), 2, "空きが尽きたら控えは残る")

func test_base_deploys_until_the_garrison_runs_out() -> void:
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var b := _base_with_garrison(s, _squad(s, "charge"), 4, 2, 2)
	assert_not_null(_run_deploy(s))
	assert_not_null(_run_deploy(s))
	assert_null(_brain.next_action(s, 1), "控えが尽きたら出さない")
	assert_eq(b.garrison.size(), 0)

func test_base_deploys_in_the_order_the_garrison_is_written() -> void:
	# 控えは全員が拠点hexにいて座標で並ばない＝出す順は garrison の記述順。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	_base_with_garrison(s, _squad(s, "charge"), 4, 2, 2)
	assert_eq(_run_deploy(s).garrison_index, 0)
	assert_not_null(s.unit_by_id(20), "記述順の先頭が盤に出る")
	assert_null(s.unit_by_id(21), "2体目はまだ控え")

func test_base_deploys_toward_the_nearest_enemy() -> void:
	# 出す先は、盤上距離が最小の敵に最も近い空きマス。
	var s := BattleState.new(12, 5)
	s.current_team = 1
	_base_with_garrison(s, _squad(s, "charge"), 4, 2)
	_pc(s, 1, 8, 4)   # 拠点から盤上距離4＝こちらが最寄り
	_pc(s, 2, 11, 0)  # 盤上距離7
	var a := _run_deploy(s)
	assert_eq(_col(a.to), 5, "最寄りの敵に最も近い隣接へ出す")
	assert_eq(_row(a.to), 2)

func test_base_deploys_to_the_youngest_cell_without_enemies() -> void:
	# 盤上に敵がいなければ col → row の若いマス。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	_base_with_garrison(s, _squad(s, "charge"), 4, 2)
	var a := _run_deploy(s)
	assert_eq(_col(a.to), 3)
	assert_eq(_row(a.to), 1)

func test_base_does_not_deploy_a_garrison_locked_to_the_other_side() -> void:
	# 出せるのは native ルールを満たす駒だけ（奪われた拠点の駒は閉じ込め）。doc/gdd/map.md 出撃
	var s := BattleState.new(9, 5)
	s.current_team = 1
	var b := _base_with_garrison(s, _squad(s, "charge"), 4, 2)
	(b.garrison[0] as Unit).set_native_team(0)
	_pc(s, 1, 8, 2)
	assert_null(_brain.next_action(s, 1), "帰属が自軍側の控えは敵の拠点から出せない")

func test_base_without_ai_never_deploys() -> void:
	# ai を書かない拠点は出撃しない（opt-in）。控えを抱えたまま湧かせたくない拠点を表す。
	var s := BattleState.new(9, 5)
	s.current_team = 1
	_base_with_garrison(s, -1, 4, 2)
	_pc(s, 1, 8, 2)
	assert_null(_brain.next_action(s, 1))
