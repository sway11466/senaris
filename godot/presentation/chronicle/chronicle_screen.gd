extends CanvasLayer
class_name ChronicleScreen
## クロニクル（冒険の記録）。タイトルのメニューから開き、全画面の暗幕の上に
## 目次と中身を出す。仕様 → doc/gdd/chronicle.md
##
## 画面の様式はマニュアル・設定と同じ（全画面の暗幕、木の板のボタン、戻るは左下）。
## 中は3章＝ユニット／陣形スキル／冒険譚。目次で章を選び、右に中身を出す。
## 冒険譚だけ2段目がある（戦果／物語／設定集）。戻るで上の段へ上がる。

signal closed  # 畳み終わった（暗幕が抜けたところ）

const LAYER := 78  # マニュアル(77)より前面。同時に開くことはないが番号は専用に取る

const SCRIM_COLOR := Color(0.03, 0.03, 0.04, 0.92)
const FADE_SEC := 0.25

const UI_GRAY := Color(0.82, 0.82, 0.82)
const ACCENT := Color(0.90, 0.82, 0.62)
const DIM_GRAY := Color(0.45, 0.45, 0.45)  # 未解放の枠（？のテキスト）
const FRAME_COLOR := Color(0.82, 0.82, 0.82, 0.75)
const FRAME_WIDTH := 2

const TITLE_FONT_SIZE := 24
const HEAD_FONT_SIZE := 20
const BODY_FONT_SIZE := 16
const TOC_FONT_SIZE := 16
const COUNT_FONT_SIZE := 14
const DETAIL_FONT_SIZE := 15

const EDGE := 48
const TOP := 18
const HEAD_GAP := 14
const BOTTOM := 24
const TOC_BOTTOM := 96
const TOC_WIDTH := 200
const PANE_GAP := 32
const TOC_GAP := 4
const TOC_BUTTON_HEIGHT := 32
const CATEGORY_GAP := 20  # カテゴリ間の余白
const ITEM_GAP := 6       # アイテム間の余白
const ITEM_HEIGHT := 36   # アイテム1行の高さ

## 章の定数
enum Chapter { UNITS, FORMATIONS, CAMPAIGNS }
const CHAPTER_KEYS := ["ui.chronicle.units", "ui.chronicle.formations", "ui.chronicle.campaigns"]

## 冒険譚のなかの節（2段目の目次）
enum CampaignSection { RESULTS, STORY, LORE }
const CAMPAIGN_SECTION_KEYS := ["ui.chronicle.results", "ui.chronicle.story", "ui.chronicle.lore"]

var _root: Control
var _heading: Label
var _toc_box: VBoxContainer
var _content_scroll: ScrollContainer
var _content_box: VBoxContainer
var _detail_box: VBoxContainer  # 右の詳細ペイン（ユニットを選んだとき）
var _back: Button

var _chapter: int = Chapter.UNITS
var _store: ChronicleStore = null
var _progress: CampaignProgress = null
var _skins: Dictionary = {}  # SkinCatalog（main.gd と同じインスタンスを参照しない＝開くときに組む）
var _selected_skin_id := ""  # ユニット章で選んでいるスキン
var _selected_recipe_id := ""  # 陣形章で選んでいるレシピ
var _selected_campaign_id := ""  # 冒険譚を選んでいるとき（空ならリスト）
var _campaign_section: int = CampaignSection.RESULTS  # 冒険譚内の節

func _ready() -> void:
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	_heading = Label.new()
	_heading.text = tr("ui.chronicle.title")
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_heading.add_theme_color_override("font_color", ACCENT)
	_heading.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_heading.offset_top = TOP
	_heading.offset_bottom = TOP + TITLE_FONT_SIZE + 8
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_heading)

	_root.add_child(_panes())

	_back = TavernTheme.back_button(tr("ui.chronicle.back"))
	TavernTheme.place_bottom_left(_back)
	_back.pressed.connect(_on_back)
	_root.add_child(_back)

	visible = false

