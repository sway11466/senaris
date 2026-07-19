extends CanvasLayer
class_name SelectScreen
## セレクト画面のコーディネーター。仕様 → doc/gdd/stage_select.md
## キャンペーン選択(CampaignSelect)とステージ選択(StageSelect)の2画面を保持し、visible で切り替える。
## 背景と画面遷移・シグナル中継だけを担い、各画面の中身は持たない。出撃はシグナルで main へ委ねる。

signal stage_chosen(campaign_id: String, stage_id: String, path: String)
## セレクトを開いた（＝ステージ外の場面に戻った）。main が BGM をメニュー曲に戻すのに使う。
signal opened

var _campaign_select: CampaignSelect
var _stage_select: StageSelect

func _ready() -> void:
	layer = 10  # 盤・HUD より手前（全画面で覆う）
	add_child(TavernTheme.wall_background())  # 酒場の木の壁（両画面共通の背景）

	_campaign_select = CampaignSelect.new()
	_campaign_select.set_anchors_preset(Control.PRESET_FULL_RECT)
	_campaign_select.campaign_chosen.connect(_on_campaign_chosen)
	add_child(_campaign_select)

	_stage_select = StageSelect.new()
	_stage_select.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_select.back_requested.connect(_show_campaigns)
	_stage_select.stage_chosen.connect(_on_stage_chosen)
	add_child(_stage_select)

	visible = false

func setup(progress: CampaignProgress) -> void:
	_campaign_select.setup(progress)
	_stage_select.setup(progress)

## セレクト画面を開く（キャンペーン一覧から）。
func open() -> void:
	visible = true
	_show_campaigns()
	opened.emit()

func close() -> void:
	visible = false

func _show_campaigns() -> void:
	_stage_select.visible = false
	_campaign_select.visible = true
	_campaign_select.refresh()

func _on_campaign_chosen(campaign_id: String, variant: int = -1) -> void:
	_campaign_select.visible = false
	_stage_select.visible = true
	_stage_select.show_campaign(campaign_id, variant)  # variant＝カードで表示中の絵に固定（<0 はランダム）

func _on_stage_chosen(campaign_id: String, stage_id: String, path: String) -> void:
	stage_chosen.emit(campaign_id, stage_id, path)
	close()
