extends RefCounted
class_name BgmDirector
## いま鳴るべきトラックIDの決定（場面→曲）。application層＝純ロジック（実際の再生は presentation/ui/bgm_player.gd）。
## 詳細 → doc/audio/bgm.md, doc/tech/architecture.md
##
## BGM はステージ単位で流す＝戦闘ごとに曲を切り替えない（攻撃・着弾は SFX と戦闘演出で示す）。
## スロット制：main（必須）＋ crisis（任意＝状態切替用。未指定なら切替要求が来ても曲は変わらない）。
## フォールバック連鎖：ステージの bgm → campaign.json の既定 → 全体既定（全ステージに書かなくて済む）。
## crisis は一度立てたら戻さない（曲がパタパタ切り替わる事故を防ぐ）。ステージ開始でリセット。

const MENU_TRACK := "menu"               ## セレクト画面（酒場の依頼ボード）。ステージ外の唯一の場面
const DEFAULT_STAGE_TRACK := "map_calm"  ## 全体既定＝ステージにも冒険譚にも指定が無いとき

var _main := ""
var _crisis := ""
var _in_crisis := false

## ステージ開始：スロットを張り替えて crisis をリセットする。
## stage_bgm / campaign_bgm はどちらも BgmCatalog.parse_slots の結果（空可）。
func begin_stage(stage_bgm: Dictionary, campaign_bgm: Dictionary = {}) -> void:
	_main = _pick("main", stage_bgm, campaign_bgm, DEFAULT_STAGE_TRACK)
	_crisis = _pick("crisis", stage_bgm, campaign_bgm, "")
	_in_crisis = false

## 危機BGMへ切り替える（永続＝一度立てたら戻さない）。crisis スロットが空なら何も起きない。
## 引き金は domain 側の「盤面が変わる級」のイベント（必殺技・ボス出現など）を application が受けて呼ぶ。
func enter_crisis() -> void:
	if not _crisis.is_empty():
		_in_crisis = true

func in_crisis() -> bool:
	return _in_crisis

## いま鳴るべきトラックID。曲が未配置でもここでは判定しない（鳴らす側が無音＋ログにする）。
func track_id() -> String:
	return _crisis if _in_crisis else _main

## スロット1つをフォールバック連鎖で解決：ステージ → 冒険譚 → 既定。
static func _pick(slot: String, stage_bgm: Dictionary, campaign_bgm: Dictionary, fallback: String) -> String:
	var v: Variant = stage_bgm.get(slot, "")
	if typeof(v) == TYPE_STRING and not String(v).is_empty():
		return String(v)
	v = campaign_bgm.get(slot, "")
	if typeof(v) == TYPE_STRING and not String(v).is_empty():
		return String(v)
	return fallback
