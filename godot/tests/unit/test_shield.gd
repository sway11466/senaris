extends GutTest
## シールド（兵数の手前で損害を受ける器）のテスト。
## 入口は Unit.take_loss ひとつ＝攻撃・反撃・スキルの着弾・毒がそこを通る。詳細 → doc/gdd/combat.md シールド

func _state() -> BattleState:
	return BattleState.new(8, 8)

## 攻撃側 a（隣接・対地60）と、シールド付きの防御側 t（防50）を置いた盤。
func _pair(shield: int, t_troops := 8) -> Dictionary:
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	var a := Unit.new(1, 0, ap, 3, 8, 60, 20)
	var t := Unit.new(2, 1, Hex.neighbor(ap, 0), 3, t_troops, 70, 50)
	t.max_shield = 16
	t.shield = shield
	s.add_unit(a)
	s.add_unit(t)
	return { "s": s, "a": a, "t": t }

func _dot(unit_id: int, value: int) -> Dictionary:
	return {
		"scope": "unit", "unit_id": unit_id, "owner_team": 0,
		"op": StatusMod.OP_DOT, "value": value, "remaining": 2, "kind": StatusMod.KIND_DEBUFF,
	}

# --- Unit.take_loss（入口） ---

func test_take_loss_hits_shield_first() -> void:
	var u := Unit.new(1, 0, Vector2i.ZERO, 3, 8)
	u.max_shield = 16
	u.shield = 16
	assert_eq(u.take_loss(5), 0, "シールドで受け切った＝兵数の減りは0")
	assert_eq(u.shield, 11, "シールドが5減る")
	assert_eq(u.troops, 8, "兵数は無傷")

func test_take_loss_overflow_goes_to_troops() -> void:
	var u := Unit.new(1, 0, Vector2i.ZERO, 3, 8)
	u.max_shield = 16
	u.shield = 1
	assert_eq(u.take_loss(5), 4, "シールド1を超えた4が本体へ")
	assert_eq(u.shield, 0)
	assert_eq(u.troops, 4)

func test_take_loss_without_shield_is_plain() -> void:
	var u := Unit.new(1, 0, Vector2i.ZERO, 3, 8)
	assert_eq(u.take_loss(3), 3)
	assert_eq(u.troops, 5, "シールド無し＝そのまま兵数が減る")
	assert_eq(u.take_loss(10), 5, "兵数は0で止まる（減った分だけ返す）")
	assert_eq(u.troops, 0)

# --- 戦闘（BattleState.attack） ---

func test_attack_strips_shield_and_keeps_troops() -> void:
	var p := _pair(16)
	var s: BattleState = p["s"]
	var a: Unit = p["a"]
	var t: Unit = p["t"]
	var r: AttackResult = s.attack(1, 2)
	assert_not_null(r)
	var loss: int = r.to_defender.loss
	assert_gt(loss, 0, "前提: 削る量がある")
	assert_eq(t.troops, 8, "兵数は無傷")
	assert_eq(t.shield, 16 - loss, "損害はシールドから引かれる")
	assert_eq(r.defender.shield_before, 16)
	assert_eq(r.defender.shield_after, 16 - loss, "スナップショットに前後が乗る")
	assert_eq(r.defender.troops_after, 8)
	assert_eq(a.level, 2, "シールドしか削れなくても戦った＝+1")

func test_attack_overflow_reaches_troops() -> void:
	var p := _pair(1)
	var s: BattleState = p["s"]
	var t: Unit = p["t"]
	var r: AttackResult = s.attack(1, 2)
	var loss: int = r.to_defender.loss
	assert_eq(t.shield, 0, "シールドは尽きる")
	assert_eq(t.troops, 8 - (loss - 1), "超過分だけ本体が減る")
	assert_eq(r.defender.troops_after, 8 - (loss - 1))

