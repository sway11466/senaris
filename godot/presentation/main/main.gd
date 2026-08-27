extends Node2D
## Presentation 層のエントリポイント。
## ステージ(data/stages/*.json)を読み込み、進行役(MatchController)と盤(HexBoard)を組む。
## load_stage(path) が本体＝ステージセレクト（presentation/select/）がこれを駆動する（再呼び出しで切替可）。
## 進行管理（解放判定・クリア記録）は application/campaign_progress.gd。仕様 → doc/gdd/stage_select.md
## デバッグ用ステージは data/stages/debug-*/（機能別の debug:true 冒険譚としてセレクトに出る）。一覧 → doc/tech/debug-stages.md

const BOARD_LOGO_PATH := "res://assets/ui/logo.png"  # 盤の右上に常設するタイトルロゴ

var _skins := {}
var _ai_presets := {}  # 特性表（data/ai/ai.json）。特性id -> パラメーター辞書（既定値）
var _controller: MatchController = null
var _hud: Hud = null
var _turn_plate: TurnPlate = null  # ターン板（永続・盤エリア上端中央）。仕様 → doc/gdd/uiux.md
var _event_plate: EventPlate = null  # 残りターン板（右ボックスの直下）。仕様 → doc/gdd/uiux.md
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
var _progress: CampaignProgress = null
var _roster_store: RosterStore = null  # 戦力継承(carryover)のスナップショット永続化。冒険譚IDで引く
var _saves: SaveSlots = null  # 中断セーブ5枠＋オートセーブ1枠。user://save_1.json … save_auto.json
var _slot_panel: SaveSlotPanel = null  # 枠一覧（セーブ/ロード共通・盤とタイトルの両方から出す）
var _slot_intent := ""  # 枠一覧をどちらの用で開いたか（"save"/"load"）＝選ばれた枠の使い道
## 自ターン開始時点の盤（BattleState.to_dict）。中断セーブ・オートセーブはこれを書く
## ＝操作の途中でセーブしてもターンの頭に戻る（実質的なアンドゥ）。仕様 → doc/tech/gamesystem.md
var _turn_snapshot := {}
var _select: SelectScreen = null
var _title: TitleScreen = null  # 起動時のタイトル画面（酒場の扉）。閉じたらセレクトを開く
var _settings: SettingsScreen = null  # 設定画面（タイトルに重ねて開く）。仕様 → doc/gdd/settings.md
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
var _start_ally := 0   # ステージ開始時の自軍数（戦果票の「生存 n/N」の分母）
var _start_enemy := 0  # ステージ開始時の敵数（同・「撃破」の基準）
var _rank_data := {}   # ステージ JSON の "rank"（評価ランクの閾値）。空＝ランクなし
var _bgm: BgmPlayer = null  # BGM の再生（永続・旧曲フェードアウト＋新曲は頭出し）。曲の決定は _bgm_director
var _bgm_director: BgmDirector = null  # 場面→曲の決定（application）。ステージ/既定のフォールバック
var _sfx: SfxPlayer = null  # 効果音の再生（永続・プール）。各画面は SfxPlayer.play_event で鳴らす
var _dialogue := { "intro": [], "outro": [] }  # 現ステージの会話（台本キー→行。presentation専用・案P）
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
	_skins = SkinCatalog.load_standard()
	_ai_presets = AiCatalog.load_default()
	# HexBoard と InfoPanel は永続。選択→情報パネルの配線は1回だけ（controller 非依存）。
	# InfoPanel は前面パネル層 $Front（層45）＝暗転（ScreenLighting・層40）で沈まない側。
	$HexBoard.selection_changed.connect($Front/InfoPanel.show_unit)
	$HexBoard.tile_inspected.connect($Front/InfoPanel.show_terrain)  # 空きマス選択→地形/拠点情報
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
	_install_bgm()  # 永続BGM。load_stage が曲を張り替えるので、それより前に用意
	_install_sfx()  # 永続SFX。盤・セレクトから静的に鳴らすので、それらより前に用意
	_install_hud()  # 永続HUD（ターン終了ボタン＋システムメニュー）。load_stage より前に用意
	_install_turn_plate()  # 永続のターン板（盤エリア上端中央）。load_stage がターン・代表ユニットを流し込む
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
	_install_state(state, path)
	_maybe_start_intro()  # intro 会話があれば盤をロックして先に流す（新規開始のみ）

