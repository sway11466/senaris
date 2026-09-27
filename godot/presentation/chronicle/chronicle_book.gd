extends RefCounted
class_name ChronicleBook
## クロニクルの本＝羊皮紙2枚の見開き。物語の節と会話／イベントの節が使う。
## 仕様 → doc/gdd/chronicle.md 画面・会話／イベント・本文の持ち方
##
## 物語は本文を chronicle.csv の book.<冒険譚>.<ページ>（1キー＝1ページ）、挿絵は
## assets/chronicle/<冒険譚>/book_<ページ>.png。ページは本文か挿絵のどちらかが在るぶんだけ
## 1 から連番で続く。紙の寸法は基準の画面で固定＝1ページに収まるかをテストで見られる。

const SHEET_SIZE := Vector2(900, 520)   # 見開き（羊皮紙2枚を突き合わせた全体。1枚が1ページ）
const PAGE_PAD := Vector2(36, 34)       # ページの縁と文字の間（左右・上下）
const TEXT_WIDTH := SHEET_SIZE.x * 0.5 - PAGE_PAD.x * 2
const TEXT_HEIGHT := SHEET_SIZE.y - PAGE_PAD.y * 2
const FONT_SIZE := ChronicleStyle.BODY_FONT_SIZE
const IMAGE_GAP := 12                   # 挿絵と本文の間
const NAV_GAP := 16                     # 紙とめくりの板の間・板とページ番号の間
const FOLD_WIDTH := 30                  # 綴じ目の影の幅（ページごと）
const FOLD_COLOR := Color(0.25, 0.16, 0.08)
const FOLD_ALPHA := 0.35
const GUTTER_TRIM := 10                 # 綴じ目の側で切り落とす紙の縁（透けた破れ目は最大7px・実測）

static func text_key(campaign_id: String, page: int) -> String:
	return "book.%s.%d" % [campaign_id, page]

## 本文。キーが無ければ空。
static func page_text(campaign_id: String, page: int) -> String:
	var key := text_key(campaign_id, page)
	var text := TranslationServer.translate(key)
	return "" if text == key else String(text)

## 挿絵のパス。置いていなければ空。
static func image_path(campaign_id: String, page: int) -> String:
	var path := "res://assets/chronicle/%s/book_%d.png" % [campaign_id, page]
	return path if ResourceLoader.exists(path) else ""

static func page_count(campaign_id: String) -> int:
	var n := 0
	while not page_text(campaign_id, n + 1).is_empty() or not image_path(campaign_id, n + 1).is_empty():
		n += 1
	return n

## 挿絵の高さ＝幅を本文の幅に合わせ、縦横比どおり（本文の場所を超えない）。挿絵が無ければ 0。
static func image_height(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	return minf(TEXT_WIDTH * tex.get_height() / float(tex.get_width()), TEXT_HEIGHT)

## 本文に使える高さ＝ページの文字の場所から挿絵とその下の間を引いた残り。
static func body_height_limit(tex: Texture2D) -> float:
	if tex == null:
		return TEXT_HEIGHT
	return TEXT_HEIGHT - image_height(tex) - IMAGE_GAP

## 物語の1ページ。page がページ数を超えていれば白紙（見開きの右が余ったとき）。
## 本文の Label には meta "book_body" を付ける＝テストが収まりを測る。
static func build_page(campaign_id: String, page: int, gutter_right := false) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", IMAGE_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var path := image_path(campaign_id, page)
	if not path.is_empty():
		var tex := load(path) as Texture2D
		if tex != null:
			col.add_child(image_rect(tex))

	var text := page_text(campaign_id, page)
	if not text.is_empty():
		var body := Label.new()
		body.text = text
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
		body.add_theme_font_size_override("font_size", FONT_SIZE)
		body.add_theme_color_override("font_color", TavernTheme.INK)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.set_meta("book_body", true)
		col.add_child(body)
	return sheet_page(hash(campaign_id) + page, gutter_right, col)

## 物語の見開き。left は奇数ページ。
static func build_spread(campaign_id: String, left: int) -> Control:
	return spread(build_page(campaign_id, left, true), build_page(campaign_id, left + 1, false))

## ページの上に載せる絵（物語の挿絵・会話／イベントの盤の絵）。幅は文字の幅、高さは縦横比。
static func image_rect(tex: Texture2D) -> TextureRect:
	var art := TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(TEXT_WIDTH, image_height(tex))
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art

## 見開き＝羊皮紙2枚を綴じ目で突き合わせる（左ページ・右ページは sheet_page で組んだもの）。
static func spread(left_page: Control, right_page: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left_page)
	row.add_child(right_page)
	return row

## 1ページ＝羊皮紙1枚に中身を載せる。中身は縁から PAGE_PAD 内側の文字の場所に置く。
## gutter_right＝綴じ目がページの右にある（左ページ）。綴じ目の側に内向きの影を付けて折り目に見せる。
static func sheet_page(seed: int, gutter_right: bool, content: Control) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(SHEET_SIZE.x * 0.5, SHEET_SIZE.y)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var paper := Panel.new()
	paper.add_theme_stylebox_override("panel", _paper_box(seed, gutter_right))
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(paper)

	var fold := TextureRect.new()
	fold.texture = _fold_texture(gutter_right)
	fold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fold.stretch_mode = TextureRect.STRETCH_SCALE
	fold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if gutter_right:
		fold.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		fold.offset_left = -FOLD_WIDTH
	else:
		fold.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		fold.offset_right = FOLD_WIDTH
	root.add_child(fold)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(PAGE_PAD.x))
	margin.add_theme_constant_override("margin_right", int(PAGE_PAD.x))
	margin.add_theme_constant_override("margin_top", int(PAGE_PAD.y))
	margin.add_theme_constant_override("margin_bottom", int(PAGE_PAD.y))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	margin.add_child(content)
	return root

## 紙＝貼り紙の羊皮紙（変種は seed で決まる＝同じページは常に同じ紙）。ページは紙の実寸より
## 縦に長いので、タイルの継ぎ目が出ないよう縦も引き伸ばす。余白はページが持つ。
## 綴じ目の側は破れた縁（透けている）を切り落とす＝合わせ目に後ろの暗い地がのぞかない。
static func _paper_box(seed: int, gutter_right: bool) -> StyleBox:
	var box := TavernTheme.parchment_stylebox(seed).duplicate() as StyleBox
	var sbt := box as StyleBoxTexture
	if sbt != null:
		sbt.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		var size := sbt.texture.get_size()
		if gutter_right:
			sbt.region_rect = Rect2(0, 0, size.x - GUTTER_TRIM, size.y)
			sbt.texture_margin_right = 0
		else:
			sbt.region_rect = Rect2(GUTTER_TRIM, 0, size.x - GUTTER_TRIM, size.y)
			sbt.texture_margin_left = 0
	box.set_content_margin_all(0)
	return box

## 折り目の影。綴じ目の側が濃く、ページの内側へ消える横のグラデーション。
static func _fold_texture(gutter_right: bool) -> Texture2D:
	var g := Gradient.new()
	var edge := Color(FOLD_COLOR, FOLD_ALPHA)
	var clear := Color(FOLD_COLOR, 0.0)
	g.set_color(0, clear if gutter_right else edge)
	g.set_color(1, edge if gutter_right else clear)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 1
	return tex
