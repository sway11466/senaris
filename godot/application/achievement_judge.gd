extends RefCounted
class_name AchievementJudge
## 冒険譚の実績（踏破・全ステージ A 以上・全ステージ S）を進捗から判定して解除する。
## 条件は進捗（クリアとベストランク）だけを見る＝解除済みかは覚えず、満たす段を毎回 unlock する
## （unlock は何度呼んでもよい）。仕様 → doc/tech/platform.md 実績の中身

var _progress: CampaignProgress
var _vault: AchievementVault

func _init(progress: CampaignProgress, vault: AchievementVault) -> void:
	_progress = progress
	_vault = vault

## その冒険譚を判定し直す。ステージをクリアして進捗を書いたあとに呼ぶ。
## 段ごとに独立して見る＝S を満たせば A 以上も踏破も満たすので、下の段も同時に立つ。
func judge(campaign_id: String) -> void:
	var c := _progress.campaign(campaign_id)
	if c.is_empty() or c["debug"] or String(c.get("achievement", "")).is_empty():
		return
	if not _progress.is_all_cleared(campaign_id):
		return
	var key := String(c.get("achievement", ""))
	_vault.unlock(key + "_CLEAR")
	if _all_ranks(c, ["S", "A"]):
		_vault.unlock(key + "_RANK_A")
	if _all_ranks(c, ["S"]):
		_vault.unlock(key + "_RANK_S")

## 全冒険譚を判定し直す。起動時に呼ぶ＝実績の仕組みより前に進めた進捗も拾う。
func judge_all() -> void:
	for c in _progress.campaigns(false):
		judge(String(c["id"]))

## 全ステージのベストランクが accepted のどれかか。
func _all_ranks(c: Dictionary, accepted: Array) -> bool:
	for s in c["stages"]:
		if not accepted.has(_progress.best_rank(String(c["id"]), String(s["id"]))):
			return false
	return true
