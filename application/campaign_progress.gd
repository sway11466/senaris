extends RefCounted
class_name CampaignProgress
## ステージセレクトの進行管理＝解放判定サービス。仕様 → doc/gdd/stage_select.md
## 冒険譚マニフェスト(CampaignCatalog)＋クリア記録(ProgressStore)から
## locked / unlocked / cleared を毎回導出する（状態そのものは保存しない）。

const LOCKED := "locked"
const UNLOCKED := "unlocked"
const CLEARED := "cleared"

var _campaigns: Array  # CampaignCatalog.load_all() の結果
var _store: ProgressStore

func _init(campaigns: Array, store: ProgressStore) -> void:
	_campaigns = campaigns
	_store = store

## 冒険譚リスト。include_debug=false でデバッグ冒険譚(debug:true)を除く。
func campaigns(include_debug: bool) -> Array:
	var out: Array = []
	for c in _campaigns:
		if c["debug"] and not include_debug:
			continue
		out.append(c)
	return out

func campaign(campaign_id: String) -> Dictionary:
	for c in _campaigns:
		if c["id"] == campaign_id:
			return c
	return {}

## 冒険譚のクリア済みステージ数（冒険譚カードの進捗「n / m」用）。
## マニフェストに載っているステージだけ数える＝消えたステージの記録は数えない。
func cleared_count(campaign_id: String) -> int:
	var c := campaign(campaign_id)
	if c.is_empty() or c["debug"]:
		return 0
	var n := 0
	for s in c["stages"]:
		if _store.is_cleared(campaign_id, s["id"]):
			n += 1
	return n

## ステージの状態（locked / unlocked / cleared）を導出する。
## デバッグ冒険譚は常時 unlocked（クリア記録も付けない）。
func stage_state(campaign_id: String, stage_id: String) -> String:
	var c := campaign(campaign_id)
	if c.is_empty():
		return LOCKED
	if c["debug"]:
		return UNLOCKED
	if _store.is_cleared(campaign_id, stage_id):
		return CLEARED
	var stage := _find_stage(c, stage_id)
	if stage.is_empty():
		return LOCKED
	for cond in stage["unlock"]:  # AND評価＝すべて満たして解放（勝敗条件のORと逆）
		if not _is_satisfied(campaign_id, cond):
			return LOCKED
	return UNLOCKED

## locked カードに出す解放条件の説明文（例「「高所の敵陣」クリアで解放」）。
func unlock_text(campaign_id: String, stage_id: String) -> String:
	var c := campaign(campaign_id)
	var stage := _find_stage(c, stage_id)
	if stage.is_empty():
		return ""
	var parts: Array[String] = []
	for cond in stage["unlock"]:
		if typeof(cond) != TYPE_DICTIONARY:
			continue
		match String(cond.get("type", "")):
			"cleared":
				var ref := _find_stage(c, String(cond.get("stage", "")))
				var title: String = ref.get("title", String(cond.get("stage", "")))
				parts.append("「%s」クリアで解放" % title)
			"entitlement":
				parts.append("追加コンテンツ")
			_:
				pass
	return "・".join(parts)

## クリアを記録する（勝利時に main が呼ぶ）。デバッグ冒険譚・未知のステージは記録しない。
func record_clear(campaign_id: String, stage_id: String) -> void:
	var c := campaign(campaign_id)
	if c.is_empty() or c["debug"]:
		return
	if _find_stage(c, stage_id).is_empty():
		return
	_store.mark_cleared(campaign_id, stage_id)

func _find_stage(c: Dictionary, stage_id: String) -> Dictionary:
	if c.is_empty():
		return {}
	for s in c["stages"]:
		if s["id"] == stage_id:
			return s
	return {}

## 解放条件1つの充足判定。未知の type（entitlement 含む・未実装）は未充足＝locked 側に倒す。
func _is_satisfied(campaign_id: String, cond: Variant) -> bool:
	if typeof(cond) != TYPE_DICTIONARY:
		return false
	match String(cond.get("type", "")):
		"cleared":
			return _store.is_cleared(campaign_id, String(cond.get("stage", "")))
		_:
			return false
