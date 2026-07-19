extends GutTest
## 状態補正（バフ/デバフ・持続）＝汎用レイヤーの集計・combat反映・持続満了を検証。
## 詳細 → doc/gdd/combat.md「状態補正（バフ/デバフ・持続）」

func _state() -> BattleState:
	return BattleState.new(10, 8)

# --- 集計（StatusMod / status_aggregate） ---

func test_team_mul_applies_to_team_only() -> void:
	var s := _state()
	var ally := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 30)
	var foe := Unit.new(2, 1, Hex.offset_to_axial(5, 2), 3, 8, 30, 30)
	s.add_unit(ally)
	s.add_unit(foe)
	s.add_status_mod({"scope": "team", "team": 0, "owner_team": 0, "op": "mul", "target": "both", "value": 1.3, "remaining": 2})
	assert_almost_eq(float(s.status_aggregate(ally, "attack")["mul"]), 1.3, 0.001, "味方(team0)に乗る")
	assert_almost_eq(float(s.status_aggregate(foe, "attack")["mul"]), 1.0, 0.001, "敵(team1)には乗らない")

func test_target_filter() -> void:
	var s := _state()
	var u := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 30)
	s.add_unit(u)
	s.add_status_mod({"scope": "team", "team": 0, "owner_team": 0, "op": "mul", "target": "attack", "value": 1.5, "remaining": 1})
	assert_almost_eq(float(s.status_aggregate(u, "attack")["mul"]), 1.5, 0.001, "attack のみ")
	assert_almost_eq(float(s.status_aggregate(u, "defense")["mul"]), 1.0, 0.001, "defense は素通し")

func test_unit_scope_add_and_debuff() -> void:
	var s := _state()
	var u := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 30)
	var v := Unit.new(2, 0, Hex.offset_to_axial(3, 2), 3, 8, 30, 30)
	s.add_unit(u)
	s.add_unit(v)
	s.add_status_mod({"scope": "unit", "unit_id": 1, "owner_team": 0, "op": "add", "target": "defense", "value": 40, "remaining": 1})
	s.add_status_mod({"scope": "unit", "unit_id": 1, "owner_team": 0, "op": "mul", "target": "defense", "value": 0.5, "remaining": 1})  # デバフ＝不利な値
	var a := s.status_aggregate(u, "defense")
	assert_almost_eq(float(a["add"]), 40.0, 0.001, "個別add")
	assert_almost_eq(float(a["mul"]), 0.5, 0.001, "個別mul（デバフ）")
	assert_almost_eq(float(s.status_aggregate(v, "defense")["add"]), 0.0, 0.001, "scope=unit は別ユニットに乗らない")

# --- combat 反映 ---

func test_mul_scales_effective_attack() -> void:
	var s := _state()
	var atk := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 30)
	var foe := Unit.new(2, 1, Hex.neighbor(atk.pos, 0), 3, 8, 30, 30)
	s.add_unit(atk)
	s.add_unit(foe)
	var before := Combat.effective_attack(s, atk, foe, false)
	s.add_status_mod({"scope": "team", "team": 0, "owner_team": 0, "op": "mul", "target": "both", "value": 1.3, "remaining": 2})
	assert_almost_eq(Combat.effective_attack(s, atk, foe, false), before * 1.3, 0.01, "実効攻撃力が×1.3")

func test_no_mods_is_regression() -> void:
	# 状態補正が無ければ mul=1.0・add=0＝従来の計算と一致（回帰防止）。
	var s := _state()
	var u := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 30)
	s.add_unit(u)
	var a := s.status_aggregate(u, "attack")
	assert_almost_eq(float(a["mul"]), 1.0, 0.001, "既定 mul=1.0")
	assert_almost_eq(float(a["add"]), 0.0, 0.001, "既定 add=0")

# --- 表示用一覧（applied / snapshot statuses） ---

