extends ChronicleChapter
class_name ChronicleFormationsChapter
## クロニクルの陣形スキル章。仕様 → doc/gdd/chronicle.md 陣形スキル
##
## レシピの一覧と「埋まった数／全部」を上段に、選んだレシピの詳細を下段に出す。
## 並ぶのは陣形スキル（shape != "solo"）だけ＝単独発動のユニットスキルはユニット章の
## 拡大カードに載る（doc/gdd/skills.md）。

## 配置の形 → 翻訳キーの引き。
const SHAPE_KEYS := {
	"triangle": "ui.chronicle.shape_triangle",
	"escort": "ui.chronicle.shape_escort",
	"cluster": "ui.chronicle.shape_cluster",
}

var _selected_recipe_id := ""  # 選んでいるレシピ（空なら詳細なし）

func reset() -> void:
	_selected_recipe_id = ""

## Formation.RECIPES から陣形スキル（shape != "solo"）だけを挿入順に返す。
func _formation_recipes() -> Array:
	var out: Array = []
	for recipe_id in Formation.RECIPES:
		var r: Dictionary = Formation.RECIPES[recipe_id]
		if r.get("shape", "") != "solo":
			out.append(recipe_id)
	return out

## レシピの一覧と「埋まった数／全部」、選択で詳細。
func _build() -> void:
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
	head_label.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	head_label.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
	head.add_child(head_label)
	var count_label := Label.new()
	count_label.text = tr("ui.chronicle.count") % [found, recipes.size()]
	count_label.add_theme_font_size_override("font_size", ChronicleStyle.COUNT_FONT_SIZE)
	count_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
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
	btn.custom_minimum_size = Vector2(0, ChronicleStyle.ITEM_HEIGHT)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	if known:
		btn.text = "  " + tr("recipe.%s.name" % recipe_id)
		btn.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		var rid := recipe_id
		btn.pressed.connect(func() -> void: _select_recipe(rid))
	else:
		btn.text = "  " + tr("ui.chronicle.unknown")
		btn.add_theme_color_override("font_color", ChronicleStyle.DIM_GRAY)
		btn.add_theme_color_override("font_hover_color", ChronicleStyle.DIM_GRAY)
		btn.disabled = true
	btn.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
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
		sb_sel.border_color = ChronicleStyle.FRAME_COLOR
		sb_sel.border_width_left = ChronicleStyle.FRAME_WIDTH
		btn.add_theme_stylebox_override("normal", sb_sel)
	return btn

func _select_recipe(recipe_id: String) -> void:
	_selected_recipe_id = recipe_id
	SfxPlayer.play_event("menu_select")
	rebuild()

# ---------------------------------------------------------------------------
# 詳細（下段）
# ---------------------------------------------------------------------------

func _build_recipe_detail(recipe_id: String) -> void:
	if not Formation.RECIPES.has(recipe_id):
		return
	var recipe: Dictionary = Formation.RECIPES[recipe_id]
	# 名前
	var name_label := Label.new()
	name_label.text = tr("recipe.%s.name" % recipe_id)
	name_label.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	name_label.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
	_detail_box.add_child(name_label)
	# 配置の形
	var shape: String = recipe.get("shape", "")
	var shape_key: String = SHAPE_KEYS.get(shape, "")
	if not shape_key.is_empty():
		var shape_label := Label.new()
		shape_label.text = tr(shape_key)
		shape_label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		shape_label.add_theme_color_override("font_color", ChronicleStyle.DIM_GRAY)
		_detail_box.add_child(shape_label)
	# 発動者と参加者（スキン名の翻訳）
	var leader_skins: Array = recipe.get("leader_skins", [])
	if not leader_skins.is_empty():
		var leader_names := _skin_names_text(leader_skins)
		var leader_label := Label.new()
		leader_label.text = tr("ui.chronicle.recipe_leader") % leader_names
		leader_label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		leader_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
		_detail_box.add_child(leader_label)
	var member_skins: Array = recipe.get("member_skins", [])
	if not member_skins.is_empty():
		var member_names := _skin_names_text(member_skins)
		var member_label := Label.new()
		member_label.text = tr("ui.chronicle.recipe_members") % member_names
		member_label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		member_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
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
		info_label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		info_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
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
			first_label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
			first_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
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

## desc 翻訳キーが存在すれば説明文ラベルを下段に追加する。
## recipe.*.desc は names.csv。tr() はまとめて解決する。
func _add_desc_label(desc_key: String) -> void:
	var desc_text := tr(desc_key)
	if desc_text != desc_key:
		var desc_label := Label.new()
		desc_label.text = desc_text
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		desc_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
		_detail_box.add_child(desc_label)
