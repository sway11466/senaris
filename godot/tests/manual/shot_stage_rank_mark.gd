extends SceneTree
## feature-19 検証用（使い捨て）: ステージの木札に押すランクの印を撮る。
## 進捗は使い捨てのセーブに作る（ProgressStore は既定パスだと本物の進捗を読み書きするので必ず別パス）。
## 実行: godot --path . -s res://tests/manual/shot_stage_rank_mark.gd（--headless 不可）

const OUT_DIR := "res://tests/manual/out"
const CAMPAIGN := "tutorial1-goblin-raid"
const RANKS := ["S", "A", "B", "S", "A"]  # 先頭から5ステージぶん（残りは未クリア＝裏返しの札）
const MOCK_SAVE := "user://mock_rank_progress.json"  # 本物の progress.json を汚さないための捨てファイル

var _frame := 0
var _screen: SelectScreen
var _idx := -1

func _process(_delta: float) -> bool:
	_frame += 1
	if _screen == null:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		if FileAccess.file_exists(MOCK_SAVE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(MOCK_SAVE))
		var progress := CampaignProgress.new(CampaignCatalog.load_all(), ProgressStore.new(MOCK_SAVE))
		var stages: Array = progress.campaign(CAMPAIGN).get("stages", [])
		for i in mini(RANKS.size(), stages.size()):
			var sid := String(stages[i].get("id", ""))
			progress.record_clear(CAMPAIGN, sid)
			progress.record_rank(CAMPAIGN, sid, String(RANKS[i]))
		_screen = SelectScreen.new()
		root.add_child(_screen)
		_screen.setup(progress)
		_screen.open()
		_frame = 0
		return false
	if _frame % 12 != 0:
		return false
	if _idx >= 0:
		root.get_texture().get_image().save_png(OUT_DIR.path_join("stage_rank.png"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MOCK_SAVE))  # 捨てファイルを片付ける
		quit()
		return true
	_idx += 1
	_screen._on_campaign_chosen(CAMPAIGN, -1)  # 冒険譚を選んだのと同じ経路でステージ一覧を出す
	return false
