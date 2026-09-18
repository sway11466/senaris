extends GutTest
## セーブエディタの「クロニクルを全部ON」（SaveEditorModel.all_on）のテスト。
## 実データ（冒険譚1のマニフェスト・スキン表・スキル）を、テスト用の置き場に置いたストアへ書く。
## 仕様 → doc/backlog.md feature-130 / doc/gdd/chronicle.md 記録の持ち方

const DIR := "user://test_save_editor_all_on"
const PROGRESS_PATH := "user://test_save_editor_all_on/progress.json"
const CHRONICLE_PATH := "user://test_save_editor_all_on/chronicle.json"
const T1 := "tutorial1-goblin-raid"
const T3 := "tutorial3-dragon-hunt"

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

func _campaigns() -> Array:
	return [
		CampaignCatalog.load_file("res://data/stages/%s/campaign.json" % T1),
		CampaignCatalog.load_file("res://data/stages/%s/campaign.json" % T3),
	]

func _run() -> Dictionary:
	var progress := ProgressStore.new(PROGRESS_PATH)
	var chronicle := ChronicleStore.new(CHRONICLE_PATH)
	var n := SaveEditorModel.all_on(progress, chronicle, _campaigns(), ChronicleLoader.load_all(),
			UnitCatalog.load_default(), SkinCatalog.load_standard())
	chronicle.save()
	return n

func test_all_on_records_every_skin_and_skill() -> void:
	var n := _run()
	var chronicle := ChronicleStore.new(CHRONICLE_PATH)  # 読み直し＝ファイルに書けている
	var skins := SkinCatalog.load_standard()
	assert_eq(n["skins"], (skins[SkinCatalog.BY_ID_KEY] as Dictionary).size(), "全スキンを書いた")
	for skin_id in skins[SkinCatalog.BY_ID_KEY]:
		assert_true(chronicle.has_skin(skin_id), "スキン: %s" % skin_id)
	var skills := chronicle.skills()
	assert_eq(n["skills"], SaveEditorModel.formation_skill_ids().size(), "全陣形スキルを書いた")
	for skill_id in SaveEditorModel.formation_skill_ids():
		assert_true(skills.has(skill_id), "スキル: %s" % skill_id)
		assert_eq(skills[skill_id]["first"], "", "初出の冒険譚は空")

func test_all_on_writes_story_records_from_manifest() -> void:
	# 冒険譚1はクロニクルのマニフェスト（data/chronicle）を持つ＝全ステージに開始時・クリア後の記録と、
	# マニフェストにあるイベント（st4 の town-freed）が入る。
	var n := _run()
	assert_gt(n["stages"], 0)
	var progress := ProgressStore.new(PROGRESS_PATH)
	var st4 := progress.story(T1, "goblin-raid-st4")
	assert_true(st4.has("clear"), "クリア後の記録がある＝決着の会話が読める")
	assert_eq(st4["events"], ["town-freed"], "マニフェストのイベントが起きた扱い")
	assert_eq(st4["start"], [], "冒険譚1は名簿を使わない＝在籍は空")
	var chronicle := ChronicleStore.new(CHRONICLE_PATH)
	assert_eq(chronicle.story(T1, "goblin-raid-st4")["events"], ["town-freed"], "クロニクル側にも足す")
	assert_eq(chronicle.story(T1, "goblin-raid-st1")["clear"].size(), 1, "顔ぶれ（空）が1つ溜まる")

func test_all_on_is_idempotent() -> void:
	var first := _run()
	var second := _run()
	assert_eq(second["skins"], 0, "2回目は新規に書くスキンが無い")
	assert_eq(second["skills"], 0, "2回目は新規に書くスキルが無い")
	assert_eq(first["stages"], second["stages"], "物語の記録は毎回同じ数を通る（重複はストアが畳む）")
	var chronicle := ChronicleStore.new(CHRONICLE_PATH)
	assert_eq(chronicle.story(T1, "goblin-raid-st4")["events"], ["town-freed"], "イベントは重複しない")
