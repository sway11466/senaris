extends CanvasLayer
class_name SaveSlotPanel
## セーブ／ロードの枠一覧（オートセーブ1枠＋中断セーブ5枠）。仕様 → doc/tech/gamesystem.md
## 盤（システムメニュー）とタイトル（冒険の続き）の両方から同じ物を出す＝枠の見え方が場所で変わらない。
##
## 材質は酒場の物にしない＝セーブは作中の誰の行為でもなくアプリケーションの操作なので、
## 依頼書（羊皮紙）ではなく中立の暗い板に載せる（doc/gdd/title.md メニューの見せ方と同じ判断）。
## 行そのものは木札ボタン＝タイトルのメニュー項目と同じ手触りにする。
##
## 選べない行（セーブ時のオート＝読み出し専用／ロード時の空き枠）は disabled にせず沈んだ見た目にする
## ＝押すと拒否音が返る（無反応だと壊れているのか選べないのかが分からない・doc/audio/sfx.md）。

signal slot_chosen(slot: String)  # 枠が決まった（確認を通ったあと）
signal closed                     # 何も選ばずに閉じた（やめる・幕クリック・Esc）

const PANEL_WIDTH := 760
const ROW_HEIGHT := 54
const ROW_GAP := 10
const HEADING_SIZE := 26
const ROW_FONT_SIZE := 17

enum Mode { SAVE, LOAD }

var _mode := Mode.LOAD
var _slots: SaveSlots = null
var _warn_board := false  # ロードで「いまの盤面が失われる」確認を挟むか（盤から開いたときだけ）

var _root: Control
var _heading: Label
var _rows: VBoxContainer
var _confirm: Control
var _confirm_text: Label
var _confirm_yes: Button
var _pending_slot := ""

func _ready() -> void:
	layer = 75  # タイトル画面（70）より前面＝「冒険の続き」から重ねて出せる
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 後ろ（盤・タイトル）へ触らせない
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.add_theme_stylebox_override("panel", _slate_box())
	center.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 28)
	panel.add_child(pad)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	pad.add_child(content)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", HEADING_SIZE)
	_heading.add_theme_color_override("font_color", Color(0.90, 0.84, 0.70))
	content.add_child(_heading)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", ROW_GAP)
	content.add_child(_rows)

	var footer := HBoxContainer.new()
	content.add_child(footer)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	var back := TavernTheme.wood_button(tr("ui.save.cancel"))
	back.custom_minimum_size = Vector2(160, 44)
	back.pressed.connect(_cancel)
	footer.add_child(back)

	_confirm = _build_confirm()
	_root.add_child(_confirm)

	visible = false

## セーブ先を選ばせる（中断5枠のみ選択可・オートは読み出し専用）。
func open_save(slots: SaveSlots) -> void:
	_open(Mode.SAVE, slots, tr("ui.save.heading_save"), false)

## ロード元を選ばせる。warn_board＝いまの盤面が失われる旨の確認を挟む（盤から開いたとき true）。
func open_load(slots: SaveSlots, heading: String, warn_board: bool) -> void:
	_open(Mode.LOAD, slots, heading, warn_board)

func close() -> void:
	visible = false
	_confirm.visible = false
	_pending_slot = ""

func _open(mode: int, slots: SaveSlots, heading: String, warn_board: bool) -> void:
	_mode = mode
	_slots = slots
	_warn_board = warn_board
	_heading.text = heading
	_confirm.visible = false
	_pending_slot = ""
	_build_rows()
	visible = true

func _build_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	if _slots == null:
		return
	for e in _slots.list():
		_rows.add_child(_row_button(e))

## 枠1行。選べる行＝木札ボタン、選べない行＝沈んだ板（押すと拒否音）。
func _row_button(entry: Dictionary) -> Button:
	var slot := String(entry["slot"])
	var b := TavernTheme.wood_button(_row_text(entry))
	b.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	if _is_selectable(entry):
		b.pressed.connect(func() -> void: _on_row_pressed(slot, bool(entry["used"])))
	else:
		TavernTheme.dim_wood_button(b)
		b.pressed.connect(func() -> void: SfxPlayer.play_event("menu_locked"))
	return b

## セーブ時＝中断5枠だけ（オートはゲームが書く枠）。ロード時＝中身が在る枠だけ。
func _is_selectable(entry: Dictionary) -> bool:
	if _mode == Mode.SAVE:
		return not bool(entry["auto"])
	return bool(entry["used"])

