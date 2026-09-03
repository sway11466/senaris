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

const SHEET := Vector2(640, 480)           ## 羊皮紙の大きさ。素材は 560x400 で、縦横とも引き伸ばして使う
                                           ## （タイルだと中途半端な繰り返しの継ぎ目が出る）。横は明細の右に
                                           ## 印を置ける幅、縦は明細4行＋脚注が収まる高さ（実測 → tests/manual）
const INK_WIN := Color(0.56, 0.13, 0.11)   ## 封蝋の赤（TavernTheme.WAX と同じインク）
const INK_LOSS := Color(0.26, 0.24, 0.25)  ## 灰墨（敗北は色で沈める＝派手にしない）
const STAMP_FONT := 200                    ## 印の字の上限。実際の大きさは STAMP_MAX_D の側で決まる
                                           ## （長い語ほど字が縮む＝丸は常に直径いっぱい。ランクの1文字もここまで太る）
const STAMP_MAX_D := 220.0                 ## 丸印の直径の上限。語が長ければ字を縮めて収める（i18n 対策）
const STAMP_LEFT := 40.0                   ## 紙の左端から印までの余白（印は左・明細は右）
const CAPTION_GAP := 8.0                   ## 「ランク」の見出しと印の間
const CAPTION_H := 26.0                    ## 見出しの高さ（印と合わせて縦中央に置くため）
const BODY_LEFT := 300.0                   ## 明細の左端（印の右）
const STAMP_INK := 0.9                     ## インクの濃さ。明細に重ならないので濃く押す（判を押した重さが出る）
const RANK_FONT_PATH := "res://assets/fonts/IMFellEnglish-Regular.ttf"
                                           ## ランクの1文字だけ活版風で押す。手書き風のままだと S・A の形が読めない。
                                           ## 語（VICTORY・DEFEAT・ボードの DONE）は手書き風のまま＝前後の字が読みを助ける。
const STAMP_FILL := 1.15                   ## 丸はそのままで字だけ太らせる（1文字は放っておくと丸の中で小さい）
const STAMP_DROP := 0.04                   ## 字を丸の中心より少し下げる（見た目の重心が上に寄るため）
const LABEL_W := 110.0                     ## 見出しの桁（ターン／生存／撃破）
const VALUE_W := 120.0                     ## 値の桁（"12 / 30" が入る＝右揃えで桁が縦に揃う）
const GOAL_INDENT := 36.0                  ## ランク基準の字下げ（見出しの下にぶら下げる）
const NOTE_GAP := 6.0                      ## 脚注と明細のあいだ（直前の行の続きに見えないよう空ける）
const GOAL_CHECK := "✓"                    ## 達成した基準の印
const SCRIM_A := 0.55                      ## 盤を沈める暗幕の濃さ
const SHEET_IN := 0.22                     ## 紙が浮かび上がる
const STAMP_WAIT := 0.30                   ## 紙が出てから印が落ちるまでの溜め
const STAMP_WAIT_FLASH := 0.55             ## 白フラッシュから受ける回の溜め＝白が引き切るあたりで印が落ちる
const STAMP_IN := 0.20                     ## 印が落ちる（叩きつけ）

var _root: Control        # 全画面の入力キャッチ（モーダル）
var _scrim: ColorRect     # 盤を沈める暗幕
var _sheet: Panel         # 羊皮紙（非コンテナ＝印を好きな位置に重ねられる）
var _body: VBoxContainer  # 見出し＋戦果の行
var _stamp: Control       # ゴム印（毎回作り直す＝文言・色が変わる）
var _caption: Label       # 印の上の「ランク」（ランクを押す回だけ出す＝用紙の欄名）
var _rank_font_cache: Font = null  # ランクの1文字を押す書体（初回に読む）
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
	# 紙は縦横とも引き伸ばす。素材（parchment_sheet.png）は 560x400 で、戦果票はランク基準の列ぶん
	# 横に広く、所要時間の行ぶん縦に高い＝タイルのままだと繰り返しの継ぎ目が出る（実測）。
	# 横 1.14・縦 1.2 の伸びなら繊維は目に付かない（縦の伸びは sheet_stylebox が既に持っている）。
	var sheet_box := TavernTheme.sheet_stylebox()
	if sheet_box is StyleBoxTexture:
		(sheet_box as StyleBoxTexture).axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_sheet.add_theme_stylebox_override("panel", sheet_box)
	center.add_child(_sheet)
	# 中身は紙の内側に余白を取って置く（Panel は非コンテナなのでアンカーで敷く）。
	_body = VBoxContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = BODY_LEFT
	_body.offset_right = -30.0
	_body.offset_top = 32.0
	_body.offset_bottom = -30.0
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN  # 明細は紙の上から並べる（右下は印の場所）
	_body.add_theme_constant_override("separation", 10)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_body)
	visible = false

