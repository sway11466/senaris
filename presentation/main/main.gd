extends Node2D
## Presentation 層のエントリポイント。
## ステージ(data/stages/*.json)を読み込み、進行役(MatchController)と盤(HexBoard)を組む。
## load_stage(path) が本体＝ステージセレクト（presentation/select/）がこれを駆動する（再呼び出しで切替可）。
## 進行管理（解放判定・クリア記録）は application/campaign_progress.gd。仕様 → doc/gdd/stage_select.md
## デバッグ用ステージは data/stages/debug-*/（機能別の debug:true 冒険譚としてセレクトに出る）。一覧 → doc/tech/debug-stages.md

var _skins := {}
var _ai_presets := {}  # AI思考プリセット（data/ai/ai.json）。label -> パラメーター辞書
var _controller: MatchController = null
var _hud: Hud = null
var _current_stage_path := ""
var _progress: CampaignProgress = null
var _roster_store: RosterStore = null  # 戦力継承(carryover)のスナップショット永続化。冒険譚IDで引く
var _save_store: SaveStore = null  # 中断セーブ（盤の状態まるごと・1枠）。user://save.json
var _select: SelectScreen = null
var _current_campaign_id := ""  # セレクト経由で選んだ現ステージ（勝利時のクリア記録・carryover のキー用）
var _current_stage_id := ""
var _conversation: ConversationPanel = null
var _scrim: ColorRect = null  # 会話中に盤を沈める暗幕（会話パネルより後ろ・盤より前）
var _scrim_tween: Tween = null  # 進行中のフェード。次のフェード開始時に kill する（off の hide が on を消す競合対策）
var _combat_scene: CombatScene = null  # 戦闘演出オーバーレイ（永続・combat_resolved を受ける）
var _victory_screen: VictoryScreen = null  # キャンペーン完走の勝利イラスト（永続・最終勝利で play）
var _bgm: BgmPlayer = null  # BGM の再生（永続・クロスフェード）。曲の決定は _bgm_director
var _bgm_director: BgmDirector = null  # 場面→曲の決定（application）。ステージ/冒険譚/既定のフォールバック連鎖
var _dialogue := { "intro": [], "outro": [] }  # 現ステージの会話（presentation専用・案P）
var _conversation_phase := ""  # "intro"/"outro"/""＝いま流している会話フェーズ

func _ready() -> void:
	print("Senaris booted.")
	_skins = SkinCatalog.load_standard()
	_ai_presets = AiCatalog.load_default()
	# HexBoard と InfoPanel は永続。選択→情報パネルの配線は1回だけ（controller 非依存）。
	$HexBoard.selection_changed.connect($InfoPanel.show_unit)
	$HexBoard.tile_inspected.connect($InfoPanel.show_terrain)  # 空きマス選択→地形/拠点情報
	_combat_scene = CombatScene.new()  # 戦闘演出オーバーレイ（永続）。load_stage で controller に結線
	_combat_scene.bind(_skins)
	add_child(_combat_scene)
	_victory_screen = VictoryScreen.new()  # キャンペーン完走の勝利イラスト（永続）
	add_child(_victory_screen)
	_install_bgm()  # 永続BGM。load_stage が曲を張り替えるので、それより前に用意
	_install_hud()  # 永続HUD（ターン終了ボタン＋システムメニュー）。load_stage より前に用意
	_install_conversation()  # 永続の会話パネル（右エリア）。load_stage の intro より前に用意
	_progress = CampaignProgress.new(CampaignCatalog.load_all(), ProgressStore.new())
	_roster_store = RosterStore.new()  # carryover の戦力スナップショット（user://roster.json）
	_save_store = SaveStore.new()  # 中断セーブ（user://save.json）
	_hud.set_load_available(_save_store.has_save())  # 起動時に中断セーブが在ればロードを有効化
	load_stage("res://data/stages/_boot/underlay.json")  # セレクトの下敷き（盤を空にしない）。選択で差し替わる
	_install_select()  # 起動直後はセレクトを開く（タイトル画面は未実装＝将来ここに挟む）

## ステージ(JSON)を読み込み、マッチ（最小AI込み）を組み直す。再呼び出しで切替できる。
func load_stage(path: String) -> void:
	# carryover: 冒険譚に持ち越し戦力があれば渡す。fresh ステージ（carryover_slots 無し）では無視される。
	var carried: Array = []
	if _roster_store != null and not _current_campaign_id.is_empty():
		carried = _roster_store.load_roster(_current_campaign_id)
	var state := StageLoader.load_file(path, carried)
	if state == null:
		push_error("main: ステージを読めない: %s" % path)
		return
	_install_state(state, path)
	_maybe_start_intro()  # intro 会話があれば盤をロックして先に流す（新規開始のみ）