func test_applied_returns_only_applying_entries() -> void:
	var ally := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 30)
	var foe := Unit.new(2, 1, Hex.offset_to_axial(5, 2), 3, 8, 30, 30)
	var mods := [
		{"scope": "team", "team": 0, "op": "mul", "target": "both", "value": 1.3, "name": "ホーリーアリア"},
		{"scope": "unit", "unit_id": 2, "op": "add", "target": "attack", "value": 10},
	]
	var ally_list := StatusMod.applied(mods, ally)
	assert_eq(ally_list.size(), 1, "味方に効くエントリだけ返る")
	assert_eq(String(ally_list[0]["name"]), "ホーリーアリア", "表示名を保持する")
	var foe_list := StatusMod.applied(mods, foe)
	assert_eq(foe_list.size(), 1, "個別(unit_id=2)エントリだけ効く")
	assert_eq(String(foe_list[0].get("op", "")), "add", "team0 のバフは敵に効かない")

func test_combat_detail_snapshot_includes_statuses() -> void:
	# 戦闘結果 detail のスナップショットに、その時点で効いていた状態補正一覧が同梱される（戦闘レポート用）。
	var s := _state()
	var ap := Hex.offset_to_axial(2, 2)
	s.add_unit(Unit.new(1, 0, ap, 3, 8, 30, 30))
	s.add_unit(Unit.new(2, 1, Hex.neighbor(ap, 0), 3, 8, 30, 30))
	s.add_status_mod({"scope": "team", "team": 0, "owner_team": 0, "op": "mul", "target": "both", "value": 1.3, "remaining": 2, "name": "ホーリーアリア"})
	var d: Dictionary = s.attack(1, 2)["detail"]
	var a_statuses: Array = d["attacker"]["statuses"]
	assert_eq(a_statuses.size(), 1, "攻撃側(team0)にバフ1件")
	assert_eq(String(a_statuses[0]["name"]), "ホーリーアリア", "表示名まで届く")
	assert_eq((d["defender"]["statuses"] as Array).size(), 0, "防御側(team1)には効いていない")

func test_formation_buff_entry_carries_recipe_name() -> void:
	# resolve_formation の buff 経路で、エントリに陣形レシピの表示名が焼き込まれる。
	var s := _state()
	var c := Hex.offset_to_axial(3, 3)
	var members: Array[Unit] = []
	for i in 5:  # ホーリーアリア＝聖職5体の隣接クラスタ
		var u := Unit.new(10 + i, 0, Hex.offset_to_axial(3 + i, 3), 3, 8, 10, 10, 1, "cleric")
		s.add_unit(u)
		members.append(u)
	var options := Formation.available_for(s, members[0])
	assert_gt(options.size(), 0, "ホーリーアリアが成立している前提")
	assert_true(s.resolve_formation(options[0], c).size() > 0, "発動成功")
	var lead := members[0]
	var applied := StatusMod.applied(s._status_mods, lead)
	assert_eq(applied.size(), 1, "バフエントリが積まれる")
	assert_eq(String(applied[0]["name"]), "ホーリーアリア", "レシピ表示名が入る")

# --- 持続満了 ---

func test_duration_expires_after_two_self_turns() -> void:
	# team0 が発動→remaining2。自軍ターン2回ぶん有効、次の次の自軍ターン開始で消える。
	var s := _state()
	var u := Unit.new(1, 0, Hex.offset_to_axial(2, 2), 3, 8, 30, 30)
	s.add_unit(u)
	s.add_status_mod({"scope": "team", "team": 0, "owner_team": 0, "op": "mul", "target": "both", "value": 1.3, "remaining": 2})
	assert_almost_eq(float(s.status_aggregate(u, "attack")["mul"]), 1.3, 0.001, "発動ターン: 有効")
	s.end_turn()  # 0→1（敵ターン開始・owner≠現手番で減らない）
	assert_almost_eq(float(s.status_aggregate(u, "attack")["mul"]), 1.3, 0.001, "敵ターン: 有効のまま")
	s.end_turn()  # 1→0（次の自軍ターン開始・remaining 2→1）
	assert_almost_eq(float(s.status_aggregate(u, "attack")["mul"]), 1.3, 0.001, "次の自軍ターン: まだ有効")
	s.end_turn()  # 0→1
	s.end_turn()  # 1→0（次の次の自軍ターン開始・remaining 1→0で満了）
	assert_almost_eq(float(s.status_aggregate(u, "attack")["mul"]), 1.0, 0.001, "次の次の自軍ターン: 満了")