## 行の文字列。中身が在れば「枠名｜冒険譚名 — ステージ名｜ターンN 開始時｜保存日時」。
func _row_text(entry: Dictionary) -> String:
	var sep := tr("ui.save.sep")  # 区切りも言語ごと（全角の｜は欧文の行で浮く）
	var name := tr("ui.save.auto") if bool(entry["auto"]) else String(entry["slot"])
	if not bool(entry["used"]):
		return name + sep + tr("ui.save.empty")
	var meta: Dictionary = entry["meta"]
	# 冒険譚名・ステージ名は翻訳キーで保存してある（言語を変えても一覧が追従する）
	var where := tr("ui.save.campaign_stage") % [tr(String(meta.get("campaign_title", ""))), tr(String(meta.get("stage_title", "")))]
	var parts: Array = [name, where, tr("ui.save.turn_start") % int(meta.get("turn_number", 0))]
	var at := _short_datetime(String(meta.get("saved_at", "")))
	if not at.is_empty():
		parts.append(at)
	return sep.join(PackedStringArray(parts))

## 保存日時（"2026-08-22 14:03:22"）を分までに詰める。秒は一覧の判別に要らない。
static func _short_datetime(raw: String) -> String:
	return raw.substr(0, 16) if raw.length() >= 16 else raw

func _on_row_pressed(slot: String, used: bool) -> void:
	SfxPlayer.play_event("menu_command")
	if _mode == Mode.SAVE and used:
		_ask(tr("ui.save.confirm_overwrite"), tr("ui.save.confirm_overwrite_yes"))  # 既存の枠を潰すときだけ確認（空き枠は素通し）
		_pending_slot = slot
		return
	if _mode == Mode.LOAD and _warn_board:
		_ask(tr("ui.save.confirm_load"), tr("ui.save.confirm_load_yes"))
		_pending_slot = slot
		return
	_decide(slot)

func _decide(slot: String) -> void:
	close()
	slot_chosen.emit(slot)

## 確認の小窓を出す。yes_label＝進むボタンの文言（プロンプトと組で決める。
## 英訳は Yes ではなく動詞＝Overwrite / Load。ja は「はい」のままなのでキーはプロンプトごとに持つ）。
func _ask(text: String, yes_label: String) -> void:
	_confirm_text.text = text
	_confirm_yes.text = yes_label
	_confirm.visible = true

## 確認の小窓（上書き・ロード）。一覧の上に重ねる＝どの枠を選んだかが背後に見えたまま答えられる。
func _build_confirm() -> Control:
	var layer_root := Control.new()
	layer_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 後ろの一覧を押させない
	layer_root.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0.0)
	panel.add_theme_stylebox_override("panel", _slate_box())
	center.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 24)
	panel.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	pad.add_child(box)

	_confirm_text = Label.new()
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.add_theme_font_size_override("font_size", 19)
	_confirm_text.add_theme_color_override("font_color", Color(0.90, 0.84, 0.70))
	box.add_child(_confirm_text)

	# 左＝やめる／右＝進む（doc/gdd/uiux.md ボタンの左右）
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var no := TavernTheme.wood_button(tr("ui.save.cancel"))
	no.custom_minimum_size = Vector2(150, 44)
	no.pressed.connect(_on_confirm_no)
	buttons.add_child(no)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	_confirm_yes = TavernTheme.wood_button("")  # 文言は _ask がプロンプトごとに入れる
	_confirm_yes.custom_minimum_size = Vector2(150, 44)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	buttons.add_child(_confirm_yes)
	return layer_root

func _on_confirm_yes() -> void:
	SfxPlayer.play_event("menu_command")
	_decide(_pending_slot)

## 確認をやめる＝一覧へ戻る（パネルごと閉じない＝別の枠を選び直せる）。
func _on_confirm_no() -> void:
	SfxPlayer.play_event("menu_back")
	_confirm.visible = false
	_pending_slot = ""

## 中立の暗い板（酒場の木ではない・操作の道具の面）。
static func _slate_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.06, 0.06, 0.96)
	box.border_color = Color(0.32, 0.28, 0.24)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	return box

func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_cancel()

## 何も選ばずに閉じる（やめる・幕クリック・Esc）。
func _cancel() -> void:
	SfxPlayer.play_event("menu_back")
	close()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _confirm.visible:
		_on_confirm_no()  # 確認だけ畳んで一覧へ戻る
	else:
		_cancel()