## 戦果票を出す。title＝ステージ名、stamp_text＝印の文言（勝利はランク S/A/B、無ければ VICTORY）、
## win＝インクの色分け、caption＝印の上に刷る欄名（ランクを押す回だけ渡す。空＝出さない）、
## rows＝戦果の行。1行は辞書で
## { "label": 見出し, "value": 値, "s": S基準の文言, "s_ok": 達成したか, "a": A基準, "a_ok": … }。
## 基準の文言が空の行（撃破など）は基準の欄を空けたまま並べる。
## "sub"／"sub_ok" はランク基準ではない添え行（所要時間の「最速」）。同じ字下げとチェックで並ぶ。
## note＝明細の下に置く脚注（空＝出さない）。掛かる先は見出しに付けた印で示す＝呼び出し側の管轄。
## from_flash＝決着の白フラッシュから受ける回（勝利）。白が画面を覆っている間に呼ばれる前提で、
## 暗幕と紙をフェードさせず最初から据える＝白が引くと票が既に出ている（doc/gdd/uiux.md 決着の合図）。
## 溜めは白の引きに合わせて長めに取る＝白が引き切るあたりで印が落ちる。
func play(title: String, stamp_text: String, win: bool, rows: Array, caption := "", note := "", from_flash := false) -> void:
	_build()
	_fill(title, rows, note)
	_can_close = false
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 紙が浮かぶ → 溜め → 印が落ちる（落ちた瞬間に stamped＝スティンガーと同時）
	_scrim.modulate.a = 1.0 if from_flash else 0.0
	_sheet.modulate.a = 1.0 if from_flash else 0.0
	_sheet.scale = Vector2.ONE if from_flash else Vector2(0.97, 0.97)
	_sheet.pivot_offset = SHEET / 2.0
	# 字を太らせる／下げるのはランクの1文字のときだけ。VICTORY のような語に効かせると
	# 字が丸枠に触る（実測）。語は元の比率のまま押す。
	var one_letter := stamp_text.length() <= 1
	_stamp = TavernTheme.stamp(stamp_text, INK_WIN if win else INK_LOSS, -9.0, STAMP_FONT, STAMP_INK,
		STAMP_MAX_D, _rank_font() if one_letter else null,
		STAMP_FILL if one_letter else 1.0, STAMP_DROP if one_letter else 0.0)
	# 印は紙の左、明細は右。ランクの1文字は数字と同じく読ませたい情報なので、明細には重ねない
	# （重ねると印の線が数字を割る）。欄名（「ランク」）と印を1つの塊として紙の高さの中央に置く。
	var block_h := _stamp.size.y + (CAPTION_H + CAPTION_GAP if not caption.is_empty() else 0.0)
	var block_top := (SHEET.y - block_h) * 0.5
	_stamp.position = Vector2(STAMP_LEFT + (STAMP_MAX_D - _stamp.size.x) * 0.5, SHEET.y - block_top - _stamp.size.y)
	if not caption.is_empty():
		_caption = _cell(caption, 20, HORIZONTAL_ALIGNMENT_CENTER, STAMP_MAX_D)
		_caption.position = Vector2(STAMP_LEFT, block_top)
		_sheet.add_child(_caption)
	_stamp.scale = Vector2(1.9, 1.9)               # 上から降ってくる
	_stamp.modulate.a = 0.0
	_sheet.add_child(_stamp)
	_tween = create_tween()
	if not from_flash:
		_tween.set_parallel(true)
		_tween.tween_property(_scrim, "modulate:a", 1.0, SHEET_IN)
		_tween.tween_property(_sheet, "modulate:a", 1.0, SHEET_IN)
		_tween.tween_property(_sheet, "scale", Vector2.ONE, SHEET_IN)
		_tween.set_parallel(false)
	_tween.tween_interval(STAMP_WAIT_FLASH if from_flash else STAMP_WAIT)
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

## ランクの1文字用の書体（読み取れる字形が要る。語には使わない）。無ければ既定の印の書体で押す。
func _rank_font() -> Font:
	if _rank_font_cache == null and ResourceLoader.exists(RANK_FONT_PATH):
		_rank_font_cache = load(RANK_FONT_PATH) as Font
	return _rank_font_cache

## 見出しと戦果の行を作り直す（前回の中身は捨てる）。
## 1つの戦果につき「見出し＋値」の行を1本、その下にランク基準を字下げしてぶら下げる。
## 横に並べると1行が長くなって読む順が分からなくなる＝縦に積んで、上から順に読ませる。
func _fill(title: String, rows: Array, note: String) -> void:
	for c in _body.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.custom_minimum_size.x = LABEL_W + VALUE_W
	head.add_theme_color_override("font_color", TavernTheme.INK)
	head.add_theme_font_size_override("font_size", 22)
	_body.add_child(head)
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		_body.add_child(_row_block(r))
	if not note.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = NOTE_GAP
		_body.add_child(gap)
		_body.add_child(_cell(note, 17, HORIZONTAL_ALIGNMENT_LEFT, 0.0))

## 戦果1つぶんの塊（見出し＋値の行と、その下のランク基準）。
func _row_block(r: Dictionary) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.add_child(_cell(String(r.get("label", "")), 22, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W))
	line.add_child(_cell(String(r.get("value", "")), 24, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_W))
	block.add_child(line)
	for key in ["s", "a", "sub"]:
		var text := String(r.get(key, ""))
		if text.is_empty():
			continue
		block.add_child(_goal_line(text, bool(r.get("%s_ok" % key, false))))
	return block

## 見出しの下にぶら下げる1行（ランク基準・所要時間の「最速」）。達成／更新にチェックを付ける
## （達成の有無は印ではなくここで読ませる）。
## 未達も色は落とさない＝薄墨は紙に沈んで読みにくいので、違いはチェックの有無だけで示す。
func _goal_line(text: String, ok: bool) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	var indent := Control.new()
	indent.custom_minimum_size.x = GOAL_INDENT
	line.add_child(indent)
	var t := text
	if ok:
		t = "%s %s" % [text, GOAL_CHECK]
	line.add_child(_cell(t, 19, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	return line

func _cell(text: String, fsize: int, align: int, min_w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.custom_minimum_size.x = min_w  # 桁を揃える（票らしく整列させる）
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
	if _caption != null:
		_caption.queue_free()
		_caption = null
	finished.emit()
