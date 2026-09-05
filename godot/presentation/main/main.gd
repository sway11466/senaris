extends Node2D
## Presentation 層のエントリポイント。
## ステージ(data/stages/*.json)を読み込み、進行役(MatchController)と盤(HexBoard)を組む。
## load_stage(path) が本体＝ステージセレクト（presentation/select/）がこれを駆動する（再呼び出しで切替可）。
## 進行管理（解放判定・クリア記録）は application/campaign_progress.gd。仕様 → doc/gdd/stage_select.md
## デバッグ用ステージは data/stages/debug-*/（機能別の debug:true 冒険譚としてセレクトに出る）。一覧 → doc/tech/debug-stages.md

const BOARD_LOGO_PATH := "res://assets/logo/logo.png"  # 盤の右上に常設するタイトルロゴ

var _skins := {}
var _ai_presets := {}  # 特性表（data/ai/ai.json）。特性id -> パラメーター辞書（既定値）
var _controller: MatchController = null
var _hud: Hud = null
var _turn_plate: TurnPlate = null  # ターン板（永続・画面上端中央）。仕様 → doc/gdd/uiux.md
var _turn_banner: TurnBanner = null  # ターンの切り替わりを見せる横帯（永続・画面中央）。同上
var _formation_cutin: FormationCutin = null  # 陣形スキルの1枚絵カットイン（永続）。仕様 → doc/gdd/formations.md
const TURN_BANNER_GAP := 0.3  # 敵ターンでバナーが引けてから最初の行動までの間（秒）
## タイトルのざわめきを無音から立ち上げる時間（秒）。起動直後の一発目なので、素の音量で
## 出ると音が唐突に生える。扉に近づいていくくらいの間をとる。
const TITLE_BGM_FADE_IN := 2.5
## メニューが出たときに menu 曲へ渡す時間（秒）。ざわめきの落ちと曲の立ち上がりを同じ長さで
## 重ねる＝クロスフェード。店のざわめきから旋律へゆっくり持ち替える場面なので長めにとる。
const TITLE_MENU_FADE := 3.0
## 「おわる」で決定音を聞かせてから窓を閉じるまでの待ち（秒）。
const QUIT_SFX_SEC := 0.7
var _screen: ScreenLighting = null  # 画面の明暗の共通基盤（永続・層40）。暗幕と加護の光を持つ
var _current_stage_path := ""
var _current_stage_digest := ""  # 今のステージ定義の印（StageDigest）。セーブの meta に載せる
var _progress: CampaignProgress = null
var _roster_store: RosterStore = null  # 戦力継承(carryover)のスナップショット永続化。冒険譚IDで引く
var _saves: SaveSlots = null  # 中断セーブ5枠＋オートセーブ1枠。user://save_1.json … save_auto.json
var _slot_panel: SaveSlotPanel = null  # 枠一覧（セーブ/ロード共通・盤とタイトルの両方から出す）
var _slot_intent := ""  # 枠一覧をどちらの用で開いたか（"save"/"load"）＝選ばれた枠の使い道
## 自ターン開始時点の盤の動的差分（BattleState.to_save_diff）。中断セーブ・オートセーブはこれを書く
## ＝操作の途中でセーブしてもターンの頭に戻る（実質的なアンドゥ）。仕様 → doc/tech/gamesystem.md
var _turn_snapshot := {}
var _select: SelectScreen = null
var _title: TitleScreen = null  # 起動時のタイトル画面（酒場の扉）。閉じたらセレクトを開く
var _settings: SettingsScreen = null  # 設定画面（タイトルに重ねて開く）。仕様 → doc/gdd/settings.md
var _manual: ManualScreen = null  # マニュアル（タイトルに重ねて開く）。仕様 → doc/gdd/manual.md
var _settings_store: SettingsStore = null  # 設定値（user://settings.json）。触るのはここだけ
## タイトルを抜けるまで true。下敷きステージ（セレクトの背景）の曲がタイトルのざわめきを
## 上書きしないためのガード。下敷きの曲は盤が描き切ってから鳴る＝タイトルより後に割り込む。
var _title_pending := true
var _current_campaign_id := ""  # セレクト経由で選んだ現ステージ（勝利時のクリア記録・carryover のキー用）
var _current_stage_id := ""
var _conversation: ConversationPanel = null
var _combat_scene: CombatScene = null  # 戦闘演出オーバーレイ（永続・combat_resolved を受ける）
var _skill_scene: SkillScene = null  # ユニットスキルの演出（永続・formation_resolved のスキル分を受ける）
var _victory_screen: VictoryScreen = null  # キャンペーン完走の勝利イラスト（永続・最終勝利で play）
var _victory_overlay := false  # 完走イラストを outro 会話に重ねて出した＝会話後に全画面で出し直さない印
var _result: ResultBanner = null  # 決着の戦果票（永続・羊皮紙＋ゴム印）。決着で play
var _flash: FinishFlash = null  # 決着の白フラッシュ（永続・勝ちの回だけ）。仕様 → doc/gdd/uiux.md 決着の合図
## 勝ちを確定させた一手の演出経路（"combat"＝戦闘シーン／"formation"＝盤の着弾／""＝どちらでもない
## ＝占領など）。決着の合図をどの器で見せたかの印＝盤側のとどめ（カメラ寄せ）を重ねて出さない。
var _finisher_route := ""
var _start_ally := 0   # ステージ開始時の自軍数（戦果票の「生存 n/N」の分母）
var _rank_data := {}   # ステージ JSON の "rank"（評価ランクの閾値）。空＝ランクなし
## 所要時間（戦果票の「所要時間」→ doc/tech/gamesystem.md §所要時間）。
var _started_at := 0   # ステージを始めた実時刻（Unix秒）。中断セーブに持ち越す。0＝不明（旧セーブから再開）
var _elapsed := 0      # 決着までの所要秒。0＝測れていない＝票に出さず記録もしない
var _best_time := 0    # この回を記録する前の自己ベスト（秒）。0＝記録なし
var _bgm: BgmPlayer = null  # BGM の再生（永続・旧曲フェードアウト＋新曲は頭出し）。曲の決定は _bgm_director
var _bgm_director: BgmDirector = null  # 場面→曲の決定（application）。ステージ/既定のフォールバック
var _sfx: SfxPlayer = null  # 効果音の再生（永続・プール）。各画面は SfxPlayer.play_event で鳴らす
## 畳んでいて会話を出さないイベントで、カメラ寄せを見せ切ったことを知らせる
## （AIターンの待ち＝_await_dialogue が、会話の代わりにこれを待つ）。
signal event_skip_finished

var _dialogue := { "intro": [], "outro": [] }  # 現ステージの会話（台本キー→行。presentation専用・案P）
var _event_talks := {}  # 会話つきイベント id -> { name, dialogue }（「ストーリーを確認」の目次用）
var _turn_enabled_before_review := false  # 読み直しの前のターン終了の可否（読み終えたら戻す）
var _conversation_phase := ""  # "intro"/"outro"/"event"/""＝いま流している会話フェーズ

## 設定を読んで言語を決める。_ready ではなく _init で行うのは、main.tscn の子（InfoPanel が
## 抱える戦闘レポートのタブ）が親の _ready より先に文言を焼くため＝_ready で決めると起動時だけ
## その画面が別の言語で組まれる。仕様 → doc/tech/gamesystem.md §設定
func _init() -> void:
	_settings_store = SettingsStore.new()
	TranslationServer.set_locale(_settings_store.locale())

