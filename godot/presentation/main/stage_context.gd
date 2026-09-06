extends RefCounted
class_name StageContext
## いま挑んでいるステージの文脈（presentation/main）。main が1つ持ち、戦果（StageTally）・
## 中断セーブ（SaveCoordinator）・会話（StoryDirector）へ渡す＝5つの値を別々に配らない。
## 冒険譚の外（デバッグの直起動・セレクトの下敷き）では campaign_id が空。

var campaign_id := ""  # セレクト経由で選んだ冒険譚（クリア記録・carryover のキー）。空＝冒険譚の外
var stage_id := ""  # 同じくステージ（冒険譚マニフェストの id）
var stage_path := ""  # ステージJSONのパス（リスタート・セーブの meta）
var stage_digest := ""  # ステージ定義の印（StageDigest）。セーブの meta に載せて更新検出に使う
## ステージを始めた実時刻（Unix秒）。中断セーブに持ち越し、閉じていた間も所要時間に含める。
## 0＝不明（開始時刻を持たない旧セーブから再開した回）。
var started_at := 0

## 冒険譚の中のステージか（クリア記録・オートセーブ・会話の記録はこのときだけ）。
func in_campaign() -> bool:
	return not campaign_id.is_empty()
