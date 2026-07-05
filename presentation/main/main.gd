extends Node2D
## Presentation 層のエントリポイント。
## ステージ(data/stages/*.json)を読み込み、進行役(MatchController)と盤(HexBoard)を組む。
## load_stage(path) が本体＝ステージセレクト（presentation/select/）がこれを駆動する（再呼び出しで切替可）。
## 進行管理（解放判定・クリア記録）は application/campaign_progress.gd。仕様 → doc/gdd/stage_select.md
## デバッグ用ステージは data/stages/debug/（campaign.json の debug:true 冒険譚としてセレクトに出る）。

var _skins := {}
var _ai_presets := {}  # AI思考プリセット（data/ai/ai.json）。label -> パラメーター辞書
var _controller: MatchController = null
var _hud: Hud = null
var _current_stage_path := ""
var _progress: CampaignProgress = null
var _select: SelectScreen = null
var _current_campaign_id := ""  # セレクト経由で選んだ現ステージ（勝利時のクリア記録用）
var _current_stage_id := ""

func _ready() -> void:
	print("Senaris booted.")
	_skins = SkinCatalog.load_standard()
	_ai_presets = AiCatalog.load_default()
	# HexBoard と InfoPanel は永続。選択→情報パネルの配線は1回だけ（controller 非依存）。
	$HexBoard.selection_changed.connect($InfoPanel.show_unit)
	$HexBoard.tile_inspected.connect($InfoPanel.show_terrain)  # 空きマス選択→地形/拠点情報
	_install_hud()  # 永続HUD（ターン終了ボタン＋システムメニュー）。load_stage より前に用意
	_progress = CampaignProgress.new(CampaignCatalog.load_all(), ProgressStore.new())
	load_stage("res://data/stages/debug/debug.json")  # セレクトの下敷き（盤を空にしない）。選択で差し替わる
	_install_select()  # 起動直後はセレクトを開く（タイトル画面は未実装＝将来ここに挟む）

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
	# 敵軍(team 1)のAI: 部隊(squad)はステージ定義のラベルで、部隊外はステージ既定ラベルで振る舞う。
	_controller.ai_team = 1
	var brain := NearestAttackerBrain.from_preset(_ai_presets.get(state.enemy_ai, {}))
	brain.presets = _ai_presets  # 部隊のラベル解決用
	_controller.ai_brain = brain
	add_child(_controller)
	$HexBoard.bind(state, _controller, _skins, StageLoader.load_terrain_skins(path))  # 見た目差分(座標→skin)は presentation へ（案P）
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
			if not _current_campaign_id.is_empty():  # セレクト経由のステージだけクリア記録
				_progress.record_clear(_current_campaign_id, _current_stage_id)
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

# --- セレクト画面（presentation/select/）。仕様 → doc/gdd/stage_select.md ---
func _install_select() -> void:
	_select = preload("res://presentation/select/select_screen.gd").new()
	add_child(_select)
	_select.setup(_progress)
	_select.stage_chosen.connect(_on_stage_chosen)
	_hud.stage_select_requested.connect(_select.open)
	_select.open()

func _on_stage_chosen(campaign_id: String, stage_id: String, path: String) -> void:
	_current_campaign_id = campaign_id
	_current_stage_id = stage_id
	load_stage(path)

