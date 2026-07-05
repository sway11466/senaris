extends Control
class_name CampaignSelect
## キャンペーン選択画面。仕様 → doc/gdd/stage_select.md
## カード一覧＝絵（上）＋情報帯（下: タイトル／クリア数＋難易度星／タグ）。
## 状態は持たず、refresh() のたびに CampaignProgress から導出して描く。
## デバッグ冒険譚はデバッグビルドのみ表示（OS.is_debug_build）。選択はシグナルで SelectScreen へ委ねる。

signal campaign_chosen(campaign_id: String)

const CARD_SIZE := Vector2(340, 330)  # 絵(340x210)＋情報帯
const CARD_ART_HEIGHT := 210.0        # 絵は黄金比 1.618:1（340x210）

var _progress: CampaignProgress
var _cards: HFlowContainer

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

	var title := Label.new()
	title.text = "冒険譚を選ぶ"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_cards = HFlowContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_cards)

func setup(progress: CampaignProgress) -> void:
	_progress = progress

## カード一覧を作り直す（クリア数などを都度導出するため表示ごとに呼ぶ）。
func refresh() -> void:
	_clear_children(_cards)
	for c in _progress.campaigns(OS.is_debug_build()):
		_cards.add_child(_campaign_card(c))

## 冒険譚カード＝絵（上）＋情報帯（下）。
## クリック判定はカード全面の Button。中身は mouse_filter=IGNORE でクリックを Button へ透過。
func _campaign_card(c: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	card.pressed.connect(_on_card_pressed.bind(String(c["id"])))

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

func _on_card_pressed(campaign_id: String) -> void:
	campaign_chosen.emit(campaign_id)

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

## ボタン自身の pressed 発行中に呼ばれる（＝即時 free は「locked object」エラー）ため遅延解放。
func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
