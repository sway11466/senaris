extends Panel
class_name ConversationPanel
## ステージ前後の会話（チャット風）。右エリアに顔＋ふきだしを上から積み、
## 「次へ」で1行ずつ追加、「会話をスキップ」で丸ごと飛ばす。presentation 専用（盤面に触れない・案P）。
## 話者は左右交互で出す。セリフ/話者名は翻訳キー＝tr() で解決（i18n・正本 data/i18n/dialogue.csv）。
## 詳細 → doc/campaign/authoring.md
##
## 顔は UnitSkin の portrait スロット（未用意は名前2文字のプレースホルダ）。

signal closed  # 会話終了（読了 or スキップ）。呼び出し側が次（戦闘/セレクト）へ進む。

const FACE_SIZE := 112   # 顔（絵）の幅。高さは絵の縦横比で伸びる（縦長可）
const COLOR_BUBBLE_L := Color(0.22, 0.25, 0.31)  # 左（相手側）の吹き出し
const COLOR_BUBBLE_R := Color(0.17, 0.33, 0.29)  # 右の吹き出し（色で左右を区別）
const COLOR_FACE_BG := Color(0.28, 0.32, 0.40)
const COLOR_NAME := Color(0.75, 0.82, 0.92)
const BUBBLE_RATIO := 4.0   # 吹き出しと余白の幅比（顔が大きい分、吹き出しを広めに）

var _skins := {}
var _lines: Array = []
var _shown := 0
var _finish_label := "閉じる"
var _scroll: ScrollContainer
var _messages: VBoxContainer
var _next_btn: Button
var _skip_btn: Button

func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 12
	_scroll.offset_top = 12
	_scroll.offset_right = -12
	_scroll.offset_bottom = -52
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE  # バー分の幅を常に確保＝出現で幅が変わり折返しがズレるのを防ぐ（バーは必要時のみ表示）
	add_child(_scroll)
	_messages = VBoxContainer.new()
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages.add_theme_constant_override("separation", 8)
	_scroll.add_child(_messages)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_top = -44
	bar.offset_bottom = -10
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_skip_btn = Button.new()
	_skip_btn.text = "会話をスキップ"
	_skip_btn.pressed.connect(_on_skip)
	bar.add_child(_skip_btn)
	_next_btn = Button.new()
	_next_btn.text = "次へ ▶"
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.pressed.connect(_on_next)
	bar.add_child(_next_btn)

	var panel_bg := StyleBoxFlat.new()  # 不透明背景＝下の InfoPanel を透かさない
	panel_bg.bg_color = Color(0.11, 0.13, 0.17)
	panel_bg.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", panel_bg)
	hide()

## スキン表を渡す（main から1回）。
func bind(skin_catalog: Dictionary) -> void:
	_skins = skin_catalog

## 会話を開始。lines＝[{ speaker, skin, text }]（speaker/text は翻訳キー）。
## finish_label＝最後の1行を読んだ後のボタン文言（intro="戦闘開始" / outro="閉じる" 等）。
func start(lines: Array, finish_label: String) -> void:
	_lines = lines
	_finish_label = finish_label
	_shown = 0
	for c in _messages.get_children():
		c.queue_free()
	show()
	if _lines.is_empty():
		_close()
		return
	_reveal_next()

func _reveal_next() -> void:
	_add_message(_lines[_shown], _shown)
	_shown += 1
	_next_btn.text = _finish_label if _shown >= _lines.size() else "次へ ▶"
	_scroll.set_deferred("scroll_vertical", 1 << 30)  # レイアウト確定後に最下部へクランプ

func _on_next() -> void:
	if _shown >= _lines.size():
		_close()
	else:
		_reveal_next()

func _on_skip() -> void:
	_close()

func _close() -> void:
	hide()
	closed.emit()

# --- 1メッセージ（顔＋ふきだし）。index の偶奇で左右交互。---

func _add_message(line: Dictionary, index: int) -> void:
	var right := index % 2 == 1
	var row := HBoxContainer.new()  # 行に背景は付けず、セリフだけを吹き出しで囲む
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var face := _make_face(String(line.get("skin", "")))
	var bubble := _make_bubble(line, right)  # 丸角バルーン
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_stretch_ratio = BUBBLE_RATIO
	var gap := Control.new()  # 反対側の余白＝チャットらしく片側を空ける
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = 1.0
	if right:
		row.add_child(gap)
		row.add_child(bubble)
		row.add_child(face)
	else:
		row.add_child(face)
		row.add_child(bubble)
		row.add_child(gap)
	_messages.add_child(row)

## ふきだし＝丸角バルーン（話者名＋セリフ）。翻訳キーは tr() で解決。左右で色を変える。
func _make_bubble(line: Dictionary, right: bool) -> Control:
	var balloon := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = COLOR_BUBBLE_R if right else COLOR_BUBBLE_L
	st.set_corner_radius_all(12)  # 丸角＝吹き出しらしさ
	st.set_content_margin_all(10)
	balloon.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	var name_lbl := Label.new()
	name_lbl.text = tr(String(line.get("speaker", "")))
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", COLOR_NAME)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var text_lbl := Label.new()
	text_lbl.text = tr(String(line.get("text", "")))
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(name_lbl)
	vb.add_child(text_lbl)
	balloon.add_child(vb)
	return balloon

## 顔＝キャラの絵（portrait 優先／無ければ map スプライトを流用）を背景枠なしで大きく載せる。
## 幅=FACE_SIZE 固定、高さは絵の縦横比で伸びる（縦長可）。透過はそのまま活きる（座布団なし）。
## 絵が無い時だけ、名前2文字の小さなプレースホルダ枠を出す。上寄せ固定＝行が高くても伸びない。
func _make_face(skin_id: String) -> Control:
	var sk := SkinCatalog.skin_by_id(_skins, skin_id)
	var path := _face_image(sk)
	if path != "":
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.custom_minimum_size = Vector2(FACE_SIZE, FACE_SIZE)  # 大きめの正方枠（背景なし＝透過そのまま）
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED  # 縦横比を保って枠内に収める（クリップしない）
		tex.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tex.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # 上寄せ・行が高くても伸びない
		return tex
	# プレースホルダ（絵が無い時だけ）: 小さな色枠＋名前2文字
	var box := Panel.new()
	box.custom_minimum_size = Vector2(FACE_SIZE, FACE_SIZE)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var st := StyleBoxFlat.new()
	st.bg_color = COLOR_FACE_BG
	st.set_corner_radius_all(6)
	box.add_theme_stylebox_override("panel", st)
	var lbl := Label.new()
	lbl.text = sk.portrait_label() if sk != null else "？"
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	return box

## 会話の顔画像パス＝portrait 優先、無ければ map スプライトを流用、どちらも無ければ ""（プレースホルダ）。
func _face_image(sk: UnitSkin) -> String:
	if sk == null:
		return ""
	for slot in ["portrait", "map"]:
		var p := sk.image(slot)
		if p != "" and ResourceLoader.exists(p):
			return p
	return ""
