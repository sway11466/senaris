extends RefCounted
class_name ChronicleService
## クロニクルの記録 API（application 層）。盤に出た駒（skin_id）と発動した
## 陣形スキル（レシピ id）をメモリに溜め、盤を離れるときにまとめて書く。
## 仕様 → doc/gdd/chronicle.md / doc/tech/gamesystem.md §クロニクル
##
## 入口:
##   begin       — ステージ開始（盤の初期配置を走査して全駒を記録）
##   note_unit   — 駒が盤に現れた（出撃・増援）
##   note_recipe — 陣形スキルが発動した
##   note_story_* — 遊んだ回の顔ぶれ・起きたイベントを足す（StageOutcome から呼ぶ）
##   flush       — 盤を離れる（ファイルに書く）
##
## デバッグ冒険譚や冒険譚の外では記録しない。呼び出し側が campaign_id を空にして渡す
## ＝StageOutcome と同じ規約。

var _store: ChronicleStore
var _campaign_id: String = ""

func _init(store: ChronicleStore) -> void:
	_store = store

## ステージ開始。盤の初期配置を走査して全駒のスキンを記録する。
## 中断セーブから再開した回も盤を渡せば取りこぼさない。
func begin(campaign_id: String, state: BattleState) -> void:
	_campaign_id = campaign_id
	if not _records():
		return
	for u in state.units():
		_note_skin(u)

## 駒が盤に現れた（出撃・増援・敵の拠点配備を含む）。
func note_unit(unit: Unit) -> void:
	if not _records():
		return
	_note_skin(unit)

## 陣形スキルが発動した。
func note_recipe(recipe_id: String) -> void:
	if not _records() or recipe_id.is_empty():
		return
	_store.record_recipe(recipe_id, _campaign_id)

## ステージを始めた＝開始時の在籍 actor を足す。同じ顔ぶれの回は畳まれる。
## 駒・レシピと違い冒険譚とステージを引数で受ける＝StageOutcome と同じ規約で呼ばれるため。
func note_story_start(campaign_id: String, stage_id: String, roster: Array) -> void:
	_store.record_story_roster(campaign_id, stage_id, "start", _actor_names(roster))

## クリアした＝クリア後の在籍 actor を足す。
func note_story_clear(campaign_id: String, stage_id: String, roster: Array) -> void:
	_store.record_story_roster(campaign_id, stage_id, "clear", _actor_names(roster))

## 会話つきイベントが起きた＝そのイベント id を足す。
func note_story_event(campaign_id: String, stage_id: String, event_id: String) -> void:
	_store.record_story_event(campaign_id, stage_id, event_id)

## 盤を離れるとき（決着・中断・タイトルへ戻る）にファイルへ書き出す。
## 変更がなければ何もしない（ChronicleStore が判断する）。
func flush() -> void:
	_store.save()

# ---------------------------------------------------------------------------

## 記録するか。冒険譚の外（空文字）やデバッグ冒険譚は呼び出し側が空を渡す。
func _records() -> bool:
	return not _campaign_id.is_empty()

## ユニットの実効スキン（skin_id → type_id フォールバック）を記録する。
## Formation._matches と同じ照合規約。
func _note_skin(unit: Unit) -> void:
	var sid := unit.skin_id if unit.skin_id != "" else unit.type_id
	_store.record_skin(sid, _campaign_id)

## 名簿（Unit の直列化）から actor の名前だけを取り出す。会話の when が見るのは在籍だけ
## （doc/campaign/authoring.md 会話の分岐）＝素性も損耗も持たない。ProgressStore と同じ規約。
static func _actor_names(units: Array) -> Array:
	var out: Array = []
	for u in units:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var a := String((u as Dictionary).get("actor", ""))
		if a != "" and not out.has(a):
			out.append(a)
	return out
