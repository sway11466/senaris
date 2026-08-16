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
  "margin": 0,
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
    { "order": 1, "name": "本隊", "ai": "ambush", "sight": 3, "units": [
      { "skin": "goblin", "col": 4, "row": 1 },
      { "skin": "hobgoblin", "actor": "hobgoblin", "col": 4, "row": 2 }
    ] }
  ],
  "bases": [
    { "order": 2, "col": 5, "row": 3, "team": "enemy", "ai": "charge",
      "garrison": [ { "skin": "goblin", "count": 4 } ] }
  ],
  "victory": [
    { "type": "defeat_unit", "actor": "hobgoblin" }
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


## イベント（時限発生＝増援）を持つステージ。搭載駒つきの輸送が来る形。
const EVENT_SAMPLE := """
{
  "turn_limit": 50,
  "name": "event-sample",
  "cols": 6,
  "rows": 4,
  "margin": 0,
  "terrain": [
    "......",
    "......",
    "......",
    "......"
  ],
  "player": [
    { "type": "fighter", "col": 1, "row": 1 }
  ],
  "enemy": [],
  "events": [
    { "turn": 5, "type": "reinforce", "team": "player",
      "label": "t2.st7.event.airship",
      "units": [
        { "type": "airship", "col": 0, "row": 3,
          "passengers": [ { "type": "paladin" } ] }
      ] }
  ]
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


func test_fill_paints_connected_region_and_returns_count() -> void:
	var doc := MapEditorDoc.new_stage(4, 3)  # 全マス平地・スキン指定なし＝ひと続き
	assert_eq(doc.fill_terrain(0, 0, "F", "forest"), 12)
	assert_eq(doc.terrain_char(3, 2), "F")
	assert_eq(doc.terrain_skin(3, 2), "forest")


func test_fill_does_not_leak_across_a_different_skin() -> void:
	# 同じ平地でも skin が違えば別の見た目＝別領域。壁になって塗りが漏れない。
	var doc := MapEditorDoc.new_stage(3, 3)
	for row in 3:
		doc.set_terrain_skin(1, row, "plain_cave1")  # 中央の列で盤を左右に分断
	assert_eq(doc.fill_terrain(0, 0, ".", "wasteland"), 3, "左の列だけ")
	assert_eq(doc.terrain_skin(1, 0), "plain_cave1", "境界のマスは塗られない")
	assert_eq(doc.terrain_skin(2, 0), "", "向こう側にも渡らない")


func test_fill_from_a_skinned_region_takes_only_that_region() -> void:
	# 逆向き：スキン側から塗ると、既定スキンの領域には広がらない。
	var doc := MapEditorDoc.new_stage(3, 3)
	for row in 3:
		doc.set_terrain_skin(1, row, "plain_cave1")
	assert_eq(doc.fill_terrain(1, 1, "#", "wall_stone1"), 3)
	assert_eq(doc.terrain_char(1, 1), "#")
	assert_eq(doc.terrain_char(0, 1), ".", "既定スキンの隣は据え置き")


func test_fill_at_board_edge_stays_inside() -> void:
	# 端のマスから塗っても盤外を辿らない（連結判定が範囲外へ出ない）。
	var doc := MapEditorDoc.new_stage(3, 2)
	assert_eq(doc.fill_terrain(0, 0, "F", ""), 6, "隅から全面＝盤内の6マスだけ")
	assert_eq(doc.fill_terrain(2, 1, ".", "cave"), 6, "反対の隅からも同じ")
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_eq(out["terrain"].size(), 2)
	assert_eq(out["terrain_skins"].size(), 6, "盤内のマスだけが差分になる")
	for line in out["terrain"]:
		assert_eq(String(line).length(), 3)


func test_connected_cells_outside_board_is_empty() -> void:
	var doc := MapEditorDoc.new_stage(3, 2)
	assert_eq(doc.connected_cells(9, 9).size(), 0)
	assert_eq(doc.connected_cells(-1, 0).size(), 0)


func test_fill_output_keeps_write_format() -> void:
	var doc := MapEditorDoc.new_stage(3, 2)
	doc.fill_terrain(0, 0, ".", "plain_cave1")
	var text := doc.to_text()
	assert_string_contains(text, "{ \"col\": 0, \"row\": 0, \"skin\": \"plain_cave1\" }")
	assert_lt(text.find("\"col\": 0, \"row\": 0"), text.find("\"col\": 0, \"row\": 1"), "row→col 並び")


func test_undo_restores_terrain_and_skins() -> void:
	var doc := MapEditorDoc.new_stage(3, 2)
	doc.set_terrain_skin(0, 0, "plain_cave1")
	doc.push_terrain_undo()
	doc.fill_terrain(1, 0, "F", "forest")
	assert_true(doc.can_undo_terrain())
	assert_true(doc.undo_terrain())
	assert_eq(doc.terrain_char(1, 0), ".")
	assert_eq(doc.terrain_skin(0, 0), "plain_cave1", "操作前の差分は残る")
	assert_eq(doc.terrain_skin(1, 0), "", "操作で足した差分は消える")
	assert_false(doc.can_undo_terrain(), "戻せるのは直前の1操作だけ")
	assert_false(doc.undo_terrain())


func test_undo_erases_terrain_skins_key_when_it_did_not_exist() -> void:
	var doc := MapEditorDoc.new_stage(3, 2)
	doc.push_terrain_undo()
	doc.fill_terrain(0, 0, ".", "plain_cave1")
	assert_true(doc.undo_terrain())
	assert_false(JSON.parse_string(doc.to_text()).has("terrain_skins"))


func test_resize_drops_terrain_undo() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	doc.push_terrain_undo()
	doc.resize(4, 3)
	assert_false(doc.can_undo_terrain(), "旧サイズには戻せない")


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


func test_move_base_at_carries_the_defeat_target() -> void:
	var doc := _doc_with_base()
	doc.add_base(6, 2, "neutral", "fort")
	doc.add_defeat_lose_base(3, 2)
	assert_false(doc.move_base_at(3, 2, 6, 2), "拠点のあるマスへは動かせない")
	assert_false(doc.move_base_at(3, 2, 99, 0), "盤外へは動かせない")
	assert_false(doc.move_base_at(0, 0, 5, 4), "拠点のないマスからは動かせない")
	assert_true(doc.move_base_at(3, 2, 5, 4))
	assert_true(doc.base_at(5, 4).size() > 0, "動いた先に拠点がある")
	var t: Dictionary = MapEditorDoc.lose_base_targets(doc.defeat_list()[0])[0]
	assert_eq([int(t["col"]), int(t["row"])], [5, 4], "防衛対象の座標も連れて動く")


func test_move_unit_at() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	assert_true(doc.move_unit_at(1, 1, 2, 2), "空きマスへは動かせる")
	assert_eq(int(doc.data["player"][0]["col"]), 2)
	assert_eq(int(doc.data["player"][0]["row"]), 2)
	assert_false(doc.move_unit_at(2, 2, 4, 1), "駒のいるマスへは動かせない")
	assert_false(doc.move_unit_at(2, 2, 99, 0), "盤外へは動かせない")
	assert_false(doc.move_unit_at(0, 0, 3, 3), "駒のいないマスからは動かせない")
	assert_true(doc.move_unit_at(4, 2, 5, 2), "敵の駒も動かせる")
	assert_eq(int(doc.data["enemy"][0]["units"][1]["col"]), 5)


func test_move_unit_to_squad() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	var to := doc.add_squad("charge")
	assert_false(doc.move_unit_to_squad(0, 0, 0), "同じ部隊へは移さない")
	assert_true(doc.move_unit_to_squad(0, 0, to))
	assert_eq(doc.data["enemy"][0]["units"].size(), 1)
	assert_eq(String(doc.data["enemy"][to]["units"][0]["skin"]), "goblin", "駒の中身はそのまま")
	assert_eq(int(doc.data["enemy"][to]["units"][0]["col"]), 4, "位置も変えない")
	assert_false(doc.move_unit_to_squad(0, 9, to), "居ない駒は移せない")


func test_base_add_remove() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	assert_true(doc.add_base(2, 2, "neutral", "fort", ""))
	assert_false(doc.add_base(2, 2, "enemy", "hq"), "重ね置きは不可")
	assert_false(doc.base_at(2, 2)["base"].has("ai"), "ai空文字はキーを書かない")
	assert_true(doc.remove_base_at(2, 2))


func test_garrison_count_sums_the_rows() -> void:
	assert_eq(MapEditorDoc.garrison_count({}), 0, "garrison が無い拠点は0体")
	assert_eq(MapEditorDoc.garrison_count({ "garrison": [] }), 0)
	assert_eq(MapEditorDoc.garrison_count({ "garrison": [
		{ "skin": "goblin", "count": 3 }, { "skin": "elf" },
	] }), 4, "count 省略は1体として足す")
	assert_eq(MapEditorDoc.garrison_count({ "garrison": [{ "skin": "goblin", "count": 0 }] }), 1,
		"0以下の count も1体として数える（編集UIの下限に合わせる）")
	assert_eq(MapEditorDoc.garrison_count({ "garrison": "壊れた値" }), 0, "配列でなければ0体")


# --- 名指し(actor)・行動順(order)・勝利条件 ---


func test_used_actors_collects_named_pieces() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	assert_true(doc.used_actors().has("hobgoblin"), "部隊の駒の actor を拾う")
	assert_eq(doc.used_actors().size(), 1, "名前なしの駒は数えない")


func test_free_actor_avoids_duplicate() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	assert_eq(doc.free_actor("goblin"), "goblin", "未使用ならそのまま")
	assert_eq(doc.free_actor("hobgoblin"), "hobgoblin2", "使用済みなら連番を足す")


func test_set_actor_names_player_and_enemy() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	doc.set_actor(doc.data["player"][0], "cap")
	doc.set_actor(doc.data["enemy"][0]["units"][0], "goblin")
	assert_eq(doc.data["player"][0]["actor"], "cap", "自軍にも名前を付けられる")
	assert_false(doc.data["player"][0].has("id"), "数値 id は書かない")
	assert_true(doc.used_actors().has("cap"))
	assert_eq(doc.used_actors().size(), 3)


func test_set_actor_rename_follows_victory() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	doc.set_actor(doc.data["enemy"][0]["units"][1], "necromancer")
	assert_eq(doc.victory_list()[0]["actor"], "necromancer", "勝利条件の名指しも付け替わる")


func test_set_actor_clear_drops_condition() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	doc.set_actor(doc.data["enemy"][0]["units"][1], "")
	assert_false(doc.data["enemy"][0]["units"][1].has("actor"))
	assert_eq(doc.victory_list().size(), 0, "指す先が無くなった条件は残さない")
	assert_false(doc.data.has("victory"), "空の victory キーは書き出さない")


func test_set_actor_follows_lose_unit() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	doc.set_actor(doc.data["player"][0], "cap")
	doc.data["defeat"] = [{ "type": "lose_unit", "actors": ["cap", "other"] }]
	doc.set_actor(doc.data["player"][0], "captain")
	assert_eq(doc.defeat_list()[0]["actors"], ["captain", "other"], "護衛対象の名指しも追随")
	doc.set_actor(doc.data["player"][0], "")
	assert_eq(doc.defeat_list()[0]["actors"], ["other"], "外した名前だけ落ちる")


func test_add_squad_gets_next_order() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	assert_eq(doc.max_order(), 2, "部隊1＋AI出撃する拠点2")
	assert_eq(doc.data["enemy"][doc.add_squad("charge")]["order"], 3, "追加した部隊は末尾の順番")


func test_remove_victory_erases_empty_key() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)
	doc.remove_victory(0)
	assert_false(doc.data.has("victory"))
	assert_false(JSON.parse_string(doc.to_text()).has("victory"))


# --- 外周（margin）。terrain だけ盤より大きく持ち、駒・拠点は盤にしか置けない ---
# エディタが margin を知らないまま保存すると terrain の行数・桁数が cols/rows と食い違って壊れる。
# ここで守るのは「開いて保存しても外周が消えない」こと。詳細 → doc/gdd/map.md

const MARGIN_SAMPLE := """
{
  "turn_limit": 30,
  "name": "ring",
  "cols": 4,
  "rows": 3,
  "margin": 1,
  "terrain": [
    "FFFFFF",
    "FPP..F",
    "F..%%F",
    "F....F",
    "FFFFFF"
  ],
  "terrain_skins": [
    { "col": -1, "row": 1, "skin": "plain_grave1" }
  ],
  "player": [
    { "type": "fighter", "col": 1, "row": 1 }
  ],
  "enemy": [],
  "bases": []
}
"""


func test_margin_roundtrip_keeps_the_ring() -> void:
	var out := _roundtrip(MARGIN_SAMPLE)
	var src: Dictionary = JSON.parse_string(MARGIN_SAMPLE)
	assert_eq_deep(out, src)  # 読込→保存で外周が消えたり切り詰められたりしない


func test_margin_terrain_char_is_addressed_from_the_board_origin() -> void:
	var doc := MapEditorDoc.from_text(MARGIN_SAMPLE)
	assert_eq(doc.cols(), 4, "cols は遊べる盤のまま")
	assert_eq(doc.rows(), 3, "rows は遊べる盤のまま")
	assert_eq(doc.margin(), 1)
	assert_eq(doc.terrain_char(0, 0), "P", "盤の(0,0)は grid の行1・文字1")
	assert_eq(doc.terrain_char(2, 1), "%", "盤の(2,1)")
	assert_eq(doc.terrain_char(-1, -1), "F", "外周の左上")
	assert_eq(doc.terrain_char(4, 3), "F", "外周の右下")


func test_margin_cells_are_paintable_and_survive_saving() -> void:
	var doc := MapEditorDoc.from_text(MARGIN_SAMPLE)
	doc.set_terrain_char(-1, 1, "L")   # 左辺の外周を道に
	doc.set_terrain_char(1, 3, "L")    # 下辺の外周を道に
	assert_eq(doc.terrain_char(-1, 1), "L")
	assert_eq(doc.terrain_char(1, 3), "L")
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_eq(String(out["terrain"][2]), "L..%%F", "左辺の外周が書き出しに乗る")
	assert_eq(String(out["terrain"][4]), "FFLFFF", "下辺の外周が書き出しに乗る")


func test_margin_rejects_cells_outside_the_canvas() -> void:
	var doc := MapEditorDoc.from_text(MARGIN_SAMPLE)
	doc.set_terrain_char(-2, 0, "L")  # 外周のさらに外
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_eq(out["terrain"].size(), 5, "行数は変わらない")
	for line in out["terrain"]:
		assert_eq(String(line).length(), 6, "桁数も変わらない")


func test_in_board_excludes_the_ring() -> void:
	var doc := MapEditorDoc.from_text(MARGIN_SAMPLE)
	assert_true(doc.in_board(0, 0), "盤の左上")
	assert_true(doc.in_board(3, 2), "盤の右下")
	assert_false(doc.in_board(-1, 0), "外周は盤ではない＝駒を置けない")
	assert_false(doc.in_board(4, 0), "同上")
	assert_true(doc.in_canvas(-1, -1), "外周は描画領域には入る")
	assert_false(doc.in_canvas(-2, -1), "外周の外は描画領域でもない")


func test_terrain_skins_can_address_the_ring() -> void:
	# 外周のセルにも見た目差分を書ける（座標が盤外になるだけ＝形式はそのまま）
	var doc := MapEditorDoc.from_text(MARGIN_SAMPLE)
	assert_eq(doc.terrain_skin(-1, 1), "plain_grave1", "読み込んだ外周の skin 指定")
	doc.set_terrain_skin(4, 2, "road")
	assert_eq(doc.terrain_skin(4, 2), "road", "外周に skin を足せる")


func test_fill_does_not_cross_the_board_edge() -> void:
	# 盤の中で始めた塗りが外周へ漏れない（逆も同じ）＝縁の絵を作者が握れる
	var doc := MapEditorDoc.from_text("""
{ "cols": 3, "rows": 3, "margin": 1, "terrain": [
	".....", ".....", ".....", ".....", "....."
], "player": [], "enemy": [], "bases": [] }
""")
	assert_eq(doc.fill_terrain(1, 1, "L", ""), 9, "盤の9マスだけ塗る（外周には出ない）")
	assert_eq(doc.terrain_char(0, 0), "L", "盤は塗られた")
	assert_eq(doc.terrain_char(-1, -1), ".", "外周は塗られていない")
	assert_eq(doc.fill_terrain(-1, -1, "M", ""), 16, "外周だけを塗る（5×5 - 3×3）")
	assert_eq(doc.terrain_char(1, 1), "L", "盤は巻き込まれない")


func test_set_margin_grows_and_shrinks_the_grid() -> void:
	var doc := MapEditorDoc.from_text(SAMPLE)  # 6×4・margin 0
	doc.set_margin(1)
	var grown: Dictionary = JSON.parse_string(doc.to_text())
	assert_eq(grown["terrain"].size(), 6, "行が2つ増える")
	assert_eq(String(grown["terrain"][0]).length(), 8, "桁も2つ増える")
	assert_eq(doc.terrain_char(2, 0), "F", "盤の中身はずれない")
	doc.set_margin(0)
	var shrunk: Dictionary = JSON.parse_string(doc.to_text())
	assert_eq(shrunk["terrain"].size(), 4, "元の行数に戻る")
	assert_eq(String(shrunk["terrain"][0]), "..FF..", "盤の中身も元のまま")


func test_margin_is_written_even_when_absent_from_the_source() -> void:
	# 既定値に頼らない方針＝読み込んだファイルに margin が無ければ 0 を書き足して保存する
	var doc := MapEditorDoc.from_text("""
{ "cols": 3, "rows": 2, "terrain": ["...", "..."], "player": [], "enemy": [], "bases": [] }
""")
	var out: Dictionary = JSON.parse_string(doc.to_text())
	assert_true(out.has("margin"), "margin キーが書き出される")
	assert_eq(int(out["margin"]), 0)

# --- 全体の平行移動（盤を広げたあと、左上に描いた中身を寄せ直す操作） ---
# ここで守るのは「座標を持つものが1つ残らず同じだけ動く」ことと「外へ出るなら1つも動かさない」こと。
# 後者があるので逆向きに押せば必ず元へ戻せる（この操作は地形の Ctrl+Z の対象外）。


func test_shift_moves_board_contents_together() -> void:
	var doc := MapEditorDoc.new_stage(8, 6)
	doc.set_terrain_char(1, 1, "F")
	doc.set_terrain_skin(1, 1, "forest_pine1")
	doc.add_player("fighter", 2, 1)
	doc.add_squad("charge")
	doc.add_enemy(0, "goblin", 2, 2)
	doc.add_base(3, 1, "enemy", "fort")
	doc.add_defeat_lose_base(3, 1)
	assert_true(doc.shift(2, 1))
	assert_eq(doc.terrain_char(3, 2), "F")
	assert_eq(doc.terrain_char(1, 1), ".", "元のマスは既定地形に戻る")
	assert_eq(doc.terrain_skin(3, 2), "forest_pine1")
	assert_eq(doc.terrain_skin(1, 1), "")
	assert_eq(int(doc.data["player"][0]["col"]), 4)
	assert_eq(int(doc.data["player"][0]["row"]), 2)
	assert_eq(int(doc.data["enemy"][0]["units"][0]["col"]), 4)
	assert_eq(int(doc.data["enemy"][0]["units"][0]["row"]), 3)
	assert_false(doc.base_at(5, 2).is_empty())
	assert_true(doc.has_defeat_lose_base(5, 2), "拠点を名指しする防衛対象も連れて動く")


func test_shift_moves_event_units() -> void:
	var doc := MapEditorDoc.from_text(EVENT_SAMPLE)
	assert_true(doc.shift(2, 0))
	var u: Dictionary = doc.event_units(0)[0]
	assert_eq(int(u["col"]), 2)
	assert_eq(int(u["row"]), 3)
	assert_false(u["passengers"][0].has("col"), "搭載駒は座標を持たない＝触らない")


func test_shift_rejects_odd_column_step() -> void:
	var doc := MapEditorDoc.new_stage(8, 6)
	doc.set_terrain_char(1, 1, "F")
	assert_false(doc.shift(1, 0), "奇数列送りは平行移動にならない（odd-q で列の偶奇が入れ替わる）")
	assert_eq(doc.terrain_char(1, 1), "F", "弾いたら1マスも動かさない")


func test_shift_does_nothing_when_contents_would_fall_off() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	doc.set_terrain_char(0, 0, "F")
	doc.add_player("fighter", 5, 1)
	assert_eq(int(doc.shift_losses(2, 0).get("units", 0)), 1)
	assert_false(doc.shift(2, 0))
	assert_eq(doc.terrain_char(0, 0), "F", "地形も駒も1つも動かさない")
	assert_eq(int(doc.data["player"][0]["col"]), 5)


func test_shift_counts_only_non_default_terrain_as_lost() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	assert_true(doc.shift_losses(0, 1).is_empty(), "空白のマスが外へ出るのは失っていない")
	doc.set_terrain_char(2, 3, "F")
	assert_eq(int(doc.shift_losses(0, 1).get("terrain", 0)), 1)


func test_shift_moves_margin_terrain_with_the_board() -> void:
	var doc := MapEditorDoc.from_text(MARGIN_SAMPLE)  # 4×3・外周1（縁が F で囲われている）
	doc.resize(6, 3)  # 右に2列ぶんの余白を作る
	assert_true(doc.shift(2, 0))
	assert_eq(doc.terrain_char(3, 0), "P", "盤の中身がそのまま2列右へ")
	assert_eq(doc.terrain_char(1, -1), "F", "外周の地形も一緒に動く")
	assert_eq(doc.terrain_char(-1, 0), ".", "何も入ってこない左端は既定地形で空く")
	assert_eq(doc.terrain_skin(1, 1), "plain_grave1", "外周(-1,1)のスキン指定も一緒に動く")


func test_shift_drops_terrain_undo() -> void:
	var doc := MapEditorDoc.new_stage(6, 4)
	doc.push_terrain_undo()
	assert_true(doc.shift(0, 1))
	assert_false(doc.can_undo_terrain(), "駒ごと動いた後に地形だけ戻せてはいけない")

# --- 敗北条件（防衛対象の拠点） ---

func _doc_with_base() -> MapEditorDoc:
	var doc := MapEditorDoc.new_stage()
	doc.add_base(3, 2, "neutral", "fort")
	return doc

func test_add_defeat_lose_base_needs_a_base() -> void:
	var doc := _doc_with_base()
	assert_false(doc.add_defeat_lose_base(0, 0), "拠点の無いマスは防衛対象にできない")
	assert_true(doc.defeat_list().is_empty())
	assert_true(doc.add_defeat_lose_base(3, 2), "拠点のマスは指定できる")
	assert_eq(doc.defeat_list().size(), 1)
	assert_true(doc.add_defeat_lose_base(3, 2), "二重指定は増やさない")
	assert_eq(doc.defeat_list().size(), 1)

func test_defeat_follows_base_removal() -> void:
	var doc := _doc_with_base()
	doc.add_defeat_lose_base(3, 2)
	assert_eq(doc.defeat_list().size(), 1)
	assert_true(doc.remove_base_at(3, 2), "拠点を消す")
	assert_true(doc.defeat_list().is_empty(), "宙に浮いた敗北条件は残さない")

func test_add_defeat_lose_base_group_makes_an_and() -> void:
	var doc := _doc_with_base()
	doc.add_base(6, 2, "neutral", "fort")
	doc.add_defeat_lose_base(3, 2)
	doc.add_defeat_lose_base(6, 2, true)  # 相乗り＝両方失って初めて敗北
	assert_eq(doc.defeat_list().size(), 1, "条件は増えない（1件の中に2対象）")
	assert_eq(MapEditorDoc.lose_base_targets(doc.defeat_list()[0]).size(), 2)

func test_add_defeat_lose_base_without_group_makes_an_or() -> void:
	var doc := _doc_with_base()
	doc.add_base(6, 2, "neutral", "fort")
	doc.add_defeat_lose_base(3, 2)
	doc.add_defeat_lose_base(6, 2)
	assert_eq(doc.defeat_list().size(), 2, "別条件＝どちらか失えば敗北")

## AND条件の対象になっている拠点を消したとき、残りの対象があれば条件は残る。
func test_removing_one_of_an_and_keeps_the_condition() -> void:
	var doc := _doc_with_base()
	doc.add_base(6, 2, "neutral", "fort")
	doc.add_defeat_lose_base(3, 2)
	doc.add_defeat_lose_base(6, 2, true)
	assert_true(doc.remove_base_at(3, 2))
	assert_eq(doc.defeat_list().size(), 1, "残りの対象があれば条件は残る")
	assert_eq(MapEditorDoc.lose_base_targets(doc.defeat_list()[0]).size(), 1)
	assert_true(doc.remove_base_at(6, 2))
	assert_true(doc.defeat_list().is_empty(), "最後の対象が消えたら条件ごと消える")

func test_defeat_key_is_omitted_when_empty() -> void:
	var doc := _doc_with_base()
	doc.add_defeat_lose_base(3, 2)
	assert_true(doc.to_text().contains("\"defeat\""), "指定があれば書き出す")
	doc.remove_defeat(0)
	assert_false(doc.to_text().contains("\"defeat\""), "空の defeat キーは書き出さない")

## 手書きの既存ステージと同じ書式で出す（エディタで開き直しただけで差分が出ない）。
func test_defeat_is_written_in_the_handwritten_style() -> void:
	var doc := _doc_with_base()
	doc.add_base(6, 2, "neutral", "fort")
	doc.add_defeat_lose_base(3, 2)
	assert_true(doc.to_text().contains(
		"  \"defeat\": [\n" +
		"    { \"type\": \"lose_base\",\n" +
		"      \"bases\": [ { \"col\": 3, \"row\": 2 } ] }\n" +
		"  ]"), "対象1つは1行に収める")
	doc.add_defeat_lose_base(6, 2, true)
	assert_true(doc.to_text().contains(
		"  \"defeat\": [\n" +
		"    { \"type\": \"lose_base\",\n" +
		"      \"bases\": [\n" +
		"        { \"col\": 3, \"row\": 2 },\n" +
		"        { \"col\": 6, \"row\": 2 }\n" +
		"      ] }\n" +
		"  ]"), "対象が複数なら1件1行で段落にする")


# --- イベント（時限発生＝増援）。仕様 → doc/gdd/map.md イベント ---

func test_events_round_trip_untouched() -> void:
	# エディタが触らないステージでも events はそのまま書き戻る（未知キーの温存と同じ扱い）。
	var src := MapEditorDoc.from_text(EVENT_SAMPLE)
	assert_not_null(src, "読み込める")
	if src == null:
		return
	var back := MapEditorDoc.from_text(src.to_text())
	assert_not_null(back, "書き戻したものを読み直せる")
	if back == null:
		return
	var e: Array = back.event_list()
	assert_eq(e.size(), 1, "イベントが1件残る")
	assert_eq(int((e[0] as Dictionary)["turn"]), 5, "ターンが保たれる")
	assert_eq(String((e[0] as Dictionary)["label"]), "t2.st7.event.airship", "予告キーが保たれる")
	var units: Array = (e[0] as Dictionary)["units"]
	assert_eq(String((units[0] as Dictionary)["type"]), "airship", "駒が保たれる")
	assert_eq(((units[0] as Dictionary)["passengers"] as Array).size(), 1, "同乗も保たれる")


func test_add_and_remove_event() -> void:
	var doc := MapEditorDoc.new_stage(8, 6)
	assert_true(doc.event_list().is_empty(), "最初は空")
	doc.add_event(5, "player")
	assert_eq(doc.event_list().size(), 1, "1件足せる")
	assert_eq(String((doc.event_list()[0] as Dictionary)["type"]), "reinforce", "型は増援")
	doc.event_units(0).append({ "type": "airship", "col": 0, "row": 5 })
	assert_eq(doc.event_units(0).size(), 1, "駒を足せる")
	assert_true(doc.to_text().contains("\"events\""), "保存に出る")
	doc.remove_event(0)
	assert_true(doc.event_list().is_empty(), "消せる")
	assert_false(doc.to_text().contains("\"events\""), "空の events キーは書き出さない")


## ターンが1未満にならない（0ターン目のイベントは発生ターンが来ない＝出ないままになる）。
func test_event_turn_is_at_least_one() -> void:
	var doc := MapEditorDoc.new_stage(8, 6)
	doc.add_event(0, "player")
	assert_eq(int((doc.event_list()[0] as Dictionary)["turn"]), 1, "1に丸める")


func test_event_units_on_missing_index_is_empty() -> void:
	var doc := MapEditorDoc.new_stage(8, 6)
	assert_true(doc.event_units(0).is_empty(), "イベントが無ければ空")
	doc.add_event(2, "enemy")
	assert_true(doc.event_units(3).is_empty(), "範囲外でも壊れない")
