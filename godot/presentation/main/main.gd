extends Node2D
## Presentation 層のエントリポイント。
## ステージ(data/stages/*.json)を読み込み、進行役(MatchController)と盤(HexBoard)を組む。
## load_stage(path) が本体＝ステージセレクト（presentation/select/）がこれを駆動する（再呼び出しで切替可）。
## 進行管理（解放判定）は application/campaign_progress.gd。決着時の記録は application/stage_outcome.gd。仕様 → doc/gdd/stage_select.md
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
## いま挑んでいるステージの文脈（冒険譚・ステージ・パス・印・開始時刻）。戦果・セーブ・会話へ渡す
var _context := StageContext.new()
var _progress: CampaignProgress = null
var _outcome: StageOutcome = null  # 決着時の記録の門番（application 層）。presentation は状態を直接書き換えない
var _chronicle_store: ChronicleStore = null  # クロニクル永続化（user://chronicle.json）
var _chronicle: ChronicleService = null  # クロニクルの記録（盤に出た駒・発動したレシピを溜め、盤を離れるときに書く）
var _roster_store: RosterStore = null  # 戦力継承(carryover)のスナップショット永続化。冒険譚IDで引く
var _save: SaveCoordinator = null  # 中断セーブ／オートセーブの段取り（枠・一覧・復元）。仕様 → doc/tech/gamesystem.md
var _save_panel: SaveSlotPanel = null  # 枠一覧（セーブ/ロード共通）。盤を覆う画面の一つとして表示を見張る
var _select: SelectScreen = null
var _title: TitleScreen = null  # 起動時のタイトル画面（酒場の扉）。閉じたらセレクトを開く
var _settings: SettingsScreen = null  # 設定画面（タイトルに重ねて開く）。仕様 → doc/gdd/settings.md
var _manual: ManualScreen = null  # マニュアル（タイトルに重ねて開く）。仕様 → doc/gdd/manual.md
var _settings_store: SettingsStore = null  # 設定値（user://settings.json）。触るのはここだけ
## タイトルを抜けるまで true。下敷きステージ（セレクトの背景）の曲がタイトルのざわめきを
## 上書きしないためのガード。下敷きの曲は盤が描き切ってから鳴る＝タイトルより後に割り込む。
var _title_pending := true
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
var _tally := StageTally.new()  # 戦果の集計（開始兵力・ランク・所要時間）と戦果票の行
var _bgm: BgmPlayer = null  # BGM の再生（永続・旧曲フェードアウト＋新曲は頭出し）。曲の決定は _bgm_director
var _bgm_director: BgmDirector = null  # 場面→曲の決定（application）。ステージ/既定のフォールバック
var _sfx: SfxPlayer = null  # 効果音の再生（永続・プール）。各画面は SfxPlayer.play_event で鳴らす
var _story: StoryDirector = null  # 会話の進行（intro／イベント／outro／読み直し）と経験した会話の記録

## 設定を読んで言語を決める。_ready ではなく _init で行うのは、main.tscn の子（InfoPanel が
## 抱える戦闘レポートのタブ）が親の _ready より先に文言を焼くため＝_ready で決めると起動時だけ
## その画面が別の言語で組まれる。仕様 → doc/tech/gamesystem.md §設定
func _init() -> void:
	_settings_store = SettingsStore.new()
	SettingsApplier.apply_locale(_settings_store.locale())

