extends GutTest
## 敵AIはプレイヤー側の陣形スキル・ユニットスキルの効果を読む（doc/gdd/ai.md 基本方針）。
## 戦果・仕留められる敵の計算は、相手の状態補正・地帯を実際の戦闘と同じく数える。
## シールドを数えることは test_shield.gd の受け持ち。

var _brain: TraitBrain

func before_each() -> void:
	_brain = TraitBrain.new()
	_brain.presets = AiCatalog.load_default()

## 睨み合い(standoff)の撃ち手を1体置いた盤。撃ち手は (5,1)・射程2〜5・その場から撃てる。
func _standoff_board() -> Dictionary:
	var s := BattleState.new(16, 3)
	s.current_team = 1
	s.squads.append({ "ai": "standoff", "order": 1 })
	var caster := _unit(10, 1, 5, 1)
	caster.move = 0
	caster.min_range = 2
	caster.attack_range = 5
	s.add_unit(caster)
	s.assign_squad(caster.handle, 0)
	return { "s": s, "caster": caster }

func _unit(id: int, team: int, col: int, row: int) -> Unit:
	var u := Unit.new(id, team, Hex.offset_to_axial(col, row), 3, 8, 20, 10)
	u.move_type = "foot"
	return u

## 同じ性能・同じ距離のプレイヤーの駒を2体置く（(7,1) と (3,1)＝撃ち手から盤上距離2）。
func _two_targets(s: BattleState) -> Array[Unit]:
	var a := _unit(1, 0, 7, 1)
	var b := _unit(2, 0, 3, 1)
	s.add_unit(a)
	s.add_unit(b)
	return [a, b]

func test_ai_avoids_the_target_with_a_player_defense_buff() -> void:
	var f := _standoff_board()
	var s: BattleState = f["s"]
	var t := _two_targets(s)
	s.add_status_mod({
		"scope": "unit", "handle": t[0].handle, "op": "mul", "target": "defense",
		"value": 1.5, "kind": StatusMod.KIND_BUFF, "owner_team": 0, "remaining": 1,
	})
	assert_lt(Combat.casualties(s, f["caster"], t[0]), Combat.casualties(s, f["caster"], t[1]),
		"前提: 防御バフの掛かった駒のほうが削れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, t[1].handle, "バフを読んで、より削れる素の駒を撃つ")

func test_ai_prefers_the_target_with_a_player_debuff() -> void:
	var f := _standoff_board()
	var s: BattleState = f["s"]
	var t := _two_targets(s)
	s.add_status_mod({
		"scope": "unit", "handle": t[0].handle, "op": "add", "target": "defense",
		"value": -5.0, "kind": StatusMod.KIND_DEBUFF, "owner_team": 1, "remaining": 1,
	})
	assert_gt(Combat.casualties(s, f["caster"], t[0]), Combat.casualties(s, f["caster"], t[1]),
		"前提: 防御デバフの掛かった駒のほうが削れる")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, t[0].handle, "デバフを読んで、弱った駒を撃つ")

func test_ai_avoids_the_target_inside_a_pierce_immune_zone() -> void:
	var f := _standoff_board()
	var s: BattleState = f["s"]
	var caster: Unit = f["caster"]
	caster.pierce = 0.5  # 魔法兵＝防御半減。結界の中では効かない
	var t := _two_targets(s)
	s.add_status_mod({
		"scope": "zone", "team": 0, "q": t[0].pos.x, "r": t[0].pos.y, "radius": 0,
		"op": "add", "target": "defense", "value": 0.0, "pierce_immune": true,
		"kind": StatusMod.KIND_BUFF, "owner_team": 0, "remaining": 1,
	})
	assert_true(s.pierce_immune(t[0]), "前提: 片方だけが結界の中")
	assert_lt(Combat.casualties(s, caster, t[0]), Combat.casualties(s, caster, t[1]),
		"前提: 結界の中の駒のほうが削れない")
	var a := _brain.next_action(s, 1)
	assert_eq(a.kind, AiAction.Kind.ATTACK)
	assert_eq(a.target_id, t[1].handle, "地帯を読んで、貫通の効く駒を撃つ")
