extends GutTest
## SaveMigration（中断セーブ v2→v3）のテスト。仕様 → doc/tech/gamesystem.md §版と移行
## v2＝盤の丸ごと直列化。v3＝動的差分（ステージJSONから引き直せるものを落とす）。

const STAGE_PATH := "user://test_migration_stage.json"

## v2 セーブの復元先として使うステージ定義（イベント3つ・拠点1つ）。
const STAGE := {
	"cols": 6, "rows": 4, "turn_limit": 9,
	"player": [{ "type": "fighter", "col": 0, "row": 0 }],
	"bases": [{ "col": 1, "row": 1, "team": "neutral" }],
	"events": [
		{ "id": "w1", "turn": 2, "type": "reinforce", "team": "enemy", "order": 1, "ai": "charge",
			"units": [{ "type": "fighter", "col": 5, "row": 3 }] },
		{ "id": "w2", "turn": 4, "type": "reinforce", "team": "enemy", "order": 2, "ai": "charge",
			"units": [{ "type": "fighter", "col": 5, "row": 3 }] },
		{ "id": "cap", "on": "capture", "col": 1, "row": 1, "team": "player", "type": "talk",
			"once": "village", "dialogue": "taken" },
	],
}

func before_each() -> void:
	var f := FileAccess.open(STAGE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(STAGE))

func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STAGE_PATH))

## v2 の state に入っていた形の未発火イベント（BattleState の旧 _events_to_dicts）。
## hex はターン起点だと Vector2i.MAX、占領起点だと拠点の axial。
func _v2_event(turn: int, team: int, on: String, hex: Vector2i, once: String, label: String) -> Dictionary:
	return { "id": "", "turn": turn, "team": team, "on": on, "hex_q": hex.x, "hex_r": hex.y,
		"once": once, "label": label, "squad": 1, "dialogue": "", "focus": false, "units": [] }

func _v2_record() -> Dictionary:
	return {
		"version": 2,
		"meta": { "campaign_id": "tutorial1-goblin-raid", "stage_id": "st1", "stage_path": STAGE_PATH },
		"state": {
			"cols": 6, "rows": 4, "turn_limit": 9,
			"current_team": 1, "turn_number": 3,
			"terrain": [{ "q": 2, "r": 1, "t": "plateau" }],
			"victory_conditions": [], "defeat_conditions": [],
			"squads": [{ "ai": "charge", "order": 1 }],
			"units": [{ "id": 1, "type": "fighter", "skin": "fighter", "team": 0, "native": 0,
				"recruited": 0, "q": 0, "r": 0, "level": 2, "troops": 5, "max_troops": 8 }],
			"bases": [{ "q": Hex.offset_to_axial(1, 1).x, "r": Hex.offset_to_axial(1, 1).y,
				"team": 0, "native": -1, "kind": "fort", "squad_index": -1,
				"garrison": [{ "id": 7, "type": "fighter", "team": 0, "native": -1, "recruited": -1,
					"q": 0, "r": 0, "level": 1, "troops": 8, "max_troops": 8 }] }],
			"status_mods": [], "passengers": {},
			"moved": [1], "post_moved": [], "attacked": [], "done": [1],
			"engaged": [], "engaged_squads": [], "defeated": [],
			"defeated_actors": [], "sortied_actors": ["hero"],
			"spent": { "1": 2 }, "squad_of": {}, "charges": {},
			# 未発火＝w2（ターン4の増援）と cap（占領イベント）。w1 は発火済みで載っていない。
			"events": [
				_v2_event(4, 1, "", Vector2i.MAX, "", ""),
				_v2_event(1, 0, "capture", Hex.offset_to_axial(1, 1), "village", ""),
			],
		},
	}

func test_current_version_passes_through() -> void:
	var got := SaveMigration.migrate({ "version": SaveStore.VERSION, "meta": { "a": 1 }, "state": { "b": 2 } })
	assert_eq(got, { "meta": { "a": 1 }, "state": { "b": 2 } }, "現行版はそのまま")

func test_unknown_version_is_rejected() -> void:
	assert_eq(SaveMigration.migrate({ "version": 1, "meta": {}, "state": {} }), {}, "変換を持たない版は読まない")
	assert_push_warning("変換を持たない版")

func test_v3_start_time_is_unknown() -> void:
	var got := SaveMigration.migrate({ "version": 3, "meta": { "stage_id": "a" }, "state": { "turn_number": 2 } })
	var meta: Dictionary = got["meta"]
	assert_eq(int(meta["started_at"]), 0, "旧セーブは開始時刻を持たない＝不明（所要時間を測れない回）")
	assert_eq(String(meta["stage_id"]), "a", "他のメタはそのまま")
	assert_eq(got["state"], { "turn_number": 2 }, "盤の差分は触らない")