func _ready() -> void:
	# 刻印はタイトル画面にも出すが、ログの1行目にも置く＝報告にログが添えられたとき版が分かる。
	print("Senaris booted. build=%s" % BuildInfo.stamp())
	# 音量と画面モードは設定から起こす。曲が鳴り出す（_install_bgm）より前に当てる。
	for bus in SettingsStore.VOLUME_BUSES:
		SettingsApplier.apply_volume(String(bus), _settings_store.volume(String(bus)))
	SettingsApplier.apply_window_mode(_settings_store.window_mode())
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
	# 会話板も同じ位置に出る（板は1枚）＝ _install_conversation が同じ設定から置く。
	if _settings_store.has_info_panel_position():
		$Front/InfoPanel.position = _settings_store.info_panel_position()
	$Front/InfoPanel.moved.connect(_on_panel_moved)
	# 盤エリアは板が塞いでいない側＝畳む／開く／動かすのたびに押し直す（設定へ書いた後に読む）。
	$Front/InfoPanel.minimized_changed.connect(func(_v: bool) -> void: _sync_board_area())
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
	_chronicle_store = ChronicleStore.new()  # クロニクル（user://chronicle.json）
	_chronicle = ChronicleService.new(_chronicle_store)  # 記録 API（盤を離れるときに書く）
	_outcome = StageOutcome.new(_progress, _roster_store, _chronicle)  # 決着時の記録の門番
	_install_story()  # 会話の進行。盤・HUD・暗幕・会話パネル・進行記録が揃ってから
	_install_save()  # 中断セーブ／オートセーブ＋枠一覧（HUD・タイトルの両方から開く）
	_hud.set_load_available(_save.has_any())  # 起動時にセーブが1枠でも在ればロードを有効化
	load_stage("res://data/stages/_boot/underlay.json")  # セレクトの下敷き（盤を空にしない）。選択で差し替わる
	_install_select()  # 生成と配線だけ。開くのはタイトルで扉をくぐってから
	_install_settings()  # 設定画面。タイトルから開くので、タイトルより前に用意
	_install_manual()  # マニュアル。同上
	_install_chronicle()  # クロニクル。同上
	_install_title()  # 起動直後はタイトル（酒場の扉）。閉じたら _select.open()
	_install_board_cover()  # 盤を覆う画面が全部揃ってから＝どれかが出ている間は盤に入力を通さない

## いま挑んでいる冒険譚の名簿（carryover）。冒険譚外（デバッグ・下敷き）では空。
## ステージ配置（player の actor 突き合わせ）と会話の when 評価の両方がこれを見る。詳細 → doc/gdd/campaigns.md
func _load_roster() -> Array:
	if _roster_store == null or _context.campaign_id.is_empty():
		return []
	return _roster_store.load_roster(_context.campaign_id)

## ステージ(JSON)を読み込み、マッチ（最小AI込み）を組み直す。再呼び出しで切替できる。
func load_stage(path: String) -> void:
	# carryover: 冒険譚の名簿があれば渡す。突き合う actor の無い fresh ステージでは無視される。
	var state := StageLoader.load_file(path, _load_roster())
	if state == null:
		push_error("main: ステージを読めない: %s" % path)
		return
	# 所要時間の起点。ここから勝敗が決まるまでを測る（intro 会話も含む＝ステージを始めた時刻）。
	# 実時刻で持ち、中断セーブにも書く＝閉じていた間も含めた「クリアまでにかかった時間」になる。
	_context.started_at = int(Time.get_unix_time_from_system())
	_install_state(state, path)
	_story.on_stage_started(_load_roster())  # 開始時の在籍 actor を控える＝あとで当時の顔ぶれで会話を組み直せる
	_story.maybe_start_intro()  # intro 会話があれば盤をロックして先に流す（新規開始のみ）

