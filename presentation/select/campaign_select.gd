extends Control
class_name CampaignSelect
## キャンペーン選択画面＝酒場の依頼ボード。方向性 → doc/gdd/stage_select.md
## 木のボードに、冒険譚を縦長の依頼書（羊皮紙ポスター）として並べる。
## ボードは難易度帯（tier）ごとに分かれ、◁▷ で1枚ずつ繰るカルーセル。ボード名は上梁に手書き風（Rock Salt）。
## 状態は持たず、refresh() のたびに CampaignProgress から導出して描く。空のボードは出さない。
## デバッグ冒険譚はデバッグビルドのみ「Debug」ボードにまとめる。選択はシグナルで SelectScreen へ委ねる。

signal campaign_chosen(campaign_id: String, variant: int)  # variant＝カードで表示中の連番index（stage側で同じ絵に固定）
signal title_requested  # タイトルのメニューへ戻る（左上のボタン・Esc）

## 貼り紙の大きさ。横幅は板の貼り付け面（画面1280で1099px＝TavernTheme の枠の厚みから決まる）を
## 3枚＋隙間4つ（枠との左右2つ＋紙どうし2つ）で埋める値 (1099-19*4)/3。
## ＝枠と紙の間隔が紙どうしの間隔と揃う。板の幅を変えたら測り直す。
const POSTER_SIZE := Vector2(341, 440)
const POSTER_SEPARATION := 19  # 貼り紙どうしの隙間（縦横とも）＝枠と紙の隙間もこれに合わせる
const POSTER_ART_HEIGHT := 230.0
const RAIL_HEIGHT := 76.0   # ボード上梁の帯（board.png のテクスチャ縁と一致・ボード名を載せる）
const BOARD_NAME_FONT := "res://assets/fonts/RockSalt-Regular.ttf"
const BOARD_NAME_COLOR := Color(0.906, 0.824, 0.627)  # 焼き付けたクリーム
const DOT_COLOR := Color(0.82, 0.82, 0.82, 0.75)  # カルーセルUI＝無機質なグレー（酒場の物ではない）
const ARROW_SIZE := Vector2(48, 72)  # 繰り矢印の当たり判定サイズ
const ARROW_INSET := 8.0             # ボード左右端からの距離（左右同値＝対称）
const BOARD_MARGIN := 8              # ボードの外周に残す壁の幅（画面の縁からボードまで）

# 難易度帯（表示順）＝ボード。名は英語固定（雰囲気優先・多言語化しない）。
const TIERS := [
	{ "tier": "tutorial", "name": "Tutorial" },
	{ "tier": "rookie", "name": "Rookie" },
	{ "tier": "adept", "name": "Adept" },
	{ "tier": "veteran", "name": "Veteran" },
]
const DEBUG_BOARD_NAME := "Debug"

var _progress: CampaignProgress
var _boards: Array = []   # [{ name:String, campaigns:Array }]（tier順・Debugは先頭）
var _idx := 0
var _positioned := false  # 初回だけ初期ボード（＝最初の実tier）に合わせる。以後はユーザーの繰り位置を保つ
var _variant_by_id := {}   # campaign_id → カードで選んだ連番index。board→stage で同じ絵を出すため保持

