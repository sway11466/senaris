extends Control
class_name QuestSheet
## 出撃確認の依頼書ダイアログ。仕様 → doc/gdd/stage_select.md（依頼書）
## ボードから紙を1枚受け取る見立て＝羊皮紙シート＋出撃する/別のステージを選ぶ。
## 標準 ConfirmationDialog の置き換え。紙に書くもの（あらすじ・幕間の印・戦果・顔ぶれ／
## 勝利条件は書かない）は doc/gdd/stage_select.md 依頼書で決める。
## 見開きの本のように左右2段に割り、どちらのページも左端から始める＝本文の左端と、右の見出し・
## 駒の左端が2本の縦の線になる。中身の量（駒の数・あらすじの長さ）は話ごとに変わるので、
## 寄せる辺を決めておかないと数によって並びが動く。
## 未解放のステージを押したときは同じ紙で解放条件を出す（open_locked）＝一覧から条件の文字を追い出す。

signal confirmed

const SHEET_SIZE := Vector2(900, 400)  # 紙の最小寸法。横長＝見開きの2段組。縦は顔ぶれの群の数で伸びる

const LOCKED_TITLE_KEY := "ui.quest.locked_title"

const COL_GAP := 28       # 左右のページの間
const COL_SEP := 18       # 左のページの中（あらすじ→幕間の印）
const BODY_FONT := 17     # あらすじ・解放条件の本文

## 幕間の印（その話の前に何が起きたか）＝絵1枚。高さは紙に並ぶ駒と同じ（doc/art/icons.md 幕間の印）。
## 絵の無い印（まだ描いていない値）は何も出さない＝欠けた枠を見せない。
const INTERLUDE_DIR := "res://assets/icons/interlude/"
const INTERLUDE_H := 54.0

## 戦果の判子（過去の最高ランク）＝紙の右上の角に押す。上と右の余白を同じにして角へ寄せる
## ＝後から書き足した検印に見える。焼き印の琥珀をそのまま押すと羊皮紙で浮くので暗く落とす。
const RANK_STAMP_D := 54.0
const RANK_STAMP_PAD := 22.0
const RANK_STAMP_TILT := -8.0
const RANK_STAMP_FONT := 38
const RANK_STAMP_FILL := 1.15  # 丸の大きさは据え置いて字だけ太らせる（1文字を押すとき用）
const RANK_STAMP_DROP := 0.04  # 字を丸の中心より少し下げる（同上）
const RANK_STAMP_DARKEN := 0.38

const PARTY_ICON_H := 54.0  # 顔ぶれ1体の高さ（絵は全員ぶんの帯で切ってから揃える）
const PARTY_SEP := 6        # 絵と絵の間
const PARTY_HEAD_SEP := 2   # 見出しと、その見出しが指す並びの間（塊の中）
const PARTY_GROUP_SEP := 16  # 塊と塊の間。中より広く取る＝見出しがどの並びのものか一目で分かる

var _title: Label
var _body: Label
var _interlude: TextureRect
var _rank_slot: Control
var _right: VBoxContainer
var _back: Button
var _sortie: Button
var _party_box: VBoxContainer
var _skins: Dictionary
var _rank_font_cache: Font = null

func _ready() -> void:
	_skins = SkinCatalog.load_standard()  # 顔ぶれの絵を引く表（開くたびに読み直さない）
	# set_anchors_preset はツリー内で呼ぶと現在の矩形（サイズ0）を保つようオフセットを
	# 補正してしまう。_and_offsets 版でオフセットもリセットする。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	# 幕: 背後のクリックを止める。幕クリック＝取り消し（誤出撃防止のワンクッションなので閉じやすく）
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = SHEET_SIZE
	sheet.add_theme_stylebox_override("panel", TavernTheme.sheet_stylebox())
	center.add_child(sheet)

	# 判子は紙の角に押す＝中身の器（余白の内側）ではなく紙そのものに載せる。
	_rank_slot = Control.new()
	_rank_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(_rank_slot)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_bottom"]:
		pad.add_theme_constant_override(side, 32)
	pad.add_theme_constant_override("margin_top", 36)
	sheet.add_child(pad)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	pad.add_child(content)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", TavernTheme.INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_title)

	# インクの罫線（題と本文の区切り）
	var rule := ColorRect.new()
	rule.color = Color(TavernTheme.INK_SOFT, 0.55)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	content.add_child(rule)

	# 見開きの本体＝左右2段。左右は同じ幅（stretch_ratio を揃える）。
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", COL_GAP)
	content.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", COL_SEP)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)

	_body = Label.new()
	_body.add_theme_font_size_override("font_size", BODY_FONT)
	_body.add_theme_color_override("font_color", TavernTheme.INK)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_body)

	# 幕間の印。絵は横の比率を保つので、幅は絵ごとに変わる（左端は揃う）。
	_interlude = TextureRect.new()
	_interlude.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_interlude.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_interlude.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(_interlude)

	# 右＝出撃する顔ぶれ＝盤と同じマップ絵をページの幅で折り返して並べる。継承のステージでは
	# 「引き継ぐ隊」と「この戦い限りの駒」を別の塊に分ける（混ぜると全部引き継ぐように読める）。
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_right)

	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", PARTY_GROUP_SEP)
	_right.add_child(_party_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	# 左＝やめる／右＝進む（doc/gdd/uiux.md ボタンの左右）。紙の下辺の両端に開いて置く。
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	content.add_child(buttons)

	_back = TavernTheme.ink_button(tr("ui.quest.back"))
	_back.pressed.connect(_cancel)
	buttons.add_child(_back)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)

	_sortie = TavernTheme.wax_button(tr("ui.quest.sortie"))
	_sortie.pressed.connect(_on_sortie_pressed)
	buttons.add_child(_sortie)