func _ready() -> void:
	# 刻印はタイトル画面にも出すが、ログの1行目にも置く＝報告にログが添えられたとき版が分かる。
	print("Senaris booted. build=%s" % BuildInfo.stamp())
	# 音量と画面モードは設定から起こす。曲が鳴り出す（_install_bgm）より前に当てる。
	for bus in SettingsStore.VOLUME_BUSES:
		_apply_volume(String(bus), _settings_store.volume(String(bus)))
	_apply_window_mode(_settings_store.window_mode())
	_skins = SkinCatalog.load_standard()
	_ai_presets = AiCatalog.load_default()
	# HexBoard と InfoPanel は永続。選択→情報パネルの配線は1回だけ（controller 非依存）。
	# InfoPanel は前面パネル層 $Front（層45）＝暗転（ScreenLighting・層40）で沈まない側。
	$HexBoard.selection_changed.connect($Front/InfoPanel.show_unit)
	$HexBoard.tile_inspected.connect($Front/InfoPanel.show_terrain)  # 空きマス選択→地形/拠点情報
	# 畳んでいるかは設定に残る（doc/gdd/uiux.md 最小化）。先に状態を入れてから配線する＝起動時の
	# 復元で設定を書き直さない。
	$Front/InfoPanel.set_minimized(_settings_store.info_panel_minimized())
	$Front/InfoPanel.minimized_changed.connect(_settings_store.set_info_panel_minimized)
	# 動かした位置も同じく設定から復元（doc/gdd/uiux.md 移動）。動かしていなければ main.tscn の置き場のまま。
	if _settings_store.has_info_panel_position():
		$Front/InfoPanel.position = _settings_store.info_panel_position()
	$Front/InfoPanel.moved.connect(_settings_store.set_info_panel_position)
	# 盤エリアは板が塞いでいない側＝畳む／開く／動かすのたびに押し直す（設定へ書いた後に読む）。
	$Front/InfoPanel.minimized_changed.connect(func(_v: bool) -> void: _sync_board_area())
	$Front/InfoPanel.moved.connect(func(_p: Vector2) -> void: _sync_board_area())
	_sync_board_area()
	_install_screen()  # 画面の明暗の共通基盤（暗幕＋加護の光）。暗転を頼む演出より先に用意
	_combat_scene = CombatScene.new()  # 戦闘演出オーバーレイ（永続）。load_stage で controller に結線
	_combat_scene.bind(_skins)
	_combat_scene.bind_screen(_screen)
	add_child(_combat_scene)
	_skill_scene = SkillScene.new()  # ユニットスキルの演出（永続）。舞台は戦闘と共通＝CombatStage
	_skill_scene.bind(_skins)
	_skill_scene.bind_screen(_screen)
	add_child(_skill_scene)
	_victory_screen = VictoryScreen.new()  # キャンペーン完走の勝利イラスト（永続）
	add_child(_victory_screen)
	_result = ResultBanner.new()  # 決着の戦果票（永続）。load_stage より前に用意
	_result.name = "ResultBanner"
	add_child(_result)
	_flash = FinishFlash.new()  # 決着の白フラッシュ（永続）。勝ちの回に戦果票への幕として使う
	_flash.name = "FinishFlash"
	add_child(_flash)
	_install_bgm()  # 永続BGM。load_stage が曲を張り替えるので、それより前に用意
	_install_sfx()  # 永続SFX。盤・セレクトから静的に鳴らすので、それらより前に用意
	_install_hud()  # 永続HUD（ターン終了ボタン＋システムメニュー）。load_stage より前に用意
	_install_turn_plate()  # 永続のターン板（画面上端中央）。load_stage がターン・代表ユニットを流し込む
	_install_board_logo()  # 永続のタイトルロゴ（右上・情報ボックスの上の帯）
	_install_turn_banner()  # 永続のターンバナー（画面中央・ターンが移った瞬間だけ出る）
	_install_formation_cutin()  # 永続の陣形カットイン（絵が在るレシピの発動時だけ出る）
	_install_conversation()  # 永続の会話パネル（右エリア）。load_stage の intro より前に用意
	_progress = CampaignProgress.new(CampaignCatalog.load_all(), ProgressStore.new())
	_roster_store = RosterStore.new()  # carryover の戦力スナップショット（user://roster.json）
	_saves = SaveSlots.new()  # 中断セーブ5枠＋オートセーブ1枠
	_install_slot_panel()  # 枠一覧（セーブ/ロード）。HUD・タイトルの両方から開く
	_hud.set_load_available(_saves.has_any())  # 起動時にセーブが1枠でも在ればロードを有効化
	load_stage("res://data/stages/_boot/underlay.json")  # セレクトの下敷き（盤を空にしない）。選択で差し替わる
	_install_select()  # 生成と配線だけ。開くのはタイトルで扉をくぐってから
	_install_settings()  # 設定画面。タイトルから開くので、タイトルより前に用意
	_install_manual()  # マニュアル。同上
	_install_title()  # 起動直後はタイトル（酒場の扉）。閉じたら _select.open()

## いま挑んでいる冒険譚の名簿（carryover）。冒険譚外（デバッグ・下敷き）では空。
## ステージ配置（player の actor 突き合わせ）と会話の when 評価の両方がこれを見る。詳細 → doc/gdd/campaigns.md
func _load_roster() -> Array:
	if _roster_store == null or _current_campaign_id.is_empty():
		return []
	return _roster_store.load_roster(_current_campaign_id)

## ステージ(JSON)を読み込み、マッチ（最小AI込み）を組み直す。再呼び出しで切替できる。
func load_stage(path: String) -> void:
	# carryover: 冒険譚の名簿があれば渡す。突き合う actor の無い fresh ステージでは無視される。
	var state := StageLoader.load_file(path, _load_roster())
	if state == null:
		push_error("main: ステージを読めない: %s" % path)
		return
	# 所要時間の起点。ここから勝敗が決まるまでを測る（intro 会話も含む＝ステージを始めた時刻）。
	# 実時刻で持ち、中断セーブにも書く＝閉じていた間も含めた「クリアまでにかかった時間」になる。
	_started_at = int(Time.get_unix_time_from_system())
	_install_state(state, path)
	_record_story_start()  # 開始時の在籍 actor を控える＝あとで当時の顔ぶれで会話を組み直せる
	_maybe_start_intro()  # intro 会話があれば盤をロックして先に流す（新規開始のみ）

## 与えられた BattleState を盤・進行役に据える（新規ロードと中断セーブ復元で共有）。
## intro 会話の再生は含めない＝新規開始（load_stage）だけが呼ぶ。詳細 → doc/tech/gamesystem.md
func _install_state(state: BattleState, path: String) -> void:
	_current_stage_path = path  # システムメニューのリスタート用
	_current_stage_digest = StageDigest.of_file(path)  # ステージ定義の印＝セーブの meta へ（更新検出用）
	_victory_overlay = false  # 前ステージの完走演出を持ち越さない
	_dialogue = StageLoader.load_dialogue(path, _load_roster())  # 会話（intro/outro）を presentation へ（案P・名簿で when を評価）
	_event_talks = StageLoader.load_event_talks(path)  # 会話つきイベントの見出しと台本キー（目次用・同じく presentation へ）
	_hud.hide_dialogue_badge()  # 前ステージの吹き出しを持ち越さない
	if _controller != null:
		_controller.free()  # 旧マッチを破棄（旧 controller のシグナル接続も消える）
		_controller = null
	_controller = MatchController.new()
	_controller.name = "MatchController"
	_controller.setup(state)
	# 敵軍(team 1)のAI: 特性ベース。敵の駒は必ず部隊(squad)に属し、その部隊の特性で振る舞う。
	_controller.ai_team = 1
	var brain := TraitBrain.new()
	brain.presets = _ai_presets  # 部隊の特性解決用（特性id -> パラメーターの既定値）
	_controller.ai_brain = brain
	add_child(_controller)
	var terrain_skins := StageLoader.load_terrain_skins(path)  # 見た目差分(座標→skin)は presentation へ（案P）
	# 外周(margin)＝盤の外側1周ぶんの地形。盤には入らず、縁の接続タイルの向き決めにだけ使う。
	$HexBoard.bind(state, _controller, _skins, terrain_skins, StageLoader.load_margin_terrain(path), StageLoader.load_board_height(path, state.cols, state.rows), StageLoader.load_height_overrides(path))
	_combat_scene.bind_terrain_skins(terrain_skins)  # 演出の地面も同じ見た目差分から組む
	_combat_scene.bind_state(state)  # 重ね絵を拠点の持ち主で選ぶ（占領で絵が変わる）
	var backdrop := StageLoader.load_backdrop(path)  # 水平線から上に敷く1枚（空・岩壁）。空文字＝引かない
	_combat_scene.bind_backdrop(backdrop)
	var haze := StageLoader.load_haze(path)  # 奥の靄の濃さ（ステージが持つ・必須）
	_combat_scene.bind_haze(haze)
	_skill_scene.bind_terrain_skins(terrain_skins)  # スキルの演出も同じ地面を組む
	_skill_scene.bind_state(state)
	_skill_scene.bind_backdrop(backdrop)
	_skill_scene.bind_haze(haze)
	$Front/InfoPanel.bind(state, _skins)
	$Front/InfoPanel.bind_terrain_skins(terrain_skins)  # 地形名を盤に見えている絵（スキン）の名前で出す
	$Front/InfoPanel.bind_ai_presets(_ai_presets)  # 敵の見出しに出す特性名の引き先
	_finisher_route = ""  # 前ステージの決着の印を持ち越さない
	# controller は作り直すので、controller 由来のシグナルは load ごとに繋ぐ。
	_controller.combat_resolved.connect($Front/InfoPanel.show_combat)
	_controller.combat_resolved.connect(_on_combat_resolved)  # 演出シーン（結果＝シーン／根拠＝右パネル）
	_controller.combat_pace = _await_combat_view  # AIターンは演出の完了を待ってから次へ
	_controller.move_pace = $HexBoard.await_move_animation  # 同上＝移動アニメも歩き切るまで待つ
	_controller.focus_pace = $HexBoard.focus_camera_on  # AIターンは次の主体をカメラに収めてから見せる
	_controller.turn_start_pace = _await_turn_banner  # 敵ターンは頭の一拍（バナー）を見せてから動く
	_controller.dialogue_pace = _await_dialogue  # 敵ターンの占領で入る会話は読み終えるまで待つ
	_controller.turn_changed.connect(_on_turn_changed)
	_controller.event_fired.connect(_on_event_fired)
	_controller.battle_finished.connect(_on_battle_finished)
	_controller.formation_resolved.connect(_on_formation_resolved)
	_apply_emblem()  # ターン板の左右（冒険譚の代表ユニット）。ステージが変われば差し替わる
	_update_turn_plate(state.current_team, state.turn_number)
	_hud.set_player_turn(state.current_team == 0)  # ターン終了ボタンの有効/無効
	_update_aura()  # 加護の光（中断セーブ復元で効果が残っていることがある）
	_count_start_forces(state, path)  # 戦果票の基準（開始時の兵力）を控える
	_rank_data = StageLoader.load_rank(path)  # 評価ランクの閾値（無ければ空＝ランクなし）
	_refresh_story_menu()  # 目次はステージごと＝新規ロードでも中断セーブ復元でも貼り直す
	if state.current_team == 0:
		_take_turn_snapshot()  # ステージの頭＝自ターン開始時点。ここでオートセーブも入る
	_start_stage_bgm_when_drawn(path)  # 盤が出てから鳴らす（新規ロード・中断セーブ復元で共通）