var _posters: HFlowContainer
var _board_name: Label
var _left_arrow: Button
var _right_arrow: Button
var _dots: HBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# ボードを画面いっぱい近くまで広げる（壁は縁に細く残す）。28px 空けていた頃は、ボードの下辺が
	# 画面下から28px＝左下の戻るボタンの底辺（画面下から24px）と4px しか離れず、線がぶつかっていた。
	# 広げるとボタンは下梁の帯の中に収まる（実測: 梁 y633-712 に対しボタン y652-696）。
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, BOARD_MARGIN)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# ボード土台（Control）＝ボード本体＋上梁のボード名＋左右の繰り矢印を重ねる
	var board_area := Control.new()
	board_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(board_area)

	# ボード本体（木板）＝貼り紙を貼る面。土台いっぱいに敷く
	var board := PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.add_theme_stylebox_override("panel", TavernTheme.board_stylebox())
	board_area.add_child(board)

	# 貼り付け面（board の content margin＝彫り枠の内側ちょうど）の内側に、さらに紙1枚ぶんの
	# 隙間を左右へ入れる＝枠と紙の間隔が紙どうしの間隔と揃う。上下は板側の余白のままにする。
	var paste := MarginContainer.new()
	paste.add_theme_constant_override("margin_left", POSTER_SEPARATION)
	paste.add_theme_constant_override("margin_right", POSTER_SEPARATION)
	board.add_child(paste)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 縦スクロールバーは出さない（ホイールでは動く）。出すと幅を取って貼り紙の置き場が
	# 狭くなり、3枚が2枚に折り返してしまう（4枚以上のボードで実測）。
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	paste.add_child(scroll)

	_posters = HFlowContainer.new()
	_posters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_posters.add_theme_constant_override("h_separation", POSTER_SEPARATION)
	_posters.add_theme_constant_override("v_separation", POSTER_SEPARATION)
	scroll.add_child(_posters)

	# ボード名＝上梁に手書き風で載せる（貼り紙エリアの外＝紙と干渉しない）
	var name_strip := Control.new()
	name_strip.anchor_right = 1.0
	name_strip.offset_bottom = RAIL_HEIGHT
	name_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_area.add_child(name_strip)
	var name_center := CenterContainer.new()
	name_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_strip.add_child(name_center)
	_board_name = Label.new()
	_board_name.add_theme_font_size_override("font_size", 30)
	_board_name.add_theme_color_override("font_color", BOARD_NAME_COLOR)
	var font := load(BOARD_NAME_FONT)
	if font != null:
		_board_name.add_theme_font_override("font", font)
	name_center.add_child(_board_name)

	# 繰り矢印＝カルーセルのUI。酒場のオブジェクトではない＝あえて無機質なグレー矢印（板ボタンにしない）。
	# ボードの左右端に縦センターで浮かせる。preset任せだと左右で計算がズレるので、各辺からの
	# inset を同値で明示配置＝完全対称。1枚のときは隠す。
	_left_arrow = _nav_arrow("◀")
	_left_arrow.anchor_top = 0.5
	_left_arrow.anchor_bottom = 0.5
	_left_arrow.offset_top = -ARROW_SIZE.y / 2.0
	_left_arrow.offset_bottom = ARROW_SIZE.y / 2.0
	_left_arrow.anchor_left = 0.0
	_left_arrow.anchor_right = 0.0
	_left_arrow.offset_left = ARROW_INSET
	_left_arrow.offset_right = ARROW_INSET + ARROW_SIZE.x
	_left_arrow.pressed.connect(_on_prev)
	board_area.add_child(_left_arrow)
	_right_arrow = _nav_arrow("▶")
	_right_arrow.anchor_top = 0.5
	_right_arrow.anchor_bottom = 0.5
	_right_arrow.offset_top = -ARROW_SIZE.y / 2.0
	_right_arrow.offset_bottom = ARROW_SIZE.y / 2.0
	_right_arrow.anchor_left = 1.0
	_right_arrow.anchor_right = 1.0
	_right_arrow.offset_left = -ARROW_INSET - ARROW_SIZE.x
	_right_arrow.offset_right = -ARROW_INSET
	_right_arrow.pressed.connect(_on_next)
	board_area.add_child(_right_arrow)

	# タイトルのメニューへ戻る。ボードではなく画面の左下に置く＝どの画面でも戻るは同じ場所。
	# 上梁はボード名の場所なので空けておく。Esc でも同じ入口を通る。
	var to_menu := TavernTheme.back_button("← メニュー")
	TavernTheme.place_bottom_left(to_menu)
	to_menu.pressed.connect(_on_back_to_title)
	add_child(to_menu)

	# 現在地ドット＝カルーセルのUI。板の下梁にオーバーレイ（レイアウト幅を取らない）。1枚のときは隠す。
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 8)
	_dots.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	_dots.offset_top = -34
	_dots.offset_bottom = -10
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_area.add_child(_dots)

func setup(progress: CampaignProgress) -> void:
	_progress = progress

