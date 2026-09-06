extends RefCounted
class_name StageTally
## 戦果の集計（presentation/main）。ステージ開始時の兵力とランク閾値を控え、決着でランクと
## 所要時間を確定し、戦果票（ResultBanner）に載せる行を組む。集計は presentation 側＝domain に
## 戦績を持たせない。仕様 → doc/gdd/rank.md・doc/tech/gamesystem.md §所要時間

var _state: BattleState = null
var _context: StageContext = null
var _start_ally := 0   # ステージ開始時の自軍数（戦果票の「生存 n/N」の分母）
var _rank_data := {}   # ステージ JSON の "rank"（評価ランクの閾値）。空＝ランクなし
var _elapsed := 0      # 決着までの所要秒。0＝測れていない＝票に出さず記録もしない
var _best_time := 0    # この回を記録する前の自己ベスト（秒）。0＝記録なし

## ステージ開始。開始時の兵力は盤の現況ではなくステージ定義から導出する＝中断セーブから
## 再開しても同じ値になる（doc/gdd/rank.md 生存）。
func begin(state: BattleState, path: String, context: StageContext) -> void:
	_state = state
	_context = context
	_start_ally = StageLoader.count_start_allies_at(path, state)
	_rank_data = StageLoader.load_rank(path)  # 無ければ空＝ランクなし
	_elapsed = 0
	_best_time = 0

## 決着。ランク（勝利でランクを持つステージだけ。ほかは空文字）を返し、所要秒を確定する。
## 決着の直後＝名簿更新より前（盤の駒がまだ動いていない）に呼ぶ。
## best_time＝この回を記録する前の自己ベスト（秒・0＝記録なし）＝票には「この回の前のベスト」を出す。
func finish(outcome: int, best_time: int) -> String:
	_elapsed = _elapsed_seconds()
	_best_time = best_time
	if outcome != BattleState.PLAYER_WIN:
		return ""
	return _evaluate_rank()

## 決着までの所要秒（finish の後）。0＝測れていない。
func elapsed() -> int:
	return _elapsed

## 評価ランクを算出する（勝利時）。rank_data が空ならランクなし＝空文字。
func _evaluate_rank() -> String:
	if _rank_data.is_empty() or _state == null:
		return ""
	return RankEvaluator.evaluate(_state.turn_number, _state.ally_survivor_count(), _start_ally, _rank_data)

## ステージを始めてから決着までの秒数。0＝測れていない（開始時刻を持たない旧セーブから再開した回）。
## 時計が巻き戻ったとき（システム時刻の変更）も 0 に倒す＝負の時間を記録に混ぜない。
func _elapsed_seconds() -> int:
	if _context == null or _context.started_at <= 0:
		return 0
	return maxi(int(Time.get_unix_time_from_system()) - _context.started_at, 0)

## 戦果の行（ターン数・生存・撃破・所要時間）。
## 勝利のときだけ、ターン数と生存にランク基準（S・A の具体値と達成の可否）を添える＝何を詰めれば
## 上がるかを読ませる。敗北にランクは付かないので基準も出さない。撃破はランクに使わないので基準なし。
## 撃破は実際に倒した敵の駒の数＝domain が数えた敵の損失をそのまま出す。
## 生存・撃破は兵器を数えない（doc/gdd/rank.md）＝その2行の見出しに印を付け、脚注で受ける。
func rows(win: bool) -> Array:
	var alive_ally := _state.ally_survivor_count()
	var mark := tr("ui.result.note_mark")
	var turns := "%d / %d" % [_state.turn_number, _state.turn_limit] if _state.turn_limit > 0 else str(_state.turn_number)
	var turn_row := {"label": tr("ui.result.turns"), "value": turns}
	var alive_row := {"label": tr("ui.result.survived") + mark, "value": "%d / %d" % [alive_ally, _start_ally]}
	if win and not _rank_data.is_empty():
		var turn_got := RankEvaluator.turn_rank(_state.turn_number, _rank_data)
		var alive_got := RankEvaluator.survival_rank(alive_ally, _start_ally, _rank_data)
		_fill_goals(turn_row, "ui.result.goal_turn", "turn_s", "turn_a", turn_got)
		_fill_goals(alive_row, "ui.result.goal_alive", "survival_s", "survival_a", alive_got)
	var out := [turn_row, alive_row,
		{"label": tr("ui.result.defeated") + mark, "value": str(_state.losses(1))}]
	if _elapsed > 0:
		out.append(_time_row(win))  # 測れていない回（開始時刻を持たない旧セーブ）は行ごと出さない
	return out

## 所要時間の行。下に自己ベストをぶら下げ、更新した回はチェックを付ける（ランク基準と同じ見せ方）。
## ベストを添えるのは勝った回だけ＝負けた回は記録に触らないので、比べる相手を出さない。
func _time_row(win: bool) -> Dictionary:
	var row := {"label": tr("ui.result.time"), "value": format_duration(_elapsed)}
	if not win or _context == null or not _context.in_campaign():
		return row
	var updated := _best_time <= 0 or _elapsed < _best_time
	row["sub"] = tr("ui.result.best_time") % format_duration(_elapsed if updated else _best_time)
	row["sub_ok"] = updated
	return row

## 所要時間の表記。1時間未満は "12:34"、1時間以上は "1:02:34"、1日以上は "3日 2:15"。
## 中断を挟めば日をまたぐ（閉じていた間も含める）ので、日は捨てずに出す。
func format_duration(seconds: int) -> String:
	var total := maxi(seconds, 0)
	var days := total / 86400
	var hours := (total % 86400) / 3600
	var minutes := (total % 3600) / 60
	if days > 0:
		return tr("ui.result.time_days") % [days, hours, minutes]
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total % 60]
	return "%d:%02d" % [minutes, total % 60]

## 1行ぶんのランク基準を辞書に足す。閾値が 0（＝その軸に基準を置いていないステージ）の段は空欄。
## 達成は「その軸のランクがその段以上か」で見る＝閾値の比べ方を presentation に写さない。
func _fill_goals(row: Dictionary, fmt_key: String, s_key: String, a_key: String, got: String) -> void:
	var s_val := int(_rank_data.get(s_key, 0))
	var a_val := int(_rank_data.get(a_key, 0))
	if s_val > 0:
		row["s"] = tr(fmt_key) % [RankEvaluator.RANK_S, s_val]
		row["s_ok"] = got == RankEvaluator.RANK_S
	if a_val > 0:
		row["a"] = tr(fmt_key) % [RankEvaluator.RANK_A, a_val]
		row["a_ok"] = not RankEvaluator.is_better(RankEvaluator.RANK_A, got)

## 戦果票の見出し＝ステージ名。campaign は冒険譚マニフェスト（CampaignProgress.campaign）＝
## そこに載る翻訳キーを解決する。載っていないステージ（デバッグの直起動など）はステージJSONの
## ファイル名で代用する。
func title(campaign: Dictionary) -> String:
	for s in campaign.get("stages", []):
		if String(s.get("id", "")) == _context.stage_id:
			return tr(String(s.get("title", "")))
	return _context.stage_path.get_file().get_basename()
