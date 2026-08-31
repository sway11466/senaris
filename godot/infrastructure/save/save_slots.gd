extends RefCounted
class_name SaveSlots
## 中断セーブ5枠＋オートセーブ1枠の枠管理。仕様 → doc/tech/gamesystem.md
## 枠ごとに1ファイル（user://save_1.json … save_5.json ／ user://save_auto.json）で、
## 1枠ぶんの読み書き・破損フォールバックは SaveStore に任せる＝ここは枠の集合と並び順だけを持つ。
## オートセーブはゲームだけが書く枠（プレイヤーは読むのみ）。書き分けは呼び出し側（main）の責務で、
## ここは「auto も枠のひとつ」として同じ扱いをする＝一覧に並べる側が分岐を持たずに済む。

const AUTO := "auto"          # オートセーブの枠ID（一覧の先頭）
const MANUAL_COUNT := 5       # 中断セーブの枠数
const DEFAULT_DIR := "user://"
const PREFIX := "save_"

var _dir: String
var _stores := {}  # 枠ID -> SaveStore

func _init(dir: String = DEFAULT_DIR) -> void:
	_dir = dir if dir.ends_with("/") else dir + "/"
	for slot in slot_ids():
		_stores[slot] = SaveStore.new("%s%s%s.json" % [_dir, PREFIX, slot])

## 一覧の並び順に並べた枠ID（オートセーブが先頭・以降は中断セーブの1〜5）。
static func slot_ids() -> Array:
	var ids: Array = [AUTO]
	for i in range(1, MANUAL_COUNT + 1):
		ids.append(str(i))
	return ids

## プレイヤーが保存先に選べる枠（＝中断セーブの5枠。オートセーブは含まない）。
static func manual_slot_ids() -> Array:
	var ids := slot_ids()
	ids.erase(AUTO)
	return ids

static func is_auto(slot: String) -> bool:
	return slot == AUTO

## 有効なセーブが入っている枠か。
func has(slot: String) -> bool:
	var store: SaveStore = _stores.get(slot)
	return store != null and store.has_save()

## どれか1枠でもセーブが在るか（タイトルの「冒険の続き」の可否）。
func has_any() -> bool:
	for slot in slot_ids():
		if has(slot):
			return true
	return false

## 枠を読む。{ "version": int, "meta": Dictionary, "state": Dictionary }。無効/無ければ空 dict。
func load_slot(slot: String) -> Dictionary:
	var store: SaveStore = _stores.get(slot)
	return {} if store == null else store.load()

## 枠へ保存する（上書き）。state_dict は BattleState.to_save_diff の戻り値。
func save_slot(slot: String, state_dict: Dictionary, meta: Dictionary = {}) -> void:
	var store: SaveStore = _stores.get(slot)
	if store == null:
		push_error("SaveSlots: 知らない枠: %s" % slot)
		return
	store.save(state_dict, meta)

## 枠を消す。
func clear_slot(slot: String) -> void:
	var store: SaveStore = _stores.get(slot)
	if store != null:
		store.clear()

## 一覧表示用の全枠。並びは slot_ids（オート→1〜5）。
## [ { "slot": String, "auto": bool, "used": bool, "meta": Dictionary } ]
## 空き枠も used=false で必ず並べる＝枠の数と位置が保存状況で動かない。
func list() -> Array:
	var out: Array = []
	for slot in slot_ids():
		var data := load_slot(slot)
		out.append({
			"slot": slot,
			"auto": is_auto(slot),
			"used": not data.is_empty(),
			"meta": data.get("meta", {}) as Dictionary,
		})
	return out