## ボード一覧を作り直す（クリア数などを都度導出するため表示ごとに呼ぶ）。
func refresh() -> void:
	_boards = _build_boards()
	if not _positioned:
		_idx = _first_real_index()  # 初回はチュートリアル等の実tierを開く（Debugは左に控える）
		_positioned = true
	_idx = clampi(_idx, 0, maxi(0, _boards.size() - 1))
	_render_current()

## Debug でない最初のボードの添字（＝初期表示位置）。無ければ 0。
func _first_real_index() -> int:
	for i in _boards.size():
		if String(_boards[i]["name"]) != DEBUG_BOARD_NAME:
			return i
	return 0

## 冒険譚を tier ごとのボードへ振り分ける。4帯は空でも常に出す（カルーセルで巡れる＝今後の見通しを見せる）。
## デバッグは末尾の Debug ボード（デバッグ冒険譚がある時だけ）。
func _build_boards() -> Array:
	var by_tier := {}
	var debugs: Array = []
	for c in _progress.campaigns(OS.is_debug_build()):
		if c["debug"]:
			debugs.append(c)
		else:
			var t := String(c.get("tier", "rookie"))
			if not by_tier.has(t):
				by_tier[t] = []
			by_tier[t].append(c)
	var boards: Array = []
	if not debugs.is_empty():
		boards.append({ "name": DEBUG_BOARD_NAME, "campaigns": debugs })  # 先頭＝チュートリアルの左
	for entry in TIERS:
		boards.append({ "name": entry["name"], "campaigns": by_tier.get(entry["tier"], []) })
	return boards

## 現在のボードを描く（貼り紙・ボード名・矢印の有効/無効・ドット）。
func _render_current() -> void:
	_clear_children(_posters)
	var multi := _boards.size() > 1
	_left_arrow.visible = multi
	_right_arrow.visible = multi
	_dots.visible = multi
	if _boards.is_empty():
		_board_name.text = ""
		return
	var board: Dictionary = _boards[_idx]
	_board_name.text = String(board["name"])
	if board["campaigns"].is_empty():
		_posters.add_child(_empty_note())
	for c in board["campaigns"]:
		_posters.add_child(_poster(c))
	_left_arrow.disabled = _idx <= 0
	_right_arrow.disabled = _idx >= _boards.size() - 1
	_rebuild_dots()

## 現在地ドット（●＝現在／○＝他）を作り直す。カルーセルUI＝無機質なグレー。
func _rebuild_dots() -> void:
	_clear_children(_dots)
	if _boards.size() <= 1:
		return
	for i in _boards.size():
		var dot := Label.new()
		dot.text = "●" if i == _idx else "○"
		dot.add_theme_color_override("font_color", DOT_COLOR)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.add_child(dot)

## 空ボードの控えめな注記（貼り紙はまだ無い＝準備中を示す。焼き印色で板になじませる）。
func _empty_note() -> Control:
	var note := Label.new()
	note.text = "― 準備中 ―"
	note.custom_minimum_size = POSTER_SIZE
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_color_override("font_color", Color(BOARD_NAME_COLOR, 0.5))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return note

## カルーセルの繰り矢印＝無機質なグレー矢印（酒場のオブジェクトではない＝UI視点。板ボタンにしない）。
func _nav_arrow(glyph: String) -> Button:
	return TavernTheme.nav_button(glyph, 34)

## タイトルのメニューへ戻る（左下のボタン・Esc の共通入口）。一段戻る音は他の戻ると同じ。
func _on_back_to_title() -> void:
	SfxPlayer.play_event("menu_back")
	title_requested.emit()

## この画面が出ているときだけ Esc を拾う（ステージ選択・依頼書が前に出ているときは相手が受ける）。
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_back_to_title()
		get_viewport().set_input_as_handled()

func _on_prev() -> void:
	if _idx > 0:
		_idx -= 1
		SfxPlayer.play_event("menu_tier")
		_render_current()

func _on_next() -> void:
	if _idx < _boards.size() - 1:
		_idx += 1
		SfxPlayer.play_event("menu_tier")
		_render_current()

