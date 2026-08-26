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

## 冒険譚を全クリアしたか（カードの「DONE」焼き印・ステージ一覧の扉絵差し替えの条件）。
## デバッグ冒険譚とステージ0本は false＝制覇の概念を持たせない。
func is_all_cleared(campaign_id: String) -> bool:
	var c := campaign(campaign_id)
	if c.is_empty() or c["debug"] or c["stages"].is_empty():
		return false
	return cleared_count(campaign_id) >= c["stages"].size()

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

## locked ステージを押したときに依頼書へ出す解放条件（例「「高所の敵陣」クリアで解放」）。
## 前提ステージ自身が locked なら名前を出さず番号で指す＝一覧で伏せている名前を条件文が漏らさない。
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
				var ref_id := String(cond.get("stage", ""))
				if stage_state(campaign_id, ref_id) == LOCKED:
					var n := _stage_number(c, ref_id)
					# Node 外（RefCounted）なので tr() ではなく TranslationServer で解決する
					if n > 0:
						parts.append(String(TranslationServer.translate("ui.quest.unlock_nth")) % n)
					else:
						parts.append(String(TranslationServer.translate("ui.quest.unlock_other")))
					continue
				var ref := _find_stage(c, ref_id)
				# title は翻訳キー（i18n）。TranslationServer で解決（生テキストは素通し）
				var title := String(TranslationServer.translate(ref.get("title", ref_id)))
				parts.append(String(TranslationServer.translate("ui.quest.unlock_stage")) % title)
			"entitlement":
				parts.append(String(TranslationServer.translate("ui.quest.unlock_dlc")))
			_:
				pass
	return String(TranslationServer.translate("ui.quest.unlock_sep")).join(parts)

## クリアを記録する（勝利時に main が呼ぶ）。デバッグ冒険譚・未知のステージは記録しない。
func record_clear(campaign_id: String, stage_id: String) -> void:
	var c := campaign(campaign_id)
	if c.is_empty() or c["debug"]:
		return
	if _find_stage(c, stage_id).is_empty():
		return
	_store.mark_cleared(campaign_id, stage_id)

## ランクを記録する（勝利時に main が呼ぶ）。ベスト更新は ProgressStore が判定する。
func record_rank(campaign_id: String, stage_id: String, rank: String) -> void:
	if rank.is_empty():
		return
	var c := campaign(campaign_id)
	if c.is_empty() or c["debug"]:
		return
	if _find_stage(c, stage_id).is_empty():
		return
	_store.mark_rank(campaign_id, stage_id, rank)

## そのステージのベストランク（"S"/"A"/"B"）。まだ記録が無ければ空文字。
## セレクトの木札に押す印が引く（記録は record_rank・保存は ProgressStore）。
func best_rank(campaign_id: String, stage_id: String) -> String:
	return _store.best_rank(campaign_id, stage_id)

## マニフェスト順で stage_id の直後のステージを返す（無ければ {}）。クリア後の自動遷移に使う。
## 解放状態は見ない＝呼び出し側が stage_state で判定する（LOCKED なら進まない等）。
func next_stage(campaign_id: String, stage_id: String) -> Dictionary:
	var c := campaign(campaign_id)
	if c.is_empty():
		return {}
	var stages: Array = c["stages"]
	for i in stages.size():
		if stages[i]["id"] == stage_id:
			return stages[i + 1] if i + 1 < stages.size() else {}
	return {}

## クリア後に自動で進める「次ステージ」を返す（無ければ {}）。仕様 → doc/gdd/stage_select.md 戦闘後フロー
## 非デバッグ冒険譚・マニフェスト順で直後・locked でない、をすべて満たすときだけ返す。
## {} は「セレクトへ戻る」の意味＝デバッグ冒険譚・最終ステージ・次が locked・未知の冒険譚で止まる。
func next_playable_stage(campaign_id: String, stage_id: String) -> Dictionary:
	var c := campaign(campaign_id)
	if c.is_empty() or c["debug"]:
		return {}
	var nxt := next_stage(campaign_id, stage_id)
	if nxt.is_empty() or stage_state(campaign_id, String(nxt["id"])) == LOCKED:
		return {}
	return nxt

## ステージ一覧での通し番号（1始まり・見つからなければ 0）。ステージ名を伏せたまま指すのに使う。
func _stage_number(c: Dictionary, stage_id: String) -> int:
	if c.is_empty():
		return 0
	for i in c["stages"].size():
		if c["stages"][i]["id"] == stage_id:
			return i + 1
	return 0

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
