extends GutTest
## MapEditorDoc（tools/map_editor/map_editor_doc.gd）のテスト。
## マップエディタの入出力＝「読み込んだ stage.json を編集しても、会話などの非編集キーを失わず、
## StageLoader が読める JSON を書き出せる」ことを守る。

const SAMPLE := """
{
  "turn_limit": 30,
  "name": "sample",
  "cols": 6,
  "rows": 4,
  "terrain": [
    "..FF..",
    "......",
    "..CC..",
    "......"
  ],
  "player": [
    { "type": "fighter", "col": 1, "row": 1 }
  ],
  "enemy": [
    { "name": "本隊", "ai": "guard", "sight": 3, "units": [
      { "skin": "goblin", "col": 4, "row": 1 },
      { "id": 99, "skin": "hobgoblin", "col": 4, "row": 2 }
    ] }
  ],
  "bases": [
    { "col": 5, "row": 3, "team": "enemy", "ai": "charge",
      "garrison": [ { "skin": "goblin", "count": 4 } ] }
  ],
  "victory": [
    { "type": "defeat_unit", "unit_id": 99 }
  ],
  "dialogue": {
    "intro": [
      { "speaker": "char.cap.name", "skin": "fighter", "text": "t1.st1.intro.1" }
    ],
    "outro": [
      { "speaker": "char.cap.name", "skin": "fighter", "text": "t1.st1.outro.1" }
    ]
  }
}
"""


func _roundtrip(text: String) -> Dictionary:
	var doc := MapEditorDoc.from_text(text)
	assert_not_null(doc, "パースできること")
	return JSON.parse_string(doc.to_text())


# --- 入出力 ---


func test_roundtrip_keeps_all_data() -> void:
	var out := _roundtrip(SAMPLE)
	var src: Dictionary = JSON.parse_string(SAMPLE)
	assert_eq_deep(out, src)  # 編集なしの読込→保存で内容が変わらない


func test_roundtrip_keeps_dialogue_untouched() -> void:
	var out := _roundtrip(SAMPLE)
	var src: Dictionary = JSON.parse_string(SAMPLE)
	assert_eq_deep(out["dialogue"], src["dialogue"])


func test_output_starts_with_turn_limit_and_ints_have_no_decimal() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	var text := doc.to_text()
	assert_string_contains(text.split("\n")[1], "\"turn_limit\": 30")  # 先頭キー＝手書き慣習
	assert_false(text.contains("30.0"), "JSON由来のfloatを整数表記で書き戻す")


func test_from_text_rejects_broken_json() -> void:
	assert_null(MapEditorDoc.from_text("{ broken"))


func test_empty_optional_keys_are_not_emitted() -> void:
	var doc := MapEditorDoc.new_stage(4, 3)
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_false(out.has("bases"), "空のbasesは書かない")
	assert_false(out.has("victory"), "空のvictoryは書かない")
	assert_true(out.has("player"))
	assert_true(out.has("enemy"))


func test_empty_optional_key_from_source_is_preserved() -> void:
	# units.json 等は "bases": [] を明示している＝往復で消してはいけない
	var doc := MapEditorDoc.from_text("{ \"turn_limit\": 30, \"cols\": 4, \"rows\": 3, \"bases\": [] }")
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_true(out.has("bases"))
	assert_eq(out["bases"], [])


# --- 地形 ---


func test_terrain_paint_and_read() -> void:
	var doc := MapEditorDoc.new_stage(4, 3)
	doc.set_terrain_char(2, 1, "F")
	assert_eq(doc.terrain_char(2, 1), "F")
	assert_eq(doc.terrain_char(0, 0), ".")
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_eq(out["terrain"][1], "..F.")


func test_resize_pads_and_crops_terrain() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	doc.resize(8, 2)
	assert_eq(doc.terrain_char(2, 0), "F")  # 既存は残る
	assert_eq(doc.terrain_char(7, 0), ".")  # 拡張分は平地
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_eq(out["terrain"].size(), 2)
	assert_eq(String(out["terrain"][0]).length(), 8)


func test_resize_drops_out_of_range_entities() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	var dropped := doc.resize(4, 4)  # col4以上の敵2体・col5の拠点が範囲外
	assert_eq(dropped, 3)
	assert_eq(doc.data["enemy"][0]["units"].size(), 0)
	assert_eq(doc.data["bases"].size(), 0)
	assert_eq(doc.data["player"].size(), 1)  # 範囲内は残る


# --- 見た目レイヤー（terrain_skins） ---


func test_terrain_skin_set_overwrite_and_clear() -> void:
	var doc := MapEditorDoc.new_stage(4, 3)
	doc.set_terrain_skin(2, 1, "wall_stone1")
	assert_eq(doc.terrain_skin(2, 1), "wall_stone1")
	doc.set_terrain_skin(2, 1, "wall")
	assert_eq(doc.data["terrain_skins"].size(), 1, "同じマスは上書き＝重複を作らない")
	assert_eq(doc.terrain_skin(2, 1), "wall")
	doc.set_terrain_skin(2, 1, "")
	assert_eq(doc.terrain_skin(2, 1), "", "空文字は指定の削除＝type の既定に戻る")
	assert_eq(doc.data["terrain_skins"].size(), 0)


