extends DraggablePanel
class_name ConversationPanel
## ステージ前後の会話（チャット風）。右エリアに顔＋ふきだしを上から積み、
## 「次へ」で1行ずつ追加、「会話をスキップ」で丸ごと飛ばす。presentation 専用（盤面に触れない・案P）。
## 話者は左右交互で出す。セリフ/話者名は翻訳キー＝tr() で解決（i18n・正本 data/i18n/dialogue.csv）。
## 話者のいない行（効果音・ト書き）も1行として挟める＝顔を出さず中央に文字だけ、`sfx` があればその音を鳴らす。
## 場面の切り替え（`scene`）は横線の真ん中にト書きを小さく置く区切り＝以後の話者は左から始め直す。
## 駒の登場（`enter`）は何も表示しない行＝名指しのイベントを起こして盤に駒を出し、続けて次の行へ進む。
## 詳細 → doc/campaign/authoring.md
##
## 顔は UnitSkin の portrait スロット（未用意は名前2文字のプレースホルダ）。
##
## 板は情報板と同じ手つきで掴んで動かせる（DraggablePanel）。吹き出しも顔も押下を止めない＝
## ボタン以外のどこを押して引きずっても板が動く（仕様 → doc/gdd/uiux.md 移動）。

signal closed  # 会話終了（読了 or スキップ）。呼び出し側が次（戦闘/セレクト）へ進む。

const FACE_SCALE := 0.33   # キャラ絵の表示倍率。全キャラ共通の固定比＝相対サイズ（大型は大きい）を維持
const COLOR_BUBBLE_L := Color(0.22, 0.25, 0.31)  # 左（相手側）の吹き出し
const COLOR_BUBBLE_R := Color(0.17, 0.33, 0.29)  # 右の吹き出し（色で左右を区別）
const COLOR_FACE_BG := Color(0.28, 0.32, 0.40)
const COLOR_NAME := Color(0.75, 0.82, 0.92)
const COLOR_NARRATION := Color(0.72, 0.70, 0.62)  # 話者のいない行（効果音・ト書き）。話者より落として地の文に見せる
const BUBBLE_RATIO := 6.0   # 吹き出しと余白の幅比（余白を詰めて吹き出しを広めに）
const NARRATION_FONT_SIZE := 22    # 擬音は大きく出す（音そのものの大きさを字で見せる）
const NARRATION_MARGIN := 18       # 上下に1行ぶんの空き＝前後の吹き出しから離して間を作る
const COLOR_SCENE := Color(0.84, 0.82, 0.74)   # 場面の区切りのト書き。小さめの字なので色は落とさず読ませる
const COLOR_SCENE_RULE := Color(0.55, 0.53, 0.47)  # 区切りの横線。文字より落として線は脇役に
const SCENE_FONT_SIZE := 16        # ト書き＝台詞よりやや小さい程度に留める（13 では読みにくかった）
const SCENE_MARGIN := 14           # 上下の空き。擬音ほど間は取らない
const SCENE_TEXT_RATIO := 5.0      # ト書きと左右の横線の幅比（線1：文5：線1）。長い英文でも2行に収める

var _skins := {}
var _lines: Array = []
var _shown := 0
var _speakers := 0  # 話者のいる行だけを数える＝左右交互の順番（効果音の行を挟んでも左右が入れ替わらない）
var _finish_label := ""

## 会話の enter 行で呼ぶフック（StoryDirector が注入）＝ call(event_id: String, reading: bool)。
## reading＝1行ずつ読み進めている最中（カメラ寄せまで見せ切る）／false＝スキップの後始末
## （駒は出すが見せない）。未注入＝enter 行は素通りする。詳細 → doc/campaign/authoring.md
var enter_pace: Callable = Callable()

var _revealing := false  ## enter 行の待ちの最中＝「次へ」の連打で二重に進めない
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
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS  # ホイールは自分で使い、左ボタンは板へ通す（＝吹き出しの上でも板を掴める）
	add_child(_scroll)
	_messages = VBoxContainer.new()
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages.add_theme_constant_override("separation", 4)
	_scroll.add_child(_messages)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_top = -44
	bar.offset_bottom = -10
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_skip_btn = TavernTheme.wood_button(tr("ui.talk.skip"))
	_skip_btn.pressed.connect(_on_skip)
	bar.add_child(_skip_btn)
	_next_btn = TavernTheme.wood_button(tr("ui.talk.next"))
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.pressed.connect(_on_next)
	bar.add_child(_next_btn)

	# 暗い木の看板（不透明＝下の InfoPanel を透かさない。材質ルールは TavernTheme 参照）
	add_theme_stylebox_override("panel", TavernTheme.signboard_stylebox())
	add_child(TavernTheme.signboard_frame())
	hide()

