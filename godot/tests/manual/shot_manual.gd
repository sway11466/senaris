extends SceneTree
## feature-52 検証用（使い捨て）: ゲーム内マニュアルの目次と本文をスクショし、寸法を採る。
## 見るのは (1) 目次がスクロールなしで収まるか (2) 本文が横に溢れないか
## (3) 行動ルールの行が読めるか (4) 英語で目次のボタンから字がはみ出さないか。
## 実行: godot --path . -s res://tests/manual/shot_manual.gd（--headless 不可）

const OUT_DIR := "res://tests/manual/out"

## [ロケール, 章の添字, 節の添字, ファイル名]
const SHOTS := [
	["ja", 0, 0, "manual_ja_unit.png"],       # 章の一覧＋用語の並び（dl）
	["ja", 1, 0, "manual_ja_combat.png"],     # 小見出し＋段落＋dl の混在
	["ja", 5, 0, "manual_ja_ai_common.png"],  # 節まで潜った目次
	["ja", 5, 1, "manual_ja_ai_terms.png"],   # 用語集（長い dl）
	["ja", 5, 4, "manual_ja_ai_raid.png"],    # 行動ルール13行＝いちばん長い表
	["en", 5, 4, "manual_en_ai_raid.png"],    # 英語で溢れないか
	["en", 0, 0, "manual_en_unit.png"],       # 英語の目次（章名の長さ）
]

var _frame := 0
var _idx := -1
var _screen: ManualScreen

func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.11, 0.07)  # 店内の絵の代わり（暗幕の下に何かある状態にする）
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_screen = ManualScreen.new()
	root.add_child(_screen)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 12 != 0:  # 暗幕のフェードと折り返しの確定を待つ
		return false
	if _idx >= 0:
		_measure(SHOTS[_idx])
		root.get_texture().get_image().save_png(OUT_DIR.path_join(String(SHOTS[_idx][3])))
	_idx += 1
	if _idx >= SHOTS.size():
		quit()
		return true
	var s: Array = SHOTS[_idx]
	TranslationServer.set_locale(String(s[0]))
	_screen.refresh_labels()
	_screen.open()
	_screen._on_chapter(int(s[1]))
	if int(s[2]) > 0:
		_screen._on_section(int(s[2]))
	return false

## 実寸を出す（目視で断定しない）。溢れは「中身の高さ／幅」対「入れ物」で見る。
func _measure(shot: Array) -> void:
	var toc: VBoxContainer = _screen._toc_box
	var body: VBoxContainer = _screen._body_box
	var scroll: ScrollContainer = _screen._body_scroll
	var toc_scroll := toc.get_parent() as ScrollContainer
	var over := 0
	var widest := 0.0
	for l: Label in _labels(body):
		widest = maxf(widest, l.get_global_rect().end.x)
		if l.get_global_rect().end.x > scroll.get_global_rect().end.x + 0.5:
			over += 1
	var toc_over := 0
	for b: Button in _buttons(toc):
		# 板から字がはみ出していないか＝字の外接がボタンの箱を超えていないか
		var need := b.get_theme_font("font").get_string_size(
			b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		if need > b.size.x - 24.0:  # 板の左右の内側余白ぶん
			toc_over += 1
	print("--- %s" % shot[3])
	print("  目次: 中身の高さ=%.0f / 入れ物=%.0f  行数=%d  はみ出す行=%d" % [
		toc.size.y, toc_scroll.size.y, toc.get_child_count(), toc_over])
	print("  本文: 中身の高さ=%.0f / 入れ物=%.0f  右端=%.0f / 入れ物の右端=%.0f  溢れる行=%d" % [
		body.size.y, scroll.size.y, widest, scroll.get_global_rect().end.x, over])

func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out

func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out
