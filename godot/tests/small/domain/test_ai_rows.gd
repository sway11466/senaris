extends GutTest
## domain/ai の行ごとの成立を補うテスト（純ロジック・ツリー不要）。仕様の正本は doc/gdd/ai.md。
## test_ai.gd が各特性の主な行を見るのに対し、ここは下段の行（見込前進・直線寄せ）・対象の選び方・
## パラメーターの解決・退き先の絞り方を見る。
##
## 盤は flat-top / odd-q（座標指定は offset）。敵ユニットは必ず部隊(squad)に属する形で組む。

const PLAIN_WALL := { "foot": { "plain": 1, "wall": "x" } }

var _brain: TraitBrain

func before_each() -> void:
	_brain = TraitBrain.new()
	_brain.presets = AiCatalog.load_default()  # 特性の既定は ai.csv 由来の実データを使う

# --- 盤の組み立て ---

func _state(cols: int, rows: int) -> BattleState:
	var s := BattleState.new(cols, rows)
	s.current_team = 1
	return s

## 敵(team 1)の部隊を作って index を返す。overrides＝部隊ごとのパラメーター上書き。
func _squad(s: BattleState, ai: String, overrides := {}) -> int:
	var squad := { "ai": ai, "order": s.squads.size() + 1 }
	for k in overrides:
		squad[k] = overrides[k]
	s.squads.append(squad)
	return s.squads.size() - 1

## 地上の駒を1体作る（座標は offset で指定）。
func _u(id: int, team: int, col: int, row: int, move := 3, def := 10) -> Unit:
	var u := Unit.new(id, team, Hex.offset_to_axial(col, row), move, 8, 20, def)
	u.move_type = "foot"
	return u

## 敵AIの駒（team 1）を部隊に入れて盤へ置く。
func _ai(s: BattleState, squad_index: int, id: int, col: int, row: int, move := 3) -> Unit:
	var u := _u(id, 1, col, row, move)
	s.add_unit(u)
	s.assign_squad(u.handle, squad_index)
	return u

## プレイヤーの駒（team 0）を盤へ置く。
func _pc(s: BattleState, id: int, col: int, row: int, def := 10) -> Unit:
	var u := _u(id, 0, col, row, 3, def)
	s.add_unit(u)
	return u

## 飛行の駒（team 0）。対空攻撃力を持つ駒だけが触れる相手。
func _air(s: BattleState, id: int, col: int, row: int, def := 10) -> Unit:
	var u := _u(id, 0, col, row, 3, def)
	u.move_type = "flight"
	s.add_unit(u)
	return u

## 損耗させる（満員兵数は変えない＝損耗は割合で見る）。
func _hurt(u: Unit, troops: int) -> Unit:
	u.troops = troops
	return u

func _skin(u: Unit, skin: String) -> Unit:
	u.skin_id = skin
	return u

## 対象1体に掛かった弱体を1本積む。
func _debuff(s: BattleState, u: Unit) -> void:
	s.add_status_mod({
		"scope": "unit", "handle": u.handle, "op": "add", "target": "both",
		"value": -10.0, "kind": StatusMod.KIND_DEBUFF, "owner_team": 1, "remaining": 3,
	})

## 壁で通路を残した盤（開いている row だけが道）。
func _corridor(s: BattleState, open_rows: Array) -> void:
	s.set_movement(PLAIN_WALL)
	for col in s.cols:
		for row in s.rows:
			if not (row in open_rows):
				s.set_terrain(Hex.offset_to_axial(col, row), "wall")

## col 列を上から下まで壁にする（どの道のりも測れなくする）。
func _wall_column(s: BattleState, col: int) -> void:
	s.set_movement(PLAIN_WALL)
	for row in s.rows:
		s.set_terrain(Hex.offset_to_axial(col, row), "wall")

## target の隣接マスを、もう動かない同じ部隊の駒で埋める（移動距離を測れなくする）。
func _ring_of_done_mates(s: BattleState, squad_index: int, target: Unit, first_id := 20) -> void:
	var id := first_id
	for nb in Hex.neighbors(target.pos):
		if not s.in_field(nb):
			continue
		var o := Hex.axial_to_offset(nb)
		s.set_done(_ai(s, squad_index, id, o.x, o.y).handle)
		id += 1