## 戦闘結果 → 演出シーンへ。この一撃で勝ちが確定していれば（domain は解決済み＝演出より先に
## 分かる）、とどめの演出（スロー＋寄り＋白フラッシュへの繋ぎ）として見せる。
## 仕様 → doc/gdd/uiux.md 決着の合図
func _on_combat_resolved(detail: Dictionary) -> void:
	if _win_decided():
		_finisher_route = "combat"
		_combat_scene.arm_finisher()
	_combat_scene.play(detail)

## この時点で勝ちが確定しているか。combat_resolved / formation_resolved は盤の状態が確定した後・
## battle_finished より前に飛ぶ＝演出を組む前に決着を読める。
func _win_decided() -> bool:
	return _controller != null and _controller.state.is_over() \
		and _controller.state.outcome() == BattleState.PLAYER_WIN

## AIターンのテンポ制御（controller.combat_pace）：演出が出ていれば閉じるまで待つ。
## 戦闘とユニットスキルは別のシーンだが同時には出ない（1手＝どちらか一方）。
func _await_combat_view() -> void:
	if _combat_scene != null and _combat_scene.visible:
		await _combat_scene.finished
	if _skill_scene != null and _skill_scene.visible:
		await _skill_scene.finished
	await _await_board_impact()

## 陣形スキルの着弾が出ている間は待つ（敵ターンのテンポ制御・決着の告知の両方から呼ぶ）。
## カットインの最中もこれが立っている＝カットイン→着弾を最後まで見せてから次へ進む。
func _await_board_impact() -> void:
	if $HexBoard.is_impacting():
		await $HexBoard.formation_impact_finished

func _on_turn_changed(team: int, turn_number: int) -> void:
	_update_turn_plate(team, turn_number)
	_hud.set_player_turn(team == 0)
	_update_aura()  # ターン開始で持続が減る＝ここで切れることがある
	SfxPlayer.play_event("map_turn_player" if team == 0 else "map_turn_enemy")
	_show_turn_banner(team)
	if team == 0:
		_take_turn_snapshot()  # 自ターンの頭を控える＝以後のセーブはここへ戻る／オートセーブも入る

## ターンの切り替わりを見せる横帯。自分のターンは操作を受け付けたまま（クリック等で即消し）、
## 敵のターンは turn_start_pace で待たせる＝1手も動かないターンでも見える。仕様 → doc/gdd/uiux.md
func _show_turn_banner(team: int) -> void:
	if _turn_banner == null:
		return
	var ally := team == 0
	var skin := String(_emblem().get("ally" if ally else "enemy", ""))
	# 文言は当面直書き（UI文言のキー化は backlog feature-12 で一括）。
	_turn_banner.play(team, tr("ui.banner.player_turn") if ally else tr("ui.banner.enemy_turn"), _skins, skin, ally)

## 敵ターンの頭で待つフック（controller に注入）。バナーが引き終わってから少し置いて最初の行動へ。
func _await_turn_banner() -> void:
	if _turn_banner != null and _turn_banner.visible:
		await _turn_banner.finished
	if is_inside_tree():
		await get_tree().create_timer(TURN_BANNER_GAP).timeout

## 陣形スキル／ユニットスキルの発動演出。陣形は発動の頭で音を鳴らし、1枚絵のカットインを挟んでから
## 盤に戻って結果（着弾音・加護の光）を見せる。ユニットスキルはカットインではなく演出シーン
## （効果対象が1体のものだけ＝doc/tech/combat_scene.md）を出す。
## 絵が無いレシピはカットインを飛ばす＝音と盤の結果は同じに出る。仕様 → doc/gdd/formations.md
func _on_formation_resolved(result: Dictionary) -> void:
	# 発動と同時にスキルレポート（カットイン・着弾の間も右パネルに出ている）。盤側の選択解除
	# （clear）が先に走る＝HexBoard.bind の接続がこのハンドラより先。仕様 → doc/tech/combat_scene.md
	$Front/InfoPanel.show_skill_report(result)
	# このスキルで勝ちが確定していれば、盤の着弾をとどめ（スロー＋カメラ寄せ）として見せる。
	if _win_decided():
		_finisher_route = "formation"
		$HexBoard.arm_finisher_impact()
	var recipe := String(result.get("recipe", ""))
	if Formation.is_unit_skill(recipe):
		# 音はここでは鳴らさない。演出シーンの一撃に合わせる（SkillScene._cast）＝ため 0.8 秒ぶん
		# 先に鳴ってしまうため。陣形は発動と着弾で2音あるので頭で鳴らしてよい。
		_update_aura()
		$HexBoard.play_formation_impact(result)  # 効果対象が1体＝着弾があれば盤にも出す
		var skill: Dictionary = result.get("skill", {})
		if _skill_scene != null and not skill.is_empty():
			_skill_scene.play(skill)
		return
	# 陣形の音はレシピごとに違う＝規約解決（assets/sfx/{recipe_id}.ogg と {recipe_id}_hit.ogg）。
	# 面殲滅と全体バフで同じ音を鳴らすと、何が起きたのかが音から分からない。
	SfxPlayer.play_sfx(recipe)
	if _formation_cutin != null and _formation_cutin.play(recipe):
		await _formation_cutin.finished
	SfxPlayer.play_sfx("%s_hit" % recipe)
	# 着弾＝揺れ → 面の光 → 被弾した駒を1体ずつ。揺れは画面全体（右の情報ボックスも同じ衝撃の下に
	# 置く）＝2D側はここ、盤（3D）は HexBoard がカメラに同じ量を掛ける。着弾の無いバフは揺らさない。
	if $HexBoard.is_impacting():
		_shake_screen()
	await $HexBoard.play_formation_impact(result)
	_update_aura()

## 着弾の揺れ（2D側）。このノードごと振る＝盤の上に載る UI・オーバーレイが一緒に動く。
## 前面パネル層 $Front（CanvasLayer）はこのノードの移動に乗らないので offset を同じ量で振る
## ＝右の情報ボックスも同じ衝撃の下に置く（仕様）。ScreenLighting（明暗）は光なので揺らさない。
## ほかの別レイヤー（戦闘演出・戦果票・セレクト）は着弾の瞬間には出ていない。
func _shake_screen() -> void:
	_shake_prop(self, "position")
	_shake_prop($Front, "offset")
	$HexBoard.shake()

func _shake_prop(target: Object, prop: String) -> void:
	var d := float(BoardCamera.SHAKE_PX)
	var step := float(BoardCamera.SHAKE_STEP)
	var tw := create_tween()
	tw.tween_property(target, prop, Vector2(-d, d * 0.5), step)
	tw.tween_property(target, prop, Vector2(d * 0.8, -d * 0.3), step)
	tw.tween_property(target, prop, Vector2(-d * 0.4, -d * 0.2), step)
	tw.tween_property(target, prop, Vector2.ZERO, step)

func _update_turn_plate(team: int, turn_number: int) -> void:
	var limit := _controller.state.turn_limit if _controller != null else 0
	_turn_plate.set_turn(team, turn_number, limit)
	_update_event()

## 情報板の位置を戻す（システムメニュー）。板を既定の場所へ戻し、設定の位置は項目ごと消す
## ＝「動かしていない」に戻す。仕様 → doc/gdd/uiux.md ターン終了・システムメニュー
func _on_info_panel_reset_requested() -> void:
	$Front/InfoPanel.reset_position()
	_settings_store.clear_info_panel_position()
	_sync_board_area()  # 既定の場所へ戻した＝また板が右ボックスを塞ぐ

## 盤エリア（→ doc/gdd/uiux.md 盤エリア）は情報板が塞いでいない側。板の状態を知っているのは
## ここだけなので、変わるたびに UiLayout へ押す。カメラはここでは動かさない＝畳む・開く・動かすで
## 見ている場所を失わせない（合わせ直すのはステージを開いたときだけ）。
func _sync_board_area() -> void:
	var holds: bool = not $Front/InfoPanel.is_minimized() and not _settings_store.has_info_panel_position()
	UiLayout.set_panel_holds_right_box(holds)

## 残りターン（増援の予告）を情報パネルへ流し込む。未発生のイベントが無ければ行が隠れる。
## 仕様 → doc/gdd/uiux.md 残りターン
func _update_event() -> void:
	$Front/InfoPanel.set_event(_controller.state.next_event() if _controller != null else {})

## 冒険譚マニフェストの emblem（代表ユニットの skin_id）。ターン板とバナーが使う。
## セレクトを経ないステージ（デバッグ直起動・起動時の下敷き）は指定が無い＝空辞書。
func _emblem() -> Dictionary:
	if _progress == null or _current_campaign_id.is_empty():
		return {}
	return _progress.campaign(_current_campaign_id).get("emblem", {})

## ターン板の左右に出す代表ユニット。指定が無ければ枠を出さない。
func _apply_emblem() -> void:
	var emblem := _emblem()
	_turn_plate.set_emblem(_skins, String(emblem.get("ally", "")), String(emblem.get("enemy", "")))