## synopsis＝あらすじの本文（訳したもの）。interlude＝その話の前の幕間（CampaignCatalog.INTERLUDES・
## ""＝幕間なし）。rank＝過去の最高ランク（""＝未クリア）。
## party＝StageLoader.preview_player_units の配列（{ skin_id, available, carried }）。
## carryover＝この戦いの生き残りが次へ渡るか（doc/gdd/campaigns.md 戦力供給モデル）。
func open(stage_title: String, synopsis: String, interlude: String, rank: String,
		party: Array = [], carryover: bool = false) -> void:
	_title.text = stage_title
	_body.text = synopsis
	_back.text = tr("ui.quest.back")
	_sortie.text = tr("ui.quest.sortie")  # 開くたびに貼り直す＝言語を変えたあとも紙の文字が揃う
	_set_interlude(interlude)
	_set_rank(rank)
	_fill_party(party, carryover)
	_sortie.visible = true
	visible = true

## 未解放のステージを押したときの紙＝解放条件だけを書いて出す。ステージ名は伏せたまま
## （一覧では札を裏返している）＝紙が名前を漏らさない。出撃は無いので閉じるだけ。
func open_locked(unlock_text: String) -> void:
	_title.text = tr(LOCKED_TITLE_KEY)
	_body.text = unlock_text
	_back.text = tr("ui.quest.close")
	_set_interlude("")
	_set_rank("")
	_fill_party([], false)  # 顔ぶれも出さない＝名前を伏せた紙が中身を漏らさない
	_sortie.visible = false
	visible = true

func close() -> void:
	visible = false

## 幕間の印を貼り替える。印なし・絵がまだ無い値は器ごと隠す＝空きも詰まる。
func _set_interlude(interlude: String) -> void:
	var path := INTERLUDE_DIR + interlude + ".png"
	var tex: Texture2D = load(path) if not interlude.is_empty() and ResourceLoader.exists(path) else null
	_interlude.texture = tex
	_interlude.visible = tex != null
	if tex == null:
		return
	var size: Vector2 = tex.get_size()
	_interlude.custom_minimum_size = Vector2(INTERLUDE_H * size.x / maxf(size.y, 1.0), INTERLUDE_H)

## 戦果の判子を押し直す。未クリア（ランクなし）は何も押さない。
## 字は戦果票の印と同じ書体＝1文字でも形が読める（手書き風は1文字だと崩れが形の全部になる）。
func _set_rank(rank: String) -> void:
	for child in _rank_slot.get_children():
		_rank_slot.remove_child(child)
		child.queue_free()
	if rank.is_empty():
		return
	var mark := TavernTheme.stamp(rank, TavernTheme.BRAND.darkened(RANK_STAMP_DARKEN),
		RANK_STAMP_TILT, RANK_STAMP_FONT, 1.0, RANK_STAMP_D, _rank_font(),
		RANK_STAMP_FILL, RANK_STAMP_DROP)
	mark.anchor_left = 1.0
	mark.anchor_right = 1.0
	mark.offset_left = -(RANK_STAMP_D + RANK_STAMP_PAD)
	mark.offset_right = -RANK_STAMP_PAD
	mark.offset_top = RANK_STAMP_PAD
	mark.offset_bottom = RANK_STAMP_PAD + RANK_STAMP_D
	_rank_slot.add_child(mark)

## 判子の字の書体（戦果票と同じ）。無ければ既定のまま。
func _rank_font() -> Font:
	if _rank_font_cache == null and ResourceLoader.exists(ResultBanner.RANK_FONT_PATH):
		_rank_font_cache = load(ResultBanner.RANK_FONT_PATH) as Font
	return _rank_font_cache

