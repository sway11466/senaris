extends RefCounted
class_name StageOutcome
## 決着時の記録（application 層）。presentation が ProgressStore / RosterStore を直接
## 書き換えないための門番。3つの入口で受け、進捗・名簿・経験した会話を正しい順序で書く。
## 経験した会話は2か所に書く＝進捗は最後に遊んだ回（上書き）、クロニクルは遊んだ回を足す
## （doc/gdd/chronicle.md 分岐の切り替え）。
## 冒険譚の外（デバッグ・直接起動）なら書かない。
## 仕様 → doc/tech/gamesystem.md / doc/gdd/rank.md / doc/gdd/campaigns.md
##
## 入口:
##   stage_started   — ステージを始めた（開始時の在籍 actor を記録）
##   event_fired     — 会話つきイベントが起きた（イベント id を記録）
##   battle_finished — 決着した（クリア・ランク・所要時間・名簿・経験した会話を記録）

var _progress: CampaignProgress
var _roster_store: RosterStore
var _chronicle: ChronicleService

func _init(progress: CampaignProgress, roster_store: RosterStore,
		chronicle: ChronicleService) -> void:
	_progress = progress
	_roster_store = roster_store
	_chronicle = chronicle

## ステージ開始＝開始時の在籍 actor を記録する。
func stage_started(campaign_id: String, stage_id: String, roster: Array) -> void:
	if not _records(campaign_id, stage_id):
		return
	_progress.record_story_start(campaign_id, stage_id, roster)
	_chronicle.note_story_start(campaign_id, stage_id, roster)

## イベント発生＝イベント id を記録する。
func event_fired(campaign_id: String, stage_id: String, event_id: String) -> void:
	if event_id.is_empty() or not _records(campaign_id, stage_id):
		return
	_progress.record_story_event(campaign_id, stage_id, event_id)
	_chronicle.note_story_event(campaign_id, stage_id, event_id)

## 決着。記録して結果を返す。
## 返り値の辞書:
##   rank:           String — 評価ランク（勝利でランクを持つステージだけ。ほかは空文字）
##   elapsed:        int    — 決着までの所要秒（0＝測れていない）
##   best_time:      int    — この回を記録する前の自己ベスト（0＝記録なし）
##   updated_roster: Array  — 更新後の名簿（名簿を更新しなかった回は空配列）
## previous_roster＝開始時の名簿（引き継ぎ元のステージの控え）。名簿は冒険譚ID×ステージIDの控えで、
## クリアしたステージの控えとして書く＝前のステージをやり直しても先の控えは変わらない（doc/gdd/campaigns.md 名簿）。
func battle_finished(campaign_id: String, stage_id: String, outcome: int,
		state: BattleState, started_at: int, stage_path: String,
		previous_roster: Array) -> Dictionary:
	var elapsed := _compute_elapsed(started_at)
	var rank := _compute_rank(outcome, state, stage_path)
	var in_campaign := _records(campaign_id, stage_id)
	var best_time := _progress.best_time(campaign_id, stage_id) if in_campaign else 0
	var updated_roster: Array = []

	if outcome == BattleState.PLAYER_WIN and in_campaign:
		# 書く順序は旧 main.gd と同一。崩すと名簿の前にクリア記録が無い、等が起きる。
		# ①クリア → ②ランク → ③所要時間 → ④名簿更新 → ⑤経験した会話(clear)
		_progress.record_clear(campaign_id, stage_id)                           # ①
		if not rank.is_empty():
			_progress.record_rank(campaign_id, stage_id, rank)                  # ②
		_progress.record_time(campaign_id, stage_id, elapsed)                   # ③
		if _roster_store != null and state != null:                              # ④
			updated_roster = RosterService.update_after_clear(previous_roster, state)
			_roster_store.save_roster(campaign_id, stage_id, updated_roster)
		# 経験した会話の clear＝名簿の保存より後。この回で仲間になった駒を含む顔ぶれ。
		var clear_roster := _roster_store.load_roster(campaign_id, stage_id) \
				if _roster_store != null else []
		_progress.record_story_clear(campaign_id, stage_id, clear_roster)       # ⑤
		_chronicle.note_story_clear(campaign_id, stage_id, clear_roster)

	return {
		"rank": rank,
		"elapsed": elapsed,
		"best_time": best_time,
		"updated_roster": updated_roster,
	}

# ---------------------------------------------------------------------------

## 記録を残す冒険譚・ステージか。空文字＝冒険譚の外（デバッグの直起動・下敷き）。
## CampaignProgress 側にもデバッグ冒険譚・未知ステージの弾きがあるので二重ガード。
func _records(campaign_id: String, stage_id: String) -> bool:
	return not campaign_id.is_empty() and not stage_id.is_empty()

## 決着までの所要秒。0＝測れていない（開始時刻を持たない旧セーブから再開した回）。
## 時計が巻き戻ったとき（システム時刻の変更）も 0 に倒す。
static func _compute_elapsed(started_at: int) -> int:
	if started_at <= 0:
		return 0
	return maxi(int(Time.get_unix_time_from_system()) - started_at, 0)

## 評価ランクを算出する（勝利時）。ランクを持たないステージは空文字。
static func _compute_rank(outcome: int, state: BattleState, stage_path: String) -> String:
	if outcome != BattleState.PLAYER_WIN or state == null:
		return ""
	var rank_data := StageLoader.load_rank(stage_path)
	if rank_data.is_empty():
		return ""
	var start_ally := StageLoader.count_start_allies_at(stage_path, state)
	return RankEvaluator.evaluate(
			state.turn_number, state.ally_survivor_count(), start_ally, rank_data)
