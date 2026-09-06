extends RefCounted
class_name SaveCoordinator
## 中断セーブ／オートセーブの段取り（presentation/main）。自ターン開始時点の盤を控え、枠一覧
## （SaveSlotPanel）を開き、選ばれた枠へ書く／枠から盤を組み立てる。仕様 → doc/tech/gamesystem.md
## 盤に据える・タイトルを畳む・HUD と情報板への知らせは main＝ここはシグナルで返すだけ。

## 枠へ書いた（オートセーブも）。slot＝書いた枠（SaveSlots.AUTO ならオートセーブ）。
signal saved(slot: String)
## 枠から盤を組み立てた。据えるのは main（_install_state）。meta＝セーブに添えた文脈（冒険譚・ステージ・開始時刻）。
signal restored(state: BattleState, path: String, meta: Dictionary)

var _saves: SaveSlots = null  # 中断セーブ5枠＋オートセーブ1枠。user://save_1.json … save_auto.json
var _slot_panel: SaveSlotPanel = null  # 枠一覧（セーブ/ロード共通・盤とタイトルの両方から出す）
var _slot_intent := ""  # 枠一覧をどちらの用で開いたか（"save"/"load"）＝選ばれた枠の使い道
## 自ターン開始時点の盤の動的差分（BattleState.to_save_diff）。中断セーブ・オートセーブはこれを書く
## ＝操作の途中でセーブしてもターンの頭に戻る（実質的なアンドゥ）。
var _turn_snapshot := {}
var _context: StageContext = null  # 控えた盤の文脈（meta の材料）
var _campaign := {}  # 控えた盤の冒険譚マニフェスト（冒険譚名・ステージ名の翻訳キー）

func _init() -> void:
	_saves = SaveSlots.new()

## セーブが1枠でも在るか（HUD のロード・タイトルの「冒険の続き」の有効化）。
func has_any() -> bool:
	return _saves.has_any()

## 枠一覧のパネルを作って返す。ツリーへ足すのは呼ぶ側（main）。
func install_slot_panel() -> SaveSlotPanel:
	_slot_panel = SaveSlotPanel.new()
	_slot_panel.name = "SaveSlotPanel"
	_slot_panel.slot_chosen.connect(_on_slot_chosen)
	return _slot_panel

func refresh_labels() -> void:
	_slot_panel.refresh_labels()

## 自ターン開始時点の盤を控える（＝セーブが書く中身）。同じ瞬間にオートセーブも上書きする。
## 状態が真実なのでターン・位置・損耗・行動フラグごと再現できる（BattleState.to_dict）。
## 冒険譚の外（セレクトの下敷き）ではオートセーブを書かない＝一覧に行き先の無い盤を並べない。
func snapshot(state: BattleState, context: StageContext, campaign: Dictionary) -> void:
	_turn_snapshot = state.to_save_diff()
	_context = context
	_campaign = campaign
	if not context.in_campaign():
		return
	_saves.save_slot(SaveSlots.AUTO, _turn_snapshot, _snapshot_meta())
	saved.emit(SaveSlots.AUTO)

## セーブに添える文脈メタ（一覧の表示材料＋再開に要るステージパス）。
## 冒険譚名・ステージ名は翻訳キーのまま持つ＝言語を変えても一覧がその言語で出る。
func _snapshot_meta() -> Dictionary:
	var stage_title := ""
	for s in _campaign.get("stages", []):
		if String(s.get("id", "")) == _context.stage_id:
			stage_title = String(s.get("title", ""))
			break
	return {
		"campaign_id": _context.campaign_id, "stage_id": _context.stage_id,
		"stage_path": _context.stage_path,
		"stage_digest": _context.stage_digest,  # ステージ定義の印（更新検出 → doc/tech/gamesystem.md）
		"campaign_title": String(_campaign.get("title", "")), "stage_title": stage_title,
		"turn_number": int(_turn_snapshot.get("turn_number", 0)),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"started_at": _context.started_at,  # ステージを始めた実時刻＝再開しても所要時間が続く
	}

## システムメニュー「セーブ」＝保存先の枠を選ばせる（書くのは _write_slot）。
func open_save() -> void:
	if _turn_snapshot.is_empty():
		return
	_slot_intent = "save"
	_slot_panel.open_save(_saves)

## 読み出す枠を選ばせる。heading＝一覧の見出し（訳した文言）。warn_board＝盤が出ているので
## 失われる旨の確認を挟む（タイトルからは盤がまだ無い＝挟まない）。
func open_load(heading: String, warn_board: bool) -> void:
	if not _saves.has_any():
		return
	_slot_intent = "load"
	_slot_panel.open_load(_saves, heading, warn_board)

func _on_slot_chosen(slot: String) -> void:
	if _slot_intent == "save":
		_write_slot(slot)
	else:
		_load_slot(slot)

## 選ばれた枠へ書く。中身は自ターン開始時点のスナップショット（操作の途中でも頭に戻る）。
func _write_slot(slot: String) -> void:
	_saves.save_slot(slot, _turn_snapshot, _snapshot_meta())
	saved.emit(slot)

## 選ばれた枠から盤を組み立てる：ステージJSONで盤を組み直し、セーブの動的差分を被せる。
## 旧版のセーブはここで現行版へ変換してから使う（版と移行 → doc/tech/gamesystem.md）。
## 据える（intro は流さない）のは main＝restored で返す。
func _load_slot(slot: String) -> void:
	var data := _saves.load_slot(slot)
	if data.is_empty():
		return
	data = SaveMigration.migrate(data)
	if data.is_empty():
		return  # 変換を持たない版（SaveFile が弾くのでここには来ないはず）
	var meta: Dictionary = data.get("meta", {})
	var path := String(meta.get("stage_path", ""))
	var state := SaveRestore.restore(path, data["state"])
	if state == null:
		return  # ステージJSONが無い/読めない＝復元できない（エラーは SaveRestore が出す）
	restored.emit(state, path, meta)
