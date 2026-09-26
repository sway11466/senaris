extends RefCounted
class_name StageStats
## チュートリアルの離脱を測る Stats（ステージを始めた回数・クリアした回数）を刻む。
## ID は <実績キー>_ST<n>_START / _CLEAR（n はマニフェストでの並び・1始まり）。
## 対象はチュートリアル（board＝tutorial）で実績キーを持つ冒険譚だけ。仕様 → doc/tech/platform.md Stats の中身

const BOARD := "tutorial"

var _progress: CampaignProgress
var _sink: StatsSink

func _init(progress: CampaignProgress, sink: StatsSink) -> void:
	_progress = progress
	_sink = sink

## ステージを新しく始めた。中断セーブからの再開では呼ばない＝同じ挑戦を2回数えない。
func started(campaign_id: String, stage_id: String) -> void:
	var prefix := _prefix(campaign_id, stage_id)
	if not prefix.is_empty():
		_sink.add(prefix + "_START")

## ステージをクリアした。
func cleared(campaign_id: String, stage_id: String) -> void:
	var prefix := _prefix(campaign_id, stage_id)
	if not prefix.is_empty():
		_sink.add(prefix + "_CLEAR")

## "<キー>_ST<n>"。数えない冒険譚・ステージは空文字。
func _prefix(campaign_id: String, stage_id: String) -> String:
	var c := _progress.campaign(campaign_id)
	if c.is_empty() or c["debug"] or c.get("board", "") != BOARD or String(c.get("achievement", "")).is_empty():
		return ""
	for i in c["stages"].size():
		if c["stages"][i]["id"] == stage_id:
			return "%s_ST%d" % [c["achievement"], i + 1]
	return ""