## 与えられた BattleState を盤・進行役に据える（新規ロードと中断セーブ復元で共有）。
## intro 会話の再生は含めない＝新規開始（load_stage）だけが呼ぶ。詳細 → doc/tech/gamesystem.md
func _install_state(state: BattleState, path: String) -> void:
	_current_stage_path = path  # システムメニューのリスタート用
	_victory_overlay = false  # 前ステージの完走演出を持ち越さない
	_dialogue = StageLoader.load_dialogue(path, _load_roster())  # 会話（intro/outro）を presentation へ（案P・名簿で when を評価）
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
	# controller は作り直すので、controller 由来のシグナルは load ごとに繋ぐ。
	_controller.combat_resolved.connect($Front/InfoPanel.show_combat)
	_controller.combat_resolved.connect(_combat_scene.play)  # 演出シーン（結果＝シーン／根拠＝右パネル）
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
	_count_start_forces(state)  # 戦果票の基準（開始時の兵力）を控える
	_rank_data = StageLoader.load_rank(path)  # 評価ランクの閾値（無ければ空＝ランクなし）
	if state.current_team == 0:
		_take_turn_snapshot()  # ステージの頭＝自ターン開始時点。ここでオートセーブも入る
	_start_stage_bgm_when_drawn(path)  # 盤が出てから鳴らす（新規ロード・中断セーブ復元で共通）

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
	_update_event_plate()

## 残りターン板（増援の予告）。未発生のイベントが無ければ隠れる。仕様 → doc/gdd/uiux.md
func _update_event_plate() -> void:
	if _event_plate == null:
		return
	_event_plate.set_event(_controller.state.next_event() if _controller != null else {})

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
	match outcome:
		BattleState.PLAYER_WIN:
			if not _current_campaign_id.is_empty():  # セレクト経由のステージだけクリア記録
				_progress.record_clear(_current_campaign_id, _current_stage_id)
				if not rank.is_empty():
					_progress.record_rank(_current_campaign_id, _current_stage_id, rank)
				# carryover: 勝利時に名簿を更新＝次の継承ステージが引き継ぐ。保存は勝利時のみなので
				# 負けて再挑戦しても「前ステージ勝利時の戦力」からやり直せる（ソフトロック救済）。詳細 → doc/gdd/campaigns.md
				if _roster_store != null and _controller != null:
					var updated := RosterService.update_after_clear(_load_roster(), _controller.state)
					_roster_store.save_roster(_current_campaign_id, updated)
					# 戦闘後の会話は「クリア後の名簿」で条件を見る＝この回で仲間になった駒が喋れる。
					# 読み込み時の名簿のままだと、加入が確定するのはクリア時なので合流の台詞が落ちる。
					_dialogue = StageLoader.load_dialogue(_current_stage_path, updated)
	_hud.set_player_turn(false)  # 決着後はターン終了を無効化
	# 決着シグナルは戦闘結果の直後に飛ぶ＝演出がまだ画面に出ている。勝敗を告げるのは演出が
	# 閉じてから（戦闘中に勝利音が鳴るのは気が早い）。ターン制限切れなど演出が無い決着は素通り。
	await _await_combat_view()
	await _show_result(outcome, rank)  # 戦果票＋スティンガー。プレイヤーが閉じるまで待つ
	if outcome == BattleState.PLAYER_WIN:
		if not _dialogue.get("outro", []).is_empty():
			_conversation_phase = "outro"
			$Front/InfoPanel.hide()
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

# --- 決着の戦果票（羊皮紙＋ゴム印）。presentation/ui/result_banner.gd ---

## 戦果票を出し、プレイヤーが閉じるまで待つ。印が落ちた瞬間に勝敗スティンガーを鳴らす
## （演出と音を揃える）。曲が未配置でも無音で進む＝演出だけは出る。
func _show_result(outcome: int, rank: String) -> void:
	if _result == null or _controller == null:
		return
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
	_result.play(_stage_title(), stamp_text, win, _result_rows(win), tr("ui.result.rank") if not rank.is_empty() else "")
	await _result.finished