## 与えられた BattleState を盤・進行役に据える（新規ロードと中断セーブ復元で共有）。
## intro 会話の再生は含めない＝新規開始（load_stage）だけが呼ぶ。詳細 → doc/tech/gamesystem.md
func _install_state(state: BattleState, path: String) -> void:
	_current_stage_path = path  # システムメニューのリスタート用
	_dialogue = StageLoader.load_dialogue(path)  # 会話（intro/outro）を presentation へ（案P）
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
	_controller.combat_resolved.connect(_combat_scene.play)  # 演出シーン（結果＝シーン／根拠＝右パネル）
	_controller.combat_pace = _await_combat_view  # AI手番は演出の完了を待ってから次へ
	_controller.move_pace = $HexBoard.await_move_animation  # 同上＝移動アニメも歩き切るまで待つ
	_controller.focus_pace = $HexBoard.focus_camera_on  # AI手番は次の主体をカメラに収めてから見せる
	_controller.turn_changed.connect(_on_turn_changed)
	_controller.battle_finished.connect(_on_battle_finished)
	_update_turn_label(state.current_team, state.turn_number)
	_hud.set_player_turn(state.current_team == 0)  # ターン終了ボタンの有効/無効
	_start_stage_bgm(path)  # ステージ単位でBGMを張り替える（新規ロード・中断セーブ復元で共通）

## AI手番のテンポ制御（controller.combat_pace）：戦闘演出が出ていれば閉じるまで待つ。
func _await_combat_view() -> void:
	if _combat_scene != null and _combat_scene.visible:
		await _combat_scene.finished

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
				# carryover: 勝利時に生存自軍を保存＝次の継承ステージが引き継ぐ。保存は勝利時のみなので
				# 負けて再挑戦しても「前ステージ勝利時の戦力」からやり直せる（ソフトロック救済）。詳細 → doc/gdd/map.md
				if _roster_store != null and _controller != null:
					_roster_store.save_roster(_current_campaign_id, StageLoader.survivors_snapshot(_controller.state))
		BattleState.PLAYER_LOSS:
			text = "自軍の敗北…"
	$Title.text = "Senaris — %s" % text
	_hud.set_player_turn(false)  # 決着後はターン終了を無効化
	if outcome == BattleState.PLAYER_WIN:
		if not _dialogue.get("outro", []).is_empty():
			_conversation_phase = "outro"
			$InfoPanel.hide()
			$HexBoard.set_input_locked(true)  # 会話中はスクロール等を会話エリアだけに
			_set_scrim(true)  # 盤を沈めて会話に注視させる
			var label := "次のステージへ ▶" if not _next_playable_stage().is_empty() else "閉じる"
			_conversation.start(_dialogue["outro"], label)  # 読了/スキップで次ステージ or セレクトへ
		else:
			_advance_or_select()  # 会話なし＝すぐ次へ（テンポ優先）

# --- 会話（ステージ前後のチャット風シーン）。presentation/ui/conversation_panel.gd ---
func _install_conversation() -> void:
	# 暗幕は会話パネルより先に add＝パネルの後ろ（下）・盤や HUD の前（前面）に来る。
	# Node2D の子の Control はアンカーで自動リサイズされない（親にサイズが無い）ため、
	# ビューポート全体を size で明示し、リサイズに追従させる（Title/InfoPanel と同じ事情）。
	_scrim = ColorRect.new()
	_scrim.color = Color(0.0, 0.0, 0.0, 0.5)  # 暗さの度合い（叩き台。実機で調整）
	_scrim.position = Vector2.ZERO
	_scrim.size = get_viewport().get_visible_rect().size
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP  # 会話中は盤エリアのクリックを吸う（入力ガードの二重化）
	_scrim.modulate.a = 0.0
	_scrim.hide()
	add_child(_scrim)
	get_viewport().size_changed.connect(func() -> void:
		if _scrim != null:
			_scrim.size = get_viewport().get_visible_rect().size)
	_conversation = preload("res://presentation/ui/conversation_panel.gd").new()
	_conversation.offset_left = UiLayout.RIGHT_BOX.position.x  # InfoPanel と同じ箱に重ねる（会話中は InfoPanel を隠す）
	_conversation.offset_top = UiLayout.RIGHT_BOX.position.y
	_conversation.offset_right = UiLayout.RIGHT_BOX.end.x
	_conversation.offset_bottom = UiLayout.RIGHT_BOX.end.y
	_conversation.bind(_skins)
	_conversation.closed.connect(_on_conversation_closed)
	add_child(_conversation)