## スキン表を渡す（main から1回）。
func bind(skin_catalog: Dictionary) -> void:
	_skins = skin_catalog

## 会話を開始。lines＝[{ speaker, skin, text }]（speaker/text は翻訳キー）。
## 話者のいない行 { text, sfx } は効果音・ト書き（顔も名前も出さず中央に文字だけ）。
## { scene } は場面の切り替え（横線＋ト書き。以後の話者は左から）。
## finish_label＝最後の1行を読んだ後のボタン文言の翻訳キー（intro="ui.talk.start_battle" / outro="ui.talk.close" 等）。
## セリフ・話者名と同じくキーで受けてここで tr() する＝言語を切り替えても表示が追従する。
func start(lines: Array, finish_label: String) -> void:
	_lines = lines
	_finish_label = finish_label
	_shown = 0
	_speakers = 0
	_revealing = false  # 前の会話が enter 行の待ちのまま閉じられていても、新しい会話は進められる
	for c in _messages.get_children():
		c.queue_free()
	show()
	if _lines.is_empty():
		_close()
		return
	_reveal_next()

## 次の1行を出す。行の作りで見た目と音が決まる。
## - speaker あり＝顔＋吹き出し（左右交互）
## - scene あり＝場面の区切り（横線の真ん中にト書き）。左右交互を最初に戻す
## - speaker なし・text あり＝中央に文字だけ（効果音・ト書き）
## - sfx あり＝その行が出るときにその音を鳴らす（文字送り音の代わり）
## - enter あり＝名指しのイベントの駒が盤に出る（表示は無い＝出し切るまで待ってから次の行へ）
## 表示するものが何も無い行（sfx・enter だけ）は「次へ」を消費させず、続けて次の行まで進める。
func _reveal_next() -> void:
	if _revealing:
		return  # enter 行の待ちの最中＝連打を捨てる（1行ぶんが二度進むのを防ぐ）
	_revealing = true
	while _shown < _lines.size():
		var line := _line_at(_shown)
		_shown += 1
		var shown_here := true
		if line.has("speaker"):
			_add_message(line, _speakers)
			_speakers += 1
		elif line.has("scene"):
			_add_scene(line)
			_speakers = 0  # 場面が変わる＝新しい場面の最初の話者は左から
		elif String(line.get("text", "")) != "":
			_add_narration(line)
		else:
			shown_here = false
		var sfx := String(line.get("sfx", ""))
		if sfx != "":
			SfxPlayer.play_sfx(sfx)  # 効果音の行＝文字送り音は鳴らさない（音が重ならないように）
		elif shown_here:
			SfxPlayer.play_event("map_talk")
		await _run_enter(line, true)  # 駒の登場は表示より後＝物音の行の「次へ」で出てくる
		if shown_here:
			break
	_revealing = false
	_next_btn.text = tr(_finish_label) if _shown >= _lines.size() else tr("ui.talk.next")
	_scroll_to_last()

## 行が enter を持っていれば、その駒を盤に出してもらう（出し切るまで待つ）。
## reading＝読み進めている最中か（スキップの後始末では見せずに出すだけ）。
func _run_enter(line: Dictionary, reading: bool) -> void:
	var event_id := String(line.get("enter", ""))
	if event_id.is_empty() or not enter_pace.is_valid():
		return
	await enter_pace.call(event_id, reading)

## 読み残した enter 行を全部起こす（スキップ・会話を出さないときの後始末）。
## 読まなくても盤は台本どおりの顔ぶれで始まる＝出てくるはずの駒が消えない。
func drain_enters() -> void:
	while _shown < _lines.size():
		var line := _line_at(_shown)
		_shown += 1
		await _run_enter(line, false)

## 言語が変わったので文言を貼り直す（doc/tech/i18n.md 言語の切り替え）。
## パネルは起動時に1度だけ作って生き続けるので、板に焼いたボタンの文字だけ差し替える。
## 会話の本文は流すたびに組むので触らない。
func refresh_labels() -> void:
	_skip_btn.text = tr("ui.talk.skip")
	_next_btn.text = tr(_finish_label) if not _finish_label.is_empty() and _shown >= _lines.size() else tr("ui.talk.next")

