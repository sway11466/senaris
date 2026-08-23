extends RefCounted
class_name BgmDirector
## いま鳴るべきトラックIDの決定（場面→曲）。application層＝純ロジック（実際の再生は presentation/ui/bgm_player.gd）。
## 詳細 → doc/audio/bgm.md, doc/tech/architecture.md
##
## BGM はステージ単位で流す＝戦闘ごとに曲を切り替えない（攻撃・着弾は SFX と戦闘演出で示す）。
## スロット制：いまは main（必須）だけ。将来 intro 等が要るならスロット追加で対応。
## フォールバック連鎖：ステージの bgm → 全体既定。曲はステージJSONに1ステージずつ書く。

const TITLE_TRACK := "title"             ## タイトル画面。曲ではなく酒場のざわめき（外部素材）
const MENU_TRACK := "menu"               ## セレクト画面（酒場の依頼ボード）。ステージ外の唯一の場面
const DEFAULT_STAGE_TRACK := "map_calm"  ## 全体既定＝ステージにも冒険譚にも指定が無いとき
const AFTERGLOW_TRACK := "afterglow"     ## 勝利スティンガーの後に続ける曲（outro 会話を読む間の下敷き）

var _main := ""

## ステージ開始：スロットを張り替える。
## stage_bgm は BgmCatalog.parse_slots の結果（空可）。
func begin_stage(stage_bgm: Dictionary) -> void:
	_main = _pick("main", stage_bgm, DEFAULT_STAGE_TRACK)

## いま鳴るべきトラックID。曲が未配置でもここでは判定しない（鳴らす側が無音＋ログにする）。
func track_id() -> String:
	return _main

## スロット1つを解決：ステージ → 既定。
static func _pick(slot: String, stage_bgm: Dictionary, fallback: String) -> String:
	var v: Variant = stage_bgm.get(slot, "")
	if typeof(v) == TYPE_STRING and not String(v).is_empty():
		return String(v)
	return fallback
