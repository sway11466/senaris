extends GutTest
## 継承(carryover)の受け渡しフロー結線テスト。main.gd が勝利時／ステージ開始時に呼ぶ手順を
## 同じ公開APIで再現し、S1勝利→保存→S2開始→配置 が繋がることを固定する。詳細 → doc/gdd/campaigns.md
## （main.gd 自体は Node2D/シーン依存で単体テスト外＝ここでロジック経路を担保する。）

const DIR := "user://test_carryover_flow"
const PATH := "user://test_carryover_flow/roster.json"

func before_each() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

func after_all() -> void:
	_clean()

func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

func _catalog() -> Dictionary:
	return {
		"archer": UnitType.from_dict({ "id": "archer", "atk_ground": 8, "defense": 5, "move": 4, "range": "1-2", "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 8 }),
	}

func test_win_saves_survivors_and_next_stage_inherits_them() -> void:
	var cat := _catalog()
	# --- S1 を組む（自軍2体）。
	var s1 := StageLoader.build({ "cols": 8, "rows": 6, "player": [ { "units": [
		{ "type": "archer", "col": 0, "row": 0, "actor": "c.archer", "supply": "join" },
		{ "type": "knight", "col": 1, "row": 0, "actor": "c.knight", "supply": "join" },
	] } ] }, cat)  # 名簿に載るのは actor を持つ駒だけ（join＝初登場なので配給）
	# --- 戦闘の結果を模す：archer が損耗（troops 8→4・Lv +2）。
	var archer := s1.unit_by_handle(1)
	archer.troops = 4
	archer.gain_level(2)  # level 1→3

	# --- main の勝利フック相当：生存自軍を保存。
	var store := RosterStore.new(PATH)
	store.save_roster("camp", "s1", RosterService.update_after_clear([], s1))

	# --- main のステージ開始フック相当：別インスタンスで読み直し、S2(carryover)に渡す。
	var carried := RosterStore.new(PATH).load_roster("camp", "s1")
	var s2 := StageLoader.build({ "cols": 8, "rows": 6, "player": [ { "units": [
		{ "col": 2, "row": 2, "actor": "c.archer" }, { "col": 2, "row": 3, "actor": "c.knight" },
	] } ] }, cat, {}, carried)

	# --- S2 に S1 の生存者が損耗・成長つきで並ぶ。
	assert_eq(s2.units().size(), 2, "生存2体が S2 に継承される")
	var a2 := s2.unit_at(Hex.offset_to_axial(2, 2))
	assert_eq(a2.type_id, "archer")
	assert_eq(a2.troops, 4, "損耗を持ち越す（回復しない）")
	assert_eq(a2.level, 3, "レベルを持ち越す")
	assert_eq(a2.unit_attack, 8, "性能は type から再構築")
	var k2 := s2.unit_at(Hex.offset_to_axial(2, 3))
	assert_eq(k2.type_id, "knight")
	assert_eq(k2.troops, 8, "無傷の駒は満員のまま")

func test_retry_uses_previous_win_snapshot_not_current_run() -> void:
	# 保存は勝利時のみ＝S2で負けて作り直しても、S2開始時の carried は「S1勝利時の戦力」で不変。
	var cat := _catalog()
	var s1 := StageLoader.build({ "cols": 8, "rows": 6, "player": [ { "units": [
		{ "type": "knight", "col": 0, "row": 0, "actor": "c.knight", "supply": "join" },
	] } ] }, cat)
	s1.unit_by_handle(1).troops = 5  # S1 を 兵5 で勝ち抜けた
	var store := RosterStore.new(PATH)
	store.save_roster("camp", "s1", RosterService.update_after_clear([], s1))

	# S2 開始（1回目）＝兵5を継承。
	var carried1 := RosterStore.new(PATH).load_roster("camp", "s1")
	var s2a := StageLoader.build({ "cols": 8, "rows": 6,
		"player": [ { "units": [{ "col": 1, "row": 1, "actor": "c.knight" }] } ] }, cat, {}, carried1)
	assert_eq(s2a.unit_at(Hex.offset_to_axial(1, 1)).troops, 5)
	# S2 で敗北（保存しない）→ 再挑戦。スナップショットは触れていない。
	var carried2 := RosterStore.new(PATH).load_roster("camp", "s1")
	var s2b := StageLoader.build({ "cols": 8, "rows": 6,
		"player": [ { "units": [{ "col": 1, "row": 1, "actor": "c.knight" }] } ] }, cat, {}, carried2)
	assert_eq(s2b.unit_at(Hex.offset_to_axial(1, 1)).troops, 5, "再挑戦も S1勝利時の兵5からやり直せる")

func test_replaying_earlier_stage_keeps_later_snapshot() -> void:
	# S1→S2 と進んだあと S1 をやり直しても、S2 クリア後の控えは変わらない。
	# S1 の開始は「S1 の引き継ぎ元」の控え（ここでは無し＝join で配給）から＝S2 の育ちを持ち込まない。
	var cat := _catalog()
	var store := RosterStore.new(PATH)
	# S1 初回クリア：knight 兵5。
	var s1 := StageLoader.build({ "cols": 8, "rows": 6, "player": [ { "units": [
		{ "type": "knight", "col": 0, "row": 0, "actor": "c.knight", "supply": "join" },
	] } ] }, cat)
	s1.unit_by_handle(1).troops = 5
	store.save_roster("camp", "s1", RosterService.update_after_clear([], s1))
	# S2 クリア：S1 の控えで始め、Lv+2・兵3 で勝ち抜けた。
	var s2 := StageLoader.build({ "cols": 8, "rows": 6,
		"player": [ { "units": [{ "col": 1, "row": 1, "actor": "c.knight" }] } ] }, cat, {}, store.load_roster("camp", "s1"))
	var k2 := s2.unit_at(Hex.offset_to_axial(1, 1))
	assert_eq(k2.troops, 5, "S2 は S1 の控えで始まる")
	k2.gain_level(2)
	k2.troops = 3
	store.save_roster("camp", "s2", RosterService.update_after_clear(store.load_roster("camp", "s1"), s2))
	# S1 をやり直す：引き継ぎ元が無いので配給＝初回と同じ Lv1・満員で始まる。
	var s1_again := StageLoader.build({ "cols": 8, "rows": 6, "player": [ { "units": [
		{ "type": "knight", "col": 0, "row": 0, "actor": "c.knight", "supply": "join" },
	] } ] }, cat, {}, [])
	var k1 := s1_again.unit_by_handle(1)
	assert_eq(k1.level, 1, "やり直しの S1 は初回と同じ状態で始まる")
	assert_eq(k1.troops, 8)
	k1.troops = 7
	store.save_roster("camp", "s1", RosterService.update_after_clear([], s1_again))
	# S1 の控えは書き換わり、S2 の控えはそのまま。
	var reloaded := RosterStore.new(PATH)
	assert_eq(reloaded.load_roster("camp", "s1")[0]["troops"], 7, "やり直した S1 の控えは新しい結果")
	assert_eq(reloaded.load_roster("camp", "s2")[0]["troops"], 3, "先の S2 の控えは変わらない")
	assert_eq(reloaded.load_roster("camp", "s2")[0]["level"], 3, "S2 で育った Lv も残る")
