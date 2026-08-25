extends SceneTree
## feature-19 検証用（使い捨て）: 戦果票にランクの印（S/A/B）と基準チェックを出し、
## ja/en でスクショと寸法を採る。見るのは (1) 印が紙の半分以上を覆うか (2) 基準の列が紙に収まるか。
## 実行: godot --path . -s res://tests/manual/shot_result_rank.gd（--headless 不可）

const OUT_DIR := "res://tests/manual/out"
const RANK_DATA := {"turn_s": 15, "turn_a": 22, "survival_s": 4, "survival_a": 2}

var _frame := 0
var _banner: ResultBanner
var _shots: Array = []  # [locale, ターン数, 生存数, 勝ちか, 基準を出すか, ファイル名]
var _idx := -1

func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.10, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_banner = ResultBanner.new()
	root.add_child(_banner)
	_shots = [
		["ja", 12, 5, true, true, "result_ja_s.png"],    # 両方 S
		["ja", 18, 3, true, true, "result_ja_a.png"],    # ターン A・生存 A
		["ja", 25, 1, true, true, "result_ja_b.png"],    # 両方 B
		["ja", 18, 3, false, true, "result_ja_lost.png"],  # 敗北＝ランクなし
		["ja", 12, 5, true, false, "result_ja_norank.png"],  # rank を持たないステージ
		["en", 18, 3, true, true, "result_en_a.png"],
	]

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 20 != 0:  # 印が落ちきってから撮る
		return false
	if _idx >= 0:
		_measure(_shots[_idx])
		root.get_texture().get_image().save_png(OUT_DIR.path_join(String(_shots[_idx][5])))
	_idx += 1
	if _idx >= _shots.size():
		quit()
		return true
	var s: Array = _shots[_idx]
	_banner._dismiss()  # 前の印を片付ける（本番は入力で閉じてから次が出る）
	TranslationServer.set_locale(String(s[0]))
	var win: bool = bool(s[3])
	var rank_data: Dictionary = RANK_DATA if bool(s[4]) and win else {}  # 敗北は基準を出さない（main と同じ）
	var rank := RankEvaluator.evaluate(int(s[1]), int(s[2]), 5, rank_data) if win else ""
	var stamp := rank
	if stamp.is_empty():
		stamp = "VICTORY" if win else "DEFEAT"
	_banner.play("森の追撃", stamp, win, _rows(int(s[1]), int(s[2]), rank_data),
		tr("ui.result.rank") if not rank.is_empty() else "")
	return false

## main.gd の _result_rows と同じ組み立て（あちらは盤の状態から数える）。
func _rows(turn: int, alive: int, rank_data: Dictionary) -> Array:
	var turn_row := {"label": tr("ui.result.turns"), "value": "%d / %d" % [turn, 30]}
	var alive_row := {"label": tr("ui.result.survived"), "value": "%d / %d" % [alive, 5]}
	if not rank_data.is_empty():
		_goals(turn_row, "ui.result.goal_turn", rank_data["turn_s"], rank_data["turn_a"],
			RankEvaluator.turn_rank(turn, rank_data))
		_goals(alive_row, "ui.result.goal_alive", rank_data["survival_s"], rank_data["survival_a"],
			RankEvaluator.survival_rank(alive, 5, rank_data))
	return [turn_row, alive_row, {"label": tr("ui.result.defeated"), "value": "6"}]

func _goals(row: Dictionary, fmt_key: String, s_val: int, a_val: int, got: String) -> void:
	row["s"] = tr(fmt_key) % [RankEvaluator.RANK_S, s_val]
	row["s_ok"] = got == RankEvaluator.RANK_S
	row["a"] = tr(fmt_key) % [RankEvaluator.RANK_A, a_val]
	row["a_ok"] = not RankEvaluator.is_better(RankEvaluator.RANK_A, got)

## 紙・印・明細の実寸を出す（目視で断定しない）。字の実寸は Label の外接から採る。
func _measure(shot: Array) -> void:
	var sheet: Panel = _banner._sheet
	var stamp: Control = _banner._stamp
	var origin := sheet.get_global_rect().position
	var right := 0.0
	var bottom := 0.0
	for l: Label in _labels(_banner._body):
		var r: Rect2 = l.get_global_rect()
		right = maxf(right, r.end.x - origin.x)
		bottom = maxf(bottom, r.end.y - origin.y)
	print("--- %s" % shot[5])
	print("  sheet=%s  印の直径=%.0f  印の左上=(%.0f, %.0f)" % [sheet.size, stamp.size.x, stamp.position.x, stamp.position.y])
	print("  字の右端=%.0f 下端=%.0f  印まで横に %.0f・縦に紙の余り %.0f" % [
		right, bottom, stamp.position.x - right, sheet.size.y - bottom])

func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		# 見出し（中央揃え）は箱が紙幅いっぱいなので測らない＝印とぶつかるのは左揃えの明細のほう。
		if c is Label and not (c as Label).text.is_empty() 				and (c as Label).horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			out.append(c)
		out.append_array(_labels(c))
	return out
