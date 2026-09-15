extends GutTest
## 敵AIの輸送（乗る・運ぶ・降ろす）のテスト。仕様の正本は doc/gdd/ai.md
## （特殊特性詳細＝輸送ユニット・raid の行動ルール #4〜#6）。
##
## 輸送ユニット＝搭載数2以上。特性に重ねて働く制約（部隊内で最後・目的地hexに乗らない・攻撃しない）と、
## raid の行（降ろす・乗る）を分けて見る。盤は flat-top / odd-q（座標指定は offset）。

const PLAIN_CLIFF := { "foot": { "plain": 1, "cliff": "x" }, "flight": { "plain": 1, "cliff": 1 } }

var _brain: TraitBrain

func before_each() -> void:
	_brain = TraitBrain.new()
	_brain.presets = AiCatalog.load_default()

# --- 盤の組み立て ---

func _state(cols := 12, rows := 5) -> BattleState:
	var s := BattleState.new(cols, rows)
	s.current_team = 1
	return s

func _squad(s: BattleState, ai: String) -> int:
	s.squads.append({ "ai": ai, "order": s.squads.size() + 1 })
	return s.squads.size() - 1

## 敵(team 1)の駒を部隊に入れて盤へ置く。
func _ai(s: BattleState, si: int, id: int, col: int, row: int, move := 3) -> Unit:
	var u := Unit.new(id, 1, Hex.offset_to_axial(col, row), move)
	u.move_type = "foot"
	s.add_unit(u)
	s.assign_squad(u.id, si)
	return u

## 輸送ユニット（既定＝馬車相当: 搭載4・移動6・攻撃0）。
func _wagon(s: BattleState, si: int, id: int, col: int, row: int, cap := 4, move := 6) -> Unit:
	var u := _ai(s, si, id, col, row, move)
	u.capacity = cap
	u.unit_attack = 0
	u.atk_air = 0
	return u

## 占領兵（移動2）を輸送に積む。盤上には出さない。
func _passenger(s: BattleState, transport_id: int, id: int, move := 2, capture := true) -> Unit:
	var p := Unit.new(id, 1, Vector2i.ZERO, move)
	p.move_type = "foot"
	p.can_capture = capture
	s.put_passenger(transport_id, p)
	return p

func _pc(s: BattleState, id: int, col: int, row: int) -> Unit:
	var u := Unit.new(id, 0, Hex.offset_to_axial(col, row), 3)
	u.move_type = "foot"
	s.add_unit(u)
	return u

