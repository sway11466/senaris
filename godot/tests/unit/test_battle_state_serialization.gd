extends GutTest
## BattleState の中断セーブ直列化（to_save_diff/apply_save_diff）テスト。詳細 → doc/tech/gamesystem.md
## セーブは動的差分だけを持ち、盤の器（広さ・地形・勝敗条件・部隊定義・増援の中身）はステージJSONから
## 引き直す。実際のセーブと同じく JSON を通す＝数値の float 化・キーの文字列化まで含めて状態が保たれる
## ことと、ステージ定義がセーブ後に変わったときの振る舞い（居場所を失った駒）を固定する。

## 敵knight の駒番号。id は内部の通し番号＝自動採番（自軍 archer/wagon/搭乗knight の次）。
const BOSS_ID := 4

func _cat() -> Dictionary:
	return {
		"archer": UnitType.from_dict({ "id": "archer", "atk_ground": 8, "defense": 5, "move": 4, "range": "1-2", "max_troops": 8 }),
		"knight": UnitType.from_dict({ "id": "knight", "atk_ground": 12, "defense": 8, "move": 3, "max_troops": 8 }),
		"wagon": UnitType.from_dict({ "id": "wagon", "atk_ground": 0, "defense": 3, "move": 5, "max_troops": 8, "capacity": 4 }),
	}

func _stage_data() -> Dictionary:
	return {
		"cols": 8, "rows": 6, "turn_limit": 15,
		"terrain": ["........", "..PP....", "........", "........", "........", "........"],
		"player": [
			{ "type": "archer", "col": 1, "row": 1 },
			{ "type": "wagon", "col": 2, "row": 1, "passengers": [{ "type": "knight" }] },
		],
		"enemy": [{ "order": 1, "name": "ボス隊", "ai": "ambush", "sight": 4,
			"units": [{ "type": "knight", "col": 6, "row": 1, "actor": "boss" }] }],
		"bases": [{ "col": 4, "row": 3, "team": "player", "kind": "hq", "garrison": [{ "type": "archer", "count": 1 }] }],
		"victory": [{ "type": "defeat_unit", "actor": "boss" }],
		"defeat": [{ "type": "lose_base", "bases": [{ "col": 4, "row": 3 }] }],
	}

func _rich_state(data: Dictionary) -> BattleState:
	var s := StageLoader.build(data, _cat())
	# 進行中の状態を模す：ターン・行動フラグ・損耗・状態補正・撃破記録を仕込む。
	s.current_team = 1
	s.turn_number = 3
	s.unit_by_id(1).troops = 5      # archer 損耗
	s.unit_by_id(1).gain_level(2)  # level 1→3
	s.set_done(1)
	s.mark_engaged(BOSS_ID)
	s.mark_squad_engaged(0)  # 拠点＝部隊の起動フラグ（盤上に駒を持たないので部隊の側に立つ）
	s._moved[1] = true
	s._attacked[BOSS_ID] = true
	s._post_moved[2] = true
	s._spent[1] = 2
	s._defeated[42] = true                 # 盤外で撃破済みの駒
	s._defeated_actors["ghost"] = true     # 名指しの撃破記録（ボス撃破・護衛対象の判定用）
	s.add_status_mod({ "scope": "team", "team": 0, "op": "mul", "target": "attack", "value": 1.3, "owner_team": 0, "remaining": 2 })
	return s

## to_save_diff → JSON → data で組み直した盤に apply_save_diff（実際のセーブ→再開と同じ経路）。
## restore_data 省略＝セーブ時と同じステージ定義で復元。渡せば「セーブ後にステージが変わった」状況。
func _roundtrip(s: BattleState, data: Dictionary, restore_data: Dictionary = {}) -> BattleState:
	var raw := JSON.stringify(s.to_save_diff())
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "直列化 JSON がパースできる")
	var back := StageLoader.build(restore_data if not restore_data.is_empty() else data, _cat())
	back.apply_save_diff(parsed as Dictionary, _cat())
	return back

func _rich_roundtrip() -> BattleState:
	var data := _stage_data()
	return _roundtrip(_rich_state(data), data)

func test_scalars_roundtrip() -> void:
	var s2 := _rich_roundtrip()
	assert_eq(s2.cols, 8)
	assert_eq(s2.rows, 6)
	assert_eq(s2.current_team, 1, "ターンの陣営")
	assert_eq(s2.turn_number, 3)
	assert_eq(s2.turn_limit, 15, "ターン上限はステージJSONから引き直す")
	assert_true(s2.has_sortied("boss"), "この盤に投入された名前つきの駒の記録も復元する（名簿の更新が見る）")

