extends ChronicleChapter
class_name ChronicleUnitsChapter
## クロニクルのユニット章。仕様 → doc/gdd/chronicle.md ユニット
##
## カテゴリごとに羊皮紙のカードを格子に並べ、押すと拡大カードが手前に開く。下段の詳細ペインは
## 持たない＝詳細は拡大カードで出すので、格子に高さを全部渡す。

## 格子。1段に並ぶ枚数は CARD_COLUMNS だけで決まる（カードの幅は器の幅から割り出す）。
const CARD_COLUMNS := 6
const CARD_GAP := 12
const CARD_ASPECT := 1.15   # カードの縦／横
const CARD_PAD := 10        # 紙の縁と絵の間
const CARD_DIM := 0.78      # 未解放のカードの紙の明るさ
const SCROLLBAR_ALLOW := 16.0  # 縦スクロールバーのぶん幅を引く（出た瞬間に折り返さないため）

## 拡大カード（格子のカードを押すと手前に開く1枚）。
const EXPAND_SCRIM := Color(0.02, 0.02, 0.03, 0.72)
const EXPAND_WIDTH := 760.0
const EXPAND_ART_HEIGHT := 200.0
const EXPAND_PAD := 24
const STAT_LABEL_WIDTH := 104.0
const STAT_VALUE_WIDTH := 72.0
const NONE_TEXT := "—"

var _expanded: Control = null  # 拡大カード（開いていなければ null）
var _grid_width := 0.0  # 格子を組んだときの器の幅。変わったら組み直す

func _wants_detail_pane() -> bool:
	return false

func reset() -> void:
	_close_expanded()

func refresh_labels() -> void:
	_close_expanded()  # 開いたままの拡大カードは組み直さず畳む（格子へ戻る）

## 拡大カードが開いていれば、まずそれを畳む（段は増やさない＝画面は出ない）。
func handle_back() -> bool:
	if _expanded == null:
		return false
	_close_unit_card()
	return true

# ---------------------------------------------------------------------------
# 格子
# ---------------------------------------------------------------------------

## カテゴリごとに羊皮紙のカードを格子に並べる。カードに載るのは盤の絵だけで、名前も数値も
## 出さない（doc/gdd/chronicle.md ユニット）。カテゴリの出現順と各スキンの並び順は
## SkinCatalog の __by_id__ 辞書の挿入順（＝CSV の行順）に従う。
func _build() -> void:
	if _store == null:
		return
	var ordered := _ordered_skins()
	var encountered := _store.skins()  # 出会った skin_id の並び
	var card_size := _card_size()
	_grid_width = _content_scroll.size.x

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
		cat_label.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
		cat_label.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
		head.add_child(cat_label)
		var count_label := Label.new()
		count_label.text = tr("ui.chronicle.count") % [found, skins.size()]
		count_label.add_theme_font_size_override("font_size", ChronicleStyle.COUNT_FONT_SIZE)
		count_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
		count_label.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(count_label)
		_content_box.add_child(head)

		# カードの格子
		var grid := HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", CARD_GAP)
		grid.add_theme_constant_override("v_separation", CARD_GAP)
		for s in skins:
			grid.add_child(_unit_card(s, encountered.has(s.skin_id), card_size))
		_content_box.add_child(grid)

		# カテゴリ間の余白
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, ChronicleStyle.CATEGORY_GAP)
		_content_box.add_child(spacer)

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

## カード1枚の寸法＝格子の幅を CARD_COLUMNS で割る。器がまだ measure されていない
## （開いた直後の1フレーム目）ときは画面幅から見積もり、_on_content_resized で組み直す。
func _card_size() -> Vector2:
	var avail := _content_scroll.size.x
	if avail <= 0.0:
		avail = get_viewport().get_visible_rect().size.x - ChronicleStyle.EDGE * 2.0 \
			- ChronicleStyle.TOC_WIDTH - ChronicleStyle.PANE_GAP
	avail -= SCROLLBAR_ALLOW
	var w := maxf(floorf((avail - CARD_GAP * (CARD_COLUMNS - 1)) / float(CARD_COLUMNS)), 48.0)
	return Vector2(w, floorf(w * CARD_ASPECT))

## 器の幅が変わるとカードの寸法が変わる＝組み直す。
func _on_content_resized() -> void:
	if not is_visible_in_tree():
		return
	if absf(_content_scroll.size.x - _grid_width) < 1.0:
		return
	rebuild()

## 格子の1枚＝依頼ボードの貼り紙と同じ羊皮紙。未解放は黒いシルエットで押せない。
func _unit_card(skin: UnitSkin, known: bool, card_size: Vector2) -> Control:
	var card := Button.new()
	card.custom_minimum_size = card_size
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	var paper_seed := hash(skin.skin_id)  # カードごとに紙の変種を固定（hover でも変わらない）
	for state in ["normal", "hover", "pressed", "disabled"]:
		var bright := 1.0
		if not known:
			bright = CARD_DIM
		elif state == "hover":
			bright = 1.06
		card.add_theme_stylebox_override(state, TavernTheme.parchment_stylebox(paper_seed, bright))

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, CARD_PAD)
	pad.add_child(_art_view(skin, "map", not known))
	card.add_child(pad)

	if known:
		var sid := skin.skin_id
		card.pressed.connect(func() -> void: _open_unit_card(sid))
	else:
		card.disabled = true
	return card

