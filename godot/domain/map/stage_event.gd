extends RefCounted
class_name StageEvent
## ステージの途中で起きること（純データ・Node非依存）＝増援（開始時に盤に無い駒が加わる）と会話。
## StageLoader がステージJSONから組み、BattleState が未発生の控えとして持ち、引き金が成立したら
## 駒を盤に出して控えから外す。詳細 → doc/gdd/map.md イベント

## 引き金。TURN＝発生ターンが来た（自分の陣営の手番の頭）／CAPTURE＝拠点の所属が変わった。
enum Trigger { TURN, CAPTURE }

## ステージJSONの "on" と1対1。省略（""）＝ターン。
const TRIGGER_IDS := { "": Trigger.TURN, "capture": Trigger.CAPTURE }

var id: String                     ## ステージ内で一意（発火済みの記録＝中断セーブが持つ）
var turn: int = 1                  ## 発生ターン（TURN のとき。過ぎていても取りこぼさない）
var team: int                      ## 起こす陣営（TURN＝その陣営の手番で起きる／CAPTURE＝その陣営が取ったとき）
var trigger: Trigger = Trigger.TURN
var hex := Vector2i.MAX            ## CAPTURE のとき対象の拠点
var once: String = ""              ## 排他の名前。同じ名前の未発生イベントは、どれか1つが起きたら残りを捨てる
var label: String = ""             ## 残りターン板の予告（翻訳キー）。空＝予告しない
var squad_index := -1              ## 敵の増援が属する部隊（BattleState.squads の index）。-1＝部隊なし
var dialogue: String = ""          ## 台本キー。空＝会話なし
var focus := false                 ## 起きたときカメラを寄せるか
var units: Array[EventUnit] = []   ## 出す駒（搭乗を含む）。空＝会話だけ
var placed: Array[Vector2i] = []   ## 実際に駒が出た hex（発火時に BattleState が控える。ずれて出ても本当の場所）

## 引き金が拠点の占領か。
func is_capture() -> bool:
	return trigger == Trigger.CAPTURE

## 引き金の JSON 表記（"" / "capture"）。上へ渡す素データと、旧セーブとの突き合わせが読む。
func trigger_id() -> String:
	return String(TRIGGER_IDS.find_key(trigger))
