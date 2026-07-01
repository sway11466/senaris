extends Node2D
## Presentation 層のエントリポイント。
## ステージ(data/stages/*.json)を読み込み、進行役(MatchController)と盤(HexBoard)を組む。
## load_stage(path) が本体＝将来は冒険譚の進行管理がこれを駆動する（再呼び出しで切替可）。
## ステージ選択UIは presentation/dev/（デモ用・後で破棄可）。

var _skins := {}
var _controller: MatchController = null
var _hud: Hud = null
var _current_stage_path := ""

func _ready() -> void:
	print("Senaris booted.")
	_skins = SkinCatalog.load_standard()
	# HexBoard と InfoPanel は永続。選択→情報パネルの配線は1回だけ（controller 非依存）。
	$HexBoard.selection_changed.connect($InfoPanel.show_unit)
	_install_hud()  # 永続HUD（ターン終了ボタン＋システムメニュー）。load_stage より前に用意
	load_stage("res://data/stages/demo/demo.json")
	_install_dev_stage_selector()  # DEV: デモ用。製品化時はこの行と presentation/dev/ を削除

## ステージ(JSON)を読み込み、マッチ（最小AI込み）を組み直す。再呼び出しで切替できる。
func load_stage(path: String) -> void:
	var state := StageLoader.load_file(path)
	if state == null:
		push_error("main: ステージを読めない: %s" % path)
		return
	_current_stage_path = path  # システムメニューのリスタート用
	if _controller != null:
		_controller.free()  # 旧マッチを破棄（旧 controller のシグナル接続も消える）
		_controller = null
	_controller = MatchController.new()
	_controller.name = "MatchController"
	_controller.setup(state)
	# 敵軍(team 1)を最小AIに任せる。ステージ仕様が決まれば brain を差し替える。
	_controller.ai_team = 1
	_controller.ai_brain = NearestAttackerBrain.new()
	add_child(_controller)
	$HexBoard.bind(state, _controller, _skins)
	$InfoPanel.bind(state, _skins)
	# controller は作り直すので、controller 由来のシグナルは load ごとに繋ぐ。
	_controller.combat_resolved.connect($InfoPanel.show_combat)
	_controller.turn_changed.connect(_on_turn_changed)
	_controller.battle_finished.connect(_on_battle_finished)
	_update_turn_label(state.current_team, state.turn_number)
	_hud.set_player_turn(state.current_team == 0)  # ターン終了ボタンの有効/無効

func _on_turn_changed(team: int, turn_number: int) -> void:
	_update_turn_label(team, turn_number)
	_hud.set_player_turn(team == 0)

func _update_turn_label(team: int, turn_number: int) -> void:
	var who := "自軍" if team == 0 else "敵軍"
	$Title.text = "Senaris — Turn %d / %s（Enter=手番終了 / 2本指スクロール or 空き地ドラッグ=移動 ピンチ=ズーム F=全体）" % [turn_number, who]

func _on_battle_finished(outcome: int) -> void:
	var text := "決着"
	match outcome:
		BattleState.PLAYER_WIN:
			text = "自軍の勝利！"
		BattleState.PLAYER_LOSS:
			text = "自軍の敗北…"
	$Title.text = "Senaris — %s" % text
	_hud.set_player_turn(false)  # 決着後はターン終了を無効化

# --- 永続HUD（ターン終了ボタン＋システムメニュー）。presentation/ui/hud.gd ---
func _install_hud() -> void:
	_hud = preload("res://presentation/ui/hud.gd").new()
	add_child(_hud)
	_hud.end_turn_requested.connect(_on_end_turn_requested)
	_hud.restart_requested.connect(_on_restart_requested)
	$HexBoard.system_menu_requested.connect(_hud.open_system_menu)

func _on_end_turn_requested() -> void:
	if _controller != null:
		_controller.end_turn()

func _on_restart_requested() -> void:
	if not _current_stage_path.is_empty():
		load_stage(_current_stage_path)

# --- DEV: デモ用ステージセレクタ（presentation/dev/）。製品ではこの関数ごと削除する。---
func _install_dev_stage_selector() -> void:
	var selector = preload("res://presentation/dev/stage_selector.gd").new()
	add_child(selector)
	selector.setup(_scan_stages())
	selector.stage_selected.connect(load_stage)

## data/stages/<冒険譚>/<ステージ>.json を走査して [{label, path}] を返す（デモ用）。
func _scan_stages() -> Array:
	var out: Array = []
	var root := "res://data/stages"
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for campaign in dir.get_directories():
		var sub := DirAccess.open("%s/%s" % [root, campaign])
		if sub == null:
			continue
		for f in sub.get_files():
			if f.ends_with(".json"):
				var path := "%s/%s/%s" % [root, campaign, f]
				out.append({ "label": _stage_label(path, campaign, f), "path": path })
	return out

## ボタン表示名: ステージJSONの "name" を使う（無ければ <冒険譚>-<ファイル名>）。
func _stage_label(path: String, campaign: String, filename: String) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY and data.has("name"):
		return String(data["name"])
	return "%s-%s" % [campaign, filename.get_basename()]