## 絵1枚。画像が未用意ならプレースホルダの文字（doc/art/overview.md）。
## silhouette＝未解放のカード＝黒く塗り潰して形だけ見せる。
func _art_view(skin: UnitSkin, slot: String, silhouette: bool) -> Control:
	var path := skin.image(slot)
	var tex: Texture2D = null
	if not path.is_empty():
		tex = load(path) as Texture2D
	if tex == null:
		var ph := Label.new()
		ph.text = tr("ui.chronicle.unknown") if silhouette else tr("unit.%s.name" % skin.skin_id)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
		ph.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return ph
	var art := TextureRect.new()
	art.texture = _cropped(tex)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if silhouette:
		art.modulate = Color(0.0, 0.0, 0.0, 0.92)
	return art

## 絵の実体（非透過部分）の外接矩形だけを切り出したテクスチャ。キャンバスの余白ごと枠に
## 収めると駒が小さくしか出ない（map は 384 角に対し実体が 101×180 のような比率）。
## 会話の顔・ターン表示と同じ切り出し方（doc/art/overview.md）。
func _cropped(src: Texture2D) -> Texture2D:
	var img := src.get_image()
	if img == null:
		return src
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return src
	var atlas := AtlasTexture.new()
	atlas.atlas = src
	atlas.region = Rect2(used.position, used.size)
	return atlas

# ---------------------------------------------------------------------------
# 拡大カード
# ---------------------------------------------------------------------------

## 格子のカードを押すと手前に開く大きな羊皮紙。盤の絵と戦闘の絵を並べ、名前・兵種・初出・
## 説明文・性能・ユニットスキルを載せる。閉じると格子へ戻る（Esc・紙の外を押す・左下の戻る）。
## 画面全体を覆うので、自分の下ではなく画面が持つ手前の器（_overlay）に置く。
func _open_unit_card(skin_id: String) -> void:
	var skin := SkinCatalog.skin_by_id(_skins, skin_id)
	if skin == null:
		return
	SfxPlayer.play_event("menu_select")
	_close_expanded()

	_expanded = Control.new()
	_expanded.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_expanded.mouse_filter = Control.MOUSE_FILTER_STOP
	_expanded.gui_input.connect(func(event: InputEvent) -> void:
		# 紙そのものは STOP で受け止めるので、ここへ来るのは紙の外を押したとき
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_close_unit_card())

	var scrim := ColorRect.new()
	scrim.color = EXPAND_SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_expanded.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_expanded_sheet(skin))
	_expanded.add_child(center)

	_overlay.add_child(_expanded)
	_expanded.modulate.a = 0.0
	create_tween().tween_property(_expanded, "modulate:a", 1.0, ChronicleStyle.FADE_SEC * 0.5)

func _close_unit_card() -> void:
	SfxPlayer.play_event("menu_back")
	_close_expanded()

func _close_expanded() -> void:
	if _expanded == null:
		return
	_expanded.queue_free()
	_expanded = null

## 拡大カードの紙。文字は紙の上なのでインク色（UIのグレーではない）。
func _expanded_sheet(skin: UnitSkin) -> Control:
	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(EXPAND_WIDTH, 0)
	sheet.add_theme_stylebox_override("panel", TavernTheme.parchment_stylebox(hash(skin.skin_id)))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, EXPAND_PAD)
	sheet.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	# 絵＝盤の絵と戦闘の絵を並べる
	var arts := HBoxContainer.new()
	arts.add_theme_constant_override("separation", EXPAND_PAD)
	arts.custom_minimum_size = Vector2(0, EXPAND_ART_HEIGHT)
	for slot in ["map", "combat"]:
		var art := _art_view(skin, slot, false)
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		arts.add_child(art)
	col.add_child(arts)

	# 見出し＝ユニット名（兵種）
	var name_label := Label.new()
	name_label.text = _unit_title(skin)
	name_label.add_theme_font_size_override("font_size", ChronicleStyle.TITLE_FONT_SIZE)
	name_label.add_theme_color_override("font_color", TavernTheme.INK)
	col.add_child(name_label)

	# 説明文（chronicle.csv に unit.<skin_id>.desc があれば）
	var desc_key := "unit.%s.desc" % skin.skin_id
	var desc_text := tr(desc_key)
	if desc_text != desc_key:
		var desc_label := Label.new()
		desc_label.text = desc_text
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
		desc_label.add_theme_color_override("font_color", TavernTheme.INK)
		col.add_child(desc_label)

	# 性能の数値
	col.add_child(_stats_grid(skin.type_id))
	var traits := _trait_text(skin.type_id)
	if not traits.is_empty():
		col.add_child(_ink_line("%s  %s" % [tr("ui.info.trait"), traits], TavernTheme.INK))

	# ユニットスキル（撃てるものを性能の一部として載せる。doc/gdd/skills.md）
	for rid in _unit_skill_ids(skin):
		col.add_child(_ink_line("%s  %s" % [tr("ui.info.skill"), tr("recipe.%s.name" % rid)], TavernTheme.INK))
		var skill_desc := tr("recipe.%s.desc" % rid)
		if skill_desc != "recipe.%s.desc" % rid:
			col.add_child(_ink_line(skill_desc, TavernTheme.INK_SOFT))
	return sheet

