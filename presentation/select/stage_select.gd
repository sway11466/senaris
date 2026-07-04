extends CanvasLayer
class_name StageSelect
## ステージセレクト画面。仕様 → doc/gdd/stage_select.md
## 冒険譚＝カード（進捗 n/m・将来は絵を載せる）→ 選ぶと左に冒険譚の絵（今はプレースホルダ）＋
## 右にステージの縦リスト（locked/unlocked/cleared）→ ブリーフィング → 出撃。
## ステージはカードにしない＝絵は冒険譚単位で1枚だけ用意する方針。
## 状態は持たず、表示のたびに CampaignProgress から導出して描く。
## デバッグ冒険譚はデバッグビルドのみ表示（OS.is_debug_build）。出撃はシグナルで main へ委ねる。

signal stage_chosen(campaign_id: String, stage_id: String, path: String)

const CARD_SIZE := Vector2(340, 330)  # 絵(340x210)＋情報帯
const CARD_ART_HEIGHT := 210.0        # 絵は黄金比 1.618:1（340x210）
const ROW_HEIGHT := 48.0

var _progress: CampaignProgress
var _title: Label
var _back: Button
var _campaign_scroll: ScrollContainer  # 冒険譚ビュー（カード一覧）
var _cards: HFlowContainer
var _art: Control                      # ステージビュー左＝冒険譚の絵（絵が無ければタイトルのプレースホルダ）
var _art_label: Label
var _art_texture: TextureRect          # 冒険譚の扉絵（cover_path があれば表示）
var _stage_scroll: ScrollContainer     # ステージビュー右＝縦リスト
var _stage_list: VBoxContainer
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

	# 本文＝2ビューを重ねて visible で切り替える（冒険譚カード一覧 ／ 絵＋ステージリスト）
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# --- 冒険譚ビュー: カード一覧 ---
	_campaign_scroll = ScrollContainer.new()
	_campaign_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_campaign_scroll)

	_cards = HFlowContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	_campaign_scroll.add_child(_cards)

	# --- ステージビュー左: 冒険譚の絵（cover_path があれば扉絵／無ければタイトルのプレースホルダ） ---
	_art = ColorRect.new()
	(_art as ColorRect).color = Color(0.15, 0.18, 0.24)
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

	# --- ステージビュー右: ステージの縦リスト ---
	_stage_scroll = ScrollContainer.new()
	_stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_scroll.size_flags_stretch_ratio = 1.0
	body.add_child(_stage_scroll)

	_stage_list = VBoxContainer.new()
	_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_list.add_theme_constant_override("separation", 8)
	_stage_scroll.add_child(_stage_list)

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

# --- 冒険譚一覧（カード） ---

func _show_campaigns() -> void:
	_back.visible = false
	_title.text = "冒険譚を選ぶ"
	_campaign_scroll.visible = true
	_art.visible = false
	_stage_scroll.visible = false
	_clear_children(_cards)
	for c in _progress.campaigns(OS.is_debug_build()):
		_cards.add_child(_campaign_card(c))

## 冒険譚カード＝絵（上）＋情報帯（下: タイトル／クリア数＋難易度星／タグ）。
## クリック判定はカード全面の Button。中身は mouse_filter=IGNORE でクリックを Button へ透過。
func _campaign_card(c: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	card.pressed.connect(_show_stages.bind(String(c["id"])))

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 0)

	# 上: 絵（card 用クロップ優先／無ければ cover／どちらも無ければ暗色プレースホルダ）
	var art_path := String(c.get("card_path", ""))
	if art_path.is_empty():
		art_path = String(c.get("cover_path", ""))
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0.0, CARD_ART_HEIGHT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.clip_contents = true
	if not art_path.is_empty():
		art.texture = load(art_path) as Texture2D
	content.add_child(art)

	content.add_child(_card_info(c))
	_ignore_mouse(content)  # 中身はクリックを透過（下の Button が受ける）
	card.add_child(content)
	return card

## カード下部の情報帯。デバッグ冒険譚は開発ビルド注記のみ。
func _card_info(c: Dictionary) -> Control:
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	margin.add_child(info)

	var title := Label.new()
	title.text = String(c["title"])
	title.add_theme_font_size_override("font_size", 20)
	info.add_child(title)

	if c["debug"]:
		var note := Label.new()
		note.text = "（開発ビルド限定）"
		note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		info.add_child(note)
		return margin

	# クリア数 ＋ 難易度星
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	var total: int = c["stages"].size()
	var done := _progress.cleared_count(String(c["id"]))
	var count := Label.new()
	count.text = "クリア %d / %d" % [done, total]
	if total > 0 and done >= total:
		count.text += " ✓"
	stats.add_child(count)
	var diff_label := Label.new()
	diff_label.text = "難易度"
	stats.add_child(diff_label)
	stats.add_child(_make_stars(int(c.get("difficulty", 0))))
	info.add_child(stats)

	# タグ（チップ）
	var tags: Array = c.get("tags", [])
	if not tags.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		for t in tags:
			chips.add_child(_make_chip(String(t)))
		info.add_child(chips)
	return margin

## 難易度を★（塗り）＋☆（空き）の5段階で表示。
func _make_stars(difficulty: int) -> Label:
	var n := clampi(difficulty, 0, 5)
	var star := Label.new()
	star.text = "★".repeat(n) + "☆".repeat(5 - n)
	star.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	return star

## タグチップ＝角丸背景の小ラベル。
func _make_chip(text: String) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.26, 0.34)
	sb.set_corner_radius_all(6)
	sb.set_content_margin(SIDE_LEFT, 8)
	sb.set_content_margin(SIDE_RIGHT, 8)
	sb.set_content_margin(SIDE_TOP, 2)
	sb.set_content_margin(SIDE_BOTTOM, 2)
	chip.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	chip.add_child(label)
	return chip

## ノードと全子孫の mouse_filter を IGNORE にする（カード内容をクリック透過させる）。
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

# --- ステージ一覧（左＝冒険譚の絵／右＝縦リスト） ---

func _show_stages(campaign_id: String) -> void:
	var c := _progress.campaign(campaign_id)
	if c.is_empty():
		return
	_back.visible = true
	_title.text = String(c["title"])
	_campaign_scroll.visible = false
	_art.visible = true
	_stage_scroll.visible = true
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
	close()

# --- 部品 ---

func _clear_children(container: Node) -> void:
	# ボタン自身の pressed 発行中に呼ばれる（＝即時 free は「locked object」エラー）ため遅延解放。
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