## 控えを1体持つ team1 の拠点を置く（控えの id は 20）。
func _base_with_garrison(s: BattleState, squad_index: int, col: int, row: int) -> Base:
	var b := Base.new(Hex.offset_to_axial(col, row), 1)
	b.squad_index = squad_index
	b.garrison.append(_u(20, 1, col, row))
	s.add_base(b)
	return b

func _hex(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(col, row)

func _col(hex: Vector2i) -> int:
	return Hex.axial_to_offset(hex).x

## 移動距離（行動ユニットから拠点hexまで）。
func _move_distance_to(s: BattleState, id: int, hex: Vector2i) -> int:
	return AiDistance.min_cost_in(AiDistance.move_cost_field(s, id, s.unit_by_handle(id).pos), [hex])

# --- スキル対象の選び方（near / weak / damaged） ---

## ピクシー（味方に掛ける強化・射程は自分＋隣接）と、その隣の味方2体。敵は遠くに1体。
## 隣の味方は col が若い＝座標の同値割りだけならこちらが選ばれる位置に置く。
func _pixie_and_mates(trait_id: String) -> Dictionary:
	var s := _state(12, 5)
	var si := _squad(s, trait_id)
	var pixie := _skin(_ai(s, si, 10, 6, 2), "pixie")  # 敵に最も近い＝先に動く
	var young := _ai(s, si, 11, 5, 1)
	var other := _ai(s, si, 12, 5, 2)
	var enemy := _pc(s, 1, 11, 2)
	return { "s": s, "pixie": pixie, "young": young, "other": other, "enemy": enemy }

func test_near_skill_target_is_the_closest_by_board_distance() -> void:
	# charge #2 盤上距離が最小の対象にスキル。自分（距離0）は隣の味方（距離1）より近い。
	var d := _pixie_and_mates("charge")
	var s: BattleState = d.s
	var pixie: Unit = d.pixie
	assert_eq(Hex.distance(pixie.pos, (d.young as Unit).pos), 1, "前提: 若い味方は隣接")
	var a := _brain.next_action(s, 1)
	assert_eq(a.handle, pixie.handle, "前提: ピクシーが先に動く")
	assert_eq(a.kind, AiAction.Kind.SKILL)
	assert_eq(a.to, pixie.pos, "座標の若い隣の味方ではなく、盤上距離0の自分に掛ける")

func test_weak_skill_target_is_the_lowest_defense() -> void:
	# predator #2 防御力が最小の対象にスキル。距離や座標の若さでは選ばない。
	var d := _pixie_and_mates("predator")
	var s: BattleState = d.s
	(d.pixie as Unit).unit_defense = 30
	(d.young as Unit).unit_defense = 30
	var soft: Unit = d.other
	soft.unit_defense = 10
	var a := _brain.next_action(s, 1)
	assert_eq(a.handle, (d.pixie as Unit).handle, "前提: ピクシーが先に動く（獲物が見えて起きている）")
	assert_eq(a.kind, AiAction.Kind.SKILL)
	assert_eq(a.to, soft.pos, "防御力が最小の味方に掛ける")

func test_damaged_skill_target_is_the_most_worn() -> void:
	# swarm #5 損耗が最大の対象にスキル。味方に掛ける強化なので包囲可能は課さない。
	var d := _pixie_and_mates("swarm")
	var s: BattleState = d.s
	var worn := _hurt(d.other, 6)  # 損耗25%
	var a := _brain.next_action(s, 1)
	assert_eq(a.handle, (d.pixie as Unit).handle, "前提: ピクシーが先に動く")
	assert_eq(a.kind, AiAction.Kind.SKILL)
	assert_eq(a.to, worn.pos, "損耗が最大の味方に掛ける")

# --- charge（突撃） ---

func test_charge_backs_off_toward_the_flier_before_the_nearer_ground() -> void:
	# #3 空敵を優先し、その中で盤上距離が最小のその敵へ最大間合い。近い地上の敵から間合いを取るのではなく、
	# 飛行を撃てるマスへ動き、同じ手番で飛行を撃つ。
	var s := _state(12, 5)
	var si := _squad(s, "charge")
	var archer := _ai(s, si, 10, 4, 2)
	archer.attack_range = 2
	archer.atk_air = 40  # 対地20 ≦ 対空40 ＝ 対空得意
	var ground := _pc(s, 1, 3, 2)  # 隣接
	var flier := _air(s, 2, 7, 2)
	assert_lt(Hex.distance(archer.pos, ground.pos), Hex.distance(archer.pos, flier.pos), "前提: 地上の敵のほうが近い")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(Hex.distance(a.to, flier.pos), 2, "空敵への射程上限まで間合いを取る")
	assert_true(s.move_unit(a.handle, a.to), "前提: この移動は妥当")
	var b := _brain.next_action(s, 1)
	assert_eq(b.kind, AiAction.Kind.ATTACK, "移動後に同じ手番で撃つ")
	assert_eq(b.target_id, flier.handle)

func test_charge_captures_the_nearest_of_several_bases() -> void:
	# #1 移動範囲に拠点が複数あれば盤上距離が最小の拠点へ。座標の若さより距離が先。
	var s := _state(12, 5)
	var si := _squad(s, "charge")
	var u := _ai(s, si, 10, 4, 2)
	u.can_capture = true
	var near := _hex(6, 2)
	var far := _hex(1, 2)  # col が若い
	s.add_base(Base.new(near, 0))
	s.add_base(Base.new(far, Base.NEUTRAL))
	assert_lt(Hex.distance(u.pos, near), Hex.distance(u.pos, far), "前提: 東の拠点のほうが近い")
	assert_true(far in s.reachable(u.handle), "前提: 遠い拠点も移動範囲にある")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(a.to, near, "盤上距離が最小の拠点へ")

# --- raid（拠点攻略） ---

func test_raid_closes_in_by_terrain_distance_when_pieces_block_the_way() -> void:
	# #12 通路が味方の駒で塞がれて移動距離が測れないとき、地形距離で拠点へ詰めておく（駒はいずれ動く）。
	var s := _state(12, 5)
	_corridor(s, [2])
	var si := _squad(s, "raid")
	_ai(s, si, 10, 2, 2)
	s.set_done(_ai(s, si, 11, 5, 2).handle)  # 通路を塞ぐ味方（もう動かない）
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	assert_eq(_move_distance_to(s, 10, base_hex), BattleState.UNREACHABLE, "前提: 移動距離は測れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(a.to, _hex(4, 2), "塞いでいる駒の手前まで詰める")

func test_raid_closes_in_a_straight_line_when_walled_off() -> void:
	# #13 どの道のりも測れないとき、盤上距離が最小の拠点へ直線寄せ＝壁際まで詰める。
	var s := _state(12, 5)
	_wall_column(s, 6)
	var si := _squad(s, "raid")
	_ai(s, si, 10, 2, 2)
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	assert_eq(_move_distance_to(s, 10, base_hex), BattleState.UNREACHABLE, "前提: 道が無い")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(_col(a.to), 5, "壁の手前まで詰める")

func test_raid_does_not_shift_to_shoot_after_it_has_fired() -> void:
	# #3 は「まだ撃っておらず」。ヒット&アウェイ持ちが撃ったあとは撃てる位置を探さない
	# （もう撃てないので、ずれても意味が無い）。
	var s := _state(12, 5)
	_corridor(s, [2])
	var si := _squad(s, "raid")
	var gun := _ai(s, si, 10, 4, 2)
	gun.min_range = 2
	gun.attack_range = 3
	gun.move_after_attack = true
	_pc(s, 1, 5, 2)                 # 通路を塞ぐ敵＝隣接で撃てない
	var behind := _pc(s, 2, 2, 2)   # 西の敵＝いまの位置から撃てる
	s.add_base(Base.new(_hex(9, 2), 0))
	var first := _brain.next_action(s, 1)
	assert_eq(first.kind, AiAction.Kind.MOVE, "前提: 撃つ前なら塞ぐ敵を撃てるマスへずれる")
	assert_not_null(s.attack(gun.handle, behind.handle), "前提: いまの位置から西の敵を撃てる")
	assert_true(s.can_still_move(gun.handle), "前提: ヒット&アウェイ＝撃ったあとも動ける")
	var b := _brain.next_action(s, 1)
	assert_true(b == null or not (b.kind == AiAction.Kind.MOVE and b.to == first.to),
		"撃ったあとは撃てる位置へずれない")

func test_raid_hit_and_away_does_not_attack_twice() -> void:
	# 攻撃済みの駒は攻撃の行が見る標的が空になる。ヒット&アウェイ持ちは撃ったあとも行を見直すが、
	# そこで同じ敵を殴る手は返さない（成立しない攻撃を返し続けないため）。
	var s := _state(12, 5)
	_corridor(s, [2, 3])
	var si := _squad(s, "raid")
	var u := _ai(s, si, 10, 4, 3)
	u.move_after_attack = true
	var e := _pc(s, 1, 5, 3, 60)  # ZOCで足を止める敵。硬い＝1発では落ちない
	s.add_base(Base.new(_hex(9, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "前提: 経路上の敵を殴る")
	assert_not_null(s.attack(a.handle, a.target_id), "前提: AIの攻撃は妥当")
	assert_not_null(s.unit_by_handle(e.handle), "前提: 敵は生き残る")
	var b := _brain.next_action(s, 1)
	assert_true(b == null or b.kind != AiAction.Kind.ATTACK, "撃ったあとは攻撃の行が成立しない")

# --- predator（弱者狙い） ---

func test_predator_base_waits_until_prey_is_in_sight() -> void:
	# 拠点の行動開始条件は拠点hex基準＝拠点から視線距離 sight 以内に獲物が入るまで出さない。
	var s := _state(12, 5)
	_base_with_garrison(s, _squad(s, "predator", { "sight": 3 }), 4, 2)
	var prey := _pc(s, 1, 11, 2)
	assert_null(_brain.next_action(s, 1), "拠点hexから sight の外なら出さない")
	prey.pos = _hex(6, 2)
	var a := _brain.next_action(s, 1)
	assert_not_null(a)
	assert_eq(a.kind, AiAction.Kind.DEPLOY, "獲物が視線に入れば出す")

func test_prey_band_reaches_ten_above_the_softest() -> void:
	# 獲物＝防御力が最小の敵の防御力 +10 まで。最小10なら防御20は獲物（殴る）、防御30は獲物でない（素通り）。
	for def in [20, 30]:
		var s := _state(12, 5)
		var si := _squad(s, "predator")
		_ai(s, si, 10, 4, 2)
		var front := _pc(s, 1, 4, 1, def)  # 隣接
		_pc(s, 2, 10, 2, 10)               # 最も柔らかい敵は遠い
		var a := _brain.next_action(s, 1)
		if def == 20:
			assert_eq(a.kind, AiAction.Kind.ATTACK, "防御20＝最小+10 までなので獲物")
			assert_eq(a.target_id, front.handle)
		else:
			assert_eq(a.kind, AiAction.Kind.MOVE, "防御30＝幅の外なので殴り合わない")

func test_predator_does_not_count_a_flier_it_cannot_hit_as_prey() -> void:
	# 獲物は攻撃できる敵に絞る。対空0の駒にとって飛行は獲物の下限にも入らない＝柔らかい飛行がいても
	# 地上の敵の層で獲物を決める。
	var s := _state(12, 5)
	var si := _squad(s, "predator")
	_ai(s, si, 10, 4, 2)          # 対空0
	var ground := _pc(s, 1, 4, 1, 20)
	_air(s, 2, 8, 2, 0)           # 防御0の飛行＝数えれば地上の敵は幅の外になる
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "攻撃できない飛行は獲物の下限に入らない")
	assert_eq(a.target_id, ground.handle)

func test_predator_advances_by_move_distance_when_zoc_seals_the_flank() -> void:
	# #7 迂回距離が測れない（ZOCの帯で道が消えている）とき、移動距離で最大前進する。
	var s := _state(7, 3)
	s.set_movement(PLAIN_WALL)
	var si := _squad(s, "predator")
	var u := _ai(s, si, 10, 0, 1)
	_pc(s, 1, 3, 1, 80)            # 盤の高さ3＝この駒のZOCが盤を横切る（硬い＝獲物でない）
	var prey := _pc(s, 2, 6, 1, 10)
	assert_eq(AiDistance.detour_distance_to(s, 10, prey.handle), BattleState.UNREACHABLE, "前提: 迂回距離は測れない")
	assert_lt(AiDistance.move_distance(s, 10, s.attack_cells(10, prey.handle)), BattleState.UNREACHABLE,
		"前提: 移動距離は測れる")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "回り込めなくても前進する")
	assert_lt(Hex.distance(a.to, prey.pos), Hex.distance(u.pos, prey.pos), "獲物へ近づく")

func test_predator_closes_in_by_terrain_distance_when_pieces_block_the_prey() -> void:
	# #8 獲物の周りが駒で埋まって移動距離が測れないとき、地形距離で詰めておく。
	var s := _state(9, 5)
	var si := _squad(s, "predator")
	var u := _ai(s, si, 10, 1, 2)
	var prey := _pc(s, 1, 6, 2)
	_ring_of_done_mates(s, si, prey)
	assert_eq(AiDistance.move_distance(s, 10, s.attack_cells(10, prey.handle)), BattleState.UNREACHABLE,
		"前提: 移動距離は測れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, prey.pos), Hex.distance(u.pos, prey.pos), "獲物へ近づく")

func test_predator_closes_in_a_straight_line_when_walled_off() -> void:
	# #9 sight 範囲内に獲物がいて、どの道のりも測れないとき＝壁際まで直線寄せ。
	var s := _state(9, 5)
	_wall_column(s, 4)
	var si := _squad(s, "predator")
	_ai(s, si, 10, 1, 2)
	var prey := _pc(s, 1, 7, 2)
	assert_eq(AiDistance.terrain_distance(s, 10, s.attack_cells(10, prey.handle)), BattleState.UNREACHABLE,
		"前提: 地形距離も測れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(_col(a.to), 3, "壁の手前まで詰める")

# --- swarm（群れ） ---

func test_swarm_bites_the_nearest_enemy_when_nobody_is_wounded() -> void:
	# 手負いに損耗の下限は無い＝全員無傷のターンは移動距離が最小の敵が手負いになり、#2 で単独でも噛みつく。
	var s := _state(12, 5)
	var si := _squad(s, "swarm")
	_ai(s, si, 10, 4, 2)
	var near := _pc(s, 1, 4, 1)  # 隣接
	_pc(s, 2, 0, 2)              # 遠いが col が若い
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "包囲を待たずに最初の一噛み")
	assert_eq(a.target_id, near.handle, "最も近い敵が手負い")

func test_swarm_goes_for_the_nearest_enemy_when_the_wounded_is_out_of_sight() -> void:
	# #7・#8 は sight 範囲内の手負いだけ。手負いが視線の外なら #9 移動距離が最小の敵へ最大前進。
	for sight in ["*", 2]:
		var s := _state(16, 5)
		var si := _squad(s, "swarm", { "sight": sight })
		var u := _ai(s, si, 10, 6, 2)
		_pc(s, 1, 1, 2)                   # 無傷・西に盤上距離5
		_hurt(_pc(s, 2, 13, 2), 2)        # 手負い・東に盤上距離7
		var a := _brain.next_action(s, 1)
		assert_eq(a.kind, AiAction.Kind.MOVE)
		if sight is String:
			assert_gt(_col(a.to), _col(u.pos), "視線内なら手負い（東）へ寄る")
		else:
			assert_lt(_col(a.to), _col(u.pos), "手負いが視線の外なら最も近い敵（西）へ寄る")

func test_swarm_closes_in_by_terrain_distance_when_pieces_block_the_enemy() -> void:
	# #10 手負いが視線の外で、最寄りの敵の周りが駒で埋まっている＝地形距離で詰める。
	var s := _state(9, 5)
	var si := _squad(s, "swarm", { "sight": 1 })
	var u := _ai(s, si, 10, 1, 2)
	var e := _pc(s, 1, 6, 2)
	_ring_of_done_mates(s, si, e)
	assert_eq(AiDistance.move_distance(s, 10, s.attack_cells(10, e.handle)), BattleState.UNREACHABLE,
		"前提: 移動距離は測れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, e.pos), Hex.distance(u.pos, e.pos), "敵へ近づく")

func test_swarm_closes_in_a_straight_line_when_walled_off() -> void:
	# #11 どの道のりも測れないとき、盤上距離が最小の敵へ直線寄せ＝壁際まで詰める。
	var s := _state(9, 5)
	_wall_column(s, 4)
	var si := _squad(s, "swarm", { "sight": 1 })
	_ai(s, si, 10, 1, 2)
	_pc(s, 1, 7, 2)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(_col(a.to), 3, "壁の手前まで詰める")

## 群れのゴースト（敵に掛ける弱体）と、無傷の敵の隣へ今ターン寄れる2体目＝包囲可能。手負いは遠い。
func _ghost_pack(overrides := {}) -> Dictionary:
	var s := _state(12, 5)
	var si := _squad(s, "swarm", overrides)
	var ghost := _skin(_ai(s, si, 10, 4, 2), "ghost")
	_ai(s, si, 11, 4, 4)
	var healthy := _pc(s, 1, 4, 1)
	_hurt(_pc(s, 2, 9, 2), 2)
	return { "s": s, "ghost": ghost, "healthy": healthy }

func test_swarm_keeps_stacking_when_stack_is_unlimited() -> void:
	# stack `-`（上限なし）なら #4 は成立しない＝毒が刺さっていても殴りに切り替えず重ね続ける。
	var d := _ghost_pack({ "stack": "-" })
	var s: BattleState = d.s
	_debuff(s, d.healthy)
	var a := _brain.next_action(s, 1)
	assert_eq(a.handle, (d.ghost as Unit).handle, "前提: ゴーストが先に動く")
	assert_eq(a.kind, AiAction.Kind.SKILL, "上限なしなので重ね続ける")

func test_swarm_does_not_curse_an_enemy_it_cannot_surround() -> void:
	# #5 敵に掛けるスキルは包囲可能な相手だけ。隣の敵へ寄れる仲間がいなければ撃たない。
	var s := _state(12, 5)
	var si := _squad(s, "swarm")
	_skin(_ai(s, si, 10, 4, 2), "ghost")  # 単独
	_pc(s, 1, 4, 1)                       # 隣接・無傷
	_hurt(_pc(s, 2, 9, 2), 2)             # 手負いは遠い
	var a := _brain.next_action(s, 1)
	assert_ne(a.kind, AiAction.Kind.SKILL, "包囲できない相手には掛けない")
	assert_eq(a.kind, AiAction.Kind.MOVE, "手負いへ寄る")

# --- standoff（睨み合い） ---

func test_standoff_prefers_the_enemy_that_cannot_retaliate_over_a_bigger_hit() -> void:
	# #3〜#6 反撃されない敵は戦果より上。隣の柔らかい敵のほうが多く削れても、反撃を受けない相手を撃つ。
	var s := _state(16, 3)
	var si := _squad(s, "standoff")
	var gun := _ai(s, si, 10, 5, 1, 0)  # 移動0＝撃つ行だけを見る
	gun.attack_range = 3                # 射程1-3＝隣も撃てる
	var soft := _pc(s, 1, 4, 1, 10)     # 隣接＝反撃を受ける
	var hard := _pc(s, 2, 8, 1, 40)     # 盤上距離3＝反撃されない
	assert_gt(Combat.casualties(s, gun, soft), Combat.casualties(s, gun, hard), "前提: 隣の敵のほうが多く削れる")
	assert_lt(Combat.casualties(s, gun, soft), soft.troops, "前提: どちらも仕留められない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, hard.handle, "反撃されない敵を先に見る")

func test_standoff_closes_in_by_terrain_distance_when_pieces_block_the_enemy() -> void:
	# #8 移動距離が測れないとき、地形距離が最小の敵へ見込前進（行き先は脅威圏の外に限る）。
	var s := _state(9, 5)
	var si := _squad(s, "standoff")
	var u := _ai(s, si, 10, 1, 2)
	var e := _pc(s, 1, 6, 2)
	_ring_of_done_mates(s, si, e)
	assert_eq(AiDistance.move_distance(s, 10, s.attack_cells(10, e.handle)), BattleState.UNREACHABLE,
		"前提: 移動距離は測れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_lt(Hex.distance(a.to, e.pos), Hex.distance(u.pos, e.pos), "敵へ近づく")

func test_standoff_closes_in_a_straight_line_when_walled_off() -> void:
	# #9 どの道のりも測れないとき、盤上距離が最小の敵へ直線寄せ。壁の向こうの敵の脅威圏は壁の手前まで
	# 届かないので、壁際が行き先になる。
	var s := _state(9, 5)
	_wall_column(s, 4)
	var si := _squad(s, "standoff")
	_ai(s, si, 10, 1, 2)
	_pc(s, 1, 7, 2)
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(_col(a.to), 3, "壁の手前まで詰める")

# --- 退き先は休める拠点だけ（rest） ---

## 損耗50%の駒と、東に自陣営の拠点（rest 指定）。flee は敵なし、withdraw は西に隣接する敵を置く。
func _retreat_board(trait_id: String, rest: String) -> BattleState:
	var s := _state(15, 3)
	var si := _squad(s, trait_id)
	_hurt(_ai(s, si, 10, 5, 1), 4)
	if trait_id == "withdraw":
		_pc(s, 1, 4, 1)
	s.add_base(Base.new(_hex(12, 1), 1, Base.NO_HQ, rest))
	return s

func test_flee_does_not_run_to_a_base_it_cannot_rest_in() -> void:
	# #3 の自陣営の拠点は休める拠点に限る＝奪っただけで入れない拠点（rest:"player"）へは逃げない。
	var a := _brain.next_action(_retreat_board("flee", Base.REST_ENEMY), 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "前提: 休める拠点なら逃げる")
	assert_gt(_col(a.to), 5)
	assert_null(_brain.next_action(_retreat_board("flee", Base.REST_PLAYER), 1), "休めない拠点しか無ければ待機")

func test_withdraw_does_not_fall_back_to_a_base_it_cannot_rest_in() -> void:
	# #2・#3 の自陣営の拠点は休める拠点に限る＝休めない拠点しか無ければ突撃として戦う。
	var a := _brain.next_action(_retreat_board("withdraw", Base.REST_ENEMY), 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "前提: 休める拠点なら退く")
	var b := _brain.next_action(_retreat_board("withdraw", Base.REST_PLAYER), 1)
	assert_eq(b.kind, AiAction.Kind.ATTACK, "休めない拠点へは退かずに殴る")
	assert_eq(b.target_id, 1)

func test_withdraw_fights_when_the_way_home_is_blocked() -> void:
	# 道が塞がれて自陣営の拠点への移動距離が測れないときは #3 が不成立＝突撃として戦う。
	var s := _state(12, 5)
	_corridor(s, [2])
	var si := _squad(s, "withdraw")
	_hurt(_ai(s, si, 10, 4, 2), 4)
	s.set_done(_ai(s, si, 11, 5, 2).handle)  # 帰り道を塞ぐ味方（もう動かない）
	var e := _pc(s, 1, 3, 2)                 # 西に隣接
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 1))
	assert_eq(_move_distance_to(s, 10, base_hex), BattleState.UNREACHABLE, "前提: 帰り道が測れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK, "退けないなら諦めて殴る")
	assert_eq(a.target_id, e.handle)

# --- パラメーターの解決 ---

func test_squad_retreat_overrides_the_trait_default() -> void:
	# 解決順は 部隊の上書き ＞ 特性の既定。損耗25%は既定（50）では戦い、上書き25では退く。
	for overridden in [false, true]:
		var s := _state(15, 3)
		var si := _squad(s, "withdraw", { "retreat": 25 } if overridden else {})
		_hurt(_ai(s, si, 10, 5, 1), 6)  # 満員8 → 6 = 損耗25%
		_pc(s, 1, 4, 1)
		s.add_base(Base.new(_hex(12, 1), 1))
		var a := _brain.next_action(s, 1)
		if not overridden:
			assert_eq(a.kind, AiAction.Kind.ATTACK, "既定50では損耗25%はまだ戦う")
		else:
			assert_eq(a.kind, AiAction.Kind.MOVE, "部隊の上書き25で退く")
			assert_gt(_col(a.to), 5)

func test_unknown_trait_acts_as_charge() -> void:
	# 部隊の ai が未知の値なら charge（常時起動・前へ出る）。
	var s := _state(12, 3)
	var si := _squad(s, "no_such_trait")
	var u := _ai(s, si, 10, 0, 1)
	var e := _pc(s, 1, 10, 1)  # 待ち伏せなら sight の外
	assert_eq(_brain.detection_radius(s, u), 0, "視線で起きる特性ではない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE, "常時起動で前へ出る")
	assert_eq(Hex.distance(a.to, e.pos), Hex.distance(u.pos, e.pos) - 3, "移動力ぶん詰める")