## 台本の1行。辞書でなければ空辞書に倒す（壊れたデータで会話を止めない）。
func _line_at(index: int) -> Dictionary:
	var v: Variant = _lines[index]
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v

## 追加した行が見えるところまでスクロールする。
## 追加直後は行の高さがまだ決まっておらず（Container の再整列は次のレイアウトパス）、その時点の
## scroll_vertical は古い最大値にクランプされる＝新しい行が画面外に取り残される。高さが確定するのを
## 待ってから寄せる。1画面に収まらない長い行は上端を合わせる＝頭から読める。
func _scroll_to_last() -> void:
	var count := _messages.get_child_count()
	if count == 0:
		return
	var row := _messages.get_child(count - 1) as Control
	await get_tree().process_frame
	await get_tree().process_frame  # 1回では ScrollContainer の最大値がまだ古く、代入がクランプされる
	if not is_instance_valid(_scroll) or not is_instance_valid(row):
		return
	var view := _scroll.size.y
	var top := row.position.y
	var bottom := top + row.size.y
	var cur := float(_scroll.scroll_vertical)
	if bottom > cur + view:
		_scroll.scroll_vertical = int(minf(top, bottom - view))
	elif top < cur:  # 上へスクロールして読み返していた場合も追いつかせる
		_scroll.scroll_vertical = int(top)

func _on_next() -> void:
	if _revealing:
		return  # enter 行の待ちの最中＝連打で先へ進めない（駒が出る前に閉じさせない）
	if _shown >= _lines.size():
		_close()
	else:
		_reveal_next()

func _on_skip() -> void:
	if _revealing:
		return  # enter 行の待ちの最中＝出し切ってから閉じさせる（駒の取りこぼしを防ぐ）
	await drain_enters()  # 読まずに飛ばした登場も盤には出す
	_close()

func _close() -> void:
	hide()
	closed.emit()

# --- 1メッセージ（顔＋ふきだし）。index の偶奇で左右交互。---

func _add_message(line: Dictionary, index: int) -> void:
	var right := index % 2 == 1
	var row := HBoxContainer.new()  # 行に背景は付けず、セリフだけを吹き出しで囲む
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)  # 顔の透過余白＋しっぽで間が取れるので0
	var face := _make_face(String(line.get("skin", "")))
	var tail := _make_tail(right)  # 吹き出しのしっぽ（顔の側を指す三角）
	var bubble := _make_bubble(line, right)  # 丸角バルーン
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_stretch_ratio = BUBBLE_RATIO
	var gap := Control.new()  # 反対側の余白＝チャットらしく片側を空ける
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 余白の上でも板を掴める
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = 1.0
	if right:
		row.add_child(gap)
		row.add_child(bubble)
		row.add_child(tail)
		row.add_child(face)
	else:
		row.add_child(face)
		row.add_child(tail)
		row.add_child(bubble)
		row.add_child(gap)
	_messages.add_child(row)

## 話者のいない行＝効果音・ト書き。顔も名前も吹き出しも出さず、幅いっぱいの中央寄せで文字だけを置く。
## 誰かの発言ではないので吹き出しを与えない（左右のどちらに寄せても話者に見えてしまう）。
## 大きめの字＋上下1行ぶんの空きで、掛け合いの流れを断つ出来事として立てる。
func _add_narration(line: Dictionary) -> void:
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_top", NARRATION_MARGIN)
	mc.add_theme_constant_override("margin_bottom", NARRATION_MARGIN)
	var lbl := Label.new()
	lbl.text = tr(String(line.get("text", "")))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", NARRATION_FONT_SIZE)
	lbl.add_theme_color_override("font_color", COLOR_NARRATION)
	mc.add_child(lbl)
	_messages.add_child(mc)

## 場面の切り替え＝区切り。横線の真ん中にト書き（場所・状況）を小さく置く。
## 味方と敵で場面が入れ替わるとき、同じ流れの続きに見えないように線で断つ。
## 文字は吹き出しでも擬音でもない色と大きさ＝札として読ませる。
func _add_scene(line: Dictionary) -> void:
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_top", SCENE_MARGIN)
	mc.add_theme_constant_override("margin_bottom", SCENE_MARGIN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_make_rule())
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 文字の上でも板を掴める
	lbl.text = tr(String(line.get("scene", "")))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_stretch_ratio = SCENE_TEXT_RATIO
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", SCENE_FONT_SIZE)
	lbl.add_theme_color_override("font_color", COLOR_SCENE)
	row.add_child(lbl)
	row.add_child(_make_rule())
	mc.add_child(row)
	_messages.add_child(mc)

