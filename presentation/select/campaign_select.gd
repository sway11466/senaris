extends Control
class_name CampaignSelect
## キャンペーン選択画面＝酒場の依頼ボード。方向性 → doc/gdd/stage_select.md
## 木のボードに、冒険譚を縦長の依頼書（羊皮紙ポスター）としてピン留め表示する。
## 状態は持たず、refresh() のたびに CampaignProgress から導出して描く。
## デバッグ冒険譚はデバッグビルドのみ表示（OS.is_debug_build）。選択はシグナルで SelectScreen へ委ねる。

signal campaign_chosen(campaign_id: String)

const POSTER_SIZE := Vector2(260, 380)  # 縦長の貼り紙
const POSTER_ART_HEIGHT := 200.0

var _progress: CampaignProgress
var _posters: HFlowContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(vbox)

	# 見出し＝木の看板プレート
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", TavernTheme.plaque_stylebox())
	plaque.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var plaque_label := Label.new()
	plaque_label.text = "― 酒場の依頼ボード ―"
	plaque_label.add_theme_font_size_override("font_size", 24)
	plaque_label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.62))
	plaque.add_child(plaque_label)
	vbox.add_child(plaque)

	# ボード本体（木板）＝貼り紙を貼る面
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", TavernTheme.board_stylebox())
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(board)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_child(scroll)

	_posters = HFlowContainer.new()
	_posters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_posters.add_theme_constant_override("h_separation", 20)
	_posters.add_theme_constant_override("v_separation", 20)
	scroll.add_child(_posters)

func setup(progress: CampaignProgress) -> void:
	_progress = progress

## 貼り紙一覧を作り直す（クリア数などを都度導出するため表示ごとに呼ぶ）。
func refresh() -> void:
	_clear_children(_posters)
	for c in _progress.campaigns(OS.is_debug_build()):
		_posters.add_child(_poster(c))

## 冒険譚の依頼書＝羊皮紙の貼り紙。クリック判定はカード全面の Button。
func _poster(c: Dictionary) -> Control:
	# 封蝋のピンを紙からはみ出させて留めるため、ラッパーで上に余白を取る
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 12)

	var card := Button.new()
	card.custom_minimum_size = POSTER_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	for state in ["normal", "hover", "pressed", "disabled"]:
		var bright := 1.06 if state == "hover" else 1.0
		card.add_theme_stylebox_override(state, TavernTheme.parchment_stylebox(bright))
	card.pressed.connect(_on_card_pressed.bind(String(c["id"])))
	wrap.add_child(card)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	card.add_child(pad)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)

	# 上: カバー絵（card 用クロップ優先／無ければ cover／どちらも無ければ暗色プレースホルダ）
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0.0, POSTER_ART_HEIGHT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.clip_contents = true
	var art_path := String(c.get("card_path", ""))
	if art_path.is_empty():
		art_path = String(c.get("cover_path", ""))
	if not art_path.is_empty():
		art.texture = load(art_path) as Texture2D
	content.add_child(art)
	content.add_child(_poster_info(c))
	_ignore_mouse(content)
	pad.add_child(content)

	# 封蝋のピン（紙の上辺中央・はみ出し配置）
	var seal := TavernTheme.wax_seal()
	seal.set_anchors_preset(Control.PRESET_CENTER_TOP)
	seal.position = Vector2(POSTER_SIZE.x / 2.0 - 13.0, -1.0)
	card.add_child(seal)

	# 全ステージ制覇なら「討伐済」の焼き印を斜めに押す
	if not c["debug"]:
		var total: int = c["stages"].size()
		if total > 0 and _progress.cleared_count(String(c["id"])) >= total:
			var stamp := TavernTheme.stamp("討伐済", TavernTheme.WAX, -12.0)
			stamp.position = Vector2(POSTER_SIZE.x - 120.0, POSTER_ART_HEIGHT - 30.0)
			card.add_child(stamp)
	return wrap

func _on_card_pressed(campaign_id: String) -> void:
	campaign_chosen.emit(campaign_id)

## 貼り紙下部の情報（タイトル／クリア数／危険度／タグ）。デバッグ冒険譚は注記のみ。
func _poster_info(c: Dictionary) -> Control:
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = String(c["title"])
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TavernTheme.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title)

	if c["debug"]:
		var note := Label.new()
		note.text = "（開発ビルド限定）"
		note.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
		info.add_child(note)
		return info

	# クリア数
	var total: int = c["stages"].size()
	var done := _progress.cleared_count(String(c["id"]))
	var count := Label.new()
	count.text = "討伐 %d / %d 節" % [done, total]
	count.add_theme_color_override("font_color", TavernTheme.INK)
	info.add_child(count)

	# 危険度（焼き印風の★）
	var danger := HBoxContainer.new()
	danger.add_theme_constant_override("separation", 6)
	var danger_label := Label.new()
	danger_label.text = "危険度"
	danger_label.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	danger.add_child(danger_label)
	danger.add_child(_make_stars(int(c.get("difficulty", 0))))
	info.add_child(danger)

	# タグ（蝋のキーワード印）
	var tags: Array = c.get("tags", [])
	if not tags.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		for t in tags:
			chips.add_child(TavernTheme.tag_chip(String(t)))
		info.add_child(chips)
	return info

## 危険度を★（塗り）＋☆（空き）の5段階で表示（焼き印の茶色）。
func _make_stars(difficulty: int) -> Label:
	var n := clampi(difficulty, 0, 5)
	var star := Label.new()
	star.text = "★".repeat(n) + "☆".repeat(5 - n)
	star.add_theme_color_override("font_color", TavernTheme.BRAND)
	return star

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