## ステージ開始時の兵力を控える（戦果票の分母）。盤上の駒だけを数える＝拠点の控え(garrison)は含めない。
func _count_start_forces(state: BattleState) -> void:
	_start_ally = 0
	_start_enemy = 0
	for u in state.units():
		if u.team == 0:
			_start_ally += 1
		elif u.team == 1:
			_start_enemy += 1

## 戦果の行（ターン数・生存・撃破）。集計は presentation 側＝domain に戦績を持たせない。
## 勝利のときだけ、ターン数と生存にランク基準（S・A の具体値と達成の可否）を添える＝何を詰めれば
## 上がるかを読ませる。敗北にランクは付かないので基準も出さない。撃破はランクに使わないので基準なし。
## 撃破は「開始時の敵数 − 残っている敵数」。控えが出撃してから倒された分は数え落とす
## （開始時に盤上に居ない）＝多く見せる側には振れない。厳密に採るなら domain 側で撃破を数える。
func _result_rows(win: bool) -> Array:
	var st := _controller.state
	var alive_ally := 0
	var alive_enemy := 0
	for u in st.units():
		if u.team == 0:
			alive_ally += 1
		elif u.team == 1:
			alive_enemy += 1
	var turns := "%d / %d" % [st.turn_number, st.turn_limit] if st.turn_limit > 0 else str(st.turn_number)
	var turn_row := {"label": tr("ui.result.turns"), "value": turns}
	var alive_row := {"label": tr("ui.result.survived"), "value": "%d / %d" % [alive_ally, _start_ally]}
	if win and not _rank_data.is_empty():
		var turn_got := RankEvaluator.turn_rank(st.turn_number, _rank_data)
		var alive_got := RankEvaluator.survival_rank(alive_ally, _start_ally, _rank_data)
		_fill_goals(turn_row, "ui.result.goal_turn", "turn_s", "turn_a", turn_got)
		_fill_goals(alive_row, "ui.result.goal_alive", "survival_s", "survival_a", alive_got)
	return [
		turn_row,
		alive_row,
		{"label": tr("ui.result.defeated"), "value": str(maxi(_start_enemy - alive_enemy, 0))},
	]

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
	var alive := 0
	for u in _controller.state.units():
		if u.team == 0:
			alive += 1
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
	_conversation_phase = "intro"
	$HexBoard.set_input_locked(true)
	_set_scrim(true)  # 盤を沈めて会話に注視させる
	$Front/InfoPanel.hide()  # 会話中は情報パネルを隠す（同じ箱に会話を出す）
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
	$Front/InfoPanel.hide()
	$HexBoard.set_input_locked(true)
	_set_scrim(true)  # 盤を沈めて会話に注視させる
	_hud.set_player_turn(false)
	_conversation.start(lines, "ui.talk.resume_battle")

## AIターンのテンポ制御（controller.dialogue_pace）：占領で会話が始まっていれば閉じるまで待つ。
## 会話を始めるのは _on_event_fired ＝ここへ来た時点で phase は立っている（カメラ寄せの前に立てている）。
func _await_dialogue() -> void:
	if _conversation_phase == "event" and _conversation != null:
		await _conversation.closed

## 会話終了（読了 or スキップ）。intro→戦闘、outro→セレクトへ。
func _on_conversation_closed() -> void:
	$Front/InfoPanel.show()  # 会話が終わったら情報パネルを戻す
	$HexBoard.set_input_locked(false)  # 盤の凍結を解除（intro/outro 共通）
	_set_scrim(false)  # 暗幕を戻す（盤が主役に戻る）
	match _conversation_phase:
		"intro", "event":  # 戦闘へ戻る（開幕・途中の割り込みで同じ）
			_conversation_phase = ""
			if _controller != null:
				_hud.set_player_turn(_controller.state.current_team == 0)
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
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.save_requested.connect(_on_save_requested)
	_hud.load_requested.connect(_on_load_requested)
	_hud.wipe_enemies_requested.connect(_on_wipe_enemies_requested)  # デバッグ項目（製品ビルドでは出ない）
	$HexBoard.system_menu_requested.connect(_hud.open_system_menu)

