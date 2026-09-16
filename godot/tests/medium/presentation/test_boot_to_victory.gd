extends GutTest
## 起動から勝利までの導線を通す Medium テスト（doc/tech/testing.md テストサイズ）。
## main.tscn を立ち上げ、内部メソッドを入口にして下の層まで届いているかを見る＝配線の確認。
## 入力と画面遷移は入口にしない。値や分岐の正しさは各層のテストが見るので、ここでは見ない。
##
## セーブは実ファイルを触らない。SavePaths をこの回だけの置き場へ向け、終わったら消す
## （doc/tech/testing.md 実ファイルを触らない）。

const MAIN := preload("res://presentation/main/main.tscn")

const CAMPAIGN := "tutorial1-goblin-raid"
const STAGE := "goblin-raid-st1"
const STAGE_PATH := "res://data/stages/tutorial1-goblin-raid/goblin-raid-st1.json"

## この回のセーブの置き場。盤の動きで書き換わるファイル（進捗・名簿・クロニクル・設定・
## 中断セーブ）がまとめてここへ落ちる＝実セーブは一度も開かない。
const SAVE_DIR := "user://test_boot_to_victory/"

var _save_dir_before := ""

func before_all() -> void:
	_save_dir_before = SavePaths.dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	SavePaths.dir = SAVE_DIR

func after_all() -> void:
	SavePaths.dir = _save_dir_before
	# この回の産物（世代バックアップ SaveFile.rotate も含む）は置き場ごと消す。
	var abs := ProjectSettings.globalize_path(SAVE_DIR)
	var dir := DirAccess.open(abs)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(abs.path_join(file))
	DirAccess.remove_absolute(abs)

## main.tscn を立ち上げ、タイトルを閉じた状態にして返す。
func _boot() -> Node:
	var main: Node = MAIN.instantiate()
	add_child_autofree(main)
	await wait_process_frames(12)
	main._title_pending = false
	return main

## 冒険譚のステージに入る（ステージセレクトは通さず、同じ文脈を組んで読む）。
func _enter_stage(main: Node) -> void:
	main._context.campaign_id = CAMPAIGN
	main._context.stage_id = STAGE
	main._context.stage_path = STAGE_PATH
	main._context.started_at = int(Time.get_unix_time_from_system()) - 60
	main.load_stage(STAGE_PATH)
	await wait_process_frames(20)

func test_boot_builds_the_wiring() -> void:
	var main: Node = await _boot()
	assert_not_null(main._progress, "進行（CampaignProgress）が組み立てられている")
	assert_not_null(main._outcome, "決着時の記録の門番（StageOutcome）が組み立てられている")
	assert_not_null(main._chronicle, "クロニクルの記録 API が組み立てられている")
	assert_not_null(main.get_node_or_null("HexBoard"), "盤のノードが在る")

func test_entering_stage_puts_units_on_the_board() -> void:
	var main: Node = await _boot()
	await _enter_stage(main)
	var board: Node = main.get_node("HexBoard")
	assert_gt(board.state.units().size(), 0, "ステージを読むと盤に駒が出る")

func test_victory_records_clear_and_chronicle() -> void:
	var main: Node = await _boot()
	await _enter_stage(main)
	main._on_battle_finished(BattleState.PLAYER_WIN)
	await wait_process_frames(20)

	assert_eq(main._progress.stage_state(CAMPAIGN, STAGE), CampaignProgress.CLEARED,
			"勝利が進捗に記録される")

	# クロニクルは盤を離れるときに書く＝決着でファイルに落ちている。
	var chronicle := ChronicleStore.new()
	assert_gt(chronicle.skins().size(), 0, "盤に出た駒がクロニクルに残る")
	var story: Dictionary = chronicle.story(CAMPAIGN, STAGE)
	assert_eq(story["start"].size(), 1, "この回の開始時の顔ぶれが残る")
	assert_eq(story["clear"].size(), 1, "この回のクリア後の顔ぶれが残る（書き出しの順序）")
