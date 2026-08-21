extends SceneTree
## 使い捨て：中断セーブ5枠＋オートセーブの live 配線を実機で確かめる（doc/backlog.md feature-9）。
## 見るもの＝(1) 自ターン開始時にオートセーブが入る (2) 操作の途中でセーブしてもターンの頭が保存される
## (3) 選んだ枠から盤が本当に戻る (4) 枠一覧・確認の見た目。
## 実行: godot --path . -s res://tests/manual/verify_save_slots.gd -- <出力ディレクトリの絶対パス>
## （--headless は付けない＝描画されないと get_texture() が撮れない）

const CAMPAIGN := "debug-ai"
const STAGE_ID := "sight"
const STAGE := "res://data/stages/debug-ai/sight.json"

var _main: Node
var _dir := ""
var _frames := 0
var _unit_id := -1
var _home := Vector2i.ZERO  # 動かす前（＝ターン開始時点）の位置
var _dest := Vector2i.ZERO

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	_main = load("res://presentation/main/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		20:
			_main._title.close()
			_main._select.close()
			_wipe_slots()
			_main._on_stage_chosen(CAMPAIGN, STAGE_ID, STAGE)
		35:
			_skip_talk()
			_check_autosave()
			_move_a_unit()
		45:
			_main._on_save_requested()  # 枠一覧（セーブ）
		52:
			_save_png("slots_save")
			_panel()._on_row_pressed("2", false)  # 空き枠＝確認なしで決まる
			_check_saved_slot()
		60:
			_move_a_unit()  # もう一手動かしてから戻す＝復元が効いたか分かる
			_main._on_load_requested()
		66:
			_save_png("slots_load")
			_panel()._on_row_pressed("2", true)  # 中身が在る＝盤が失われる確認が挟まる
		70:
			_save_png("slots_confirm")
			print("[確認] 確認の小窓が出ている: ", _panel()._confirm.visible)
			_panel()._on_confirm_yes()
		85:
			_check_restored()
			return true
	return false

## 走るたび同じ条件にする＝前回の枠を消してから始める。
func _wipe_slots() -> void:
	for slot in SaveSlots.slot_ids():
		_main._saves.clear_slot(slot)
	print("[準備] 枠を空にした has_any=", _main._saves.has_any())

func _skip_talk() -> void:
	if _main._conversation != null:
		_main._conversation._on_skip()

func _check_autosave() -> void:
	var data: Dictionary = _main._saves.load_slot(SaveSlots.AUTO)
	print("[1] オートセーブ 有=", not data.is_empty(),
		" ターン=", data.get("state", {}).get("turn_number", -1),
		" meta=", data.get("meta", {}))

## 自軍の駒を1つ、行ける先へ実際に動かす（＝ターンの途中の状態を作る）。
func _move_a_unit() -> void:
	var state = _main._controller.state
	for u in state.units():
		if u.team != 0 or state.is_done(u.id):
			continue
		var cells: Array = state.reachable(u.id)
		for c in cells:
			if c != u.pos:
				_unit_id = u.id
				_home = u.pos
				_dest = c
				var ok: bool = _main._controller.execute(MoveCommand.new(u.id, c))
				print("[操作] 駒#", u.id, " ", _home, " → ", c, " 成功=", ok)
				return
	print("[操作] 動かせる駒が無い")

## セーブした枠の中身が「ターンの頭」か（動かす前の位置か）を見る。
func _check_saved_slot() -> void:
	var data: Dictionary = _main._saves.load_slot("2")
	var saved := Vector2i(-99, -99)
	for u in data.get("state", {}).get("units", []):
		if int(u.get("id", -1)) == _unit_id:
			saved = Vector2i(int(u.get("q", 0)), int(u.get("r", 0)))
	print("[2] 枠2に保存 有=", not data.is_empty(),
		" 駒#", _unit_id, " 保存位置=", saved, " ターン開始時=", _home, " 動かした先=", _dest,
		" → ターンの頭が入っている=", saved == _home)

## ロード後の盤が保存時の状態（ターンの頭）に戻っているか。
func _check_restored() -> void:
	var state = _main._controller.state
	var u = state.unit_by_id(_unit_id)
	var pos = u.pos if u != null else Vector2i(-99, -99)
	print("[3] 復元後 駒#", _unit_id, " 位置=", pos, " 期待=", _home, " → 戻った=", pos == _home)
	print("    ターン=", state.turn_number, " 手番=", state.current_team,
		" 行動済み=", state.is_done(_unit_id))

func _panel() -> SaveSlotPanel:
	return _main._slot_panel

func _save_png(name: String) -> void:
	var out := "%s/%s.png" % [_dir, name]
	root.get_texture().get_image().save_png(out)
	print("saved: ", out)