## 顔ぶれを並べ直す。空なら右のページごと畳む（未解放の紙・自軍の駒が無いステージ）＝
## 左のページが紙いっぱいに広がり、半分だけ書かれた紙にならない。
## 群ごとに見出し＋絵の並び。継承のステージは「出撃できる生存者」「この戦い限りの駒」
## 「兵力ゼロで出撃できない駒」の3群に分ける（居ない群は出さない）。
## 絵の縮尺は全員ぶんの帯から1つ決めて全群で共有する＝群が変わっても駒の大小関係が変わらない。
func _fill_party(party: Array, carryover: bool) -> void:
	for child in _party_box.get_children():
		_party_box.remove_child(child)
		child.queue_free()
	_right.visible = not party.is_empty()
	var entries: Array = []
	for e in party:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		entries.append(_party_entry(e))
	var band := _band(entries)  # 全員ぶんの絵が収まる縦の帯（キャンバス座標の上端・下端）
	var scale := PARTY_ICON_H / maxf(1.0, band.y - band.x)  # いちばん背の高い駒が PARTY_ICON_H
	if not carryover:
		_add_party_row("ui.quest.party_sortie", entries, scale)  # 群は1つ＝出撃する顔ぶれ
		return
	_add_party_row("ui.quest.party_carry",
		entries.filter(func(e: Dictionary) -> bool: return e["carried"] and e["available"]), scale)
	_add_party_row("ui.quest.party_oneoff",
		entries.filter(func(e: Dictionary) -> bool: return not e["carried"]), scale)
	_add_party_row("ui.quest.party_lost",
		entries.filter(func(e: Dictionary) -> bool: return e["carried"] and not e["available"]), scale)

## 渡された駒の絵が収まる縦の帯（キャンバス座標の上端・下端）。絵が1枚も無ければ空の帯。
func _band(entries: Array) -> Vector2:
	var band := Vector2(INF, 0.0)
	for entry in entries:
		var used: Rect2 = entry["used"]
		if used.size.y > 0.0:
			band = Vector2(minf(band.x, used.position.y), maxf(band.y, used.end.y))
	return band if band.x < band.y else Vector2.ZERO

## 1群ぶん（見出し＋絵の並び）を1つの塊として積む。中身が無ければ何も足さない＝空の見出しを出さない。
## 見出しも駒も左端から始める＝ページの左の縦線に揃う（数が変わっても並びが動かない）。
## 切り出す帯はこの群のぶんだけ＝背の低い駒しか居ない群は行も低くなり、見出しがその並びに寄る。
## 縮尺は全群で共通なので、行の高さが違っても駒の大小関係は変わらない。
func _add_party_row(title_key: String, entries: Array, scale: float) -> void:
	if entries.is_empty():
		return
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", PARTY_HEAD_SEP)
	_party_box.add_child(group)
	var head := Label.new()
	head.text = tr(title_key)
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.add_child(head)
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("h_separation", PARTY_SEP)
	row.add_theme_constant_override("v_separation", PARTY_SEP)
	group.add_child(row)
	var band := _band(entries)
	for entry in entries:
		row.add_child(_party_figure(entry, band, scale))

## 1体ぶんの材料。絵が無ければ tex=null（名前の先頭2文字で描く）。
## used＝絵の非透過部分の外接矩形（キャンバス座標）。
func _party_entry(e: Dictionary) -> Dictionary:
	var skin_id := String(e.get("skin_id", ""))
	var s: UnitSkin = SkinCatalog.skin_by_id(_skins, skin_id)
	var path := s.image("map") if s != null else ""
	var tex: Texture2D = load(path) if not path.is_empty() else null
	var used := Rect2()
	if tex != null:
		used = Rect2(Vector2.ZERO, tex.get_size())
		var img := tex.get_image()
		if img != null:
			var r := img.get_used_rect()
			if r.size.x > 0 and r.size.y > 0:
				used = Rect2(r.position, r.size)
	return { "skin_id": skin_id, "available": bool(e.get("available", true)),
		"carried": bool(e.get("carried", false)), "tex": tex, "used": used }

## 1体ぶんの絵。左右は自分の外接、縦は同じ群の帯で切る＝キャンバスの余白が消える。
## 大小関係はキャンバスに焼いてあるので（doc/art/overview.md）、切った絵を共通の縮尺で出す。
## 絵が無ければ名前の先頭2文字。出撃できない駒（兵力ゼロの離脱者）は盤の行動終了と同じ暗さで沈める。
func _party_figure(entry: Dictionary, band: Vector2, scale: float) -> Control:
	var tex: Texture2D = entry["tex"]
	var node: Control
	var height := (band.y - band.x) * scale
	if tex == null:
		var label := Label.new()
		label.text = tr("unit.%s.name" % String(entry["skin_id"])).substr(0, 2)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", TavernTheme.INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.custom_minimum_size = Vector2(PARTY_ICON_H * 0.7, maxf(height, PARTY_ICON_H * 0.5))
		node = label
	else:
		var used: Rect2 = entry["used"]
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(used.position.x, band.x, used.size.x, band.y - band.x)
		var rect := TextureRect.new()
		rect.texture = at
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(used.size.x * scale, height)
		node = rect
	if not bool(entry["available"]):
		node.modulate = BoardUnitRenderer.DONE_MODULATE
	return node

## 取り消して閉じる（「別のステージを選ぶ」・幕クリック・Esc の共通入口）。開くときに音が鳴るので、
## 閉じるときも鳴らないと非対称になる。出撃は確定音が鳴るので、こちらは通さない。
func _cancel() -> void:
	SfxPlayer.play_event("menu_back")
	close()

func _on_sortie_pressed() -> void:
	close()
	confirmed.emit()

func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_cancel()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