## 開く。開くたびに最新のストアから組み直す。
func open(store: ChronicleStore, progress: CampaignProgress) -> void:
	_store = store
	_progress = progress
	_skins = SkinCatalog.load_standard()
	_chapter = Chapter.UNITS
	_selected_skin_id = ""
	_selected_recipe_id = ""
	_selected_campaign_id = ""
	_campaign_section = CampaignSection.RESULTS
	_back.text = tr("ui.chronicle.back")
	_rebuild()
	visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_SEC)

func close() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	tween.tween_callback(func() -> void:
		visible = false
		closed.emit())

func refresh_labels() -> void:
	_heading.text = tr("ui.chronicle.title")
	_back.text = tr("ui.chronicle.back")
	if visible:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
	get_viewport().set_input_as_handled()

func _on_back() -> void:
	SfxPlayer.play_event("menu_back")
	# 冒険譚の2段目にいれば上の段（冒険譚リスト）へ戻る。それ以外は画面を出る。
	if _chapter == Chapter.CAMPAIGNS and not _selected_campaign_id.is_empty():
		_selected_campaign_id = ""
		_campaign_section = CampaignSection.RESULTS
		_back.text = tr("ui.chronicle.back")
		_rebuild()
		return
	close()

# ---------------------------------------------------------------------------
# ペイン
# ---------------------------------------------------------------------------

func _panes() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PANE_GAP)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = EDGE
	row.offset_right = -EDGE
	row.offset_top = TOP + TITLE_FONT_SIZE + HEAD_GAP
	row.offset_bottom = -BOTTOM

	# 左：目次
	var toc_scroll := ScrollContainer.new()
	toc_scroll.custom_minimum_size = Vector2(TOC_WIDTH, 0)
	toc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_toc_box = VBoxContainer.new()
	_toc_box.add_theme_constant_override("separation", TOC_GAP)
	_toc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toc_scroll.add_child(_toc_box)
	row.add_child(toc_scroll)

	# 右：中身（2段＝上がカテゴリ一覧のスクロール、下が詳細）
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", HEAD_GAP)

	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_box = VBoxContainer.new()
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", ITEM_GAP)
	_content_scroll.add_child(_content_box)
	right.add_child(_content_scroll)

	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.custom_minimum_size = Vector2(0, 160)
	_detail_box.add_theme_constant_override("separation", 4)
	right.add_child(_detail_box)

	row.add_child(right)
	return row

# ---------------------------------------------------------------------------
# 目次
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	_rebuild_toc()
	_rebuild_content()

func _rebuild_toc() -> void:
	for c in _toc_box.get_children():
		c.queue_free()
	# 冒険譚を選んでいるとき＝2段目（戦果／物語／設定集）
	if _chapter == Chapter.CAMPAIGNS and not _selected_campaign_id.is_empty():
		_rebuild_toc_campaign()
		return
	# 1段目（ユニット／陣形スキル／冒険譚）
	for i in CHAPTER_KEYS.size():
		var btn := TavernTheme.wood_button(tr(CHAPTER_KEYS[i]))
		btn.custom_minimum_size = Vector2(TOC_WIDTH - 8, TOC_BUTTON_HEIGHT)
		var idx := i
		btn.pressed.connect(func() -> void: _select_chapter(idx))
		_toc_box.add_child(btn)
		if i == _chapter:
			_add_frame(btn)

## 冒険譚の2段目の目次（戦果／物語／設定集）。
func _rebuild_toc_campaign() -> void:
	for i in CAMPAIGN_SECTION_KEYS.size():
		var btn := TavernTheme.wood_button(tr(CAMPAIGN_SECTION_KEYS[i]))
		btn.custom_minimum_size = Vector2(TOC_WIDTH - 8, TOC_BUTTON_HEIGHT)
		var idx := i
		btn.pressed.connect(func() -> void: _select_campaign_section(idx))
		_toc_box.add_child(btn)
		if i == _campaign_section:
			_add_frame(btn)

