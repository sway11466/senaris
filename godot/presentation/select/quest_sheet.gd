extends Control
class_name QuestSheet
## 出撃確認の依頼書ダイアログ。仕様 → doc/gdd/stage_select.md（依頼書）
## ボードから紙を1枚受け取る見立て＝羊皮紙シート＋出撃する/別のステージを選ぶ。
## 標準 ConfirmationDialog の置き換え。紙に書くもの（顔ぶれ・戦力の供給／勝利条件は書かない）は
## doc/gdd/stage_select.md 依頼書で決める。
## 未解放のステージを押したときは同じ紙で解放条件を出す（open_locked）＝一覧から条件の文字を追い出す。

signal confirmed

const SHEET_SIZE := Vector2(560, 400)  # 紙の最小寸法（parchment_sheet.png と同寸）。顔ぶれの群が増えると縦に伸びる

const LOCKED_TITLE_KEY := "ui.quest.locked_title"

const PARTY_ICON_H := 54.0  # 顔ぶれ1体の高さ（絵は全員ぶんの帯で切ってから揃える）
const PARTY_SEP := 6        # 絵と絵の間
const PARTY_ROW_SEP := 4    # 見出しと絵の行の間

var _title: Label
var _body: Label
var _back: Button
var _sortie: Button
var _party_box: VBoxContainer
var _skins: Dictionary

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

	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_theme_font_size_override("font_size", 18)
	_body.add_theme_color_override("font_color", TavernTheme.INK)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_body)

	# 出撃する顔ぶれ＝盤と同じマップ絵を紙の幅で折り返して並べる。継承のステージでは
	# 「引き継ぐ隊」と「この戦い限りの駒」を別の行に分ける（混ぜると全部引き継ぐように読める）。
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", PARTY_ROW_SEP)
	content.add_child(_party_box)

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

## party＝StageLoader.preview_player_units の配列（{ skin_id, available }）。
## carryover＝この戦いの生き残りが次へ渡るか（doc/gdd/campaigns.md 戦力供給モデル）。
func open(stage_title: String, party: Array = [], carryover: bool = false) -> void:
	_title.text = stage_title
	_body.text = tr("ui.quest.confirm")
	_back.text = tr("ui.quest.back")
	_fill_party(party, carryover)
	_sortie.visible = true
	visible = true

## 未解放のステージを押したときの紙＝解放条件だけを書いて出す。ステージ名は伏せたまま
## （一覧では札を裏返している）＝紙が名前を漏らさない。出撃は無いので閉じるだけ。
func open_locked(unlock_text: String) -> void:
	_title.text = tr(LOCKED_TITLE_KEY)
	_body.text = unlock_text
	_back.text = tr("ui.quest.close")
	_fill_party([], false)  # 顔ぶれも出さない＝名前を伏せた紙が中身を漏らさない
	_sortie.visible = false
	visible = true

func close() -> void:
	visible = false

## 顔ぶれを並べ直す。空なら行ごと消える（未解放の紙・自軍の駒が無いステージ）。
## 群ごとに見出し＋絵の並び。継承のステージは「出撃できる生存者」「この戦い限りの駒」
## 「兵力ゼロで出撃できない駒」の3群に分ける（居ない群は出さない）。
## 絵の大きさを揃える帯は群をまたいで1つ＝群が変わっても駒の大小関係が変わらない。
func _fill_party(party: Array, carryover: bool) -> void:
	for child in _party_box.get_children():
		_party_box.remove_child(child)
		child.queue_free()
	_party_box.visible = not party.is_empty()
	var entries: Array = []
	var band := Vector2(INF, 0.0)  # 全員ぶんの絵が収まる縦の帯（キャンバス座標の上端・下端）
	for e in party:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var entry := _party_entry(e)
		entries.append(entry)
		var used: Rect2 = entry["used"]
		if used.size.y > 0.0:
			band = Vector2(minf(band.x, used.position.y), maxf(band.y, used.end.y))
	if not carryover:
		_add_party_row("ui.quest.party_sortie", entries, band)  # 群は1つ＝出撃する顔ぶれ
		return
	_add_party_row("ui.quest.party_carry",
		entries.filter(func(e: Dictionary) -> bool: return e["carried"] and e["available"]), band)
	_add_party_row("ui.quest.party_oneoff",
		entries.filter(func(e: Dictionary) -> bool: return not e["carried"]), band)
	_add_party_row("ui.quest.party_lost",
		entries.filter(func(e: Dictionary) -> bool: return e["carried"] and not e["available"]), band)

## 1群ぶんの行（見出し＋絵の並び）。中身が無ければ何も足さない＝空の見出しを出さない。
func _add_party_row(title_key: String, entries: Array, band: Vector2) -> void:
	if entries.is_empty():
		return
	var head := Label.new()
	head.text = tr(title_key)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", TavernTheme.INK_SOFT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_box.add_child(head)
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", PARTY_SEP)
	row.add_theme_constant_override("v_separation", PARTY_SEP)
	_party_box.add_child(row)
	for entry in entries:
		row.add_child(_party_figure(entry, band))

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

## 1体ぶんの絵。左右は自分の外接、縦は全員ぶんの帯で切る＝キャンバスの余白が消えて絵が大きくなり、
## 駒どうしの大小関係は残る（大小はキャンバスに焼いてある。doc/art/overview.md）。
## 絵が無ければ名前の先頭2文字。出撃できない駒（兵力ゼロの離脱者）は盤の行動終了と同じ暗さで沈める。
func _party_figure(entry: Dictionary, band: Vector2) -> Control:
	var tex: Texture2D = entry["tex"]
	var node: Control
	if tex == null:
		var label := Label.new()
		label.text = tr("unit.%s.name" % String(entry["skin_id"])).substr(0, 2)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", TavernTheme.INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.custom_minimum_size = Vector2(PARTY_ICON_H * 0.7, PARTY_ICON_H)
		node = label
	else:
		var used: Rect2 = entry["used"]
		var top := band.x if band.x < band.y else 0.0                      # 帯が無い＝絵が1枚も無い
		var bottom := band.y if band.x < band.y else float(tex.get_height())
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(used.position.x, top, used.size.x, bottom - top)
		var rect := TextureRect.new()
		rect.texture = at
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(PARTY_ICON_H * used.size.x / (bottom - top), PARTY_ICON_H)
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