func test_v2_climbs_to_current_version() -> void:
	var meta: Dictionary = SaveMigration.migrate(_v2_record())["meta"]
	assert_true(meta.has("started_at"), "v2 は v3 を経て現行版まで上がる")

func test_v2_drops_stage_side_keys() -> void:
	var got := SaveMigration.migrate(_v2_record())
	var state: Dictionary = got["state"]
	for key in ["cols", "rows", "turn_limit", "terrain", "victory_conditions", "defeat_conditions", "squads", "events"]:
		assert_false(state.has(key), "ステージJSONから引き直すものは落とす: %s" % key)

func test_v2_keeps_dynamic_state() -> void:
	var state: Dictionary = SaveMigration.migrate(_v2_record())["state"]
	assert_eq(int(state["current_team"]), 1)
	assert_eq(int(state["turn_number"]), 3)
	assert_eq((state["units"] as Array).size(), 1, "盤上の駒はそのまま")
	assert_eq(state["moved"], [1])
	assert_eq(state["sortied_actors"], ["hero"])
	assert_eq(int(state["spent"]["1"]), 2)

func test_v2_bases_become_diff_form() -> void:
	var state: Dictionary = SaveMigration.migrate(_v2_record())["state"]
	var b: Dictionary = state["bases"][0]
	assert_eq(int(b["team"]), 0, "現在の帰属を保つ")
	assert_eq((b["garrison"] as Array).size(), 1, "駐留兵を保つ")
	assert_false(b.has("native"), "native/kind/squad_index はステージJSONから引き直す")
	assert_false(b.has("kind"))
	assert_false(b.has("squad_index"))

func test_v2_events_become_fired_ids() -> void:
	# 旧セーブは未発火を丸ごと持つ（id なし）。今のステージJSONと内容で突き合わせて未発火を
	# 消し込み、残り＝発火済みの id として記録する（v3 は発火済みの側を持つ）。
	var state: Dictionary = SaveMigration.migrate(_v2_record())["state"]
	assert_eq(state["fired_events"], ["w1"], "未発火(w2/cap)に突き合わなかった w1 が発火済み")

func test_v2_event_missing_from_stage_is_ignored() -> void:
	var record := _v2_record()
	record["state"]["events"].append(_v2_event(7, 1, "", Vector2i.MAX, "", ""))  # 今のステージに無い
	var state: Dictionary = SaveMigration.migrate(record)["state"]
	assert_eq(state["fired_events"], ["w1"], "突き合わないイベントは無視（発火済みの算出に影響しない）")
	assert_push_warning("見当たらない")

func test_v2_fills_digest_from_demo_table() -> void:
	# 体験版の印の表（データ同梱）からステージIDで引いて埋める。今のステージJSONからは計算しない。
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveMigration.DEMO_DIGESTS_PATH))
	var got := SaveMigration.migrate(_v2_record())
	assert_eq(String(got["meta"]["stage_digest"]), String(table["tutorial1-goblin-raid/st1"]),
		"表の印がそのまま meta に入る")

func test_v2_without_table_entry_leaves_digest_absent() -> void:
	var record := _v2_record()
	record["meta"]["campaign_id"] = "no-such-campaign"
	var got := SaveMigration.migrate(record)
	assert_false((got["meta"] as Dictionary).has("stage_digest"), "表に無ければ印なし＝不明として通知側へ倒す")

func test_v2_migrated_save_restores_on_the_stage() -> void:
	# 変換した差分が実際にステージ定義の上へ被さる（v2 セーブ→v3 復元の通し）。
	var got := SaveMigration.migrate(_v2_record())
	var s := SaveRestore.restore(STAGE_PATH, got["state"])
	assert_not_null(s, "復元できる")
	assert_eq(s.turn_number, 3, "ターンを復元")
	assert_eq(s.units().size(), 1, "駒はセーブの顔ぶれ")
	assert_eq(s.base_at(Hex.offset_to_axial(1, 1)).team, 0, "拠点の帰属はセーブから")
	assert_eq(s.base_at(Hex.offset_to_axial(1, 1)).native_team, Base.NEUTRAL, "本来の持ち主はステージJSONから")
	assert_eq(s.pending_events().size(), 2, "未発火イベントだけ残る")
	assert_eq(s.turn_limit, 9, "ターン上限はステージJSONから")