func _select_campaign_section(idx: int) -> void:
	if idx == _campaign_section:
		return
	_campaign_section = idx
	SfxPlayer.play_event("menu_select")
	_rebuild()

func _select_chapter(idx: int) -> void:
	if idx == _chapter:
		return
	_chapter = idx
	_selected_skin_id = ""
	_selected_recipe_id = ""
	_selected_campaign_id = ""
	_campaign_section = CampaignSection.RESULTS
	_back.text = tr("ui.chronicle.back")
	SfxPlayer.play_event("menu_select")
	_rebuild()

func _add_frame(c: Control) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = FRAME_COLOR
	sb.border_width_left = FRAME_WIDTH
	sb.border_width_right = FRAME_WIDTH
	sb.border_width_top = FRAME_WIDTH
	sb.border_width_bottom = FRAME_WIDTH
	if c is Button:
		c.add_theme_stylebox_override("normal", sb)

# ---------------------------------------------------------------------------
# 中身
# ---------------------------------------------------------------------------

func _rebuild_content() -> void:
	for c in _content_box.get_children():
		c.queue_free()
	for c in _detail_box.get_children():
		c.queue_free()
	match _chapter:
		Chapter.UNITS:
			_build_units_chapter()
		Chapter.FORMATIONS:
			_build_formations_chapter()
		Chapter.CAMPAIGNS:
			if _selected_campaign_id.is_empty():
				_build_campaigns_chapter()
			else:
				match _campaign_section:
					CampaignSection.RESULTS:
						_build_campaign_results()
					CampaignSection.STORY:
						_build_placeholder(tr("ui.chronicle.story"))
					CampaignSection.LORE:
						_build_campaign_lore()

func _build_placeholder(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	label.add_theme_color_override("font_color", DIM_GRAY)
	_content_box.add_child(label)

# ---------------------------------------------------------------------------
# ユニット章
# ---------------------------------------------------------------------------

## カテゴリごとにユニットを束ねて出す。カテゴリの出現順と各スキンの並び順は
## SkinCatalog の __by_id__ 辞書の挿入順（＝CSV の行順）に従う。
func _build_units_chapter() -> void:
	if _store == null:
		return
	var ordered := _ordered_skins()
	var encountered := _store.skins()  # { skin_id: { first: campaign_id } }

	for cat_entry in ordered:
		var category: String = cat_entry["category"]
		var skins: Array = cat_entry["skins"]
		var found := 0
		for s in skins:
			if encountered.has(s.skin_id):
				found += 1

		# カテゴリ見出し + カウント
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var cat_label := Label.new()
		cat_label.text = tr("unit_group.%s.name" % category)
		cat_label.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
		cat_label.add_theme_color_override("font_color", ACCENT)
		head.add_child(cat_label)
		var count_label := Label.new()
		count_label.text = tr("ui.chronicle.count") % [found, skins.size()]
		count_label.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
		count_label.add_theme_color_override("font_color", UI_GRAY)
		count_label.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(count_label)
		_content_box.add_child(head)

		# スキンの行を並べる
		for s in skins:
			var known := encountered.has(s.skin_id)
			var row := _unit_row(s, known)
			_content_box.add_child(row)

		# カテゴリ間の余白
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, CATEGORY_GAP)
		_content_box.add_child(spacer)

	# 選択中のスキンがあれば詳細を出す
	if not _selected_skin_id.is_empty():
		_build_unit_detail(_selected_skin_id)

## SkinCatalog の __by_id__ からカテゴリ順にまとめた配列を返す。
## [{ "category": String, "skins": [UnitSkin, ...] }, ...]
func _ordered_skins() -> Array:
	var by_id: Dictionary = _skins.get(SkinCatalog.BY_ID_KEY, {})
	var categories: Array = []  # [{ category, skins }]
	var cat_map := {}  # category -> index in categories
	for skin_id in by_id:
		var s: UnitSkin = by_id[skin_id]
		if not cat_map.has(s.category):
			cat_map[s.category] = categories.size()
			categories.append({ "category": s.category, "skins": [] })
		categories[cat_map[s.category]]["skins"].append(s)
	return categories