func test_units_roundtrip_with_board_and_growth() -> void:
	var s2 := _rich_roundtrip()
	assert_eq(s2.units().size(), 3, "盤上3体（archer/wagon/敵knight）")
	var a := s2.unit_by_id(1)
	assert_eq(a.type_id, "archer")
	assert_eq(a.team, 0)
	assert_eq(a.pos, Hex.offset_to_axial(1, 1), "位置を保つ")
	assert_eq(a.troops, 5, "損耗を保つ")
	assert_eq(a.level, 3, "レベルを保つ")
	assert_eq(a.unit_attack, 8, "性能は type から再構築")
	assert_eq(a.attack_range, 2)
	var e := s2.unit_by_id(BOSS_ID)
	assert_eq(e.team, 1, "敵の陣営を保つ")
	assert_eq(e.pos, Hex.offset_to_axial(6, 1))

func test_action_flags_roundtrip() -> void:
	var s2 := _rich_roundtrip()
	assert_true(s2.has_moved(1), "移動済みフラグ")
	assert_true(s2.has_attacked(BOSS_ID), "攻撃済みフラグ")
	assert_true(s2._post_moved.has(2), "攻撃後移動フラグ")
	assert_true(s2._done.has(1), "待機フラグ")
	assert_true(s2.is_engaged(BOSS_ID), "AI起動フラグ")
	assert_true(s2.is_squad_engaged(0), "部隊(拠点)のAI起動フラグ＝再開後に眠り直さない")
	assert_eq(int(s2._spent.get(1, 0)), 2, "使った移動コスト")
	assert_true(s2._defeated.has(42), "撃破記録")
	assert_true(s2.is_actor_defeated("ghost"), "名指しの撃破記録（ボス撃破・護衛対象の判定用）")

func test_terrain_comes_from_stage() -> void:
	var s2 := _rich_roundtrip()
	assert_eq(s2.terrain_at(Hex.offset_to_axial(2, 1)), "plateau", "地形はステージJSONから引き直す")
	assert_eq(s2.terrain_at(Hex.offset_to_axial(3, 1)), "plateau")
	assert_eq(s2.terrain_at(Hex.offset_to_axial(0, 0)), "plain", "未指定は平地")

func test_bases_and_garrison_roundtrip() -> void:
	var s2 := _rich_roundtrip()
	assert_eq(s2.bases().size(), 1)
	var b := s2.bases()[0]
	assert_eq(b.hex, Hex.offset_to_axial(4, 3), "拠点位置")
	assert_eq(b.team, 0, "所属")
	assert_eq(b.native_team, 0, "本来の持ち主（ステージJSONから）")
	assert_true(b.is_hq(), "hq 種別（ステージJSONから）")
	assert_eq(b.garrison.size(), 1, "garrison 1体")
	assert_eq(b.garrison[0].type_id, "archer", "garrison の type を再構築")

func test_squads_and_membership_roundtrip() -> void:
	# 部隊定義はステージJSONから、「駒→部隊」の対応はセーブから。落ちると復元後の敵が特性を失う＝別物になる。
	var s2 := _rich_roundtrip()
	assert_eq(s2.squads.size(), 1, "敵の部隊")
	assert_eq(s2.squad_index_of(BOSS_ID), 0, "敵knight は部隊0所属")
	var sq := s2.squad_of(BOSS_ID)
	assert_eq(String(sq.get("ai", "")), "ambush", "部隊の特性id")
	assert_eq(int(sq.get("order", 0)), 1, "行動順")
	assert_eq(int(sq.get("sight", 0)), 4, "部隊ごとのパラメーター上書き")

func test_passengers_roundtrip() -> void:
	var s2 := _rich_roundtrip()
	var riders := s2.passengers(2)  # wagon id=2
	assert_eq(riders.size(), 1, "搭乗1体")
	assert_eq(riders[0].type_id, "knight", "搭乗兵の type")
	assert_eq(riders[0].id, 3, "搭乗兵の id")

func test_status_mods_roundtrip() -> void:
	var s2 := _rich_roundtrip()
	var agg := s2.status_aggregate(s2.unit_by_id(1), "attack")
	assert_almost_eq(float(agg["mul"]), 1.3, 0.001, "team バフが復元され攻撃に係数")

func test_victory_conditions_come_from_stage() -> void:
	var s2 := _rich_roundtrip()
	assert_eq(s2.victory_conditions.size(), 1)
	assert_eq(String(s2.victory_conditions[0]["actor"]), "boss", "ボス撃破条件はステージJSONから引き直す")

