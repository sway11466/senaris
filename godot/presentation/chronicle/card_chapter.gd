extends ChronicleChapter
class_name ChronicleCardChapter
## 羊皮紙のカードを格子に並べ、押すと拡大カードが手前に開く章の共通部分（ユニット／陣形スキル）。
## 仕様 → doc/gdd/chronicle.md ユニット・陣形スキル
##
## 章ごとに違うのは 何を1枚にするか（スキン／レシピ）・1段の枚数と縦横比・カードの面・拡大カードの
## 中身。ここは格子の寸法・紙・黒塗りの絵・拡大カードの開閉だけを持つ。下段の詳細ペインは持たない
## ＝詳細は拡大カードで出すので、格子に高さを全部渡す。

const PAIR_LABEL_WIDTH := 104.0  # 項目・値の表の項目の幅
const PAIR_VALUE_WIDTH := 72.0   # 同じく値の幅

var _expanded: Control = null  # 拡大カード（開いていなければ null）
var _grid_width := 0.0  # 格子を組んだときの器の幅。変わったら組み直す

## 1段に並ぶ枚数。カードの幅は器の幅からこれで割り出す。
func _card_columns() -> int:
	return 6

## カードの縦／横。
func _card_aspect() -> float:
	return 1.15

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
	_close_by_user()
	return true

func rebuild() -> void:
	_grid_width = _content_scroll.size.x
	super()

# ---------------------------------------------------------------------------
# 格子
# ---------------------------------------------------------------------------

## カード1枚の寸法＝格子の幅を _card_columns で割る。器がまだ measure されていない
## （開いた直後の1フレーム目）ときは画面幅から見積もり、_on_content_resized で組み直す。
func _card_size() -> Vector2:
	var avail := _content_scroll.size.x
	if avail <= 0.0:
		avail = get_viewport().get_visible_rect().size.x - ChronicleStyle.EDGE * 2.0 \
			- ChronicleStyle.TOC_WIDTH - ChronicleStyle.PANE_GAP
	avail -= ChronicleStyle.SCROLLBAR_ALLOW
	var cols := _card_columns()
	var w := maxf(floorf((avail - ChronicleStyle.CARD_GAP * (cols - 1)) / float(cols)), 48.0)
	return Vector2(w, floorf(w * _card_aspect()))

## 器の幅が変わるとカードの寸法が変わる＝組み直す。
func _on_content_resized() -> void:
	if not is_visible_in_tree():
		return
	if absf(_content_scroll.size.x - _grid_width) < 1.0:
		return
	rebuild()

## 分類1つぶん（見出し＋「埋まった数／全部」・カードの格子・分類間の余白）を上段に置く。
## cards は _paper_card の並び。
func _add_group(title: String, found: int, cards: Array) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", ChronicleStyle.HEAD_FONT_SIZE)
	title_label.add_theme_color_override("font_color", ChronicleStyle.ACCENT)
	head.add_child(title_label)
	var count_label := Label.new()
	count_label.text = tr("ui.chronicle.count") % [found, cards.size()]
	count_label.add_theme_font_size_override("font_size", ChronicleStyle.COUNT_FONT_SIZE)
	count_label.add_theme_color_override("font_color", ChronicleStyle.UI_GRAY)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(count_label)
	_content_box.add_child(head)

	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", ChronicleStyle.CARD_GAP)
	grid.add_theme_constant_override("v_separation", ChronicleStyle.CARD_GAP)
	for c in cards:
		grid.add_child(c)
	_content_box.add_child(grid)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ChronicleStyle.CATEGORY_GAP)
	_content_box.add_child(spacer)

## 格子の1枚＝依頼ボードの貼り紙と同じ羊皮紙。face が紙の上に載るもの（絵だけ。名前も数値も出さない）。
## 未解放は紙を暗くして押せない。seed はカードごとの紙の変種（hover でも変わらない）。
func _paper_card(seed: int, known: bool, card_size: Vector2, face: Control,
		on_pressed: Callable) -> Control:
	var card := Button.new()
	card.custom_minimum_size = card_size
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	for state in ["normal", "hover", "pressed", "disabled"]:
		var bright := 1.0
		if not known:
			bright = ChronicleStyle.CARD_DIM
		elif state == "hover":
			bright = 1.06
		card.add_theme_stylebox_override(state, TavernTheme.parchment_stylebox(seed, bright))

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, ChronicleStyle.CARD_PAD)
	pad.add_child(face)
	card.add_child(pad)

	if known:
		card.pressed.connect(on_pressed)
	else:
		card.disabled = true
	return card