## ユニット1行。解放済みは名前とアイコン、未解放は「？」。
func _unit_row(skin: UnitSkin, known: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, ITEM_HEIGHT)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	if known:
		btn.text = "  " + tr("unit.%s.name" % skin.skin_id)
		btn.add_theme_color_override("font_color", UI_GRAY)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		var sid := skin.skin_id
		btn.pressed.connect(func() -> void: _select_unit(sid))
	else:
		btn.text = "  " + tr("ui.chronicle.unknown")
		btn.add_theme_color_override("font_color", DIM_GRAY)
		btn.add_theme_color_override("font_hover_color", DIM_GRAY)
		btn.disabled = true
	btn.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	# 透明な板にする（木の板は目次だけ＝中身は素のボタン）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	btn.add_theme_stylebox_override("hover", sb_hover)
	var sb_disabled := StyleBoxFlat.new()
	sb_disabled.bg_color = Color.TRANSPARENT
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	if known and skin.skin_id == _selected_skin_id:
		var sb_sel := StyleBoxFlat.new()
		sb_sel.bg_color = Color(1.0, 1.0, 1.0, 0.08)
		sb_sel.border_color = FRAME_COLOR
		sb_sel.border_width_left = FRAME_WIDTH
		btn.add_theme_stylebox_override("normal", sb_sel)
	return btn

func _select_unit(skin_id: String) -> void:
	_selected_skin_id = skin_id
	SfxPlayer.play_event("menu_select")
	_rebuild_content()

# ---------------------------------------------------------------------------
# ユニット詳細
# ---------------------------------------------------------------------------

func _build_unit_detail(skin_id: String) -> void:
	var skin := SkinCatalog.skin_by_id(_skins, skin_id)
	if skin == null:
		return
	# 名前
	var name_label := Label.new()
	name_label.text = tr("unit.%s.name" % skin_id)
	name_label.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	name_label.add_theme_color_override("font_color", ACCENT)
	_detail_box.add_child(name_label)
	# カテゴリ
	var cat_label := Label.new()
	cat_label.text = tr("unit_group.%s.name" % skin.category)
	cat_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	cat_label.add_theme_color_override("font_color", DIM_GRAY)
	_detail_box.add_child(cat_label)
	# 初出の冒険譚
	var encountered: Dictionary = _store.skins()
	var entry: Dictionary = encountered.get(skin_id, {})
	var first_campaign: String = entry.get("first", "")
	if not first_campaign.is_empty() and _progress != null:
		var campaign := _progress.campaign(first_campaign)
		if not campaign.is_empty():
			var first_label := Label.new()
			var campaign_title := tr(String(campaign.get("id", first_campaign)))
			first_label.text = "%s: %s" % [tr("ui.chronicle.first_seen"), campaign_title]
			first_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
			first_label.add_theme_color_override("font_color", UI_GRAY)
			_detail_box.add_child(first_label)
	# 説明文（names.csv に unit.<skin_id>.desc があれば）
	_add_desc_label("unit.%s.desc" % skin_id)

# ---------------------------------------------------------------------------
# 陣形章
# ---------------------------------------------------------------------------

## 陣形章のレシピ定数。shape → 翻訳キーの引き。
const SHAPE_KEYS := {
	"triangle": "ui.chronicle.shape_triangle",
	"escort": "ui.chronicle.shape_escort",
	"cluster": "ui.chronicle.shape_cluster",
}

## Formation.RECIPES から陣形スキル（shape != "solo"）だけを挿入順に返す。
func _formation_recipes() -> Array:
	var out: Array = []
	for recipe_id in Formation.RECIPES:
		var r: Dictionary = Formation.RECIPES[recipe_id]
		if r.get("shape", "") != "solo":
			out.append(recipe_id)
	return out