## 紙の上の1行（折り返しあり）。
func _ink_line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label

## 見出しの文字列＝ユニット名（兵種）。兵種を添えるのは味方だけ。
## 敵の分類は素性（ゴブリン・アンデッド…）で兵種ではなく、格子の章見出しと同じ語になる＝
## 括弧に入れても何も足さない。兵種そのものを出すのはリスキン元が透けるので避ける
## （情報パネルと同じ線 → doc/gdd/uiux.md 見出し）。
func _unit_title(skin: UnitSkin) -> String:
	var name_text := tr("unit.%s.name" % skin.skin_id)
	if skin.side != "ally" or skin.category.is_empty():
		return name_text
	return tr("ui.chronicle.name_category") % [name_text, tr("unit_group.%s.name" % skin.category)]

## 性能の数値＝盤の状況で変わらない値だけ。項目と語は情報パネルの能力タブと揃える。
func _stats_grid(type_id: String) -> Control:
	var grid := GridContainer.new()
	grid.columns = 6  # 項目・値の対を1行に3つ（紙の幅に対して余るため）
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for row in _stat_rows(type_id):
		var label := Label.new()
		label.text = String(row[0])
		label.custom_minimum_size = Vector2(STAT_LABEL_WIDTH, 0)
		label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		label.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
		grid.add_child(label)
		var value := Label.new()
		value.text = String(row[1])
		value.custom_minimum_size = Vector2(STAT_VALUE_WIDTH, 0)
		value.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		value.add_theme_color_override("font_color", TavernTheme.INK)
		grid.add_child(value)
	return grid

## [[項目, 値], ...]。持たない駒に出しても意味のない項目（搭乗・シールド）は持つ駒だけ。
func _stat_rows(type_id: String) -> Array:
	var t: UnitType = _types.get(type_id, null) as UnitType
	if t == null:
		return []
	var rows: Array = []
	rows.append([tr("ui.info.atk_ground"), str(t.atk_ground)])
	rows.append([tr("ui.info.atk_air"), str(t.atk_air) if t.atk_air > 0 else NONE_TEXT])
	rows.append([tr("ui.info.defense"), str(t.defense)])
	rows.append([tr("ui.info.range"), str(t.attack_range) if t.min_range == t.attack_range \
		else "%d-%d" % [t.min_range, t.attack_range]])
	rows.append([tr("ui.info.move"), str(t.move)])
	rows.append([tr("ui.info.move_type"), tr("movement.%s.name" % t.move_type)])
	rows.append([tr("ui.info.strength"), str(t.max_troops)])
	if t.capacity > 0:
		rows.append([tr("ui.chronicle.capacity"), str(t.capacity)])
	if t.shield > 0:
		rows.append([tr("ui.info.shield"), str(t.shield)])
	return rows

## 特性＝他の行を見ても分からないことだけ（情報パネルと同じ線引き）。
func _trait_text(type_id: String) -> String:
	var t: UnitType = _types.get(type_id, null) as UnitType
	if t == null:
		return ""
	var traits: Array[String] = []
	if t.pierce > 0.0:
		traits.append(tr("ui.info.trait_pierce") % roundi(t.pierce * 100.0))
	if t.can_capture:
		traits.append(tr("ui.info.trait_capture"))
	if t.move_after_attack:
		traits.append(tr("ui.info.trait_move_after_attack"))
	return "   /   ".join(traits)

## その駒が撃てるユニットスキル（単独発動＝shape "solo"）のレシピid。
## 照合は skin_id だけ＝Formation._matches が盤で使う鍵と同じ（クロニクルの枠は必ず
## skin_id を持つ）。type_id でも拾うと、性能を借りているだけの別スキンに撃てない
## スキルが載る（ゴーストはピクシー性能だがピクシーダストは撃てない）。
func _unit_skill_ids(skin: UnitSkin) -> Array:
	var out: Array = []
	for rid in Formation.RECIPES:
		var recipe: Dictionary = Formation.RECIPES[rid]
		if not Formation.is_unit_skill(rid):
			continue
		if (recipe.get("leader_skins", []) as Array).has(skin.skin_id):
			out.append(rid)
	return out