func test_damage_formula_ignores_shield() -> void:
	# シールドの有無で削る量は変わらない（当たり先だけ変わる）。
	var p0 := _pair(0)
	var p1 := _pair(16)
	var l0: int = Combat.hit_detail(p0["s"], p0["a"], p0["t"], true).loss
	var l1: int = Combat.hit_detail(p1["s"], p1["a"], p1["t"], true).loss
	assert_eq(l1, l0, "損害の計算式はシールドを見ない")

# --- 毒（継続ダメージ） ---

func test_dot_eats_shield_before_troops() -> void:
	var p := _pair(3)
	var s: BattleState = p["s"]
	var t: Unit = p["t"]
	s.add_status_mod(_dot(t.id, 5))
	s.end_turn()  # 敵ターン開始＝掛けられた側の頭で減る
	assert_eq(t.shield, 0, "毒もまずシールドを溶かす")
	assert_eq(t.troops, 6, "超過2が本体へ")

func test_dot_floor_applies_to_troops_only() -> void:
	var p := _pair(2, 2)
	var s: BattleState = p["s"]
	var t: Unit = p["t"]
	s.add_status_mod(_dot(t.id, 10))
	s.end_turn()
	assert_eq(t.shield, 0, "シールドは0まで減る")
	assert_eq(t.troops, 1, "本体は残兵1で止まる")

# --- 回復・直列化・AI ---

func test_rest_does_not_restore_shield() -> void:
	var s := _state()
	var base_hex := Hex.offset_to_axial(4, 4)
	s.add_base(Base.new(base_hex, 0))
	var u := Unit.new(1, 0, base_hex, 3, 8, 10, 10)
	u.troops = 3
	u.max_shield = 16
	u.shield = 5
	s.add_unit(u)
	s.add_unit(Unit.new(2, 0, Hex.offset_to_axial(6, 6), 3))  # 盤上最後の1体にならないよう相棒
	assert_true(s.enter_base(1))
	s.end_turn()
	s.end_turn()  # 自軍ターン開始 → 駐留駒が回復
	var healed: Unit = s.base_at(base_hex).garrison[0]
	assert_eq(healed.troops, 8, "兵数は満員へ")
	assert_eq(healed.shield, 5, "シールドは回復で戻らない")

func test_dict_roundtrip_keeps_shield() -> void:
	var ty := UnitType.from_dict({ "id": "dragon", "shield": 16, "max_troops": 8 })
	var u := Unit.new(1, 1, Vector2i.ZERO, 3, 8, 70, 50, 1, "dragon")
	u.apply_type(ty)
	assert_eq(u.shield, 16, "type の初期値が現在値になる")
	assert_eq(u.max_shield, 16)
	u.take_loss(5)
	var back := Unit.from_dict(u.to_dict(), ty)
	assert_eq(back.shield, 11, "損耗した現在値が往復する")
	assert_eq(back.max_shield, 16, "初期値は type から戻る")

func test_dict_without_shield_key_restores_full() -> void:
	var ty := UnitType.from_dict({ "id": "dragon", "shield": 16 })
	var back := Unit.from_dict({ "type": "dragon", "level": 1, "troops": 8, "max_troops": 8 }, ty)
	assert_eq(back.shield, 16, "キーの無い旧データは無傷で復元")

func test_ai_kill_check_counts_shield() -> void:
	var p := _pair(16, 1)  # 残兵1＋シールド16
	var s: BattleState = p["s"]
	var a: Unit = p["a"]
	var t: Unit = p["t"]
	var ids: Array[String] = []
	var pick := AiPick.new(AiParams.new(ids))  # 特性の既定は要らない＝確殺判定は戦闘式だけを見る
	assert_false(pick.can_kill_in_one_hit(s, a, t), "一撃はシールドに吸われる＝倒しきれない")
	t.shield = 0
	assert_true(pick.can_kill_in_one_hit(s, a, t), "シールドが無ければ残兵1は倒せる")