## 与えられた BattleState を盤・進行役に据える（新規ロードと中断セーブ復元で共有）。
## intro 会話の再生は含めない＝新規開始（load_stage）だけが呼ぶ。詳細 → doc/tech/gamesystem.md
func _install_state(state: BattleState, path: String) -> void:
	_context.stage_path = path  # システムメニューのリスタート用
	_context.stage_digest = StageDigest.of_file(path)  # ステージ定義の印＝セーブの meta へ（更新検出用）
	_victory_overlay = false  # 前ステージの完走演出を持ち越さない
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
	# 会話（intro/outro・イベント）と目次の見出しを presentation へ（案P・名簿で when を評価）。
	# 目次はステージごと＝新規ロードでも中断セーブ復元でも貼り直す。
	_story.set_stage(StageLoader.load_dialogue(path, _load_roster()), StageLoader.load_event_talks(path), _context, _controller)
	var terrain_skins := StageLoader.load_terrain_skins(path)  # 見た目差分(座標→skin)は presentation へ（案P）
	# 外周(margin)＝盤の外側1周ぶんの地形。盤には入らず、縁の接続タイルの向き決めにだけ使う。
	$HexBoard.bind(state, _controller, _skins, terrain_skins, StageLoader.load_margin_terrain(path), StageLoader.load_height_overrides(path))
	_combat_scene.bind_terrain_skins(terrain_skins)  # 演出の地面も同じ見た目差分から組む
	_combat_scene.bind_state(state)  # 重ね絵を拠点の持ち主で選ぶ（占領で絵が変わる）
	var backdrop := StageLoader.load_backdrop(path)  # 水平線から上に敷く1枚（空・岩壁）。空文字＝引かない
	_combat_scene.bind_backdrop(backdrop)
	var haze := StageLoader.load_haze(path)  # 奥の靄の濃さ（ステージが持つ・必須）
	_combat_scene.bind_haze(haze)
	var actor_lineup := String(_campaign().get("actor_lineup", ""))
	_combat_scene.bind_actor_lineup(actor_lineup)  # 一行を1体で描くか（冒険譚の宣言）
	_skill_scene.bind_terrain_skins(terrain_skins)  # スキルの演出も同じ地面を組む
	_skill_scene.bind_state(state)
	_skill_scene.bind_backdrop(backdrop)
	_skill_scene.bind_haze(haze)
	_skill_scene.bind_actor_lineup(actor_lineup)
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
	_controller.dialogue_pace = _story.await_dialogue  # 敵ターンの占領で入る会話は読み終えるまで待つ
	_controller.turn_changed.connect(_on_turn_changed)
	_controller.event_fired.connect(_story.on_event_fired)  # 台本があれば会話を挟む
	_controller.event_fired.connect(_on_event_fired_chronicle)  # 増援の駒をクロニクルに記録
	_controller.battle_finished.connect(_on_battle_finished)
	_controller.formation_resolved.connect(_on_formation_resolved)
	_controller.unit_deployed.connect(_on_unit_deployed_chronicle)  # 拠点から出撃した駒をクロニクルに記録
	_apply_emblem()  # ターン板の左右（冒険譚の代表ユニット）。ステージが変われば差し替わる
	_update_turn_plate(state.current_team, state.turn_number)
	_hud.set_player_turn(state.current_team == 0)  # ターン終了ボタンの有効/無効
	_update_aura()  # 加護の光（中断セーブ復元で効果が残っていることがある）
	_tally.begin(state, path, _context)  # 戦果票の基準（開始時の兵力・ランクの閾値）を控える
	_chronicle.begin(_context.campaign_id, state)  # クロニクル＝盤の初期配置を走査して全駒を記録
	if state.current_team == 0:
		_save.snapshot(state, _context, _campaign())  # ステージの頭＝自ターン開始時点。ここでオートセーブも入る
	_start_stage_bgm_when_drawn(path)  # 盤が出てから鳴らす（新規ロード・中断セーブ復元で共通）

## 戦闘結果 → 演出シーンへ。この一撃で勝ちが確定していれば（domain は解決済み＝演出より先に
## 分かる）、とどめの演出（スロー＋寄り＋白フラッシュへの繋ぎ）として見せる。
## 仕様 → doc/gdd/uiux.md 決着の合図
func _on_combat_resolved(result: AttackResult) -> void:
	if _win_decided():
		_finisher_route = "combat"
		_combat_scene.arm_finisher()
	_combat_scene.play(result)

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
		_save.snapshot(_controller.state, _context, _campaign())  # 自ターンの頭を控える＝以後のセーブはここへ戻る／オートセーブも入る

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
func _on_formation_resolved(result: SkillResult) -> void:
	# 発動と同時にスキルレポート（カットイン・着弾の間も右パネルに出ている）。盤側の選択解除
	# （clear）が先に走る＝HexBoard.bind の接続がこのハンドラより先。仕様 → doc/tech/combat_scene.md
	$Front/InfoPanel.show_skill_report(result)
	_chronicle.note_recipe(result.recipe)  # クロニクルにレシピを記録
	# このスキルで勝ちが確定していれば、盤の着弾をとどめ（スロー＋カメラ寄せ）として見せる。
	if _win_decided():
		_finisher_route = "formation"
		$HexBoard.arm_finisher_impact()
	var recipe := result.recipe
	if Formation.is_unit_skill(recipe):
		# 音はここでは鳴らさない。演出シーンの一撃に合わせる（SkillScene._cast）＝ため 0.8 秒ぶん
		# 先に鳴ってしまうため。陣形は発動と着弾で2音あるので頭で鳴らしてよい。
		_update_aura()
		$HexBoard.play_formation_impact(result)  # 効果対象が1体＝着弾があれば盤にも出す
		if _skill_scene != null and result.cast != null:
			_skill_scene.play(result.cast)
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

