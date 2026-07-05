extends GutTest
## domain/battle_state.gd の勝敗判定のテスト（自軍＝team 0 視点）。

func test_ongoing_when_both_teams_present() -> void:
	var s := BattleState.new(8, 8)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3))
	assert_false(s.is_over(), "両軍が残っていれば未決着")
	assert_eq(s.outcome(), BattleState.ONGOING)

func test_player_wins_when_enemy_wiped() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 100, 10))               # 圧倒的攻撃
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 2, 1, 1))
	s.attack(1, 2)
	assert_true(s.is_over(), "敵全滅で決着")
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "自軍の勝利")

func test_player_loses_when_wiped() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 1, 1, 1))                  # 弱小・反撃で全滅
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 100, 10))
	s.attack(1, 2)
	assert_true(s.is_over())
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "自軍全滅は敗北")

func test_mutual_destruction_is_loss() -> void:
	var s := BattleState.new(8, 8)
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 2, 100, 1))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 2, 100, 1))
	s.attack(1, 2)  # 相討ちで両軍全滅
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "相討ち全滅も自軍全滅なので敗北")

# --- 案B: 盤上0でも「復帰手段」があれば消滅していない（doc/gdd/map.md 勝敗条件） ---

func test_no_loss_while_reinforcement_remains() -> void:
	# 盤上0でも、自軍拠点に出せる控えがあれば敗北にしない。
	var s := BattleState.new(8, 8)
	var b := Base.new(Hex.offset_to_axial(4, 4), 0)
	b.garrison.append(Unit.new(5, 0, Vector2i.ZERO, 3))  # 自軍 native の控え
	s.add_base(b)
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))  # 敵は盤上に健在
	assert_eq(s.team_unit_count(0), 0, "自軍は盤上0")
	assert_eq(s.outcome(), BattleState.ONGOING, "復帰手段があれば敗北にならない")

func test_loss_when_only_locked_garrison() -> void:
	# 奪った敵 native の控えは閉じ込めで出せない＝復帰手段にならない＝敗北。
	var s := BattleState.new(8, 8)
	var b := Base.new(Hex.offset_to_axial(4, 4), 1)  # 敵 native 拠点
	b.garrison.append(Unit.new(10, 1, Vector2i.ZERO, 3))  # native=1（敵）
	s.add_base(b)
	b.team = 0  # 自軍が奪ったが中の敵は閉じ込め
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(6, 6), 3))
	assert_eq(s.team_unit_count(0), 0, "自軍は盤上0")
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "閉じ込めの控えは復帰手段にならない")

func test_loss_when_base_blockaded() -> void:
	# 控えは出せる native だが、拠点の全周を敵が塞ぎ盤上へ出られない＝復帰手段なし＝敗北。
	var s := BattleState.new(8, 8)
	var base_hex := Hex.offset_to_axial(4, 4)
	var b := Base.new(base_hex, 0)
	b.garrison.append(Unit.new(5, 0, Vector2i.ZERO, 3))  # 自軍 native の控え
	s.add_base(b)
	for i in 6:
		s.add_unit(Unit.new(100 + i, 1, Hex.neighbor(base_hex, i), 3))  # 全周を敵で封鎖
	assert_eq(s.team_unit_count(0), 0, "自軍は盤上0")
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "全周封鎖で盤上復帰できなければ敗北")

func test_no_win_while_enemy_reinforcement_remains() -> void:
	# 勝利も対称: 敵が盤上0でも、敵拠点に出せる控えがあれば殲滅勝ちにならない（湧く）。
	var s := BattleState.new(8, 8)
	var b := Base.new(Hex.offset_to_axial(4, 4), 1)  # 敵拠点
	b.garrison.append(Unit.new(10, 1, Vector2i.ZERO, 3))  # 敵 native の控え
	s.add_base(b)
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(6, 6), 3))  # 自軍は盤上に健在
	assert_eq(s.team_unit_count(1), 0, "敵は盤上0")
	assert_eq(s.outcome(), BattleState.ONGOING, "敵に復帰手段があれば勝ちきれない")

# --- ターン制限（超過＝時間切れ敗北・引き分けなし）。doc/gdd/map.md ---

func _both_present(s: BattleState) -> void:
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))
	s.add_unit(Unit.new(2, 1, Hex.offset_to_axial(5, 5), 3))

func test_no_loss_at_turn_limit() -> void:
	var s := BattleState.new(8, 8)
	s.turn_limit = 30
	s.turn_number = 30
	_both_present(s)
	assert_eq(s.outcome(), BattleState.ONGOING, "上限ちょうど（30手番目）はまだ継続")

func test_loss_when_turn_limit_exceeded() -> void:
	var s := BattleState.new(8, 8)
	s.turn_limit = 30
	s.turn_number = 31
	_both_present(s)
	assert_eq(s.outcome(), BattleState.PLAYER_LOSS, "上限を超えたら時間切れ敗北")

func test_turn_limit_zero_is_unlimited() -> void:
	var s := BattleState.new(8, 8)  # turn_limit 既定0
	s.turn_number = 999
	_both_present(s)
	assert_eq(s.outcome(), BattleState.ONGOING, "0＝無制限（時間切れにならない）")

func test_win_takes_priority_over_turn_limit() -> void:
	# 上限超過でも、勝利条件（ここでは敵殲滅）を満たしていれば勝ち＝時間切れ敗北より優先。
	var s := BattleState.new(8, 8)
	s.turn_limit = 30
	s.turn_number = 31
	s.add_unit(Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3))  # 自軍のみ＝敵は盤上0・復帰手段なし
	assert_eq(s.outcome(), BattleState.PLAYER_WIN, "殲滅勝ちは時間切れより優先")

func test_turnlimit_debug_stage_loads() -> void:
	# デバッグステージ turnlimit.json: 敵味方1体・敵は待機(guard)・リミット10。
	var s := StageLoader.load_file("res://data/stages/debug/turnlimit.json")
	assert_not_null(s, "turnlimit.json が読める")
	assert_eq(s.turn_limit, 10, "リミット10")
	assert_eq(s.team_unit_count(0), 1, "自軍1体")
	assert_eq(s.team_unit_count(1), 1, "敵1体")
	assert_eq(String(s.squads[0].get("ai", "")), "guard", "敵は待機(guard)")

func test_build_wires_turn_limit() -> void:
	var s := StageLoader.build({ "cols": 6, "rows": 6, "turn_limit": 25 })
	assert_eq(s.turn_limit, 25, "ステージの turn_limit が載る")
	var s2 := StageLoader.build({ "cols": 6, "rows": 6 })
	assert_eq(s2.turn_limit, 0, "build は未指定を素通し（0）。実ファイルの必須チェックは load_file 側")