## 決着の告知は戦果票（ResultBanner）が担う＝ここでは記録と後続の演出だけ進める。
func _on_battle_finished(outcome: int) -> void:
	if _turn_banner != null:
		_turn_banner.dismiss()  # ターン制限切れはターンの切り替わりと同時＝戦果票と重ねない
	if _formation_cutin != null:
		_formation_cutin.dismiss()  # 陣形でボスを倒した＝カットインの最中に決着しうる
	# ランクは決着の直後に採る（この後の名簿更新より前＝盤の駒がまだ動いていない）。
	var rank := _evaluate_rank() if outcome == BattleState.PLAYER_WIN else ""
	# 所要時間も同じ瞬間に採る。自己ベストは記録より前に控える＝票には「この回の前のベスト」を出す。
	_elapsed = _elapsed_seconds()
	_best_time = 0
	if _progress != null and not _current_campaign_id.is_empty():
		_best_time = _progress.best_time(_current_campaign_id, _current_stage_id)
	match outcome:
		BattleState.PLAYER_WIN:
			if not _current_campaign_id.is_empty():  # セレクト経由のステージだけクリア記録
				_progress.record_clear(_current_campaign_id, _current_stage_id)
				if not rank.is_empty():
					_progress.record_rank(_current_campaign_id, _current_stage_id, rank)
				_progress.record_time(_current_campaign_id, _current_stage_id, _elapsed)
				# carryover: 勝利時に名簿を更新＝次の継承ステージが引き継ぐ。保存は勝利時のみなので
				# 負けて再挑戦しても「前ステージ勝利時の戦力」からやり直せる（ソフトロック救済）。詳細 → doc/gdd/campaigns.md
				if _roster_store != null and _controller != null:
					var updated := RosterService.update_after_clear(_load_roster(), _controller.state)
					_roster_store.save_roster(_current_campaign_id, updated)
					# 戦闘後の会話は「クリア後の名簿」で条件を見る＝この回で仲間になった駒が喋れる。
					# 読み込み時の名簿のままだと、加入が確定するのはクリア時なので合流の台詞が落ちる。
					_dialogue = StageLoader.load_dialogue(_current_stage_path, updated)
				# 決着の会話が読めるようになる＝クリア後の名簿を控える（doc/tech/gamesystem.md 経験した会話）。
				# 名簿の保存より後＝この回で仲間になった駒を含んだ顔ぶれが残る。
				_progress.record_story_clear(_current_campaign_id, _current_stage_id, _load_roster())
				_refresh_story_menu()
	_hud.set_player_turn(false)  # 決着後はターン終了を無効化
	# 決着シグナルは戦闘結果の直後に飛ぶ＝演出がまだ画面に出ている。勝敗を告げるのは演出が
	# 閉じてから（戦闘中に勝利音が鳴るのは気が早い）。ターン制限切れなど演出が無い決着は素通り。
	await _await_combat_view()
	if outcome == BattleState.PLAYER_WIN and _finisher_route.is_empty():
		await _play_board_finisher()  # 盤の上で決まった勝ち（本拠の占領など）＝寄せてから白へ
	var choice := await _show_result(outcome, rank)  # 戦果票＋スティンガー。プレイヤーが閉じるまで待つ
	if outcome == BattleState.PLAYER_WIN:
		# 畳んでいて会話を出さないなら、そのまま次へ。決着の会話に吹き出しは出さない
		# ＝閉じた瞬間に次のステージか依頼ボードへ移るので、知らせる場所が無い
		# （読むのはクリア後に入り直してから。doc/gdd/uiux.md 畳んでいるときの会話）。
		if not _dialogue.get("outro", []).is_empty() and _shows_dialogue():
			_conversation_phase = "outro"
			$Front/InfoPanel.set_covered(true)
			$HexBoard.set_input_locked(true)  # 会話中はスクロール等を会話エリアだけに
			_set_scrim(true)  # 盤を沈めて会話に注視させる
			# 冒険譚を完走した回だけ、盤の代わりに勝利イラストを敷いて outro を読ませる
			# （絵を見せ終えてから会話、ではなく絵の前で会話＝フィナーレを一続きにする）。
			if _should_show_victory():
				_victory_overlay = true
				_victory_screen.play_over_board(_victory_path())
			var label := "ui.talk.next_stage" if not _next_playable_stage().is_empty() else "ui.talk.close"
			_conversation.start(_dialogue["outro"], label)  # 読了/スキップで次ステージ or セレクトへ
		else:
			_advance_or_select()  # 会話なし＝すぐ次へ（テンポ優先）
	else:
		_take_defeat_route(choice)  # 敗北＝票で選ばれた行き先へ

# --- 決着の合図（勝ちが決まる瞬間）。仕様 → doc/gdd/uiux.md ---

## 本拠へ寄ってから白フラッシュまでの一拍（秒）＝旗の変わった本拠と決着の光を見せる間。
const CAPTURE_BEAT := 0.6

## 盤の上で決まった勝ち（本拠の占領など＝とどめの一撃が無い）の決着の合図。
## カメラを本拠へ寄せ、決着の光を置き、一拍見せてから白フラッシュへ渡す。
## 占領した本拠が見つからない勝ち（デバッグの殲滅など）は寄せずに白へ直行する。
func _play_board_finisher() -> void:
	await $HexBoard.await_move_animation()  # 占領の駒が歩き切ってから（旗はもう変わっている）
	var hex := _captured_enemy_hq()
	if hex == Vector2i.MAX:
		return
	await $HexBoard.zoom_to_finisher(hex)
	$HexBoard.flash_finisher_cell(hex)
	if is_inside_tree():
		await get_tree().create_timer(CAPTURE_BEAT).timeout

## 自軍が奪った敵の本拠（hq が敵の陣営で、いま自軍所属）。無ければ Vector2i.MAX。
func _captured_enemy_hq() -> Vector2i:
	for b in _controller.state.bases():
		if b.is_hq_of(1) and b.team == 0:
			return b.hex
	return Vector2i.MAX

# --- 決着の戦果票（羊皮紙＋ゴム印）。presentation/ui/result_banner.gd ---

## 戦果票を出し、プレイヤーが閉じるまで待つ。印が落ちた瞬間に勝敗スティンガーを鳴らす
## （演出と音を揃える）。曲が未配置でも無音で進む＝演出だけは出る。
## 勝利は白フラッシュを幕にする＝白が覆ってから戦闘の窓を畳んで票を敷き、白が引くと票が
## 出ている（doc/gdd/uiux.md 決着の合図）。敗北は現行のまま暗幕から。
## 返り値＝敗北の票で選ばれた行き先（ResultBanner.ACT_*）。勝利と、選ばずに閉じた回は空。
func _show_result(outcome: int, rank: String) -> String:
	if _result == null or _controller == null:
		return ""
	var win := outcome == BattleState.PLAYER_WIN
	if _bgm != null:
		# 勝利は余韻曲へ繋ぐ＝ファンファーレ（約10秒）が終わった後、outro 会話を読む間が無音にならない。
		# 敗北は繋がない（会話が無く、すぐ再挑戦かセレクトへ行くので、読ませる時間が無い）。
		var track := "victory" if win else "defeat"
		var follow := BgmDirector.AFTERGLOW_TRACK if win else ""
		_result.stamped.connect(func() -> void: _bgm.play_stinger(track, follow), CONNECT_ONE_SHOT)
	# 勝利の印はその回のランク（S/A/B）。ランクを持たないステージ（デバッグの直起動など）だけ
	# VICTORY に戻す。敗北はランクを付けないので DEFEAT のまま。表記は英語＝酒場ボードに揃える。
	var stamp_text := rank
	if stamp_text.is_empty():
		stamp_text = "VICTORY" if win else "DEFEAT"
	# 印の上の欄名はランクを押す回だけ（VICTORY / DEFEAT の上に「ランク」と刷ると嘘になる）。
	var caption := tr("ui.result.rank") if not rank.is_empty() else ""
	if win:
		# 白フラッシュ＝決着の光がそのまま票への幕になる。白が覆っている間に戦闘の窓を畳み
		# （出ていなければ何もしない）、票を白の下に敷いてから白を引く。
		await _flash.rise()
		_combat_scene.close_under_flash()
		_result.play(_stage_title(), stamp_text, win, _result_rows(win), caption,
			tr("ui.result.note_weapons"), true)
		_flash.fall()
	else:
		# 敗北の票には行き先を2つ置く＝盤に戻らず再挑戦かセレクトへ進める（doc/gdd/uiux.md 決着の演出）。
		_result.play(_stage_title(), stamp_text, win, _result_rows(win), caption,
			tr("ui.result.note_weapons"), false, true)
	_finisher_route = ""
	return await _result.finished

## 敗北の戦果票で選ばれた行き先へ進む。空＝選ばずに閉じた＝そのまま盤に戻る（負けた盤を見直せる）。
## 再挑戦は controller を作り直すので、票を閉じた入力の処理から抜けてから走らせる。
func _take_defeat_route(action: String) -> void:
	match action:
		ResultBanner.ACT_RETRY:
			call_deferred("_on_restart_requested")
		ResultBanner.ACT_SELECT:
			_select.open()

## ステージ開始時の兵力を控える（戦果票の分母）。盤の現況ではなくステージ定義から導出する
## ＝中断セーブから再開しても同じ値になる（doc/gdd/rank.md 生存）。
func _count_start_forces(state: BattleState, path: String) -> void:
	_start_ally = StageLoader.count_start_allies_at(path, state)