## 駒の絵1枚（盤の絵か戦闘の絵）。画像が未用意ならプレースホルダの文字（doc/art/overview.md）。
## silhouette＝黒く塗り潰して形だけ見せる（未解放のカード）。
func _skin_art(skin: UnitSkin, slot: String, silhouette: bool) -> Control:
	var tex := _skin_texture(skin, slot)
	if tex == null:
		return _art_placeholder(tr("ui.chronicle.unknown") if silhouette else tr("unit.%s.name" % skin.skin_id))
	return _art_rect(tex, silhouette)

## 駒の絵の実体だけを切り出したテクスチャ。画像が未用意なら null。
func _skin_texture(skin: UnitSkin, slot: String) -> Texture2D:
	var path := skin.image(slot)
	if path.is_empty():
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	return _cropped(tex)

## 絵1枚を枠いっぱいに（比率は保つ）。
func _art_rect(tex: Texture2D, silhouette: bool) -> TextureRect:
	var art := TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if silhouette:
		art.modulate = ChronicleStyle.SILHOUETTE
	return art

## 絵の代わりの文字。
func _art_placeholder(text: String) -> Label:
	var ph := Label.new()
	ph.text = text
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ph.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
	ph.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ph

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

## 格子のカードを押すと手前に開く大きな羊皮紙（sheet＝_paper_sheet）。閉じると格子へ戻る
## （Esc・紙の外を押す・左下の戻る）。画面全体を覆うので、自分の下ではなく画面が持つ手前の
## 器（_overlay）に置く。
func _open_expanded(sheet: Control) -> void:
	SfxPlayer.play_event("menu_select")
	_close_expanded()

	_expanded = Control.new()
	_expanded.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_expanded.mouse_filter = Control.MOUSE_FILTER_STOP
	_expanded.gui_input.connect(func(event: InputEvent) -> void:
		# 紙そのものは STOP で受け止めるので、ここへ来るのは紙の外を押したとき
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			_close_by_user())

	var scrim := ColorRect.new()
	scrim.color = ChronicleStyle.EXPAND_SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_expanded.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(sheet)
	_expanded.add_child(center)

	_overlay.add_child(_expanded)
	_expanded.modulate.a = 0.0
	create_tween().tween_property(_expanded, "modulate:a", 1.0, ChronicleStyle.FADE_SEC * 0.5)

func _close_by_user() -> void:
	SfxPlayer.play_event("menu_back")
	_close_expanded()

func _close_expanded() -> void:
	if _expanded == null:
		return
	_expanded.queue_free()
	_expanded = null

## 拡大カードの紙。col が紙の上に載る列（_sheet_col）。文字は紙の上なのでインク色（UIのグレーではない）。
func _paper_sheet(seed: int, col: VBoxContainer) -> Control:
	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(ChronicleStyle.EXPAND_WIDTH, 0)
	sheet.add_theme_stylebox_override("panel", TavernTheme.parchment_stylebox(seed))
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, ChronicleStyle.EXPAND_PAD)
	sheet.add_child(pad)
	pad.add_child(col)
	return sheet

## 紙の上に載せる列。
func _sheet_col() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	return col

## 拡大カードの上段＝絵を横に並べる段。
func _art_row(arts: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ChronicleStyle.EXPAND_PAD)
	row.custom_minimum_size = Vector2(0, ChronicleStyle.EXPAND_ART_HEIGHT)
	for a in arts:
		var art := a as Control
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(art)
	return row

## 紙の上の見出し。
func _sheet_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ChronicleStyle.TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", TavernTheme.INK)
	return label

## 紙の上の説明文。翻訳キーが無ければ null（載せるものが無い）。
func _desc_label(desc_key: String) -> Label:
	var desc_text := tr(desc_key)
	if desc_text == desc_key:
		return null
	var label := Label.new()
	label.text = desc_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", ChronicleStyle.BODY_FONT_SIZE)
	label.add_theme_color_override("font_color", TavernTheme.INK)
	return label

## 紙の上の1行（折り返しあり）。
func _ink_line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label

## 項目・値の対を1行に pairs_per_row 対並べる表（紙の幅に対して余るため）。rows＝[[項目, 値], ...]。
func _pairs_grid(rows: Array, pairs_per_row := 3) -> Control:
	var grid := GridContainer.new()
	grid.columns = pairs_per_row * 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for row in rows:
		var label := Label.new()
		label.text = String(row[0])
		label.custom_minimum_size = Vector2(PAIR_LABEL_WIDTH, 0)
		label.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		label.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
		grid.add_child(label)
		var value := Label.new()
		value.text = String(row[1])
		value.custom_minimum_size = Vector2(PAIR_VALUE_WIDTH, 0)
		value.add_theme_font_size_override("font_size", ChronicleStyle.DETAIL_FONT_SIZE)
		value.add_theme_color_override("font_color", TavernTheme.INK)
		grid.add_child(value)
	return grid