## 陣形章を組む。レシピの一覧と「埋まった数／全部」、選択で詳細。
func _build_formations_chapter() -> void:
	if _store == null:
		return
	var recipes := _formation_recipes()
	var encountered := _store.recipes()  # { recipe_id: { first: campaign_id } }

	var found := 0
	for rid in recipes:
		if encountered.has(rid):
			found += 1

	# 見出し＋カウント
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var head_label := Label.new()
	head_label.text = tr("ui.chronicle.formations")
	head_label.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	head_label.add_theme_color_override("font_color", ACCENT)
	head.add_child(head_label)
	var count_label := Label.new()
	count_label.text = tr("ui.chronicle.count") % [found, recipes.size()]
	count_label.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
	count_label.add_theme_color_override("font_color", UI_GRAY)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(count_label)
	_content_box.add_child(head)

	# レシピの行を並べる
	for rid in recipes:
		var known := encountered.has(rid)
		var row := _recipe_row(rid, known)
		_content_box.add_child(row)

	# 選択中のレシピがあれば詳細を出す
	if not _selected_recipe_id.is_empty():
		_build_recipe_detail(_selected_recipe_id)

## レシピ1行。解放済みは名前、未解放は「？」。
func _recipe_row(recipe_id: String, known: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, ITEM_HEIGHT)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	if known:
		btn.text = "  " + tr("recipe.%s.name" % recipe_id)
		btn.add_theme_color_override("font_color", UI_GRAY)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		var rid := recipe_id
		btn.pressed.connect(func() -> void: _select_recipe(rid))
	else:
		btn.text = "  " + tr("ui.chronicle.unknown")
		btn.add_theme_color_override("font_color", DIM_GRAY)
		btn.add_theme_color_override("font_hover_color", DIM_GRAY)
		btn.disabled = true
	btn.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	btn.add_theme_stylebox_override("hover", sb_hover)
	var sb_disabled := StyleBoxFlat.new()
	sb_disabled.bg_color = Color.TRANSPARENT
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	if known and recipe_id == _selected_recipe_id:
		var sb_sel := StyleBoxFlat.new()
		sb_sel.bg_color = Color(1.0, 1.0, 1.0, 0.08)
		sb_sel.border_color = FRAME_COLOR
		sb_sel.border_width_left = FRAME_WIDTH
		btn.add_theme_stylebox_override("normal", sb_sel)
	return btn

func _select_recipe(recipe_id: String) -> void:
	_selected_recipe_id = recipe_id
	SfxPlayer.play_event("menu_select")
	_rebuild_content()

# ---------------------------------------------------------------------------
# 陣形詳細
# ---------------------------------------------------------------------------