## 戦果の行（ターン数・生存・撃破）。集計は presentation 側＝domain に戦績を持たせない。
## 勝利のときだけ、ターン数と生存にランク基準（S・A の具体値と達成の可否）を添える＝何を詰めれば
## 上がるかを読ませる。敗北にランクは付かないので基準も出さない。撃破はランクに使わないので基準なし。
## 撃破は実際に倒した敵の駒の数＝domain が数えた敵の損失をそのまま出す。
## 生存・撃破は兵器を数えない（doc/gdd/rank.md）＝その2行の見出しに印を付け、脚注で受ける。
func _result_rows(win: bool) -> Array:
	var st := _controller.state
	var alive_ally := st.ally_survivor_count()
	var mark := tr("ui.result.note_mark")
	var turns := "%d / %d" % [st.turn_number, st.turn_limit] if st.turn_limit > 0 else str(st.turn_number)
	var turn_row := {"label": tr("ui.result.turns"), "value": turns}
	var alive_row := {"label": tr("ui.result.survived") + mark, "value": "%d / %d" % [alive_ally, _start_ally]}
	if win and not _rank_data.is_empty():
		var turn_got := RankEvaluator.turn_rank(st.turn_number, _rank_data)
		var alive_got := RankEvaluator.survival_rank(alive_ally, _start_ally, _rank_data)
		_fill_goals(turn_row, "ui.result.goal_turn", "turn_s", "turn_a", turn_got)
		_fill_goals(alive_row, "ui.result.goal_alive", "survival_s", "survival_a", alive_got)
	var rows := [turn_row, alive_row,
		{"label": tr("ui.result.defeated") + mark, "value": str(st.losses(1))}]
	if _elapsed > 0:
		rows.append(_time_row(win))  # 測れていない回（開始時刻を持たない旧セーブ）は行ごと出さない
	return rows

## 所要時間の行。下に自己ベストをぶら下げ、更新した回はチェックを付ける（ランク基準と同じ見せ方）。
## ベストを添えるのは勝った回だけ＝負けた回は記録に触らないので、比べる相手を出さない。
func _time_row(win: bool) -> Dictionary:
	var row := {"label": tr("ui.result.time"), "value": _format_duration(_elapsed)}
	if not win or _current_campaign_id.is_empty():
		return row
	var updated := _best_time <= 0 or _elapsed < _best_time
	row["sub"] = tr("ui.result.best_time") % _format_duration(_elapsed if updated else _best_time)
	row["sub_ok"] = updated
	return row

## ステージを始めてから決着までの秒数。0＝測れていない（開始時刻を持たない旧セーブから再開した回）。
## 時計が巻き戻ったとき（システム時刻の変更）も 0 に倒す＝負の時間を記録に混ぜない。
func _elapsed_seconds() -> int:
	if _started_at <= 0:
		return 0
	return maxi(int(Time.get_unix_time_from_system()) - _started_at, 0)

## 所要時間の表記。1時間未満は "12:34"、1時間以上は "1:02:34"、1日以上は "3日 2:15"。
## 中断を挟めば日をまたぐ（閉じていた間も含める）ので、日は捨てずに出す。
func _format_duration(seconds: int) -> String:
	var total := maxi(seconds, 0)
	var days := total / 86400
	var hours := (total % 86400) / 3600
	var minutes := (total % 3600) / 60
	if days > 0:
		return tr("ui.result.time_days") % [days, hours, minutes]
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total % 60]
	return "%d:%02d" % [minutes, total % 60]

## 1行ぶんのランク基準を辞書に足す。閾値が 0（＝その軸に基準を置いていないステージ）の段は空欄。
## 達成は「その軸のランクがその段以上か」で見る＝閾値の比べ方を presentation に写さない。
func _fill_goals(row: Dictionary, fmt_key: String, s_key: String, a_key: String, got: String) -> void:
	var s_val := int(_rank_data.get(s_key, 0))
	var a_val := int(_rank_data.get(a_key, 0))
	if s_val > 0:
		row["s"] = tr(fmt_key) % [RankEvaluator.RANK_S, s_val]
		row["s_ok"] = got == RankEvaluator.RANK_S
	if a_val > 0:
		row["a"] = tr(fmt_key) % [RankEvaluator.RANK_A, a_val]
		row["a_ok"] = not RankEvaluator.is_better(RankEvaluator.RANK_A, got)

## 評価ランクを算出する（勝利時）。rank_data が空ならランクなし＝空文字。
func _evaluate_rank() -> String:
	if _rank_data.is_empty() or _controller == null:
		return ""
	var alive := _controller.state.ally_survivor_count()
	return RankEvaluator.evaluate(_controller.state.turn_number, alive, _start_ally, _rank_data)

## 戦果票の見出し＝ステージ名（冒険譚マニフェストの翻訳キーを解決）。
## セレクト外（デバッグの直起動など）はステージJSONのファイル名で代用する。
func _stage_title() -> String:
	if _progress != null and not _current_campaign_id.is_empty():
		var c := _progress.campaign(_current_campaign_id)
		for s in c.get("stages", []):
			if String(s.get("id", "")) == _current_stage_id:
				return tr(String(s.get("title", "")))
	return _current_stage_path.get_file().get_basename()

# --- 会話（ステージ前後のチャット風シーン）。presentation/ui/conversation_panel.gd ---
func _install_conversation() -> void:
	# パネルは前面パネル層 $Front（層45）＝暗転で沈まない側。暗幕は共通基盤（_screen）に頼む。
	_conversation = preload("res://presentation/ui/conversation_panel.gd").new()
	_conversation.offset_left = UiLayout.RIGHT_BOX.position.x  # InfoPanel と同じ箱に重ねる（会話中は InfoPanel を隠す）
	_conversation.offset_top = UiLayout.RIGHT_BOX.position.y
	_conversation.offset_right = UiLayout.RIGHT_BOX.end.x
	_conversation.offset_bottom = UiLayout.RIGHT_BOX.end.y
	_conversation.bind(_skins)
	_conversation.closed.connect(_on_conversation_closed)
	$Front.add_child(_conversation)

## 会話中の暗転（共通基盤に頼む）。フェード・重ね掛けの管理は ScreenLighting 持ち。
## block_input=true＝幕より下（盤・HUD）へのクリックも吸う（盤ロックとの二重ガード）。
func _set_scrim(on: bool) -> void:
	if _screen == null:
		return
	if on:
		_screen.dim(self, true)
	else:
		_screen.undim(self)

## intro 会話があれば、盤操作をロックして先に流す（無ければ即戦闘）。
func _maybe_start_intro() -> void:
	if _dialogue.get("intro", []).is_empty():
		return
	if not _shows_dialogue():
		_hud.show_dialogue_badge()  # 開幕の会話があったことだけ知らせる（読むのはメニューから）
		return
	_conversation_phase = "intro"
	$HexBoard.set_input_locked(true)
	_set_scrim(true)  # 盤を沈めて会話に注視させる
	$Front/InfoPanel.set_covered(true)  # 会話中は情報パネルを隠す（同じ箱に会話を出す）
	_hud.set_player_turn(false)
	_conversation.start(_dialogue["intro"], "ui.talk.start_battle")

## 盤のイベントが起きたときの見せ方。台本があれば会話を挟み、focus 指定があれば先にその場所へ
## カメラを寄せる（喋る相手が画面に居る状態で幕を引く）。会話の間は盤とターン終了を止める
## （intro/outro と同じ扱い）。増援なら駒はもう盤に出ている＝何が来たのかを見せてから喋らせる。
## 敵ターンに出せるのは占領（on:"capture"）だけ＝1手の切れ目で controller が待ってくれている。
## turn 起点のイベントは敵の手番の頭で起きる＝AI が動き出す前に止める場所が無いので出さない
## （doc/gdd/map.md イベント）。
func _on_event_fired(info: Dictionary) -> void:
	if _controller == null or _conversation == null or _conversation_phase != "":
		return
	if _controller.is_ai_turn() and String(info.get("on", "")) != "capture":
		return
	var key := String(info.get("dialogue", ""))
	if key.is_empty():
		return
	var lines: Array = _dialogue.get(key, [])
	if lines.is_empty():
		push_warning("main: イベントの台本が見つからない: dialogue=%s" % key)
		return
	_record_story_event(String(info.get("id", "")))  # 起きた＝あとで読み直せる（会話を出すかに関わらず）
	if not _shows_dialogue():
		await _skip_event_dialogue(info)
		return
	# 幕より先に phase を立てる＝AIターンの待ち（dialogue_pace）がこの会話を取りこぼさない。
	_conversation_phase = "event"
	if not _controller.is_ai_turn():
		await $HexBoard.await_move_animation()  # 駒が歩き切ってから喋る（敵ターンは呼ぶ側が待っている）
	if bool(info.get("focus", false)):
		var hex: Vector2i = info.get("hex", Vector2i.MAX)
		if hex != Vector2i.MAX:
			await $HexBoard.focus_camera_on(hex)
	if _turn_banner != null:
		_turn_banner.dismiss()  # ターンの頭で起きる＝バナーと会話を重ねない
	$Front/InfoPanel.set_covered(true)
	$HexBoard.set_input_locked(true)
	_set_scrim(true)  # 盤を沈めて会話に注視させる
	_hud.set_player_turn(false)
	_conversation.start(lines, "ui.talk.resume_battle")

## 畳んでいて会話を出さないとき。盤は止めず暗幕も降ろさないが、カメラ寄せだけは見せる
## ＝何がどこで起きたかは戦況で、会話と一緒に切ってよいものではない
## （doc/gdd/uiux.md 畳んでいるときの会話）。見せ終えたら吹き出しで知らせる。
func _skip_event_dialogue(info: Dictionary) -> void:
	# 幕より先に phase を立てるのと同じ理由＝AIターンの待ちがカメラ寄せを取りこぼさない。
	_conversation_phase = "event_skip"
	if not _controller.is_ai_turn():
		await $HexBoard.await_move_animation()  # 駒が歩き切ってから寄せる（敵ターンは呼ぶ側が待っている）
	if bool(info.get("focus", false)):
		var hex: Vector2i = info.get("hex", Vector2i.MAX)
		if hex != Vector2i.MAX:
			await $HexBoard.focus_camera_on(hex)
	_hud.show_dialogue_badge()
	_conversation_phase = ""
	event_skip_finished.emit()

