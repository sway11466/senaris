extends GutTest
## SaveMigration（中断セーブ v2→v3）のテスト。仕様 → doc/tech/gamesystem.md §版と移行
## v2＝盤の丸ごと直列化。v3＝動的差分（ステージJSONから引き直せるものを落とす）。

const STAGE_PATH := "user://test_migration_stage.json"

## v2 セーブの復元先として使うステージ定義（イベント3つ・拠点1つ）。
## 地形は相棒のファイル（<ステージ>.terrain.json）に持つ＝本体には書かない。
const STAGE_TERRAIN := { "terrain": ["......", "......", "......", "......"] }

const STAGE := {
	"turn_limit": 9,
	"player": [ { "units": [{ "type": "fighter", "col": 0, "row": 0 }] } ],
	"bases": [{ "col": 1, "row": 1, "team": "neutral" }],
	"events": [
		{ "id": "w1", "turn": 2, "type": "reinforce", "entry": "fade",
			"enemy": [{ "order": 1, "ai": "charge", "units": [{ "type": "fighter", "col": 5, "row": 3 }] }] },
		{ "id": "w2", "turn": 4, "type": "reinforce", "entry": "fade",
			"enemy": [{ "order": 2, "ai": "charge", "units": [{ "type": "fighter", "col": 5, "row": 3 }] }] },
		{ "id": "cap", "on": "capture", "col": 1, "row": 1, "team": "player", "type": "talk",
			"once": "village", "dialogue": "taken", "name": "ui.test.event_name" },
	],
}

func before_each() -> void:
	var f := FileAccess.open(STAGE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(STAGE))
	var t := FileAccess.open(StageLoader.terrain_path(STAGE_PATH), FileAccess.WRITE)
	t.store_string(JSON.stringify(STAGE_TERRAIN))

func after_all() -> void:
	for p in [STAGE_PATH, StageLoader.terrain_path(STAGE_PATH)]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

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
	assert_eq(int((got["state"] as Dictionary)["turn_number"]), 2, "盤の差分は触らない")
	assert_eq((got["state"] as Dictionary)["squad_of"], {}, "所属の付け替えは空のまま（味方部隊のずらし幅0）")

## v4（味方は部隊に属さない）→ v5。所属は部隊の並び順で持つので、味方部隊のぶん敵の index が
## ずれる。味方の駒はどの部隊に居たかを v4 が持たない＝最初の味方部隊に入れる。
func test_v4_shifts_squads_and_puts_allies_in_the_first_party() -> void:
	var record := { "version": 4, "meta": { "stage_path": STAGE_PATH, "started_at": 0 },
		"state": { "units": [{ "id": 1, "team": 0 }, { "id": 2, "team": 1 }],
			"squad_of": { "2": 0 }, "engaged_squads": [0] } }
	var state: Dictionary = SaveMigration.migrate(record)["state"]
	var squad_of: Dictionary = state["squad_of"]
	assert_eq(int(squad_of["2"]), 1, "敵の所属は味方部隊のぶん後ろへずれる")
	assert_eq(int(squad_of["1"]), 0, "味方の駒は最初の味方部隊へ")
	assert_eq(state["engaged_squads"], [1], "拠点の起動フラグも同じだけずらす")

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

func test_v2_renames_stage_id_after_the_digest_lookup() -> void:
	# 印の表は旧IDのまま据え置き＝先に読み替えると引けなくなる。引いた後に新IDへ直す。
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveMigration.DEMO_DIGESTS_PATH))
	var meta: Dictionary = SaveMigration.migrate(_v2_record())["meta"]
	assert_eq(String(meta["stage_id"]), "goblin-raid-st1", "ステージIDは改名後の名前で返る")
	assert_eq(String(meta["stage_digest"]), String(table["tutorial1-goblin-raid/st1"]), "印は旧IDで引けている")

func test_rename_table_points_at_stages_that_exist() -> void:
	# 表の打ち間違いはセーブの復元が失敗して初めて分かるので、実在を先に見る。
	for old_path in StageRenames.PATHS:
		var new_path := String(StageRenames.PATHS[old_path])
		assert_file_exists(new_path)
		assert_file_does_not_exist(String(old_path))

