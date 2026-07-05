extends Control
class_name StageSelect
## ステージ選択画面。仕様 → doc/gdd/stage_select.md
## 左＝選んだ冒険譚の扉絵（無ければタイトルのプレースホルダ）／右＝ステージの縦リスト
## （locked/unlocked/cleared）→ ブリーフィング → 出撃。ステージはカードにしない
## ＝絵は冒険譚単位で1枚だけ。状態は持たず、show_campaign() のたびに導出して描く。
## 戻る・出撃はシグナルで SelectScreen へ委ねる。

signal stage_chosen(campaign_id: String, stage_id: String, path: String)
signal back_requested

const ROW_HEIGHT := 48.0

var _progress: CampaignProgress
var _title: Label
var _art: ColorRect                    # 左＝冒険譚の絵（絵が無ければタイトルのプレースホルダ）
var _art_label: Label
var _art_texture: TextureRect          # 冒険譚の扉絵（cover_path があれば表示）
var _stage_list: VBoxContainer         # 右＝縦リスト
var _briefing: ConfirmationDialog
var _pending := {}  # ブリーフィング表示中のステージ { campaign_id, stage_id, path }

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

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

	var back := Button.new()
	back.text = "← 冒険譚"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	header.add_child(_title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# --- 左: 冒険譚の絵（cover_path があれば扉絵／無ければタイトルのプレースホルダ） ---
	_art = ColorRect.new()
	_art.color = Color(0.15, 0.18, 0.24)
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art.size_flags_stretch_ratio = 2.0  # 絵:リスト ≒ 2:1
	_art.clip_contents = true  # 絵をパネル枠でトリミング
	body.add_child(_art)

	_art_texture = TextureRect.new()
	_art_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED  # パネルを覆う（はみ出しは clip）
	_art.add_child(_art_texture)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.add_child(center)

	_art_label = Label.new()
	_art_label.add_theme_font_size_override("font_size", 32)
	center.add_child(_art_label)

	# --- 右: ステージの縦リスト ---
	var stage_scroll := ScrollContainer.new()
	stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_scroll.size_flags_stretch_ratio = 1.0
	body.add_child(stage_scroll)

	_stage_list = VBoxContainer.new()
	_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_list.add_theme_constant_override("separation", 8)
	stage_scroll.add_child(_stage_list)

	_briefing = ConfirmationDialog.new()
	_briefing.ok_button_text = "出撃"
	_briefing.cancel_button_text = "戻る"
	_briefing.confirmed.connect(_on_sortie)
	add_child(_briefing)

func setup(progress: CampaignProgress) -> void:
	_progress = progress

## 指定した冒険譚のステージ一覧を表示する（SelectScreen から呼ばれる）。
func show_campaign(campaign_id: String) -> void:
	var c := _progress.campaign(campaign_id)
	if c.is_empty():
		return
	_title.text = String(c["title"])
	_set_cover(String(c.get("cover_path", "")), String(c["title"]))
	_clear_children(_stage_list)
	for i in c["stages"].size():
		_stage_list.add_child(_stage_row(campaign_id, c["stages"][i], i + 1))

## 扉絵を表示。cover_path があれば絵＋ラベル非表示、無ければプレースホルダ（タイトル）へ。
func _set_cover(cover_path: String, title: String) -> void:
	var tex: Texture2D = null
	if cover_path != "":
		tex = load(cover_path) as Texture2D
	_art_texture.texture = tex
	_art_texture.visible = tex != null
	_art_label.text = "" if tex != null else title

func _stage_row(campaign_id: String, s: Dictionary, number: int) -> Button:
	var label := "%d. %s" % [number, s["title"]]
	var row := Button.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_NONE
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	match _progress.stage_state(campaign_id, String(s["id"])):
		CampaignProgress.CLEARED:
			row.text = "✓ %s" % label
		CampaignProgress.LOCKED:
			row.text = "🔒 %s — %s" % [label, _progress.unlock_text(campaign_id, String(s["id"]))]
			row.disabled = true
		_:
			row.text = label
	if not row.disabled:
		row.pressed.connect(_open_briefing.bind(campaign_id, s))
	return row

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

## ボタン自身の pressed 発行中に呼ばれる（＝即時 free は「locked object」エラー）ため遅延解放。
func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