func test_terrain_skin_ignores_out_of_board_and_stays_unset() -> void:
	var doc := MapEditorDoc.new_stage(4, 3)
	doc.set_terrain_skin(9, 9, "wall_stone1")
	assert_eq(doc.terrain_skin(9, 9), "")
	assert_false(JSON.parse_string(doc.to_text()).has("terrain_skins"), "空なら書き出さない")


func test_terrain_skin_map_for_board() -> void:
	var doc := MapEditorDoc.new_stage(4, 3)
	doc.set_terrain_skin(1, 2, "fort_town1")
	assert_eq(doc.terrain_skin_map(), { Vector2i(1, 2): "fort_town1" })


func test_terrain_skins_are_emitted_sorted_row_major() -> void:
	var doc := MapEditorDoc.new_stage(4, 3)
	doc.set_terrain_skin(3, 2, "wall_stone1")
	doc.set_terrain_skin(1, 0, "fort_town1")
	var text := doc.to_text()
	assert_string_contains(text, "{ \"col\": 1, \"row\": 0, \"skin\": \"fort_town1\" }")  # 手書きのキー順
	assert_lt(text.find("\"row\": 0"), text.find("\"row\": 2"), "row→col の順に並べる")
	var out: Dictionary = JSON.parse_string(text)
	assert_eq(out["terrain_skins"].size(), 2)


func test_roundtrip_keeps_terrain_skins_including_unknown_keys() -> void:
	var src := "{ \"turn_limit\": 30, \"cols\": 4, \"rows\": 3, \"terrain_skins\": [" \
		+ " { \"col\": 1, \"row\": 0, \"skin\": \"fort_town1\", \"memo\": \"手書き\" } ] }"
	var out: Dictionary = JSON.parse_string(MapEditorDoc.from_text(src).to_text())
	assert_eq_deep(out["terrain_skins"], JSON.parse_string(src)["terrain_skins"])


func test_resize_drops_out_of_range_terrain_skins() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	doc.set_terrain_skin(5, 3, "wall_stone1")
	doc.set_terrain_skin(1, 1, "fort_town1")
	assert_eq(doc.resize(4, 4), 1)
	assert_eq(doc.terrain_skin(5, 3), "")
	assert_eq(doc.terrain_skin(1, 1), "fort_town1")


# --- 駒・拠点の操作 ---


func test_add_and_remove_units() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	assert_true(doc.add_player("fighter", 1, 1))
	assert_false(doc.add_player("novice", 1, 1), "重ね置きは不可")
	var sq := doc.add_squad("charge", "先鋒")
	assert_true(doc.add_enemy(sq, "goblin", 3, 1))
	assert_false(doc.add_enemy(sq, "goblin", 1, 1), "自軍の上にも置けない")
	assert_eq(doc.unit_at(3, 1)["squad"], sq)
	assert_true(doc.remove_unit_at(3, 1))
	assert_true(doc.unit_at(3, 1).is_empty())


func test_move_unit_and_reject_occupied() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	assert_true(doc.move(1, 1, 2, 2))
	assert_eq(int(doc.unit_at(2, 2)["unit"]["col"]), 2)
	assert_false(doc.move(2, 2, 4, 1), "駒の上には動かせない")
	assert_false(doc.move(2, 2, 99, 0), "盤外には動かせない")


func test_base_add_remove() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	assert_true(doc.add_base(2, 2, "neutral", "fort", ""))
	assert_false(doc.add_base(2, 2, "enemy", "hq"), "重ね置きは不可")
	assert_false(doc.base_at(2, 2)["base"].has("ai"), "ai空文字はキーを書かない")
	assert_true(doc.remove_base_at(2, 2))


# --- id・勝利条件 ---


func test_computed_ids_follow_stage_loader_numbering() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	var ids := doc.computed_ids()
	assert_eq(ids["p:0"], 1)      # player が 1 から
	assert_eq(ids["e:0:0"], 2)    # 敵は続き番号
	assert_eq(ids["e:0:1"], 99)   # 明示 id はそれを表示


func test_set_boss_assigns_free_id_and_victory() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	var id := doc.set_boss(0, 0)  # id 99 は使用済み → 98
	assert_eq(id, 98)
	assert_eq(doc.data["enemy"][0]["units"][0]["id"], 98)
	assert_eq(doc.victory_list().size(), 2)
	assert_eq(doc.set_boss(0, 0), 98, "再指定しても増えない")
	assert_eq(doc.victory_list().size(), 2)


func test_remove_victory_erases_empty_key() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	doc.remove_victory(0)
	assert_false(doc.data.has("victory"))
	assert_false(JSON.parse_string(doc.to_text()).has("victory"))