func _build_recipe_detail(recipe_id: String) -> void:
	if not Formation.RECIPES.has(recipe_id):
		return
	var recipe: Dictionary = Formation.RECIPES[recipe_id]
	# 名前
	var name_label := Label.new()
	name_label.text = tr("recipe.%s.name" % recipe_id)
	name_label.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	name_label.add_theme_color_override("font_color", ACCENT)
	_detail_box.add_child(name_label)
	# 配置の形
	var shape: String = recipe.get("shape", "")
	var shape_key: String = SHAPE_KEYS.get(shape, "")
	if not shape_key.is_empty():
		var shape_label := Label.new()
		shape_label.text = tr(shape_key)
		shape_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
		shape_label.add_theme_color_override("font_color", DIM_GRAY)
		_detail_box.add_child(shape_label)
	# 発動者と参加者（スキン名の翻訳）
	var leader_skins: Array = recipe.get("leader_skins", [])
	if not leader_skins.is_empty():
		var leader_names := _skin_names_text(leader_skins)
		var leader_label := Label.new()
		leader_label.text = tr("ui.chronicle.recipe_leader") % leader_names
		leader_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
		leader_label.add_theme_color_override("font_color", UI_GRAY)
		_detail_box.add_child(leader_label)
	var member_skins: Array = recipe.get("member_skins", [])
	if not member_skins.is_empty():
		var member_names := _skin_names_text(member_skins)
		var member_label := Label.new()
		member_label.text = tr("ui.chronicle.recipe_members") % member_names
		member_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
		member_label.add_theme_color_override("font_color", UI_GRAY)
		_detail_box.add_child(member_label)
	# 効果と射程
	var effect_text := _effect_text(recipe)
	var range_val: int = recipe.get("range", 0)
	var info_parts: Array = []
	if not effect_text.is_empty():
		info_parts.append(effect_text)
	if range_val > 0:
		info_parts.append(tr("ui.chronicle.recipe_range") % range_val)
	if not info_parts.is_empty():
		var info_label := Label.new()
		info_label.text = "  ".join(info_parts)
		info_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
		info_label.add_theme_color_override("font_color", UI_GRAY)
		_detail_box.add_child(info_label)
	# 初出の冒険譚
	var encountered := _store.recipes()
	var entry: Dictionary = encountered.get(recipe_id, {})
	var first_campaign: String = entry.get("first", "")
	if not first_campaign.is_empty() and _progress != null:
		var campaign := _progress.campaign(first_campaign)
		if not campaign.is_empty():
			var first_label := Label.new()
			var campaign_title := tr(String(campaign.get("id", first_campaign)))
			first_label.text = "%s: %s" % [tr("ui.chronicle.first_seen"), campaign_title]
			first_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
			first_label.add_theme_color_override("font_color", UI_GRAY)
			_detail_box.add_child(first_label)
	# 説明文
	_add_desc_label("recipe.%s.desc" % recipe_id)

## スキン id の配列を翻訳済み名前のカンマ区切りに変換する。
func _skin_names_text(skin_ids: Array) -> String:
	var names: Array = []
	for sid in skin_ids:
		var key := "unit.%s.name" % sid
		var translated := tr(key)
		# 翻訳キーが見つからなければ id をそのまま使う
		names.append(translated if translated != key else String(sid))
	# 重複を除いてカンマ区切り
	var unique: Array = []
	for n in names:
		if not unique.has(n):
			unique.append(n)
	return ", ".join(unique)

## レシピの効果を翻訳済みテキストにする。
func _effect_text(recipe: Dictionary) -> String:
	var effect: String = recipe.get("effect", "")
	match effect:
		"area":
			var radius: int = recipe.get("radius", 1)
			return tr("ui.chronicle.recipe_effect_area") % radius
		"single":
			return tr("ui.chronicle.recipe_effect_single")
		"buff":
			return tr("ui.chronicle.recipe_effect_buff")
	return ""

# ---------------------------------------------------------------------------
# 冒険譚章
# ---------------------------------------------------------------------------

## 冒険譚の一覧。タップで2段目（戦果／物語／設定集）に入る。
func _build_campaigns_chapter() -> void:
	if _progress == null:
		return
	var camps := _progress.campaigns(false)  # デバッグ冒険譚を除く
	for c in camps:
		var cid: String = c["id"]
		var stages: Array = c["stages"]
		var total: int = stages.size()
		var cleared := _progress.cleared_count(cid)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, ITEM_HEIGHT)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "  " + tr(String(c.get("title", cid)))
		btn.add_theme_color_override("font_color", UI_GRAY)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		btn.pressed.connect(func() -> void: _open_campaign(cid))
		btn.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.TRANSPARENT
		btn.add_theme_stylebox_override("normal", sb)
		var sb_hover := StyleBoxFlat.new()
		sb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
		btn.add_theme_stylebox_override("hover", sb_hover)
		_content_box.add_child(btn)

		# 進捗の行（クリア数・ランク・合計時間）
		if total > 0:
			var parts: Array = []
			parts.append(tr("ui.chronicle.cleared_progress") % [cleared, total])
			if _progress.is_all_cleared(cid):
				var rank := _campaign_rank(cid, stages)
				if not rank.is_empty():
					parts.append(tr("ui.chronicle.campaign_rank") % rank)
				var t := _campaign_total_time(cid, stages)
				if t > 0:
					parts.append(tr("ui.chronicle.total_time") % _format_duration(t))
			var info := Label.new()
			info.text = "    " + "  ".join(parts)
			info.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
			info.add_theme_color_override("font_color", DIM_GRAY)
			_content_box.add_child(info)