func _hex(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(col, row)

## AIの1手を盤へ適用する（MatchController の翻訳と同じ対応）。
func _apply(s: BattleState, a: AiAction) -> void:
	match a.kind:
		AiAction.Kind.MOVE:
			s.move_unit(a.unit_id, a.to)
		AiAction.Kind.UNLOAD:
			s.unload(a.unit_id, a.passenger_index, a.to)
		AiAction.Kind.ATTACK:
			s.attack(a.unit_id, a.target_id)

## そのターンの手を尽きるまで回す（run_ai_turn 相当）。返すのは打った手の列。
func _run_turn(s: BattleState) -> Array[AiAction]:
	var out: Array[AiAction] = []
	for _i in 20:  # 無限ループ検出用の上限（正常なら手が尽きて抜ける）
		var a := _brain.next_action(s, 1)
		if a == null:
			break
		out.append(a)
		_apply(s, a)
	return out

# --- 輸送ユニットの扱い（特殊特性） ---

func test_transport_moves_last_in_its_squad() -> void:
	# 部隊の中で最後に動く＝同じ部隊の駒が乗り込んでから動く。
	var s := _state()
	var si := _squad(s, "raid")
	_wagon(s, si, 10, 5, 2)   # 拠点に最も近い＝並べ替えでは本来先頭
	_ai(s, si, 11, 2, 2)
	s.add_base(Base.new(_hex(9, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.unit_id, 11, "輸送より先に歩兵が動く")

func test_transport_does_not_attack() -> void:
	# 攻撃力を持つ輸送（飛空艇）も、自分からは仕掛けない。
	var s := _state()
	var si := _squad(s, "charge")
	var airship := _wagon(s, si, 10, 4, 2)
	airship.unit_attack = 10
	airship.atk_air = 10
	_pc(s, 1, 5, 2)  # 隣接＝射程内
	var a := _brain.next_action(s, 1)
	assert_true(a == null or a.kind != AiAction.Kind.ATTACK, "隣の敵を殴らない")

func test_transport_stops_short_of_the_base_hex() -> void:
	# 目的地hexに乗らない＝拠点を塞ぐと運んできた占領兵も他の味方も入れない。
	var s := _state()
	var si := _squad(s, "raid")
	_wagon(s, si, 10, 5, 2)
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_ne(a.to, base_hex, "拠点hexには乗らない")

func test_non_transport_still_takes_the_base_hex() -> void:
	# 制約が効くのは輸送ユニットだけ（搭載数1の駒も含めて他は今までどおり）。
	var s := _state()
	var si := _squad(s, "raid")
	var horse := _ai(s, si, 10, 8, 2, 6)
	horse.capacity = 1  # 1体だけ乗せて戦う騎乗＝輸送ユニットではない
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.to, base_hex, "搭載数1の駒は拠点hexへ入る")

# --- 乗る（raid #6） ---

func test_slow_capturer_boards_the_squad_wagon() -> void:
	# 便乗のほうが早い＝移動2の占領兵は移動6の馬車に乗る。
	var s := _state(16, 5)
	var si := _squad(s, "raid")
	var wagon := _wagon(s, si, 10, 3, 2)
	var cleric := _ai(s, si, 11, 2, 2, 2)
	cleric.can_capture = true
	s.add_base(Base.new(_hex(14, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.unit_id, 11, "先に動くのは乗る側")
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_eq(a.to, wagon.pos, "馬車のマスへ移動＝乗車")
	_apply(s, a)
	assert_eq(s.passengers(10).size(), 1, "搭乗リストに載る")

func test_does_not_board_a_wagon_of_another_squad() -> void:
	# 目的地の違う部隊の輸送に乗ると見当違いの場所へ運ばれる。
	var s := _state(16, 5)
	var si := _squad(s, "raid")
	var other := _squad(s, "raid")
	_wagon(s, other, 10, 3, 2)
	var cleric := _ai(s, si, 11, 2, 2, 2)
	cleric.can_capture = true
	s.add_base(Base.new(_hex(14, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.unit_id, 11)
	assert_ne(a.to, s.unit_by_id(10).pos, "他部隊の馬車には乗らない")

func test_does_not_board_when_walking_is_not_slower() -> void:
	# 便乗＝輸送の道のり÷輸送の移動力 +1。同値なら乗らない（振動しない）。
	var s := _state(16, 5)
	var si := _squad(s, "raid")
	var wagon := _wagon(s, si, 10, 3, 2)
	var runner := _ai(s, si, 11, 2, 2, 6)  # 馬車と同速
	runner.can_capture = true
	s.add_base(Base.new(_hex(14, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.unit_id, 11)
	assert_ne(a.to, wagon.pos, "自分で歩いたほうが早い／同じなら乗らない")

func test_does_not_board_a_full_wagon() -> void:
	var s := _state(16, 5)
	var si := _squad(s, "raid")
	var wagon := _wagon(s, si, 10, 3, 2, 1)  # 搭載1…に見えるが輸送ユニットの線は2以上
	wagon.capacity = 2
	_passenger(s, 10, 20)
	_passenger(s, 10, 21)  # 満員
	var cleric := _ai(s, si, 11, 2, 2, 2)
	cleric.can_capture = true
	s.add_base(Base.new(_hex(14, 2), 0))
	var a := _brain.next_action(s, 1)
	assert_ne(a.to, wagon.pos, "満員の輸送には乗れない")

# --- 降ろす（raid #4・#5） ---

func test_unloads_a_capturer_onto_the_base_hex() -> void:
	# #4 占領兵の乗員を拠点hexへ降ろす＝降りた瞬間に占領。
	var s := _state()
	var si := _squad(s, "raid")
	var wagon := _wagon(s, si, 10, 8, 2)
	_passenger(s, 10, 20)
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.UNLOAD)
	assert_eq(a.unit_id, wagon.id)
	assert_eq(a.to, base_hex, "拠点hexへ降ろす")
	_apply(s, a)
	assert_eq(s.base_at(base_hex).team, 1, "降車で占領が成立")

func test_carries_and_unloads_in_one_turn() -> void:
	# 運ぶ→降ろすが同じターンに起きる（降車は乗員の手番なので輸送が動いた後でも打てる）。
	var s := _state(14, 5)
	var si := _squad(s, "raid")
	_wagon(s, si, 10, 2, 2)
	_passenger(s, 10, 20)
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	var acted := _run_turn(s)
	assert_eq(acted.size(), 2, "移動と降車の2手")
	assert_eq(acted[0].kind, AiAction.Kind.MOVE)
	assert_eq(acted[1].kind, AiAction.Kind.UNLOAD)
	assert_eq(s.base_at(base_hex).team, 1, "その回で拠点まで取り切る")
	assert_eq(s.passengers(10).size(), 0, "乗員は降りた")

func test_keeps_a_passenger_that_cannot_reach_the_base() -> void:
	# #5 たどり着けない乗員は乗せたまま。飛空艇が崖の上の拠点の隣まで来ても地上駒は降ろさない。
	var s := _state()
	s.set_movement(PLAIN_CLIFF)
	var si := _squad(s, "raid")
	var airship := _wagon(s, si, 10, 8, 2)
	airship.move_type = "flight"
	_passenger(s, 10, 20)  # 地上の占領兵
	var base_hex := _hex(9, 2)
	s.set_terrain(base_hex, "cliff")
	s.add_base(Base.new(base_hex, 0))
	var a := _brain.next_action(s, 1)
	assert_true(a == null or a.kind != AiAction.Kind.UNLOAD, "崖の拠点には降ろさない")
	assert_eq(s.passengers(10).size(), 1, "乗せたまま")

func test_carrying_transport_also_stops_short_of_the_base_hex() -> void:
	# 降ろすための移動でも拠点hexには乗らない（拠点に乗ると乗員を拠点へ降ろせなくなる）。
	var s := _state()
	var si := _squad(s, "raid")
	_wagon(s, si, 10, 5, 2)
	_passenger(s, 10, 20)
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.MOVE)
	assert_ne(a.to, base_hex, "拠点hexには乗らない")
	assert_eq(Hex.distance(a.to, base_hex), 1, "拠点の隣まで寄る")

func test_capture_row_does_not_board_a_transport_sitting_on_the_base() -> void:
	# 拠点hexに味方輸送が居ると、そのマスは「乗れる輸送のマス」として移動範囲に入る。
	# 占領の行がそれを拠点への進入と取り違えると、占領のつもりで乗車してしまう。
	var s := _state()
	var si := _squad(s, "raid")
	var base_hex := _hex(9, 2)
	_wagon(s, si, 10, 9, 2)  # 拠点の上に居る輸送（ステージデータで置かれた場合）
	var cleric := _ai(s, si, 11, 8, 2, 2)
	cleric.can_capture = true
	s.add_base(Base.new(base_hex, 0))
	assert_true(s.reachable(11).has(base_hex), "乗れる輸送のマス＝移動範囲には入る")
	var a := _brain.next_action(s, 1)
	assert_true(a == null or a.to != base_hex, "占領のつもりで乗車しない")

func test_does_not_unload_a_non_capturer_onto_the_base_hex() -> void:
	# 占領できない駒を拠点hexへ降ろしても占領は起きず、拠点を塞ぐだけ。
	var s := _state()
	var si := _squad(s, "raid")
	_wagon(s, si, 10, 8, 2)
	_passenger(s, 10, 20, 4, false)  # 護衛＝占領できない
	var base_hex := _hex(9, 2)
	s.add_base(Base.new(base_hex, 0))
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.UNLOAD, "拠点の隣へは降ろす")
	assert_ne(a.to, base_hex, "拠点hexには降ろさない")
	assert_eq(Hex.distance(a.to, base_hex), 1, "降車先は拠点に隣接")