## 会話中の暗幕をフェードで出し入れする（唐突に暗くしない）。off はフェード後に隠して
## クリックを吸わないよう戻す。intro/outro の開始で on、会話終了で off。
func _set_scrim(on: bool) -> void:
	if _scrim == null:
		return
	# 前回のフェードが生きたままだと、outro の off（完了時 hide）が直後の intro の on を
	# 上書きして「会話中なのに盤が明るい」まま固まる（次ステージ連続進行で再現）。必ず止める。
	if _scrim_tween != null and _scrim_tween.is_valid():
		_scrim_tween.kill()
	if on:
		_scrim.show()
	_scrim_tween = create_tween()
	_scrim_tween.tween_property(_scrim, "modulate:a", 1.0 if on else 0.0, 0.2)
	if not on:
		_scrim_tween.tween_callback(_scrim.hide)

## intro 会話があれば、盤操作をロックして先に流す（無ければ即戦闘）。
func _maybe_start_intro() -> void:
	if _dialogue.get("intro", []).is_empty():
		return
	_conversation_phase = "intro"
	$HexBoard.set_input_locked(true)
	_set_scrim(true)  # 盤を沈めて会話に注視させる
	$InfoPanel.hide()  # 会話中は情報パネルを隠す（同じ箱に会話を出す）
	_hud.set_player_turn(false)
	_conversation.start(_dialogue["intro"], "戦闘開始 ▶")

## 会話終了（読了 or スキップ）。intro→戦闘、outro→セレクトへ。
func _on_conversation_closed() -> void:
	$InfoPanel.show()  # 会話が終わったら情報パネルを戻す
	$HexBoard.set_input_locked(false)  # 盤の凍結を解除（intro/outro 共通）
	_set_scrim(false)  # 暗幕を戻す（盤が主役に戻る）
	match _conversation_phase:
		"intro":
			_conversation_phase = ""
			if _controller != null:
				_hud.set_player_turn(_controller.state.current_team == 0)
		"outro":
			_conversation_phase = ""
			_advance_or_select()  # 次ステージがあれば進む・無ければセレクト

## クリア後の遷移先：次に遊べるステージがあれば進む（テンポ優先）。無ければセレクト。
## 判断は application（CampaignProgress.next_playable_stage）＝ここは画面の切り替えだけ。
## controller を作り直す load_stage は決着シグナルの処理中に呼ばれうるので call_deferred で安全に。
func _advance_or_select() -> void:
	var nxt := _next_playable_stage()
	if not nxt.is_empty():
		_current_stage_id = nxt["id"]  # 冒険譚は同じまま＝次ステージのクリア記録が正しく付く
		call_deferred("load_stage", String(nxt["path"]))
		return
	# 次が無い＝セレクトへ戻る。ただしキャンペーン完走（最終ステージ勝利）なら勝利イラストを1枚挟む。
	if _should_show_victory():
		_victory_screen.finished.connect(_select.open, CONNECT_ONE_SHOT)
		_victory_screen.play(_victory_path())
	else:
		_select.open()

func _next_playable_stage() -> Dictionary:
	return _progress.next_playable_stage(_current_campaign_id, _current_stage_id)

## いまクリアしたのがキャンペーン完走（＝非デバッグ冒険譚の最終ステージ）で、勝利イラストが在るか。
## 最終判定は素の next_stage（マニフェスト順で次が無い）を使う＝next_playable は locked でも空になり不可。
func _should_show_victory() -> bool:
	if _current_campaign_id.is_empty():
		return false
	var c := _progress.campaign(_current_campaign_id)
	if c.is_empty() or c["debug"]:
		return false
	if not _progress.next_stage(_current_campaign_id, _current_stage_id).is_empty():
		return false  # まだ最終ステージではない
	return not _victory_path().is_empty()

## 現冒険譚の勝利イラストのパス（連番バリアントがあればランダムに1枚・無ければ ""）。
func _victory_path() -> String:
	var c := _progress.campaign(_current_campaign_id)
	var paths: Array = c.get("victory_paths", [])
	return String(paths[randi() % paths.size()]) if not paths.is_empty() else ""