func _open_campaign(campaign_id: String) -> void:
	_selected_campaign_id = campaign_id
	_campaign_section = CampaignSection.RESULTS
	_back.text = tr("ui.chronicle.back_campaigns")
	SfxPlayer.play_event("menu_select")
	_rebuild()

# ---------------------------------------------------------------------------
# 戦果（冒険譚2段目・RESULTS）
# ---------------------------------------------------------------------------

## 選択中の冒険譚のステージごとの戦果を出す。
func _build_campaign_results() -> void:
	if _progress == null:
		return
	var c := _progress.campaign(_selected_campaign_id)
	if c.is_empty():
		return
	# 冒険譚の見出し
	var head := Label.new()
	head.text = tr(String(c.get("title", _selected_campaign_id)))
	head.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	head.add_theme_color_override("font_color", ACCENT)
	_content_box.add_child(head)

	# 冒険譚サマリー（全クリアならランクと合計時間）
	var stages: Array = c["stages"]
	if _progress.is_all_cleared(_selected_campaign_id):
		var summary_parts: Array = []
		var rank := _campaign_rank(_selected_campaign_id, stages)
		if not rank.is_empty():
			summary_parts.append(tr("ui.chronicle.campaign_rank") % rank)
		var t := _campaign_total_time(_selected_campaign_id, stages)
		if t > 0:
			summary_parts.append(tr("ui.chronicle.total_time") % _format_duration(t))
		if not summary_parts.is_empty():
			var summary := Label.new()
			summary.text = "  ".join(summary_parts)
			summary.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
			summary.add_theme_color_override("font_color", UI_GRAY)
			_content_box.add_child(summary)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, CATEGORY_GAP)
	_content_box.add_child(spacer)

	# ステージごとの行
	for s in stages:
		var sid: String = s["id"]
		var cleared := _progress.stage_state(_selected_campaign_id, sid) == CampaignProgress.CLEARED
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, ITEM_HEIGHT)
		row.add_theme_constant_override("separation", 16)

		var title_label := Label.new()
		if cleared:
			title_label.text = tr(String(s.get("title", sid)))
		else:
			title_label.text = tr("ui.chronicle.unknown")
		title_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		title_label.add_theme_color_override("font_color", UI_GRAY if cleared else DIM_GRAY)
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title_label)

		if cleared:
			var rank := _progress.best_rank(_selected_campaign_id, sid)
			if not rank.is_empty():
				var rank_label := Label.new()
				rank_label.text = rank
				rank_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
				rank_label.add_theme_color_override("font_color", ACCENT)
				rank_label.custom_minimum_size = Vector2(30, 0)
				row.add_child(rank_label)
			var time := _progress.best_time(_selected_campaign_id, sid)
			if time > 0:
				var time_label := Label.new()
				time_label.text = _format_duration(time)
				time_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
				time_label.add_theme_color_override("font_color", DIM_GRAY)
				row.add_child(time_label)

		_content_box.add_child(row)

# ---------------------------------------------------------------------------
# 設定集（冒険譚2段目・LORE）
# ---------------------------------------------------------------------------