## 区切りの横線（1px）。行の高さの中央に置く。
func _make_rule() -> Control:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = COLOR_SCENE_RULE
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_stretch_ratio = 1.0
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r

## 吹き出しのしっぽ（三角）。バルーンの顔側の縁に付け、顔の方向を指す。色はバルーンと同じ。
## MarginContainer の上マージンで少し下げる（名前の下＝本文あたりに付く）。
func _make_tail(right: bool) -> Control:
	var mc := MarginContainer.new()
	mc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mc.add_theme_constant_override("margin_top", 18)
	var t := _Tail.new()
	t.color = COLOR_BUBBLE_R if right else COLOR_BUBBLE_L
	t.points_left = not right  # 左話者＝顔が左＝左向き
	t.custom_minimum_size = Vector2(10, 22)
	mc.add_child(t)
	return mc

## ふきだし＝丸角バルーン（話者名＋セリフ）。翻訳キーは tr() で解決。左右で色を変える。
func _make_bubble(line: Dictionary, right: bool) -> Control:
	var balloon := PanelContainer.new()
	balloon.mouse_filter = Control.MOUSE_FILTER_PASS  # 吹き出しの上でも板を掴める
	var st := StyleBoxFlat.new()
	st.bg_color = COLOR_BUBBLE_R if right else COLOR_BUBBLE_L
	st.set_corner_radius_all(12)  # 丸角＝吹き出しらしさ
	st.set_content_margin_all(8)
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

## 顔＝キャラの絵（portrait 優先／無ければ map スプライトを流用）。
## レイアウトは「基準枠」＝左右 FACE_INSET_X を詰めた中央ぶんの場所だけ取り、絵は 256 全体を描く。
## 通常キャラは枠外が透過で違和感なし／大型キャラは体が枠外（吹き出し側）へはみ出して見える。
## 背景枠なし・上寄せ固定＝行が高くても伸びない。絵が無い時だけ名前2文字のプレースホルダ枠を出す。
func _make_face(skin_id: String) -> Control:
	var sk := SkinCatalog.skin_by_id(_skins, skin_id)
	var path := _face_image(sk)
	if path != "":
		var src := load(path) as Texture2D
		var full := src.get_size()
		var bbox := Rect2(Vector2.ZERO, full)  # キャラ実体（非透過部分）の外接矩形
		var img := src.get_image()
		if img != null:
			var used := img.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				bbox = Rect2(used.position, used.size)
		var atlas := AtlasTexture.new()  # 実体の外接矩形だけ表示＝周囲の透明余白を除く（キャラは1pxも切らない）
		atlas.atlas = src
		atlas.region = bbox
		var tex := TextureRect.new()
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 顔の上でも板を掴める
		tex.texture = atlas
		tex.custom_minimum_size = bbox.size * FACE_SCALE  # 固定倍率＝相対サイズ維持・左右の隙間なし
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tex.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # 上寄せ・行が高くても伸びない
		return tex
	# プレースホルダ（絵が無い時だけ）: 小さな色枠＋名前2文字
	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 顔の上でも板を掴める
	box.custom_minimum_size = Vector2(64, 64)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var st := StyleBoxFlat.new()
	st.bg_color = COLOR_FACE_BG
	st.set_corner_radius_all(6)
	box.add_theme_stylebox_override("panel", st)
	var lbl := Label.new()
	lbl.text = tr("unit." + sk.skin_id + ".name").substr(0, 2) if sk != null else "？"
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

## 吹き出しのしっぽ＝小さな三角。points_left で向き（顔の側）を変える。バルーンと同色。
class _Tail extends Control:
	var color := Color.WHITE
	var points_left := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # しっぽの上でも板を掴める
		resized.connect(queue_redraw)  # コンテナにサイズを与えられたら描き直す

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts: PackedVector2Array
		if points_left:  # 頂点が左（顔が左）、底辺が右＝バルーン側
			pts = PackedVector2Array([Vector2(w, 0), Vector2(0, h * 0.5), Vector2(w, h)])
		else:            # 頂点が右（顔が右）
			pts = PackedVector2Array([Vector2(0, 0), Vector2(w, h * 0.5), Vector2(0, h)])
		draw_colored_polygon(pts, color)