## クロニクル：拠点から出撃した駒を記録する。自軍の出撃も敵の拠点配備も含む。
func _on_unit_deployed_chronicle(unit_id: int, _base_hex: Vector2i, _to: Vector2i) -> void:
	if _controller == null:
		return
	var unit := _controller.state.unit_by_id(unit_id)
	if unit != null:
		_chronicle.note_unit(unit)

## クロニクル：イベントで盤に出た増援の駒を記録する。info["units"] は配置された駒の id の配列。
func _on_event_fired_chronicle(info: Dictionary) -> void:
	if _controller == null:
		return
	var ids: Array = info.get("units", [])
	for uid in ids:
		var unit := _controller.state.unit_by_id(int(uid))
		if unit != null:
			_chronicle.note_unit(unit)

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
	_conversation.reset_position()  # 板は1枚＝会話の最中でも両方戻る
	_settings_store.clear_info_panel_position()
	_sync_board_area()  # 既定の場所へ戻した＝また板が右ボックスを塞ぐ

## 板（情報板か会話板のどちらか）を掴んで動かした。板は1枚なので、もう一方も同じ場所へ写し、
## 位置を設定に書き、盤エリアを押し直す。仕様 → doc/gdd/uiux.md 移動
func _on_panel_moved(pos: Vector2) -> void:
	$Front/InfoPanel.position = pos
	_conversation.position = pos
	_settings_store.set_info_panel_position(pos)
	_sync_board_area()

## 盤エリア（→ doc/gdd/uiux.md 盤エリア）は情報板が塞いでいない側。板の状態を知っているのは
## ここだけなので、変わるたびに UiLayout へ押す。カメラはここでは動かさない＝畳む・開く・動かすで
## 見ている場所を失わせない（合わせ直すのはステージを開いたときだけ）。
func _sync_board_area() -> void:
	_apply_board_area(_conversation != null and _conversation.visible)

## イベントの会話板をこれから出す（story_director.talk_opening）。板が出る前にカメラ寄せが走るので、
## 出る予定の板を先に塞いでいる扱いにする。板が出れば visibility_changed で同じ値に押し直される。
func _on_talk_opening() -> void:
	_apply_board_area(true)

## talking＝会話板が出ている（または出る直前）。
func _apply_board_area(talking: bool) -> void:
	var panel: UnitInfoPanel = $Front/InfoPanel
	# 板は1枚＝情報板を畳んでいても、「会話のみ表示する」で会話板が出ている間はその板が塞いでいる
	# （さもないと完走イラスト等の演出が画面全体に広がり、読ませたい会話板を覆う）。
	var open: bool = talking or not panel.is_minimized()
	var holds: bool = open and not _settings_store.has_info_panel_position()
	UiLayout.set_panel_holds_right_box(holds)
	# カメラは板がどこにあっても裏を避ける＝いま出ている板の矩形をそのまま渡す（何も出ていなければ空）。
	var rect := Rect2()
	if talking:
		rect = Rect2(_conversation.position, _conversation.size)
	elif not panel.is_minimized():
		rect = Rect2(panel.position, panel.size)
	UiLayout.set_panel_rect(rect)

## 残りターン（増援の予告）を情報パネルへ流し込む。未発生のイベントが無ければ行が隠れる。
## 仕様 → doc/gdd/uiux.md 残りターン
func _update_event() -> void:
	$Front/InfoPanel.set_event(_controller.state.next_event() if _controller != null else {})

## いま挑んでいる冒険譚のマニフェスト（CampaignProgress.campaign）。
## セレクトを経ないステージ（デバッグ直起動・起動時の下敷き）は無い＝空辞書。
func _campaign() -> Dictionary:
	if _progress == null or not _context.in_campaign():
		return {}
	return _progress.campaign(_context.campaign_id)

## 冒険譚マニフェストの emblem（代表ユニットの skin_id）。ターン板とバナーが使う。
func _emblem() -> Dictionary:
	return _campaign().get("emblem", {})

