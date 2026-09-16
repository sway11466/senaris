extends GutTest
## ChronicleStoryReader（物語の通し読み）のテスト。章から章へ会話を連ねる進行を見る。
## 仕様 → doc/gdd/chronicle.md 物語

const STAGE_DIR := "res://data/stages/tutorial1-goblin-raid"

var reader: ChronicleStoryReader

func before_each() -> void:
	reader = ChronicleStoryReader.new()
	add_child_autofree(reader)
	await get_tree().process_frame  # _ready で中身が組まれる

func _chapters() -> Array:
	# 台本は実物を読む（chapter_talks がステージ JSON から解く）。
	return [
		_chapter("goblin-raid-st1", ["intro", "outro"]),
		_chapter("goblin-raid-st2", ["intro", "outro"]),
	]

func _chapter(stage: String, keys: Array) -> Dictionary:
	var talks: Array = []
	for k in keys:
		talks.append({
			"key": k, "phase": k, "event": "",
			"actors": [],
		})
	return {
		"stage": stage,
		"title": "stage.%s.title" % stage,
		"path": "%s/%s.json" % [STAGE_DIR, stage],
		"art": "",
		"talks": talks,
	}

func test_open_starts_the_first_talk_of_the_chapter() -> void:
	reader.open(_chapters(), 0, {})
	assert_true(reader.visible, "通し読みが開く")
	assert_eq(reader._chapter, 0, "先頭の章から")
	assert_eq(reader._talks.size(), 2, "開幕と決着を読む")
	assert_true(reader._panel.visible, "会話板が出ている")

func test_reading_on_runs_through_the_talks_then_the_next_chapter() -> void:
	reader.open(_chapters(), 0, {})
	reader._on_talk_closed()  # 開幕を読み切った
	assert_eq(reader._talk, 1, "同じ章の次の会話へ")
	reader._on_talk_closed()  # 決着を読み切った
	assert_eq(reader._chapter, 1, "次の章へ移る")
	assert_eq(reader._talk, 0, "次の章の先頭から")

func test_skip_jumps_to_the_next_chapter() -> void:
	reader.open(_chapters(), 0, {})
	reader._panel._on_skip()  # 「次の章へ」を押した
	assert_eq(reader._chapter, 1, "章ごと飛ばす")
	assert_eq(reader._talk, 0, "次の章の開幕から")

func test_the_last_talk_finishes_the_reading() -> void:
	watch_signals(reader)
	reader.open(_chapters(), 1, {})  # 最後の章から始める
	reader._on_talk_closed()
	reader._on_talk_closed()
	assert_signal_emitted(reader, "closed", "読み終えたら畳む")
	assert_false(reader.visible, "画面は閉じている")

func test_starting_from_a_chapter_skips_the_earlier_ones() -> void:
	reader.open(_chapters(), 1, {})
	assert_eq(reader._chapter, 1, "選んだ章から始める")

func test_quit_closes_without_reading_on() -> void:
	watch_signals(reader)
	reader.open(_chapters(), 0, {})
	reader._on_quit()
	assert_signal_emitted(reader, "closed", "やめたら畳む")
	assert_false(reader.visible)
