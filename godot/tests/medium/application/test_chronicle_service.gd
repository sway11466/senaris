extends GutTest
## ChronicleService のテスト。盤に出た駒と発動したレシピの記録を検証する。
## 仕様 → doc/gdd/chronicle.md / doc/tech/gamesystem.md §クロニクル

const DIR := "user://test_chronicle_service"
const PATH := "user://test_chronicle_service/chronicle.json"

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

func _store() -> ChronicleStore:
	return ChronicleStore.new(PATH)

## テスト用の盤。自軍2体（skin_id あり・type_id フォールバック）・敵1体。
func _state() -> BattleState:
	var s := BattleState.new(8, 8)
	var u1 := Unit.new(1, 0, Hex.offset_to_axial(1, 1), 3, 8, 10, 10, 1, "knight")
	u1.skin_id = "knight"
	s.add_unit(u1)
	var u2 := Unit.new(2, 0, Hex.offset_to_axial(2, 2), 3, 8, 10, 10, 1, "archer")
	u2.skin_id = "archer_red"  # skin_id が type_id と異なる
	s.add_unit(u2)
	var u3 := Unit.new(3, 1, Hex.offset_to_axial(5, 5), 3, 8, 10, 10, 1, "goblin")
	# skin_id 未設定 → type_id("goblin") へフォールバック
	s.add_unit(u3)
	return s

# ---------------------------------------------------------------------------
# begin（初期配置の走査）
# ---------------------------------------------------------------------------

func test_begin_records_initial_units() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tc", _state())
	assert_true(st.has_skin("knight"), "初期配置の自軍が記録される")
	assert_true(st.has_skin("archer_red"), "skin_id 優先で記録される（type_id ではない）")
	assert_true(st.has_skin("goblin"), "skin_id が空なら type_id で記録される")
	assert_false(st.has_skin("archer"), "type_id ではなく skin_id が使われる")

func test_begin_empty_campaign_does_not_record() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("", _state())
	assert_eq(st.skins(), [], "冒険譚の外では記録しない")

func test_begin_records_skins_on_the_board() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tutorial1", _state())
	assert_true(st.has_skin("knight"), "盤に出ている駒が記録される")

# ---------------------------------------------------------------------------
# note_unit（出撃・増援）
# ---------------------------------------------------------------------------

func test_note_unit_records_skin() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tc", BattleState.new(8, 8))  # 空の盤で開始
	var u := Unit.new(10, 1, Hex.offset_to_axial(3, 3), 3, 8, 10, 10, 1, "dragon")
	u.skin_id = "dragon"
	svc.note_unit(u)
	assert_true(st.has_skin("dragon"), "増援の駒が記録される")

func test_note_unit_outside_campaign_does_nothing() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("", BattleState.new(8, 8))
	var u := Unit.new(10, 1, Hex.offset_to_axial(3, 3), 3, 8, 10, 10, 1, "dragon")
	u.skin_id = "dragon"
	svc.note_unit(u)
	assert_eq(st.skins(), [], "冒険譚の外では増援も記録しない")

func test_note_unit_fallback_to_type_id() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tc", BattleState.new(8, 8))
	var u := Unit.new(10, 1, Hex.offset_to_axial(3, 3), 3, 8, 10, 10, 1, "wyvern")
	# skin_id 未設定
	svc.note_unit(u)
	assert_true(st.has_skin("wyvern"), "skin_id 未設定なら type_id で記録")

# ---------------------------------------------------------------------------
# note_recipe（陣形スキル発動）
# ---------------------------------------------------------------------------

func test_note_recipe_records() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tc", BattleState.new(8, 8))
	svc.note_recipe("trinity_nova")
	assert_true(st.has_recipe("trinity_nova"), "発動したレシピが記録される")

func test_note_recipe_empty_id_does_nothing() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tc", BattleState.new(8, 8))
	svc.note_recipe("")
	assert_eq(st.recipes(), {}, "空のレシピ id は記録しない")

func test_note_recipe_outside_campaign_does_nothing() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("", BattleState.new(8, 8))
	svc.note_recipe("trinity_nova")
	assert_eq(st.recipes(), {}, "冒険譚の外ではレシピも記録しない")

# ---------------------------------------------------------------------------
# flush（盤を離れるときにファイルへ書く）
# ---------------------------------------------------------------------------

func test_flush_saves_to_file() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tc", _state())
	svc.note_recipe("trinity_nova")
	svc.flush()
	var reloaded := ChronicleStore.new(PATH)
	assert_true(reloaded.has_skin("knight"), "flush でスキンがファイルに書かれる")
	assert_true(reloaded.has_recipe("trinity_nova"), "flush でレシピがファイルに書かれる")

func test_flush_without_changes_does_not_write() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("tc", BattleState.new(8, 8))  # 空の盤＝記録なし
	svc.flush()
	assert_false(FileAccess.file_exists(PATH), "変更がなければファイルを作らない")

# ---------------------------------------------------------------------------
# 冒険譚をまたいだ累積
# ---------------------------------------------------------------------------

func test_accumulates_across_campaigns() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	# 冒険譚1 で knight と archer_red に出会う
	svc.begin("campaign1", _state())
	svc.flush()
	# 冒険譚2 で dragon に出会う（knight は既知）
	var s2 := BattleState.new(8, 8)
	var u := Unit.new(10, 0, Hex.offset_to_axial(1, 1), 3, 8, 10, 10, 1, "dragon")
	u.skin_id = "dragon"
	s2.add_unit(u)
	svc.begin("campaign2", s2)
	svc.flush()
	var reloaded := ChronicleStore.new(PATH)
	assert_true(reloaded.has_skin("knight"), "冒険譚1 のスキンが残っている")
	assert_true(reloaded.has_skin("dragon"), "冒険譚2 のスキンも足されている")

func test_already_known_skin_stays_single_entry() -> void:
	var st := _store()
	var svc := ChronicleService.new(st)
	svc.begin("campaign1", _state())
	svc.flush()
	# 冒険譚2 で同じ knight に出会っても増えない
	svc.begin("campaign2", _state())
	svc.flush()
	var reloaded := ChronicleStore.new(PATH)
	assert_eq(reloaded.skins().count("knight"), 1, "同じスキンは1件のまま")