## AIターンのテンポ制御（controller.dialogue_pace）：占領で会話が始まっていれば閉じるまで待つ。
## 会話を始めるのは _on_event_fired ＝ここへ来た時点で phase は立っている（カメラ寄せの前に立てている）。
func _await_dialogue() -> void:
	if _conversation_phase == "event" and _conversation != null:
		await _conversation.closed
	elif _conversation_phase == "event_skip":
		await event_skip_finished  # 会話は出さないが、カメラ寄せは見せ切ってから次の手へ

## 情報板を畳んでいるときに会話を出すか（設定 → doc/gdd/settings.md 会話）。
## 開いていれば常に出す＝この設定は畳んでいるときだけ効く。
func _shows_dialogue() -> bool:
	if not $Front/InfoPanel.is_minimized():
		return true
	return _settings_store.dialogue_when_minimized() == "show"

## 経験した会話の記録（doc/tech/gamesystem.md 経験した会話）。記録するかの判定は
## CampaignProgress が持つ＝デバッグ冒険譚と未知のステージには残らない。
func _record_story_start() -> void:
	if _progress == null or _current_campaign_id.is_empty():
		return
	_progress.record_story_start(_current_campaign_id, _current_stage_id, _load_roster())
	_refresh_story_menu()

func _record_story_event(event_id: String) -> void:
	if _progress == null or _current_campaign_id.is_empty() or event_id.is_empty():
		return
	_progress.record_story_event(_current_campaign_id, _current_stage_id, event_id)
	_refresh_story_menu()

## そのステージで経験した会話の記録（無ければ空）。
func _story_record() -> Dictionary:
	if _progress == null or _current_campaign_id.is_empty():
		return {}
	return _progress.story(_current_campaign_id, _current_stage_id)

## 「ストーリーを確認」の目次を貼り直す。経験していないものは並べない
## ＝まだ見ていない出来事の存在を目次で匂わせない（doc/gdd/uiux.md ターン終了・システムメニュー）。
func _refresh_story_menu() -> void:
	var record := _story_record()
	var entries: Array = []
	if record.has("start") and not _dialogue.get("intro", []).is_empty():
		entries.append(["intro", tr("ui.hud.story_intro")])
	for id in record.get("events", []):
		var talk: Dictionary = _event_talks.get(String(id), {})
		if not talk.is_empty():  # ステージを直してイベントごと消えた記録は出さない
			entries.append([String(id), tr(String(talk["name"]))])
	if record.has("clear") and not _dialogue.get("outro", []).is_empty():
		entries.append(["outro", tr("ui.hud.story_outro")])
	_hud.set_story_entries(entries)

## 目次から選ばれた会話を出す。当時の顔ぶれで台本を組み直す＝記録した在籍 actor を名簿の
## 代わりに渡す（会話の when が見るのは在籍だけ）。読み終えたら割り込む前の状態へ戻す。
func _on_story_requested(key: String) -> void:
	if _conversation == null or _conversation_phase != "":
		return
	var record := _story_record()
	var actors: Array = record.get("clear", []) if key == "outro" else record.get("start", [])
	var script := StageLoader.load_dialogue(_current_stage_path, _actors_as_roster(actors))
	var talk_key := key
	if key != "intro" and key != "outro":
		var talk: Dictionary = _event_talks.get(key, {})
		if talk.is_empty():
			return
		talk_key = String(talk["dialogue"])
	var lines: Array = script.get(talk_key, [])
	if lines.is_empty():
		push_warning("main: 読み直す台本が見つからない: %s" % talk_key)
		return
	_turn_enabled_before_review = _hud.player_turn_enabled()
	_conversation_phase = "review"
	$Front/InfoPanel.set_covered(true)
	$HexBoard.set_input_locked(true)
	_set_scrim(true)  # 盤を沈めて会話に注視させる（いつもの会話と同じ見せ方）
	_hud.set_player_turn(false)
	_hud.hide_dialogue_badge()
	_conversation.start(lines, "ui.talk.close")

## 記録した actor の並びを、会話の条件（when: joined:<actor>）が見るだけの名簿に仕立てる。
## StageLoader が見るのは actor だけ＝素性も損耗も要らない。
static func _actors_as_roster(actors: Array) -> Array:
	var out: Array = []
	for a in actors:
		out.append({ "actor": String(a) })
	return out

## 会話終了（読了 or スキップ）。intro→戦闘、outro→セレクトへ。
func _on_conversation_closed() -> void:
	$Front/InfoPanel.set_covered(false)  # 会話が終わったら情報パネルを戻す（畳んでいたなら畳んだまま）
	$HexBoard.set_input_locked(false)  # 盤の凍結を解除（intro/outro 共通）
	_set_scrim(false)  # 暗幕を戻す（盤が主役に戻る）
	match _conversation_phase:
		"intro", "event":  # 戦闘へ戻る（開幕・途中の割り込みで同じ）
			_conversation_phase = ""
			if _controller != null:
				_hud.set_player_turn(_controller.state.current_team == 0)
		"review":  # 「ストーリーを確認」の読み直し＝盤は何も進めない。割り込む前の状態へ戻すだけ
			_conversation_phase = ""
			_hud.set_player_turn(_turn_enabled_before_review)
		"outro":
			_conversation_phase = ""
			if _victory_overlay:
				_victory_screen.dismiss()  # 絵は会話と一緒に退く（全画面では出し直さない）
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
	if _victory_overlay:
		return false  # outro 会話に重ねて出し切った＝会話後に全画面で出し直さない
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

# --- SFX（対応表＝data/audio/sfx_catalog.gd・再生＝presentation/ui/sfx_player.gd）。詳細 → doc/audio/sfx.md ---
## 効果音は盤・セレクトの各所から細かく鳴らすため、実体だけここで持ち、
## 呼び出しは SfxPlayer.play_event(発火点ID) で行う（参照を各画面へ配らない）。
func _install_sfx() -> void:
	_sfx = SfxPlayer.new()
	_sfx.name = "SfxPlayer"
	add_child(_sfx)

## 盤が1枚描き切ってからステージのBGMを始める。_install_state の中で鳴らすと、残りの盤生成と
## 初回描画のぶん（実測 0.1〜0.3秒）だけ曲が先行し、盤が出る前に曲の頭が流れてしまう。
## 待っている間に別ステージへ切り替わったら捨てる（連戦は call_deferred で load_stage が重なる）。
func _start_stage_bgm_when_drawn(path: String) -> void:
	await RenderingServer.frame_post_draw
	if _current_stage_path != path:
		return
	_start_stage_bgm(path)

## ステージのBGMを張り替える。曲はステージJSONの bgm → 全体既定の順で決まる。
## 同じ曲を指すステージが続けば鳴りっぱなし（頭出しに戻らない）＝BgmPlayer 側で吸収。
func _start_stage_bgm(path: String) -> void:
	if _bgm == null:
		return
	_bgm_director.begin_stage(StageLoader.load_bgm(path))
	if _title_pending:
		return  # タイトル表示中＝ざわめきを流したまま。曲はセレクトを開くときに張り替わる
	_bgm.play(_bgm_director.track_id())

# --- 永続HUD（ターン終了ボタン＋システムメニュー）。presentation/ui/hud.gd ---
func _install_hud() -> void:
	_hud = preload("res://presentation/ui/hud.gd").new()
	add_child(_hud)
	_hud.end_turn_requested.connect(_on_end_turn_requested)
	_hud.info_panel_toggle_requested.connect($Front/InfoPanel.toggle_minimized)
	_hud.info_panel_reset_requested.connect(_on_info_panel_reset_requested)
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.save_requested.connect(_on_save_requested)
	_hud.load_requested.connect(_on_load_requested)
	_hud.zoom_in_requested.connect(func() -> void: $HexBoard.zoom_step(true))
	_hud.zoom_out_requested.connect(func() -> void: $HexBoard.zoom_step(false))
	_hud.wipe_enemies_requested.connect(_on_wipe_enemies_requested)  # デバッグ項目（製品ビルドでは出ない）
	_hud.debug_event_requested.connect(_on_debug_event_requested)  # 同上
	_hud.debug_events_provider = _debug_event_labels  # メニューを開くたびに hud から聞かれる
	_hud.story_requested.connect(_on_story_requested)  # 経験した会話の読み直し
	$HexBoard.system_menu_requested.connect(_hud.open_system_menu)
	$HexBoard.info_panel_toggle_requested.connect($Front/InfoPanel.toggle_minimized)  # Space＝情報板ボタンと同じ

# --- ターン板（画面上端中央）。presentation/ui/turn_plate.gd。仕様 → doc/gdd/uiux.md ---
func _install_turn_plate() -> void:
	_turn_plate = TurnPlate.new()
	_turn_plate.name = "TurnPlate"
	add_child(_turn_plate)