# --- BGM（決定＝application/BgmDirector・再生＝presentation/ui/bgm_player.gd）。詳細 → doc/audio/bgm.md ---
func _install_bgm() -> void:
	_bgm_director = BgmDirector.new()
	_bgm = BgmPlayer.new()
	_bgm.name = "BgmPlayer"
	add_child(_bgm)

## ステージのBGMを張り替える。曲はステージJSONの bgm → 冒険譚の既定 → 全体既定の順で決まる。
## 同じ曲を指すステージが続けば鳴りっぱなし（頭出しに戻らない）＝BgmPlayer 側で吸収。
func _start_stage_bgm(path: String) -> void:
	if _bgm == null:
		return
	_bgm_director.begin_stage(StageLoader.load_bgm(path), _campaign_bgm())
	_bgm.play(_bgm_director.track_id())

## 現冒険譚の既定BGM（campaign.json の bgm 欄）。セレクト外（デバッグ直起動など）では空。
func _campaign_bgm() -> Dictionary:
	if _progress == null or _current_campaign_id.is_empty():
		return {}
	var c := _progress.campaign(_current_campaign_id)
	var bgm: Variant = c.get("bgm", {})
	return bgm if typeof(bgm) == TYPE_DICTIONARY else {}

# --- 永続HUD（ターン終了ボタン＋システムメニュー）。presentation/ui/hud.gd ---
func _install_hud() -> void:
	_hud = preload("res://presentation/ui/hud.gd").new()
	add_child(_hud)
	_hud.end_turn_requested.connect(_on_end_turn_requested)
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.save_requested.connect(_on_save_requested)
	_hud.load_requested.connect(_on_load_requested)
	$HexBoard.system_menu_requested.connect(_hud.open_system_menu)

func _on_end_turn_requested() -> void:
	if _controller != null:
		_controller.end_turn()

func _on_restart_requested() -> void:
	if not _current_stage_path.is_empty():
		load_stage(_current_stage_path)

## 中断セーブ：現在の盤の状態まるごとを保存する（1枠・上書き）。文脈メタ（冒険譚/ステージ）も添える。
## 状態が真実なので手番・位置・損耗・行動フラグごと再現できる（BattleState.to_dict）。詳細 → doc/tech/gamesystem.md
func _on_save_requested() -> void:
	if _save_store == null or _controller == null:
		return
	var meta := {
		"campaign_id": _current_campaign_id, "stage_id": _current_stage_id,
		"stage_path": _current_stage_path,
	}
	_save_store.save(_controller.state.to_dict(), meta)
	_hud.set_load_available(true)  # 以後ロード可能に
	$Title.text = "Senaris — セーブしました"

## 中断セーブから再開：保存した状態から盤を組み直す（intro は流さない）。movement 表は復元後に再適用。
func _on_load_requested() -> void:
	if _save_store == null:
		return
	var data := _save_store.load()
	if data.is_empty():
		return
	var state := BattleState.from_dict(data["state"], UnitCatalog.load_default())
	state.set_movement(Movement.load_default())  # 静的コンフィグ＝セーブに含めず復元後に再適用（load_file と同じ）
	state.set_sight_cost(TerrainType.sight_cost_table())  # 視線コストも静的コンフィグ＝復元後に再適用
	var meta: Dictionary = data.get("meta", {})
	_current_campaign_id = String(meta.get("campaign_id", ""))
	_current_stage_id = String(meta.get("stage_id", ""))
	_install_state(state, String(meta.get("stage_path", "")))  # 盤・進行役を保存状態で据える（intro なし）

# --- セレクト画面（presentation/select/）。仕様 → doc/gdd/stage_select.md ---
func _install_select() -> void:
	_select = preload("res://presentation/select/select_screen.gd").new()
	add_child(_select)
	_select.setup(_progress)
	_select.stage_chosen.connect(_on_stage_chosen)
	_select.opened.connect(_on_select_opened)  # ステージ外に戻ったらメニュー曲へ
	_hud.stage_select_requested.connect(_select.open)
	_select.open()

## セレクトを開いた＝ステージ外の場面。盤（下敷き）は残るがBGMはメニュー曲に戻す。
func _on_select_opened() -> void:
	if _bgm != null:
		_bgm.play(BgmDirector.MENU_TRACK)

func _on_stage_chosen(campaign_id: String, stage_id: String, path: String) -> void:
	_current_campaign_id = campaign_id
	_current_stage_id = stage_id
	load_stage(path)

