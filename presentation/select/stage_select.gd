extends CanvasLayer
class_name StageSelect
## ステージセレクト画面（カード型UI）。仕様 → doc/gdd/stage_select.md
## 冒険譚カード（進捗 n/m）→ ステージカード（locked/unlocked/cleared）→ ブリーフィング → 出撃。
## 状態は持たず、表示のたびに CampaignProgress から導出して描く。
## デバッグ冒険譚はデバッグビルドのみ表示（OS.is_debug_build）。出撃はシグナルで main へ委ねる。

signal stage_chosen(campaign_id: String, stage_id: String, path: String)

const CARD_SIZE := Vector2(240, 120)

var _progress: CampaignProgress
var _title: Label
var _back: Button
var _cards: HFlowContainer
var _briefing: ConfirmationDialog
var _pending := {}  # ブリーフィング表示中のステージ { campaign_id, stage_id, path }

func _ready() -> void:
	layer = 10  # 盤・HUD より手前（全画面で覆う）
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	_back = Button.new()
	_back.text = "← 冒険譚"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(_show_campaigns)
	header.add_child(_back)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	header.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_cards = HFlowContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_cards)

	_briefing = ConfirmationDialog.new()
	_briefing.ok_button_text = "出撃"
	_briefing.cancel_button_text = "戻る"
	_briefing.confirmed.connect(_on_sortie)
	add_child(_briefing)
	visible = false

func setup(progress: CampaignProgress) -> void:
	_progress = progress

## セレクト画面を開く（冒険譚一覧から）。
func open() -> void:
	visible = true
	_show_campaigns()

func close() -> void:
	visible = false

# --- 冒険譚一覧 ---

func _show_campaigns() -> void:
	_back.visible = false
	_title.text = "冒険譚を選ぶ"
	_clear_cards()
	for c in _progress.campaigns(OS.is_debug_build()):
		_cards.add_child(_campaign_card(c))

func _campaign_card(c: Dictionary) -> Button:
	var text: String
	if c["debug"]:
		text = "%s\n（開発ビルド限定）" % c["title"]
	else:
		var total: int = c["stages"].size()
		var done := _progress.cleared_count(String(c["id"]))
		var badge := "  ✓" if (total > 0 and done >= total) else ""
		text = "%s\n%d / %d%s" % [c["title"], done, total, badge]
	var card := _card(text)
	card.pressed.connect(_show_stages.bind(String(c["id"])))
	return card

# --- ステージ一覧 ---

func _show_stages(campaign_id: String) -> void:
	var c := _progress.campaign(campaign_id)
	if c.is_empty():
		return
	_back.visible = true
	_title.text = String(c["title"])
	_clear_cards()
	for i in c["stages"].size():
		_cards.add_child(_stage_card(campaign_id, c["stages"][i], i + 1))

func _stage_card(campaign_id: String, s: Dictionary, number: int) -> Button:
	var label := "%d. %s" % [number, s["title"]]
	var card: Button
	match _progress.stage_state(campaign_id, String(s["id"])):
		CampaignProgress.CLEARED:
			card = _card("%s\n✓ クリア済み" % label)
		CampaignProgress.LOCKED:
			card = _card("🔒 %s\n%s" % [label, _progress.unlock_text(campaign_id, String(s["id"]))])
			card.disabled = true
		_:
			card = _card(label)
	if not card.disabled:
		card.pressed.connect(_open_briefing.bind(campaign_id, s))
	return card

# --- ブリーフィング → 出撃 ---

func _open_briefing(campaign_id: String, s: Dictionary) -> void:
	_pending = {
		"campaign_id": campaign_id,
		"stage_id": String(s["id"]),
		"path": String(s["path"]),
	}
	_briefing.title = String(s["title"])
	_briefing.dialog_text = "「%s」に出撃しますか？" % s["title"]
	_briefing.popup_centered()

func _on_sortie() -> void:
	if _pending.is_empty():
		return
	stage_chosen.emit(_pending["campaign_id"], _pending["stage_id"], _pending["path"])
	_pending = {}
	close()

# --- 部品 ---

func _card(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE  # Enter(手番終了)で誤発火しない
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b

func _clear_cards() -> void:
	# カード自身の pressed 発行中に呼ばれる（＝即時 free は「locked object」エラー）ため遅延解放。
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