# --- タイトルロゴ（盤の右上・常設）。仕様 → doc/gdd/uiux.md ---
## 情報ボックスの上に空く帯へ、右端をボックスの右端にそろえて置く。盤にもボックスにも掛からない。
## 前面パネル層 $Front（層45）＝会話の暗転（層40）では沈まない。戦闘演出（層50）より後ろなので、
## 演出が出ている間は隠れる（演出は数秒の切り替え画）。
## 絵は透明な余白を含むので、実体の矩形（get_used_rect）だけを切り出して使う＝右端そろえがずれない。
func _install_board_logo() -> void:
	var tex := ResourceLoader.load(BOARD_LOGO_PATH) as Texture2D
	if tex == null:
		print("main: ロゴの絵が無い＝盤に出さない: %s" % BOARD_LOGO_PATH)
		return
	var used := tex.get_image().get_used_rect()
	if used.size.y <= 0:
		return
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(used.position, used.size)
	var rect := TextureRect.new()
	rect.name = "BoardLogo"
	rect.texture = at
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 盤の操作を邪魔しない
	var w := UiLayout.LOGO_H * float(used.size.x) / float(used.size.y)
	rect.position = Vector2(UiLayout.RIGHT_BOX.end.x - w, UiLayout.LOGO_TOP)
	rect.size = Vector2(w, UiLayout.LOGO_H)
	$Front.add_child(rect)

## ターンの切り替わりを見せる横帯。presentation/ui/turn_banner.gd。仕様 → doc/gdd/uiux.md
func _install_turn_banner() -> void:
	_turn_banner = TurnBanner.new()
	_turn_banner.name = "TurnBanner"
	# 前面パネル層 $Front（層45）＝InfoPanel より後の子＝その前に出る。暗幕（層40）でも沈まない。
	$Front.add_child(_turn_banner)

func _install_formation_cutin() -> void:
	_formation_cutin = FormationCutin.new()
	_formation_cutin.name = "FormationCutin"
	_formation_cutin.bind_screen(_screen)
	$Front.add_child(_formation_cutin)  # 前面パネル層＝暗転しても絵は沈まない（暗転は自身が掛ける）

## 画面の明暗の共通基盤（presentation/ui/screen_lighting.gd）。暗幕と加護の光をここに集約する。
## 層の並び（0=盤・HUD／40=本層／45=$Front／50=演出窓 …）は ScreenLighting のヘッダ参照。
## 旧実装の「add_child の順序が光の届く範囲を決める」約束は層番号に置き換わった＝呼び順は自由。
func _install_screen() -> void:
	_screen = ScreenLighting.new()
	_screen.name = "ScreenLighting"
	add_child(_screen)

## 陣営全体バフ（グレイス）が効いている間だけ加護の光を出す。
## ターンの切り替わりで満了するので、turn_changed と陣形の解決で見直す。
func _update_aura() -> void:
	if _screen == null or _controller == null:
		return
	if _controller.state.team_aura_fx().is_empty():
		_screen.aura_stop()
	else:
		_screen.aura_play(AuraOverlay.HOLY_COLOR)

func _on_end_turn_requested() -> void:
	if _controller != null:
		SfxPlayer.play_event("map_turn_end")
		_controller.end_turn()

func _on_restart_requested() -> void:
	if not _current_stage_path.is_empty():
		load_stage(_current_stage_path)

## デバッグメニュー「敵を殲滅」。controller はステージごとに作り直すので、押された時点の
## controller へ流す（結線の張り替えをしない）。決着後・盤なしでは controller 側が弾く。
func _on_wipe_enemies_requested() -> void:
	if _controller == null:
		return
	_controller.wipe_enemies()
	$HexBoard.refresh()  # 盤は攻撃イベントで作り直す作り＝殲滅はそれを経ないので明示的に更新する

## デバッグメニュー「イベントを起こす」に並べる未発生イベントの表示名。引き金・陣営・中身が
## 一目で分かればよい＝翻訳キーは切らず直書き（デバッグ区画の流儀。doc/tech/i18n.md）。
## 自ターンで決着前のときだけ並べる。敵ターン中は会話が流れない門（_on_event_fired）があり、
## 会話の最中は盤を止めている＝どちらも起こしても見えないため。
func _debug_event_labels() -> PackedStringArray:
	var out := PackedStringArray()
	if _controller == null or _controller.is_ai_turn() or _controller.state.is_over():
		return out
	if _conversation_phase != "":
		return out
	for e in _controller.state.pending_events():
		var side := "味方" if int(e.get("team", 0)) == 0 else "敵"
		var trigger := "T%d" % int(e.get("turn", 0))
		if String(e.get("on", "")) == "capture":
			var off := Hex.axial_to_offset(Vector2i(e.get("hex", Vector2i.MAX)))
			trigger = "占領(%d,%d)" % [off.x, off.y]
		var units: Array = e.get("units", [])
		var body := "会話" if units.is_empty() else "増援%d" % units.size()
		var key := String(e.get("dialogue", ""))
		if key.is_empty():
			key = String(e.get("label", ""))
		out.append("%s %s %s%s" % [trigger, side, body, "" if key.is_empty() else " " + key])
	return out

## デバッグメニュー「イベントを起こす」。一覧はメニューを開いた時点の未発生イベントの並び順
## そのままなので、押された番号で取り直す（並びが変わるのは起こした後）。
func _on_debug_event_requested(index: int) -> void:
	if _controller == null:
		return
	var pending: Array = _controller.state.pending_events()
	if index < 0 or index >= pending.size():
		return
	_controller.force_event(pending[index])
	$HexBoard.refresh()  # 盤は攻撃イベントで作り直す作り＝増援はそれを経ないので明示的に更新する

# --- 中断セーブ／オートセーブ。仕様 → doc/tech/gamesystem.md ---
## 自ターン開始時点の盤を控える（＝セーブが書く中身）。同じ瞬間にオートセーブも上書きする。
## 状態が真実なのでターン・位置・損耗・行動フラグごと再現できる（BattleState.to_dict）。
## 冒険譚の外（セレクトの下敷き）ではオートセーブを書かない＝一覧に行き先の無い盤を並べない。
func _take_turn_snapshot() -> void:
	if _controller == null:
		return
	_turn_snapshot = _controller.state.to_save_diff()
	if _saves == null or _current_campaign_id.is_empty():
		return
	_saves.save_slot(SaveSlots.AUTO, _turn_snapshot, _snapshot_meta())
	_hud.set_load_available(true)

## セーブに添える文脈メタ（一覧の表示材料＋再開に要るステージパス）。
## 冒険譚名・ステージ名は翻訳キーのまま持つ＝言語を変えても一覧がその言語で出る。
func _snapshot_meta() -> Dictionary:
	var campaign := _progress.campaign(_current_campaign_id) if _progress != null else {}
	var stage_title := ""
	for s in campaign.get("stages", []):
		if String(s.get("id", "")) == _current_stage_id:
			stage_title = String(s.get("title", ""))
			break
	return {
		"campaign_id": _current_campaign_id, "stage_id": _current_stage_id,
		"stage_path": _current_stage_path,
		"stage_digest": _current_stage_digest,  # ステージ定義の印（更新検出 → doc/tech/gamesystem.md）
		"campaign_title": String(campaign.get("title", "")), "stage_title": stage_title,
		"turn_number": int(_turn_snapshot.get("turn_number", 0)),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"started_at": _started_at,  # ステージを始めた実時刻＝再開しても所要時間が続く
	}

## システムメニュー「セーブ」＝保存先の枠を選ばせる（書くのは _write_slot）。
func _on_save_requested() -> void:
	if _saves == null or _turn_snapshot.is_empty():
		return
	_slot_intent = "save"
	_slot_panel.open_save(_saves)

## システムメニュー「ロード」＝読み出す枠を選ばせる。盤が出ているので失われる旨の確認を挟む。
func _on_load_requested() -> void:
	if _saves == null or not _saves.has_any():
		return
	_slot_intent = "load"
	_slot_panel.open_load(_saves, tr("ui.save.heading_load"), true)

func _install_slot_panel() -> void:
	_slot_panel = SaveSlotPanel.new()
	_slot_panel.name = "SaveSlotPanel"
	add_child(_slot_panel)
	_slot_panel.slot_chosen.connect(_on_slot_chosen)

func _on_slot_chosen(slot: String) -> void:
	if _slot_intent == "save":
		_write_slot(slot)
	else:
		_load_slot(slot)

## 選ばれた枠へ書く。中身は自ターン開始時点のスナップショット（操作の途中でも頭に戻る）。
func _write_slot(slot: String) -> void:
	_saves.save_slot(slot, _turn_snapshot, _snapshot_meta())
	_hud.set_load_available(true)  # 以後ロード可能に
	$Front/InfoPanel.notify(tr("ui.info.saved"))  # 一時通知は右パネルへ（上端の情報バーは廃止）

## 選ばれた枠から再開：ステージJSONで盤を組み直し、セーブの動的差分を被せる（intro は流さない）。
## 旧版のセーブはここで現行版へ変換してから使う（版と移行 → doc/tech/gamesystem.md）。
## タイトルから来た場合はここでタイトルを畳む＝盤へ直行する。
func _load_slot(slot: String) -> void:
	var data := _saves.load_slot(slot)
	if data.is_empty():
		return
	data = SaveMigration.migrate(data)
	if data.is_empty():
		return  # 変換を持たない版（SaveFile が弾くのでここには来ないはず）
	var meta: Dictionary = data.get("meta", {})
	var state := SaveRestore.restore(String(meta.get("stage_path", "")), data["state"])
	if state == null:
		return  # ステージJSONが無い/読めない＝復元できない（エラーは SaveRestore が出す）
	_current_campaign_id = String(meta.get("campaign_id", ""))
	_current_stage_id = String(meta.get("stage_id", ""))
	_started_at = int(meta.get("started_at", 0))  # 所要時間は測り直さず続きを測る（0＝不明な旧セーブ）
	if _title != null and _title.visible:
		_title_pending = false  # 以後は盤の曲が主＝ざわめきのガードを解く
		_title.close()
	_install_state(state, String(meta.get("stage_path", "")))  # 盤・進行役を保存状態で据える（intro なし）