## 冒険譚の依頼書＝羊皮紙の貼り紙。クリック判定はカード全面の Button。
## 土台（非clip）とカード（clip）を分けてあるのは、カードの外へはみ出す飾りを後から
## 足せるようにするため。いまは飾りが無いので土台とカードは同じ大きさ。
func _poster(c: Dictionary) -> Control:
	var poster := Control.new()
	poster.custom_minimum_size = POSTER_SIZE

	var card := Button.new()
	card.custom_minimum_size = POSTER_SIZE
	card.size = POSTER_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	var paper_seed := hash(String(c["id"]))  # カードごとに羊皮紙の変種を固定（状態間で同一＝hoverで紙が変わらない）
	for state in ["normal", "hover", "pressed", "disabled"]:
		var bright := 1.06 if state == "hover" else 1.0
		card.add_theme_stylebox_override(state, TavernTheme.parchment_stylebox(paper_seed, bright))
	card.pressed.connect(_on_card_pressed.bind(String(c["id"])))
	poster.add_child(card)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	card.add_child(pad)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)

	# 上: 扉絵（cover。無ければ暗色プレースホルダ）
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0.0, POSTER_ART_HEIGHT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.clip_contents = true
	TavernTheme.round_corners(art, float(TavernTheme.ART_CORNER_RADIUS))  # 紙に貼った写真の丸み
	# 貼り紙とステージ一覧は同じ cover を使う＝押した紙がそのまま開く体験にする（専用クロップは持たない）。
	# 連番バリアントから表示ごとに1枚選び、選んだ index を stage 側へ渡して同じ絵に固定する。
	var art_paths: Array = c.get("cover_paths", [])
	var art_idx := _pick_index(art_paths)
	_variant_by_id[String(c["id"])] = art_idx
	if art_idx >= 0:
		art.texture = load(String(art_paths[art_idx])) as Texture2D
	content.add_child(art)
	content.add_child(_poster_info(c))
	_ignore_mouse(content)
	pad.add_child(content)

	# 全ステージ制覇なら「討伐済」の焼き印を斜めに押す（card 内＝クリップ内でOK）
	if _progress.is_all_cleared(String(c["id"])):
		# 絵の下半分に大きく押す（小さいと制覇の達成感が出ない）。中央揃え＝どの絵でも同じ位置。
		# 文言は依頼の内容に依らない事務的な語（討伐に限らない）。表記はボード名と同じ英語。
		var stamp := TavernTheme.stamp("DONE", TavernTheme.WAX, -12.0, 54, 1.0, 180.0)  # 絵の上＝不透明（透かすと字が絵に負ける）
		stamp.position = Vector2((POSTER_SIZE.x - stamp.size.x) * 0.5, POSTER_ART_HEIGHT - stamp.size.y - 18.0)
		card.add_child(stamp)
	return poster

func _on_card_pressed(campaign_id: String) -> void:
	SfxPlayer.play_event("menu_campaign")
	campaign_chosen.emit(campaign_id, int(_variant_by_id.get(campaign_id, -1)))

## 連番バリアントの index を1つ選ぶ（表示ごと＝呼ぶたび randi）。空なら -1。
func _pick_index(paths: Array) -> int:
	if paths.is_empty():
		return -1
	return randi() % paths.size()

## 貼り紙下部の情報（タイトル／危険度／説明文）。デバッグ冒険譚は注記のみ。
## title/desc は翻訳キー＝tr() で解決（生テキストでも tr() は素通し）。
func _poster_info(c: Dictionary) -> Control:
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = tr(String(c["title"]))
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

	# 危険度（焼き印風の★）
	var danger := HBoxContainer.new()
	danger.add_theme_constant_override("separation", 6)
	var danger_label := Label.new()
	danger_label.text = "危険度"
	danger_label.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	danger.add_child(danger_label)
	danger.add_child(_make_stars(int(c.get("difficulty", 0))))
	info.add_child(danger)

	# 説明文（依頼の紹介・自動折り返し）。カードに収まるのは5行までなので、本文側を5行以内で書く。
	var desc_key := String(c.get("desc", ""))
	if not desc_key.is_empty():
		var desc := Label.new()
		desc.text = tr(desc_key)
		desc.add_theme_font_size_override("font_size", 14)
		desc.add_theme_color_override("font_color", TavernTheme.INK)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
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