func test_defeat_conditions_come_from_stage() -> void:
	var s2 := _rich_roundtrip()
	assert_eq(s2.defeat_conditions.size(), 1)
	assert_eq(String(s2.defeat_conditions[0]["type"]), "lose_base", "防衛対象の敗北条件が復元される")
	var targets: Array = s2.defeat_conditions[0]["bases"]
	assert_eq([int(targets[0]["col"]), int(targets[0]["row"])], [4, 3], "対象の座標まで復元される")

func test_empty_state_roundtrips() -> void:
	# 最小状態（既定値）でも壊れない。
	var s2 := BattleState.new(4, 4)
	var diff: Dictionary = JSON.parse_string(JSON.stringify(BattleState.new(4, 4).to_save_diff()))
	s2.apply_save_diff(diff)
	assert_eq(s2.cols, 4)
	assert_eq(s2.units().size(), 0)
	assert_eq(s2.bases().size(), 0)
	assert_false(s2.has_sortied("boss"), "空の盤なら投入記録も空")

# --- セーブ後にステージ定義が変わったときの復元。仕様 → doc/tech/gamesystem.md §復元して居場所を失った駒 ---

## 盤が縮んで座標が盤外になった駒は盤へ出さない（近くへ寄せない）。
func test_restore_drops_units_off_the_board() -> void:
	var data := _stage_data()
	var s := _rich_state(data)
	var shrunk := _stage_data()
	shrunk["cols"] = 5  # 敵knight(6,1) が盤外になる
	var s2 := _roundtrip(s, data, shrunk)
	assert_null(s2.unit_by_id(BOSS_ID), "盤外の駒は出さない")
	assert_eq(s2.units().size(), 2, "残りの駒（archer/wagon）は出る")

## 地形が変わって移動タイプで入れないマスに立つ駒は出さない。搭乗者も一緒に落ちる。
func test_restore_drops_units_on_impassable_terrain() -> void:
	var data := _stage_data()
	var s := _rich_state(data)
	var diff: Dictionary = JSON.parse_string(JSON.stringify(s.to_save_diff()))
	var back := StageLoader.build(data, _cat())
	back.set_movement({ "foot": { "plateau": "x" } })  # wagon(2,1) の足元 plateau を進入不可に
	back.apply_save_diff(diff, _cat())
	assert_null(back.unit_by_id(2), "入れない地形の駒は出さない")
	assert_true(back.passengers(2).is_empty(), "輸送ごと落ちた搭乗者も出さない")
	assert_not_null(back.unit_by_id(1), "立てる駒は出る")

## 拠点が消えたステージでは、その駐留兵ごと出さない。拠点はステージJSONが正本。
func test_restore_drops_garrison_of_removed_base() -> void:
	var data := _stage_data()
	var s := _rich_state(data)
	var no_base := _stage_data()
	no_base.erase("bases")
	no_base.erase("defeat")  # 消した拠点を守る条件も一緒に消えた想定
	var s2 := _roundtrip(s, data, no_base)
	assert_true(s2.bases().is_empty(), "拠点はステージJSONが正本＝消えたまま")

## ステージ更新で足された拠点はステージ定義のまま出る。駐留兵の id はセーブの駒と衝突しないよう振り直す。
func test_restore_keeps_added_base_and_renumbers_its_garrison() -> void:
	var data := _stage_data()
	var s := _rich_state(data)
	var added := _stage_data()
	added["bases"].append({ "col": 6, "row": 4, "team": "enemy", "garrison": [{ "type": "knight", "count": 1 }] })
	var s2 := _roundtrip(s, data, added)
	assert_eq(s2.bases().size(), 2, "足された拠点はステージ定義のまま出る")
	var b := s2.base_at(Hex.offset_to_axial(6, 4))
	assert_eq(b.team, 1, "初期帰属もステージ定義のまま")
	var used := {}
	for u in s2.units():
		used[u.id] = true
	for p in s2.passengers(2):
		used[p.id] = true
	for gu in s2.base_at(Hex.offset_to_axial(4, 3)).garrison:
		used[gu.id] = true
	assert_false(used.has(b.garrison[0].id), "足された拠点の駐留兵はセーブの駒と id が衝突しない")

## ステージ更新で足されたイベントは、セーブの未発火一覧に無いので出ない（顔ぶれはセーブが正本）。
func test_restore_ignores_added_events() -> void:
	var data := _stage_data()
	var s := _rich_state(data)
	var added := _stage_data()
	added["events"] = [{ "id": "late-wave", "turn": 5, "type": "reinforce", "team": "enemy", "order": 2, "ai": "charge",
		"units": [{ "type": "knight", "col": 7, "row": 5 }] }]
	var s2 := _roundtrip(s, data, added)
	assert_true(s2.pending_events().is_empty(), "足されたイベントは進行中のセーブには現れない")