# --- ターン板（盤エリア上端中央）。presentation/ui/turn_plate.gd。仕様 → doc/gdd/uiux.md ---
func _install_turn_plate() -> void:
	_turn_plate = TurnPlate.new()
	_turn_plate.name = "TurnPlate"
	add_child(_turn_plate)
	_event_plate = EventPlate.new()
	_event_plate.name = "EventPlate"
	add_child(_event_plate)

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

## 陣営全体バフ（ホーリーアリア）が効いている間だけ加護の光を出す。
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

# --- 中断セーブ／オートセーブ。仕様 → doc/tech/gamesystem.md ---
## 自ターン開始時点の盤を控える（＝セーブが書く中身）。同じ瞬間にオートセーブも上書きする。
## 状態が真実なのでターン・位置・損耗・行動フラグごと再現できる（BattleState.to_dict）。
## 冒険譚の外（セレクトの下敷き）ではオートセーブを書かない＝一覧に行き先の無い盤を並べない。
func _take_turn_snapshot() -> void:
	if _controller == null:
		return
	_turn_snapshot = _controller.state.to_dict()
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
		"campaign_title": String(campaign.get("title", "")), "stage_title": stage_title,
		"turn_number": int(_turn_snapshot.get("turn_number", 0)),
		"saved_at": Time.get_datetime_string_from_system(false, true),
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

## 選ばれた枠から再開：保存した状態から盤を組み直す（intro は流さない）。movement 表は復元後に再適用。
## タイトルから来た場合はここでタイトルを畳む＝盤へ直行する。
func _load_slot(slot: String) -> void:
	var data := _saves.load_slot(slot)
	if data.is_empty():
		return
	var state := BattleState.from_dict(data["state"], UnitCatalog.load_default())
	state.set_movement(Movement.load_default())  # 静的コンフィグ＝セーブに含めず復元後に再適用（load_file と同じ）
	state.set_sight_cost(TerrainType.sight_cost_table())  # 視線コストも静的コンフィグ＝復元後に再適用
	var meta: Dictionary = data.get("meta", {})
	_current_campaign_id = String(meta.get("campaign_id", ""))
	_current_stage_id = String(meta.get("stage_id", ""))
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
## 設定画面（いまは言語だけ）。開き口はタイトルのメニューで、値の適用と保存はここが持つ。
func _install_settings() -> void:
	_settings = SettingsScreen.new()
	_settings.name = "SettingsScreen"
	_settings.locale_chosen.connect(_on_settings_locale_chosen)
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)

func _install_title() -> void:
	_title = TitleScreen.new()
	_title.name = "TitleScreen"
	add_child(_title)
	_title.door_opening.connect(_on_title_door_opening)
	_title.menu_shown.connect(_on_title_menu_shown)
	_title.continue_requested.connect(_on_title_continue)
	_title.new_game_requested.connect(_on_title_new_game)
	_title.settings_requested.connect(_on_title_settings)
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
	_title.show_stamp(false)
	_settings.open(_settings_store.locale())

## 設定を畳み終えた＝タイトルへ戻った。伏せていた刻印を出し直す。
func _on_settings_closed() -> void:
	_title.show_stamp(true)

## 言語を選んだ＝その場で適用して保存し、生き続けている画面の文言を貼り直す。
func _on_settings_locale_chosen(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_settings_store.set_locale(locale)
	_refresh_labels()

## 言語が変わったときに文言を貼り直す画面＝起動時に1度だけ作ってセッション中生き続ける物。
## 開くたびに組み直す画面（情報パネルの中身・盤のコマンドメニュー・会話・戦果票）は要らない。
## 一覧の根拠 → doc/tech/i18n.md 言語の切り替え。生き続ける画面を足したらここへも足す。
func _refresh_labels() -> void:
	_settings.refresh_labels()
	_title.refresh_labels()
	_hud.refresh_labels()
	_select.refresh_labels()
	_slot_panel.refresh_labels()
	$Front/InfoPanel.refresh_labels()

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
