extends CanvasLayer
class_name ResultBanner
## ステージ決着の演出＝羊皮紙の戦果票に大きなゴム印を叩きつける。仕様 → doc/gdd/uiux.md
##
## セレクト画面は酒場の依頼ボードで、制覇した貼り紙には「討伐済」の印が押されている
## （presentation/select/campaign_select.gd）。決着でも同じ印影を使う＝ボードのあの印は
## ここで押されたものだ、という繋がりを作る（新しい見た目を発明しない）。
##
## 演出は短く、情報は入力待ちで好きなだけ読める（尺で持たせず情報で噛み締めさせる）。
## main が play(...) を呼び、印が落ちた瞬間に stamped、入力で閉じて finished を出す。

signal stamped   ## 印が落ちた瞬間（main がスティンガーを鳴らす合図＝演出と音を揃える）
signal finished  ## 入力で閉じた（main が outro会話／次ステージへ進む）

const SHEET := Vector2(540, 390)           ## 羊皮紙の大きさ（丸印が収まる高さを確保）
const INK_WIN := Color(0.56, 0.13, 0.11)   ## 封蝋の赤（TavernTheme.WAX と同じインク）
const INK_LOSS := Color(0.26, 0.24, 0.25)  ## 灰墨（敗北は色で沈める＝派手にしない）
const STAMP_FONT := 116                    ## 印の字の上限（短い語ならこの大きさまで＝WIN 等）
const STAMP_MAX_D := 340.0                 ## 丸印の直径の上限。語が長ければ字を縮めて収める（i18n 対策）
const SCRIM_A := 0.55                      ## 盤を沈める暗幕の濃さ
const SHEET_IN := 0.22                     ## 紙が浮かび上がる
const STAMP_WAIT := 0.30                   ## 紙が出てから印が落ちるまでの溜め
const STAMP_IN := 0.20                     ## 印が落ちる（叩きつけ）

var _root: Control        # 全画面の入力キャッチ（モーダル）
var _scrim: ColorRect     # 盤を沈める暗幕
var _sheet: Panel         # 羊皮紙（非コンテナ＝印を好きな位置に重ねられる）
var _body: VBoxContainer  # 見出し＋戦果の行
var _stamp: Control       # ゴム印（毎回作り直す＝文言・色が変わる）
var _tween: Tween
var _can_close := false   # 印が落ちるまでは入力で閉じない（演出を飛ばさせない）

func _ready() -> void:
	_build()

## ノードツリーを1度だけ組む（_ready より前に play が来ても安全なよう遅延生成にも対応）。
func _build() -> void:
	if _root != null:
		return
	layer = 55  # 戦闘演出(50)より前・キャンペーン完走の勝利イラスト(60)より後ろ
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # 表示中は盤入力を食う（モーダル）
	_root.gui_input.connect(_on_input)
	add_child(_root)
	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(0, 0, 0, SCRIM_A)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_sheet = Panel.new()
	_sheet.custom_minimum_size = SHEET
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_theme_stylebox_override("panel", TavernTheme.sheet_stylebox())
	center.add_child(_sheet)
	# 中身は紙の内側に余白を取って置く（Panel は非コンテナなのでアンカーで敷く）。
	_body = VBoxContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = 36.0
	_body.offset_right = -36.0
	_body.offset_top = 30.0
	_body.offset_bottom = -30.0
	_body.alignment = BoxContainer.ALIGNMENT_CENTER  # 紙の中央に寄せる（下に空きを作らない）
	_body.add_theme_constant_override("separation", 18)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_body)
	visible = false

## 戦果票を出す。title＝ステージ名、stamp_text＝印の文言、win＝インクの色分け、
## rows＝[[見出し, 値], …] の戦果（ターン数・生存など）。
func play(title: String, stamp_text: String, win: bool, rows: Array) -> void:
	_build()
	_fill(title, rows)
	_can_close = false
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 紙が浮かぶ → 溜め → 印が落ちる（落ちた瞬間に stamped＝スティンガーと同時）
	_scrim.modulate.a = 0.0
	_sheet.modulate.a = 0.0
	_sheet.scale = Vector2(0.97, 0.97)
	_sheet.pivot_offset = SHEET / 2.0
	_stamp = TavernTheme.stamp(stamp_text, INK_WIN if win else INK_LOSS, -9.0, STAMP_FONT, 0.66, STAMP_MAX_D)
	_stamp.position = (SHEET - _stamp.size) / 2.0  # 紙の中央に重ねる（下の字は隙間から読める）
	_stamp.scale = Vector2(1.9, 1.9)               # 上から降ってくる
	_stamp.modulate.a = 0.0
	_sheet.add_child(_stamp)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_scrim, "modulate:a", 1.0, SHEET_IN)
	_tween.tween_property(_sheet, "modulate:a", 1.0, SHEET_IN)
	_tween.tween_property(_sheet, "scale", Vector2.ONE, SHEET_IN)
	_tween.set_parallel(false)
	_tween.tween_interval(STAMP_WAIT)
	_tween.set_parallel(true)
	_tween.tween_property(_stamp, "modulate:a", 1.0, STAMP_IN * 0.5)
	_tween.tween_property(_stamp, "scale", Vector2.ONE, STAMP_IN)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)  # 行き過ぎて戻る＝押した反動
	_tween.set_parallel(false)
	_tween.tween_callback(_on_stamped)
	# 紙が押し込まれて戻る（印を押す物理＝勝敗どちらでも同じ動き）。
	# position ではなく scale で潰す＝CenterContainer が位置を握っているため（position を
	# tween すると中央揃えを奪って紙が左上に寄る）。scale はコンテナが触らない。
	_tween.tween_property(_sheet, "scale", Vector2(1.03, 0.96), 0.05)
	_tween.tween_property(_sheet, "scale", Vector2.ONE, 0.10)

## 見出しと戦果の行を作り直す（前回の中身は捨てる）。
func _fill(title: String, rows: Array) -> void:
	for c in _body.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", TavernTheme.INK)
	head.add_theme_font_size_override("font_size", 22)
	_body.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)  # 左右に散らす＝印の濃い中心から見出しを逃がす
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(grid)
	# 見出しも値と同じ濃さで書く。薄墨だと印の下で沈んで読めない（実測で確認）。
	for r in rows:
		if typeof(r) != TYPE_ARRAY or r.size() < 2:
			continue
		grid.add_child(_cell(String(r[0]), 22, HORIZONTAL_ALIGNMENT_LEFT))
		grid.add_child(_cell(String(r[1]), 24, HORIZONTAL_ALIGNMENT_RIGHT))

func _cell(text: String, fsize: int, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.custom_minimum_size.x = 160.0  # 見出し／値の桁を揃える（票らしく整列させる）
	l.add_theme_color_override("font_color", TavernTheme.INK)
	l.add_theme_font_size_override("font_size", fsize)
	return l

## 印が落ちた＝スティンガーを鳴らす合図を出し、以後は入力で閉じられる。
func _on_stamped() -> void:
	_can_close = true
	stamped.emit()

func _on_input(e: InputEvent) -> void:
	if not _can_close:
		return
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed):
		_dismiss()

func _dismiss() -> void:
	if not visible:
		return
	visible = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _stamp != null:
		_stamp.queue_free()  # 次回は文言・色ごと作り直す
		_stamp = null
	finished.emit()