# --- セレクト画面（presentation/select/）。仕様 → doc/gdd/stage_select.md ---
func _install_select() -> void:
	_select = preload("res://presentation/select/select_screen.gd").new()
	add_child(_select)
	_select.setup(_progress)
	_select.stage_chosen.connect(_on_stage_chosen)
	_select.opened.connect(_on_select_opened)  # ステージ外に戻ったらメニュー曲へ
	_select.title_requested.connect(_on_select_title_requested)  # さらに戻る＝タイトルのメニュー
	_hud.stage_select_requested.connect(_select.open)
	# ここでは開かない。起動直後はタイトル画面が前に出て、扉をくぐった時点で開く（_install_title）。

# --- タイトル画面（presentation/title/）。仕様 → doc/art/menu.md §5・doc/audio/bgm.md ---
## 起動直後は酒場の扉が開いて店内へ入る動画を流す。この間は曲を鳴らさず、店から漏れるざわめき
## （title）だけをこもらせて流し、扉が開くのに合わせてこもりを解く＝音がひらける。
## 入り終わって（or スキップして）メニューが出たところで menu 曲へ渡す（_on_title_menu_shown）。
## 設定画面。開き口はタイトルのメニューと盤のシステムメニューの2つで、同じ1枚を重ねて出す。
## 値の適用と保存はここ（main）が持つ。仕様 → doc/gdd/settings.md
func _install_settings() -> void:
	_settings = SettingsScreen.new()
	_settings.name = "SettingsScreen"
	_settings.locale_chosen.connect(_on_settings_locale_chosen)
	_settings.volume_changed.connect(_apply_volume)
	_settings.volume_settled.connect(_settings_store.set_volume)
	_settings.window_mode_chosen.connect(_on_settings_window_mode_chosen)
	_settings.dialogue_mode_chosen.connect(_settings_store.set_dialogue_when_minimized)
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)
	_hud.settings_requested.connect(_open_settings)

## マニュアル（仕様リファレンス）。開き口はタイトルのメニューだけで、盤の中からは開かない。
## 読むだけで何も変えないので、設定と違い main は値を受け取らない。
func _install_manual() -> void:
	_manual = ManualScreen.new()
	_manual.name = "ManualScreen"
	_manual.closed.connect(_on_manual_closed)
	add_child(_manual)

func _install_title() -> void:
	_title = TitleScreen.new()
	_title.name = "TitleScreen"
	add_child(_title)
	_title.door_opening.connect(_on_title_door_opening)
	_title.menu_shown.connect(_on_title_menu_shown)
	_title.continue_requested.connect(_on_title_continue)
	_title.new_game_requested.connect(_on_title_new_game)
	_title.settings_requested.connect(_on_title_settings)
	_title.manual_requested.connect(_on_title_manual)
	_title.quit_requested.connect(_on_title_quit)
	if _bgm != null:
		_bgm.muffle()  # 曲を張る前に挿す＝鳴り出した瞬間からこもっている
		_bgm.play(BgmDirector.TITLE_TRACK, TITLE_BGM_FADE_IN)
	_title.play(_saves != null and _saves.has_any())

## 扉が開き始めた＝遮っていたものが無くなる。こもりを扉の動きと同じ時間で解く。
func _on_title_door_opening() -> void:
	if _bgm != null:
		_bgm.open_up(TitleScreen.OPEN_SEC)

## メニューが出た＝店に入り切った。ここで初めて旋律が立ち上がる（ざわめき→menu のクロスフェード）。
func _on_title_menu_shown() -> void:
	if _bgm == null:
		return
	_bgm.open_up(0.0)  # スキップで開き切っていない場合の後始末（挿しっぱなしを残さない）
	_bgm.play(BgmDirector.MENU_TRACK, TITLE_MENU_FADE, TITLE_MENU_FADE)

## 冒険の続き＝オートセーブ1枠＋中断5枠の一覧を出し、選ばれた枠から盤へ直行する（セレクトは開かない）。
## タイトルは畳まずに一覧を重ねる＝やめれば元のメニューに戻る。畳むのは枠が決まってから（_load_slot）。
## 項目はセーブが在るときだけ押せるが、その間に消えていれば行き先が無いのでセレクトへ落とす。
func _on_title_continue() -> void:
	if _saves == null or not _saves.has_any():
		_title_pending = false
		_title.close()
		_select.open()
		return
	_slot_intent = "load"
	_slot_panel.open_load(_saves, tr("ui.save.heading_continue"), false)  # 盤はまだ出ていない＝失う物が無いので確認は挟まない

## 新しい冒険譚＝セレクトへ。曲は既に menu なので _on_select_opened の play は空振りする。
func _on_title_new_game() -> void:
	_title_pending = false
	_title.close()
	_select.open()

## 設定＝タイトルに重ねて開く。タイトルは畳まない（暗幕の下に残り、戻れば同じ画が出る）。
## ビルドの刻印だけは伏せる＝設定の戻るボタンと同じ左下の隅に出ているため（doc/tech/build.md）。
func _on_title_settings() -> void:
	_open_settings()

## 設定画面を重ねる（タイトルのメニュー・盤のシステムメニューの両方から）。いまの値を渡して
## 選択中の印とつまみの位置に反映させる。タイトルの上に出すときは刻印を伏せる（左下で戻ると重なる）。
func _open_settings() -> void:
	if _title.visible:
		_title.show_stamp(false)
	var volumes := {}
	for bus in SettingsStore.VOLUME_BUSES:
		volumes[bus] = _settings_store.volume(String(bus))
	_settings.open(_settings_store.locale(), volumes, _settings_store.window_mode(), _settings_store.dialogue_when_minimized())

## 設定を畳み終えた。タイトルへ戻ったなら伏せていた刻印を出し直す（盤へ戻るなら何も無い）。
func _on_settings_closed() -> void:
	if _title.visible:
		_title.show_stamp(true)

## マニュアル＝タイトルに重ねて開く。畳み方も刻印の扱いも設定と同じ（戻るが同じ左下の隅に出る）。
func _on_title_manual() -> void:
	_title.show_stamp(false)
	_manual.open()

func _on_manual_closed() -> void:
	_title.show_stamp(true)

## 言語を選んだ＝その場で適用して保存し、生き続けている画面の文言を貼り直す。
func _on_settings_locale_chosen(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_settings_store.set_locale(locale)
	_refresh_labels()

## 言語が変わったときに文言を貼り直す画面＝起動時に1度だけ作ってセッション中生き続ける物。
## 開くたびに組み直す画面（盤のコマンドメニュー・会話・戦果票）は要らない。
## 一覧の根拠 → doc/tech/i18n.md 言語の切り替え。生き続ける画面を足したらここへも足す。
func _refresh_labels() -> void:
	_settings.refresh_labels()
	_manual.refresh_labels()
	_title.refresh_labels()
	_hud.refresh_labels()
	_refresh_story_menu()  # 目次の見出しは main が訳して渡す＝言語が変われば貼り直す
	_select.refresh_labels()
	_slot_panel.refresh_labels()
	$Front/InfoPanel.refresh_labels()
	_conversation.refresh_labels()

## 設定の音量の系統 -> AudioServer のバス名（default_bus_layout.tres）。
const VOLUME_BUS_NAMES := { "master": "Master", "music": BgmPlayer.BUS, "sfx": SfxPlayer.BUS }

## 音量（0〜100）をバスに当てる。100＝0 dB（素材そのまま）、0＝ミュート。間は振幅に比例させる。
## 起動時の復元と、設定画面でつまみが動くたび（引きずり中も）の両方がここを通る。
func _apply_volume(bus: String, value: int) -> void:
	var idx := AudioServer.get_bus_index(String(VOLUME_BUS_NAMES[bus]))
	if idx < 0:
		push_error("main: 音量のバスが無い: %s" % bus)
		return
	AudioServer.set_bus_mute(idx, value == 0)
	if value > 0:
		AudioServer.set_bus_volume_linear(idx, float(value) / float(SettingsStore.VOLUME_MAX))

## 画面モードを選んだ＝その場で切り替えて保存する。
func _on_settings_window_mode_chosen(mode: String) -> void:
	_settings_store.set_window_mode(mode)
	_apply_window_mode(mode)

## 画面モードを窓に当てる。全画面は枠なしの全画面（排他ではない＝Alt+Tab で崩れない）。
func _apply_window_mode(mode: String) -> void:
	match mode:
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			push_error("main: 知らない画面モード: %s" % mode)

## おわる。決定音（ui_confirm＝実測0.69秒）を鳴らし切ってから落とす＝即 quit だと音が切れる。
func _on_title_quit() -> void:
	await get_tree().create_timer(QUIT_SFX_SEC).timeout
	get_tree().quit()

## 冒険譚選択から戻る＝タイトルのメニューへ。扉と動画は見せ直さない（曲も menu のまま続く）。
## 中断セーブの有無はここで取り直す＝遊んでいる間にセーブしていれば「冒険の続き」が有効になる。
func _on_select_title_requested() -> void:
	_select.close()
	_title.reopen(_saves != null and _saves.has_any())

## セレクトを開いた＝ステージ外の場面。盤（下敷き）は残るがBGMはメニュー曲に戻す。
func _on_select_opened() -> void:
	if _bgm != null:
		_bgm.play(BgmDirector.MENU_TRACK)

func _on_stage_chosen(campaign_id: String, stage_id: String, path: String) -> void:
	_current_campaign_id = campaign_id
	_current_stage_id = stage_id
	load_stage(path)
