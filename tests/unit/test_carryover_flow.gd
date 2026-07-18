extends GutTest
## 継承(carryover)の受け渡しフロー結線テスト。main.gd が勝利時／ステージ開始時に呼ぶ手順を
## 同じ公開APIで再現し、S1勝利→保存→S2開始→配置 が繋がることを固定する。詳細 → doc/gdd/map.md
## （main.gd 自体は Node2D/シーン依存で単体テスト外＝ここでロジック経路を担保する。）

const PATH := "user://test_carryover_flow.json"

func before_each() -> void:
	_remove()

func after_all() -> void:
	_remove()

func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func _catalog() -> Dictionary:
	return {
		"archer": UnitType.from_dict({ "id": "archer", "atk_ground": 8, "defense": 5, "move": 4, "range": "1-2", "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 8 }),
	}

func test_win_saves_survivors_and_next_stage_inherits_them() -> void:
	var cat := _catalog()
	# --- S1 を組む（自軍2体）。
	var s1 := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "archer", "col": 0, "row": 0 },
		{ "type": "knight", "col": 1, "row": 0 },
	] }, cat)
	# --- 戦闘の結果を模す：archer が損耗（troops 8→4・経験 +2）。
	var archer := s1.unit_by_id(1)
	archer.troops = 4
	archer.add_experience(2)  # level 1→3

	# --- main の勝利フック相当：生存自軍を保存。
	var store := RosterStore.new(PATH)
	store.save_roster("camp", StageLoader.survivors_snapshot(s1))

	# --- main のステージ開始フック相当：別インスタンスで読み直し、S2(carryover)に渡す。
	var carried := RosterStore.new(PATH).load_roster("camp")
	var s2 := StageLoader.build({ "cols": 8, "rows": 6, "roster": "carryover", "carryover_slots": [
		{ "col": 2, "row": 2 }, { "col": 2, "row": 3 },
	] }, cat, {}, carried)

	# --- S2 に S1 の生存者が損耗・成長つきで並ぶ。
	assert_eq(s2.units().size(), 2, "生存2体が S2 に継承される")
	var a2 := s2.unit_at(Hex.offset_to_axial(2, 2))
	assert_eq(a2.type_id, "archer")
	assert_eq(a2.troops, 4, "損耗を持ち越す（回復しない）")
	assert_eq(a2.level, 3, "経験を持ち越す")
	assert_eq(a2.unit_attack, 8, "性能は type から再構築")
	var k2 := s2.unit_at(Hex.offset_to_axial(2, 3))
	assert_eq(k2.type_id, "knight")
	assert_eq(k2.troops, 8, "無傷の駒は満員のまま")

func test_retry_uses_previous_win_snapshot_not_current_run() -> void:
	# 保存は勝利時のみ＝S2で負けて作り直しても、S2開始時の carried は「S1勝利時の戦力」で不変。
	var cat := _catalog()
	var s1 := StageLoader.build({ "cols": 8, "rows": 6, "player": [
		{ "type": "knight", "col": 0, "row": 0 },
	] }, cat)
	s1.unit_by_id(1).troops = 5  # S1 を 兵5 で勝ち抜けた
	var store := RosterStore.new(PATH)
	store.save_roster("camp", StageLoader.survivors_snapshot(s1))

	# S2 開始（1回目）＝兵5を継承。
	var carried1 := RosterStore.new(PATH).load_roster("camp")
	var s2a := StageLoader.build({ "cols": 8, "rows": 6, "roster": "carryover",
		"carryover_slots": [{ "col": 1, "row": 1 }] }, cat, {}, carried1)
	assert_eq(s2a.unit_at(Hex.offset_to_axial(1, 1)).troops, 5)
	# S2 で敗北（保存しない）→ 再挑戦。スナップショットは触れていない。
	var carried2 := RosterStore.new(PATH).load_roster("camp")
	var s2b := StageLoader.build({ "cols": 8, "rows": 6, "roster": "carryover",
		"carryover_slots": [{ "col": 1, "row": 1 }] }, cat, {}, carried2)
	assert_eq(s2b.unit_at(Hex.offset_to_axial(1, 1)).troops, 5, "再挑戦も S1勝利時の兵5からやり直せる")