func test_renamed_stage_is_read_in_the_new_names() -> void:
	# 改名前に保存した現行版のセーブ（ファイル名・ステージID・翻訳キーが旧名）。
	var got := SaveMigration.migrate({ "version": SaveStore.VERSION, "state": { "turn_number": 2 },
		"meta": { "campaign_id": "tutorial1-goblin-raid", "stage_id": "st2",
			"stage_path": "res://data/stages/tutorial1-goblin-raid/st2.json",
			"campaign_title": "t1.title", "stage_title": "t1.st2.title" } })
	var meta: Dictionary = got["meta"]
	assert_eq(String(meta["stage_path"]), "res://data/stages/tutorial1-goblin-raid/goblin-raid-st2.json",
		"ステージJSONは新しいファイル名で開き直す")
	assert_eq(String(meta["stage_id"]), "goblin-raid-st2")
	assert_eq(String(meta["campaign_title"]), "goblin-raid.title", "一覧の見出しの翻訳キーも新しい語へ")
	assert_eq(String(meta["stage_title"]), "goblin-raid.st2.title")

func test_stage_outside_the_rename_table_is_untouched() -> void:
	var got := SaveMigration.migrate({ "version": SaveStore.VERSION, "state": {},
		"meta": { "campaign_id": "debug-ai", "stage_id": "charge",
			"stage_path": "res://data/stages/debug-ai/charge.json", "stage_title": "突撃" } })
	var meta: Dictionary = got["meta"]
	assert_eq(String(meta["stage_path"]), "res://data/stages/debug-ai/charge.json", "改名していないものは素通し")
	assert_eq(String(meta["stage_id"]), "charge")
	assert_eq(String(meta["stage_title"]), "突撃")

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
	assert_false(s.base_at(Hex.offset_to_axial(1, 1)).is_hq(), "本拠地の印はステージJSONから（セーブには無い）")
	assert_eq(s.pending_events().size(), 2, "未発火イベントだけ残る")
	assert_eq(s.turn_limit, 9, "ターン上限はステージJSONから")


## v6: 駒を指す語彙を分けた版。ハンドルのキーが "id" → "handle"、勝敗条件の記録が
## defeated_actors → defeated_unit_ids、状態補正の "unit_id"(int) → "handle"。
## actor を持つ駒には unit_id を無条件で複製する（旧セーブでは同じ値が両方を兼ねていた）。
func _v5_record() -> Dictionary:
	return {
		"version": 5,
		"meta": { "campaign_id": "tutorial1-goblin-raid", "stage_id": "st1", "stage_path": STAGE_PATH },
		"state": {
			"units": [{ "id": 1, "type": "fighter", "team": 0, "actor": "hero" },
				{ "id": 2, "type": "goblin", "team": 1 }],
			"passengers": { "1": [{ "id": 5, "type": "knight", "actor": "rider" }] },
			"bases": [{ "garrison": [{ "id": 7, "type": "archer", "actor": "elf" }] }],
			"status_mods": [{ "scope": "unit", "unit_id": 2, "op": "add", "target": "both", "value": 10 }],
			"defeated_actors": ["boss"], "sortied_actors": ["hero"],
		},
	}

func test_v5_to_v6_renames_handle_and_copies_unit_id() -> void:
	var got := SaveMigration.migrate(_v5_record())
	var state: Dictionary = got["state"]
	var u: Dictionary = state["units"][0]
	assert_eq(int(u["handle"]), 1, "ハンドルのキーは handle")
	assert_false(u.has("id"), "古いキーは残さない")
	assert_eq(String(u["unit_id"]), "hero", "actor を unit_id に複製＝再開後もボス撃破が解ける")
	assert_eq(String(u["actor"]), "hero", "actor はそのまま残る")
	assert_false((state["units"][1] as Dictionary).has("unit_id"), "名前のない駒には足さない")

func test_v5_to_v6_covers_passengers_and_garrison() -> void:
	var state: Dictionary = SaveMigration.migrate(_v5_record())["state"]
	var p: Dictionary = (state["passengers"] as Dictionary)["1"][0]
	assert_eq(int(p["handle"]), 5, "搭乗者も直す")
	assert_eq(String(p["unit_id"]), "rider")
	var g: Dictionary = (state["bases"][0] as Dictionary)["garrison"][0]
	assert_eq(int(g["handle"]), 7, "拠点の控えも直す")
	assert_eq(String(g["unit_id"]), "elf")

func test_v5_to_v6_renames_records_and_status_mods() -> void:
	var state: Dictionary = SaveMigration.migrate(_v5_record())["state"]
	assert_eq(state["defeated_unit_ids"], ["boss"], "撃破の記録は unit_id 側へ")
	assert_false(state.has("defeated_actors"))
	assert_eq(state["sortied_actors"], ["hero"], "出撃の記録は actor のまま（名簿の話）")
	var m: Dictionary = state["status_mods"][0]
	assert_eq(int(m["handle"]), 2, "状態補正が持つのは駒のハンドル")
	assert_false(m.has("unit_id"), "String の unit_id と同じキー名で残さない")