## ターン板の左右に出す代表ユニット。指定が無ければ枠を出さない。
func _apply_emblem() -> void:
	var emblem := _emblem()
	_turn_plate.set_emblem(_skins, String(emblem.get("ally", "")), String(emblem.get("enemy", "")))

## 決着の告知は戦果票（ResultBanner）が担う＝ここでは後続の演出だけ進める。
## 記録（クリア・ランク・所要時間・名簿・経験した会話）は application/stage_outcome.gd に委ねる。
func _on_battle_finished(outcome: int) -> void:
	if _turn_banner != null:
		_turn_banner.dismiss()  # ターン制限切れはターンの切り替わりと同時＝戦果票と重ねない
	if _formation_cutin != null:
		_formation_cutin.dismiss()  # 陣形でボスを倒した＝カットインの最中に決着しうる
	# クロニクルは盤を離れるときにまとめて書く。決着＝盤を離れる。
	_chronicle.flush()
	# 記録は application 層（StageOutcome）に委ねる。ランク・所要時間・自己ベストも向こうで採る。
	var result := _outcome.battle_finished(
			_context.campaign_id, _context.stage_id, outcome,
			_controller.state if _controller != null else null,
			_context.started_at, _context.stage_path, _load_roster())
	var rank: String = result["rank"]
	_tally.set_result(int(result["elapsed"]), int(result["best_time"]))
	match outcome:
		BattleState.PLAYER_WIN:
			if _context.in_campaign():
				# 戦闘後の会話は「クリア後の名簿」で条件を見る＝この回で仲間になった駒が喋れる。
				var updated: Array = result["updated_roster"]
				if not updated.is_empty():
					_story.set_dialogue(StageLoader.load_dialogue(_context.stage_path, updated))
				_story.refresh_menu()
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
		var outro := _story.outro_lines()
		if not outro.is_empty() and _story.shows_dialogue():
			# 冒険譚を完走した回だけ、盤の代わりに勝利イラストを敷いて outro を読ませる
			# （絵を見せ終えてから会話、ではなく絵の前で会話＝フィナーレを一続きにする）。
			# 順序は会話板→絵。絵は敷く瞬間の盤エリアに収まるので、会話板を先に出して
			# 盤エリアを右ボックスの左へ押してから敷く（畳んでいて会話だけ出す設定で、絵が会話板を覆わない）。
			var show_victory := _should_show_victory()
			var label := "ui.talk.next_stage" if not _next_playable_stage().is_empty() else "ui.talk.close"
			_story.start_outro(outro, label)  # 読了/スキップで次ステージ or セレクトへ（_on_story_closed）
			if show_victory:
				_victory_overlay = true
				_victory_screen.play_over_board(_victory_path())
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
		_result.play(_tally.title(_campaign()), stamp_text, win, _tally.rows(win), caption,
			tr("ui.result.note_weapons"), true)
		_flash.fall()
	else:
		# 敗北の票には行き先を2つ置く＝盤に戻らず再挑戦かセレクトへ進める（doc/gdd/uiux.md 決着の演出）。
		_result.play(_tally.title(_campaign()), stamp_text, win, _tally.rows(win), caption,
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

# --- 会話（ステージ前後のチャット風シーン）。presentation/ui/conversation_panel.gd ---
func _install_conversation() -> void:
	# パネルは前面パネル層 $Front（層45）＝暗転で沈まない側。暗幕は共通基盤（_screen）に頼む。
	_conversation = preload("res://presentation/ui/conversation_panel.gd").new()
	# InfoPanel と同じ箱・同じ位置に重ねる（会話中は InfoPanel を隠す）。板は1枚＝動かしてあれば同じ先へ。
	_conversation.size = UiLayout.RIGHT_BOX.size
	_conversation.position = $Front/InfoPanel.position
	_conversation.moved.connect(_on_panel_moved)
	# 会話板の出入りでも盤エリアを押し直す＝畳んでいて会話だけ出す設定のとき、会話中は板が塞ぐ側になる。
	_conversation.visibility_changed.connect(_sync_board_area)
	_conversation.bind(_skins)
	$Front.add_child(_conversation)

## 会話の進行（presentation/main/story_director.gd）。協力者を渡し、会話の終わりを受けて次へ進める。
func _install_story() -> void:
	_story = StoryDirector.new()
	_story.bind($HexBoard, $Front/InfoPanel, _hud, _screen, _conversation, _turn_banner, _progress, _settings_store, _outcome)
	_story.closed.connect(_on_story_closed)
	_story.talk_opening.connect(_on_talk_opening)

## 会話終了（読了 or スキップ）。intro・event→戦闘へ戻る、outro→次ステージ or セレクトへ。
## review（読み直し）は盤を何も進めない＝director が割り込む前の状態へ戻して終わる。
func _on_story_closed(phase: String) -> void:
	match phase:
		"intro", "event":  # 戦闘へ戻る（開幕・途中の割り込みで同じ）
			if _controller != null:
				_hud.set_player_turn(_controller.state.current_team == 0)
		"outro":
			if _victory_overlay:
				_victory_screen.dismiss()  # 絵は会話と一緒に退く（全画面では出し直さない）
			_advance_or_select()  # 次ステージがあれば進む・無ければセレクト

## クリア後の遷移先：次に遊べるステージがあれば進む（テンポ優先）。無ければセレクト。
## 判断は application（CampaignProgress.next_playable_stage）＝ここは画面の切り替えだけ。
## controller を作り直す load_stage は決着シグナルの処理中に呼ばれうるので call_deferred で安全に。
func _advance_or_select() -> void:
	var nxt := _next_playable_stage()
	if not nxt.is_empty():
		_context.stage_id = nxt["id"]  # 冒険譚は同じまま＝次ステージのクリア記録が正しく付く
		call_deferred("load_stage", String(nxt["path"]))
		return
	# 次が無い＝セレクトへ戻る。ただしキャンペーン完走（最終ステージ勝利）なら勝利イラストを1枚挟む。
	if _should_show_victory():
		_victory_screen.finished.connect(_select.open, CONNECT_ONE_SHOT)
		_victory_screen.play(_victory_path())
	else:
		_select.open()

func _next_playable_stage() -> Dictionary:
	return _progress.next_playable_stage(_context.campaign_id, _context.stage_id)

## いまクリアしたのがキャンペーン完走（＝非デバッグ冒険譚の最終ステージ）で、勝利イラストが在るか。
## 最終判定は素の next_stage（マニフェスト順で次が無い）を使う＝next_playable は locked でも空になり不可。
func _should_show_victory() -> bool:
	if _victory_overlay:
		return false  # outro 会話に重ねて出し切った＝会話後に全画面で出し直さない
	if _context.campaign_id.is_empty():
		return false
	var c := _progress.campaign(_context.campaign_id)
	if c.is_empty() or c["debug"]:
		return false
	if not _progress.next_stage(_context.campaign_id, _context.stage_id).is_empty():
		return false  # まだ最終ステージではない
	return not _victory_path().is_empty()

## 現冒険譚の勝利イラストのパス（連番バリアントがあればランダムに1枚・無ければ ""）。
func _victory_path() -> String:
	var c := _progress.campaign(_context.campaign_id)
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
	if _context.stage_path != path:
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
	if not _context.stage_path.is_empty():
		_chronicle.flush()  # 盤を離れる＝クロニクルを書き出す
		load_stage(_context.stage_path)

## デバッグメニュー「敵を殲滅」。controller はステージごとに作り直すので、押された時点の
## controller へ流す（結線の張り替えをしない）。決着後・盤なしでは controller 側が弾く。
func _on_wipe_enemies_requested() -> void:
	if _controller == null:
		return
	_controller.wipe_enemies()
	$HexBoard.refresh()  # 盤は攻撃イベントで作り直す作り＝殲滅はそれを経ないので明示的に更新する

## デバッグメニュー「イベントを起こす」に並べる未発生イベントの表示名。引き金・陣営・中身が
## 一目で分かればよい＝翻訳キーは切らず直書き（デバッグ区画の流儀。doc/tech/i18n.md）。
## 自ターンで決着前のときだけ並べる。敵ターン中は会話が流れない門（StoryDirector.on_event_fired）があり、
## 会話の最中は盤を止めている＝どちらも起こしても見えないため。
func _debug_event_labels() -> PackedStringArray:
	var out := PackedStringArray()
	if _controller == null or _controller.is_ai_turn() or _controller.state.is_over():
		return out
	if _story.is_talking():
		return out
	for e in _controller.state.pending_events():
		var side := "味方" if e.team == 0 else "敵"
		var trigger := "T%d" % e.turn
		if e.is_capture():
			var off := Hex.axial_to_offset(e.hex)
			trigger = "占領(%d,%d)" % [off.x, off.y]
		var body := "会話" if e.units.is_empty() else "増援%d" % e.units.size()
		var key := e.dialogue
		if key.is_empty():
			key = e.label
		out.append("%s %s %s%s" % [trigger, side, body, "" if key.is_empty() else " " + key])
	return out

## デバッグメニュー「イベントを起こす」。一覧はメニューを開いた時点の未発生イベントの並び順
## そのままなので、押された番号で取り直す（並びが変わるのは起こした後）。
func _on_debug_event_requested(index: int) -> void:
	if _controller == null:
		return
	var pending := _controller.state.pending_events()
	if index < 0 or index >= pending.size():
		return
	_controller.force_event(pending[index])  # 盤の貼り直しと登場の演出は StoryDirector.on_event_fired

# --- 中断セーブ／オートセーブ（段取り＝presentation/main/save_coordinator.gd）。仕様 → doc/tech/gamesystem.md ---
func _install_save() -> void:
	_save = SaveCoordinator.new()
	_save_panel = _save.install_slot_panel()  # 枠一覧（セーブ/ロード共通）
	add_child(_save_panel)
	_save.saved.connect(_on_saved)
	_save.restored.connect(_on_save_restored)

## システムメニュー「セーブ」＝保存先の枠を選ばせる。
func _on_save_requested() -> void:
	_save.open_save()

## システムメニュー「ロード」＝読み出す枠を選ばせる。盤が出ているので失われる旨の確認を挟む。
func _on_load_requested() -> void:
	_save.open_load(tr("ui.save.heading_load"), true)

## 枠へ書いた（オートセーブも）＝以後ロード可能に。手で書いた回だけ知らせる。
func _on_saved(slot: String) -> void:
	_hud.set_load_available(true)
	if slot != SaveSlots.AUTO:
		$Front/InfoPanel.notify(tr("ui.info.saved"))  # 一時通知は右パネルへ（上端の情報バーは廃止）

## 枠から盤が組み上がった＝文脈を差し替えて盤・進行役に据える（intro は流さない）。
## タイトルから来た場合はここでタイトルを畳む＝盤へ直行する。
func _on_save_restored(state: BattleState, path: String, meta: Dictionary) -> void:
	_chronicle.flush()  # 前の盤を離れる＝クロニクルを書き出す（タイトルから来た初回は空振り）
	_context.campaign_id = String(meta.get("campaign_id", ""))
	_context.stage_id = String(meta.get("stage_id", ""))
	_context.started_at = int(meta.get("started_at", 0))  # 所要時間は測り直さず続きを測る（0＝不明な旧セーブ）
	if _title != null and _title.visible:
		_title_pending = false  # 以後は盤の曲が主＝ざわめきのガードを解く
		_title.close()
	_install_state(state, path)  # 盤・進行役を保存状態で据える（intro なし）

## 盤を覆う画面（タイトル・セレクト・設定・マニュアル・セーブ枠一覧）のどれかが出ている間は、盤に入力を
## 通さない（doc/gdd/uiux.md デバイス別 操作表）。各画面の根はマウスを止めるが鍵盤は止まらず盤へ落ちる
## ＝Esc でシステムメニューが開き、Enter でターンが終わり、Space で情報板が畳まれる。
## 画面ごとに鍵盤を食う作りにはしない＝重なり順（設定はタイトルの上）に依存して Esc の取り合いになる。
func _install_board_cover() -> void:
	for screen in [_title, _select, _settings, _manual, _chronicle_screen, _save_panel]:
		screen.visibility_changed.connect(_sync_board_cover)
	_sync_board_cover()

func _sync_board_cover() -> void:
	$HexBoard.set_covered(_title.visible or _select.visible or _settings.visible
			or _manual.visible or _chronicle_screen.visible or _save_panel.visible)

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
## 値の保存はここ（main）、実機への適用は SettingsApplier。仕様 → doc/gdd/settings.md
func _install_settings() -> void:
	_settings = SettingsScreen.new()
	_settings.name = "SettingsScreen"
	_settings.locale_chosen.connect(_on_settings_locale_chosen)
	_settings.volume_changed.connect(SettingsApplier.apply_volume)
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

## クロニクル（冒険の記録）。開き口はタイトルのメニューだけ。仕様 → doc/gdd/chronicle.md
var _chronicle_screen: ChronicleScreen = null
func _install_chronicle() -> void:
	_chronicle_screen = ChronicleScreen.new()
	_chronicle_screen.name = "ChronicleScreen"
	_chronicle_screen.closed.connect(_on_chronicle_closed)
	add_child(_chronicle_screen)

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
	_title.chronicle_requested.connect(_on_title_chronicle)
	_title.quit_requested.connect(_on_title_quit)
	if _bgm != null:
		_bgm.muffle()  # 曲を張る前に挿す＝鳴り出した瞬間からこもっている
		_bgm.play(BgmDirector.TITLE_TRACK, TITLE_BGM_FADE_IN)
	_title.play(_save.has_any())

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
## タイトルは畳まずに一覧を重ねる＝やめれば元のメニューに戻る。畳むのは枠が決まってから（_on_save_restored）。
## 項目はセーブが在るときだけ押せるが、その間に消えていれば行き先が無いのでセレクトへ落とす。
func _on_title_continue() -> void:
	if not _save.has_any():
		_title_pending = false
		_title.close()
		_select.open()
		return
	_save.open_load(tr("ui.save.heading_continue"), false)  # 盤はまだ出ていない＝失う物が無いので確認は挟まない

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

## クロニクル＝タイトルに重ねて開く。マニュアルと同じ扱い。仕様 → doc/gdd/chronicle.md
func _on_title_chronicle() -> void:
	_title.show_stamp(false)
	_chronicle_screen.open(_chronicle_store, _progress)

func _on_chronicle_closed() -> void:
	_title.show_stamp(true)

## 言語を選んだ＝その場で適用して保存し、生き続けている画面の文言を貼り直す。
func _on_settings_locale_chosen(locale: String) -> void:
	SettingsApplier.apply_locale(locale)
	_settings_store.set_locale(locale)
	_refresh_labels()

## 言語が変わったときに文言を貼り直す画面＝起動時に1度だけ作ってセッション中生き続ける物。
## 開くたびに組み直す画面（盤のコマンドメニュー・会話・戦果票）は要らない。
## 一覧の根拠 → doc/tech/i18n.md 言語の切り替え。生き続ける画面を足したらここへも足す。
func _refresh_labels() -> void:
	_settings.refresh_labels()
	_manual.refresh_labels()
	_chronicle_screen.refresh_labels()
	_title.refresh_labels()
	_hud.refresh_labels()
	_story.refresh_menu()  # 目次の見出しは director が訳して渡す＝言語が変われば貼り直す
	_select.refresh_labels()
	_save.refresh_labels()
	$Front/InfoPanel.refresh_labels()
	_conversation.refresh_labels()

## 画面モードを選んだ＝その場で切り替えて保存する。
func _on_settings_window_mode_chosen(mode: String) -> void:
	_settings_store.set_window_mode(mode)
	SettingsApplier.apply_window_mode(mode)

## おわる。決定音（ui_confirm＝実測0.69秒）を鳴らし切ってから落とす＝即 quit だと音が切れる。
func _on_title_quit() -> void:
	await get_tree().create_timer(QUIT_SFX_SEC).timeout
	get_tree().quit()

## 冒険譚選択から戻る＝タイトルのメニューへ。扉と動画は見せ直さない（曲も menu のまま続く）。
## 中断セーブの有無はここで取り直す＝遊んでいる間にセーブしていれば「冒険の続き」が有効になる。
func _on_select_title_requested() -> void:
	_select.close()
	_title.reopen(_save.has_any())

## セレクトを開いた＝ステージ外の場面。盤（下敷き）は残るがBGMはメニュー曲に戻す。
func _on_select_opened() -> void:
	if _bgm != null:
		_bgm.play(BgmDirector.MENU_TRACK)

func _on_stage_chosen(campaign_id: String, stage_id: String, path: String) -> void:
	_context.campaign_id = campaign_id
	_context.stage_id = stage_id
	load_stage(path)
