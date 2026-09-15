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