## 選択中の冒険譚の設定集を出す。解放された節を順に出し、未解放があれば末尾に1行。
## 設定集データは data/chronicle/<冒険譚 id>.json（ChronicleLoader）から取得する＝ゲーム進行データとは分離。
func _build_campaign_lore() -> void:
	if _progress == null:
		return
	var chronicle := ChronicleLoader.load_for(_selected_campaign_id)
	var lore: Array = chronicle["lore"]
	if lore.is_empty():
		_build_placeholder(tr("ui.chronicle.lore"))
		return

	var has_locked := false
	for section in lore:
		if not _is_lore_section_unlocked(_selected_campaign_id, section):
			has_locked = true
			break
		_build_lore_section(_selected_campaign_id, String(section["id"]))

	if has_locked:
		var locked_label := Label.new()
		locked_label.text = tr("ui.chronicle.lore_locked")
		locked_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		locked_label.add_theme_color_override("font_color", DIM_GRAY)
		locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content_box.add_child(locked_label)

## 設定集の節が解放済みかを判定。unlock 条件をすべて満たしていれば解放（AND評価）。
## CampaignProgress.stage_state() の公開 API だけで判定する＝進行データへの依存を最小に。
func _is_lore_section_unlocked(campaign_id: String, section: Dictionary) -> bool:
	for cond in section["unlock"]:
		if typeof(cond) != TYPE_DICTIONARY:
			continue
		match String(cond.get("type", "")):
			"cleared":
				if _progress.stage_state(campaign_id, String(cond.get("stage", ""))) != CampaignProgress.CLEARED:
					return false
			_:
				return false  # 未知の条件は未充足側に倒す
	return true

## 設定集の1節を出す。見出し＋段落（連番のキーが在るぶんだけ）。
func _build_lore_section(campaign_id: String, section_id: String) -> void:
	# 節見出し
	var title_key := "lore.%s.%s.title" % [campaign_id, section_id]
	var title_text := tr(title_key)
	if title_text != title_key:
		var head := Label.new()
		head.text = title_text
		head.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
		head.add_theme_color_override("font_color", ACCENT)
		_content_box.add_child(head)
	# 段落：lore.<冒険譚>.<節>.1, .2, .3 …
	var p := 1
	while true:
		var key := "lore.%s.%s.%d" % [campaign_id, section_id, p]
		var text := tr(key)
		if text == key:
			break
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		label.add_theme_color_override("font_color", UI_GRAY)
		_content_box.add_child(label)
		p += 1
	# 節間の余白
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, CATEGORY_GAP)
	_content_box.add_child(spacer)

## 冒険譚ランク＝全ステージのベストランクのうち最も低いもの。未ランクがあれば空。
func _campaign_rank(campaign_id: String, stages: Array) -> String:
	var worst := "S"
	for s in stages:
		var r := _progress.best_rank(campaign_id, s["id"])
		if r.is_empty():
			return ""
		if RankEvaluator.is_better(worst, r):
			worst = r
	return worst

## クリア時間の合計＝各ステージのベストの和。未記録があれば 0。
func _campaign_total_time(campaign_id: String, stages: Array) -> int:
	var total := 0
	for s in stages:
		var t := _progress.best_time(campaign_id, s["id"])
		if t == 0:
			return 0
		total += t
	return total

## 秒を表示用テキストにする（stage_tally.gd と同じ形式）。
func _format_duration(seconds: int) -> String:
	var total := maxi(seconds, 0)
	var days := total / 86400
	var hours := (total % 86400) / 3600
	var minutes := (total % 3600) / 60
	if days > 0:
		return tr("ui.result.time_days") % [days, hours, minutes]
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total % 60]
	return "%d:%02d" % [minutes, total % 60]

# ---------------------------------------------------------------------------
# 共通
# ---------------------------------------------------------------------------

## desc 翻訳キーが存在すれば説明文ラベルを _detail_box に追加する。
## unit.*.desc は chronicle.csv、recipe.*.desc は names.csv。tr() はまとめて解決する。
func _add_desc_label(desc_key: String) -> void:
	var desc_text := tr(desc_key)
	if desc_text != desc_key:
		var desc_label := Label.new()
		desc_label.text = desc_text
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
		desc_label.add_theme_color_override("font_color", UI_GRAY)
		_detail_box.add_child(desc_label)
