extends Node3D
class_name HexBoard3D
## ヘックス盤面の3D表示（3Dハイブリッド）。傾けた Camera3D＋床に寝かせたヘックスタイル
## （地形テクスチャ流用）＋完全ビルボードの Sprite3D（ユニット立ち絵流用）。
## 3D なのは 描画 / picking（マウスレイ∩盤平面 y=0）/ カメラ（俯角固定リグ）で、
## インタラクション（選択→移動→コマンド・出撃・降車・乗車）は盤が状態として持つ。
## 方針 → doc/adr/ADR-0003-board-3d-hybrid.md

## 選択中ユニットが変わったとき発行（id<0＝選択解除）。情報パネル等が購読する。
signal selection_changed(unit_id: int)
## ユニットのいない空きマスをクリックしたとき発行（地形・拠点情報を右パネルに出す）。
signal tile_inspected(hex: Vector2i)
## 戻る対象が無い最上位で Esc を押したとき発行（HUD がシステムメニューを開く）。
signal system_menu_requested
## 移動アニメが終わった（歩き切った・割り込みでスナップした のどちらも）。
## AIターンのテンポ制御に使う（main が controller.move_pace へ注入）。待ち手を取り残さないため
## 中断でも必ず発行する。
signal move_animation_finished
## 陣形スキルの着弾演出が終わった（打ち切りでも必ず発行＝待ち手を取り残さない）。
## 決着の告知（戦果票）と敵ターンのテンポ制御がこれを待つ。
signal formation_impact_finished

const TILE := 1.0                # ワールドでの hex サイズ（中心〜頂点）
const MOVE_ANIM_SEC_PER_HEX := 0.12  # 移動アニメ＝1マスあたりの秒数（等速。速いほうが好まれる）
const MOVE_ANIM_MAX_SEC := 0.6       # 経路が長くてもここで頭打ち＝足の速い駒で待たされない
const INFOPANEL_LEFT := UiLayout.RIGHT_BOX_LEFT    # InfoPanel の左端（レイアウト定数は ui_layout.gd に集約）
const DRAG_THRESHOLD := 6.0      # この距離(px)を超えて動いたらクリックでなくパン

const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.30)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_DEPLOY := Color(0.65, 0.45, 0.95, 0.40)  # 出撃先候補（移動の緑と区別）
const COLOR_ENEMY_REACH := Color(0.95, 0.35, 0.30, 0.22)  # 敵の移動（脅威）範囲
const COLOR_SIGHT_EDGE := Color(0.95, 0.25, 0.25)  # 索敵の検知域の外周線（赤）＝待機中の見張りの視界。塗らず境界だけ
const SIGHT_EDGE_WIDTH := 0.16  # 検知域の外周線の太さ（TILE 比＝ヘックス幅の16%。実機で調整可）
const COLOR_FORMATION_RANGE := Color(0.55, 0.45, 0.95, 0.18)  # 陣形の着弾可能hex（射程内）
const COLOR_FORMATION_BLAST := Color(0.95, 0.35, 0.85, 0.34)  # 陣形の着弾プレビュー（面）
# 着弾演出の定数は BoardImpactRenderer に移設。
const COLOR_PENDING := Color(1.00, 0.85, 0.25, 0.35)  # 移動先プレビュー（メニュー表示中）
const COLOR_SELECT_RING := Color(1.00, 0.85, 0.25)
const COLOR_ATTACK_RING := Color(0.95, 0.25, 0.25)
const COLOR_INSPECT_RING := Color(0.85, 0.90, 1.00)
const COLOR_BASE_NEUTRAL := Color(0.80, 0.80, 0.80)  # 未占領拠点の縁取り
const TEAM_COLORS: Array[Color] = [Color(0.30, 0.55, 0.95), Color(0.92, 0.40, 0.35)]
const LABEL_GAP := TILE * 0.12  # 立ち絵の天辺から控え数ラベルの下までの隙間

const INVALID_HEX := Vector2i(-9999, -9999)

var state: BattleState
var controller: MatchController
var _skin_catalog := {}   # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }

# --- カメラリグ（BoardCamera に委譲）---
var _board_cam: BoardCamera
var _press_pos := Vector2.ZERO   # 左ボタン押下位置（クリック/ドラッグ判別の起点・スクリーン座標）
var _press_on_empty := false     # 押下が空き地（ユニット無し）から始まったか＝パン許可
var _dragging_pan := false       # 左ドラッグでパン中

# --- シーン構造（_ready で組む）---
var _terrain_renderer: BoardTerrainRenderer  # 地形タイル（タイル・グリッド線・スカート・下地）
var _bases_root: Node3D    # 拠点の縁取り・控え数（占領で変わるのでイベントごとに作り直し）
var _unit_renderer: BoardUnitRenderer  # 駒の描画（立ち絵・影・光・兵数バー・リング・マーカー）
var _overlay_root: Node3D  # 範囲・ホバー等の半透明マス（変化ごとに作り直し）
var _impact_renderer: BoardImpactRenderer  # 着弾演出（面の光・被弾フラッシュ・撃破フェード）
var _overlay_mesh: ArrayMesh      # オーバーレイ用（同形・材質だけ変える）
var _hexring_mesh: ArrayMesh      # 拠点の縁取り（六角の枠）

# --- インタラクション状態 ---
var _hover := INVALID_HEX
var _selected_id := -1
var _inspected_id := -1  # 閲覧のみのユニット（敵など）。選択とは別＝移動範囲/コマンドは出さない
var _reachable := {}     # Vector2i -> true
var _inspect_reach := {} # Vector2i -> true（閲覧中の敵ユニットの移動範囲＝脅威範囲）
var _targets := {}       # Vector2i -> target_id（攻撃可能な敵の位置）
var _deploy_base := INVALID_HEX
var _deploy_cells := {}  # Vector2i -> true（出撃先候補）
var _locked := false     # 決着・AIターン中は入力を受けない（カメラは見られる）
var _frozen := false     # 会話中フリーズ＝カメラ含む全入力を止める（set_input_locked で制御）
var _move_tween: Tween = null  # 進行中の移動アニメ（同時に1本＝次の sync_units で必ず畳む）

var _pending_to := INVALID_HEX  # メニュー表示中の移動先（未確定）
var _choosing_target := false   # 「攻撃」選択後＝攻撃対象クリック待ち
var _choosing_formation := false  # 陣形スキルの着弾中心クリック待ち
var _formation_active := {}     # 発動中の陣形 option（着弾待ち）
var _formation_cells := {}      # Vector2i -> true（着弾可能な射程内hex）
var _formation_opts: Array = [] # 現メニューで提示中の陣形 option 一覧
# 着弾演出の状態は BoardImpactRenderer に移設。
var _menu: PopupMenu = null
var _menu_handled := false
var _menu_base := INVALID_HEX
var _deploy_index := 0
enum { MENU_ATTACK, MENU_WAIT, MENU_CANCEL, MENU_BOARD, MENU_ENTER }
const DEPLOY_ID_BASE := 100
const UNLOAD_ID_BASE := 200
const FORMATION_ID_BASE := 300

var _unload_transport := -1
var _unload_index := 0
var _unload_cells := {}
var _unload_to := INVALID_HEX

func _ready() -> void:
	# 環境（背景色・環境光）。タイル/駒はアンライトなのでライトは将来の3Dプロップ用。
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.83, 0.88)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	add_child(sun)
	_board_cam = BoardCamera.new()
	add_child(_board_cam)
	# 共有メッシュとコンテナ。
	_overlay_mesh = BoardMeshFactory.make_hex_mesh(TILE)
	_hexring_mesh = BoardMeshFactory.make_hexring_mesh(TILE)
	_terrain_renderer = BoardTerrainRenderer.new(); add_child(_terrain_renderer)
	_bases_root = Node3D.new(); add_child(_bases_root)
	_unit_renderer = BoardUnitRenderer.new(); add_child(_unit_renderer)
	_overlay_root = Node3D.new(); add_child(_overlay_root)
	_impact_renderer = BoardImpactRenderer.new(); add_child(_impact_renderer)
	_impact_renderer.impact_finished.connect(func() -> void: formation_impact_finished.emit())
	# コマンドメニュー（Window なのでカメラ変換の影響を受けない）。
	_menu = PopupMenu.new()
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu_id)
	_menu.popup_hide.connect(_on_menu_closed)

func bind(p_state: BattleState, p_controller: MatchController, p_skin_catalog: Dictionary = {}, p_terrain_skins: Dictionary = {}, p_margin_terrain: Dictionary = {}, p_board_height: Dictionary = { "row": [], "col": [] }, p_height_overrides: Dictionary = {}) -> void:
	state = p_state
	controller = p_controller
	_skin_catalog = p_skin_catalog
	_terrain_renderer.setup(state, p_terrain_skins, p_margin_terrain, p_board_height, p_height_overrides)
	_unit_renderer.setup(_board_cam, state, _skin_catalog, _terrain_renderer.elev, _terrain_renderer.unit_floor)
	_impact_renderer.setup(_unit_renderer, _overlay_mesh, _terrain_renderer.elev, _in_board, state, _sync, func(v: bool) -> void: _locked = v)
	_reset_interaction()
	controller.unit_moved.connect(_on_unit_moved)
	controller.unit_attacked.connect(_on_unit_attacked)
	controller.formation_resolved.connect(_on_formation_resolved)
	controller.unit_deployed.connect(_on_unit_deployed)
	controller.unit_unloaded.connect(_on_unit_unloaded)
	controller.unit_entered_base.connect(_on_unit_entered_base)
	controller.base_captured.connect(_on_base_captured)
	controller.unit_stood.connect(_on_unit_stood)
	controller.turn_changed.connect(_on_turn_changed)
	controller.battle_finished.connect(_on_battle_finished)
	_terrain_renderer.build_tiles()
	fit_to_view()
	_sync()

## 選択・出撃モード・ロック・ホバーを初期状態へ（ステージ再ロード時に呼ぶ）。
func _reset_interaction() -> void:
	_selected_id = -1
	_inspected_id = -1
	_inspect_reach.clear()
	_reachable.clear()
	_targets.clear()
	_deploy_base = INVALID_HEX
	_deploy_cells.clear()
	_deploy_index = 0
	_menu_base = INVALID_HEX
	_unload_transport = -1
	_unload_cells.clear()
	_unload_to = INVALID_HEX
	_locked = false
	_frozen = false
	_pending_to = INVALID_HEX
	_choosing_target = false
	_clear_formation()
	_impact_renderer.reset()
	if _menu != null and _menu.visible:
		_menu.hide()
	_dragging_pan = false
	_press_on_empty = false
	_hover = INVALID_HEX

## 会話中は盤の入力を全て凍結する（カメラ・パン・ズーム・クリック）。presentation の会話フローが使う。
## 決着後の _locked（カメラは見られる）とは別軸＝会話中だけ完全に止め、スクロールを会話エリアに閉じる。
func set_input_locked(v: bool) -> void:
	_frozen = v

## 盤の見た目を今の状態から作り直す（外からの強制更新）。
## 通常の更新は controller のイベント（移動・攻撃・出撃…）で走るので、それを経ない状態変更＝
## デバッグメニューの「敵を殲滅」だけがこれを呼ぶ。仕様 → doc/gdd/uiux.md
func refresh() -> void:
	_sync()

func _process(_delta: float) -> void:
	if state == null:
		return
	var h := _hex_at_mouse()
	if h != _hover:
		_hover = h
		_sync_overlay()
		_play_hover_sfx(h)

## ホバー音は駒と拠点の上でだけ鳴らす。盤は空きマスが大半で、全マスで鳴らすとカーソルを
## 動かすだけで鳴り続け、音が「そこに何かある」という情報を失う。→ doc/audio/sfx.md
func _play_hover_sfx(hex: Vector2i) -> void:
	if not _on_board(hex):
		return
	if state.unit_at(hex) == null and state.base_at(hex) == null:
		return
	SfxPlayer.play_event("map_hover")

# =========================================================================
# 入力（パン/ズームは3Dカメラ流儀）
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if _frozen:
		return  # 会話中＝盤の入力を全て止める（スクロールを会話エリアだけに閉じる）
	# --- カメラ（パン/ズーム/全体表示）。AIターン・決着後も見渡せるよう常時受ける。---
	if _handle_camera_scroll(event):
		return
	# 左ボタン: 押下で起点を記録し、離した時にクリック/パンを判別（しきい値）。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = get_viewport().get_mouse_position()
			_press_on_empty = state.unit_at(_hex_at_mouse()) == null  # 空き地からのみパン
			_dragging_pan = false
		elif _dragging_pan:
			_dragging_pan = false  # パンだった＝クリック扱いにしない
		elif not _locked and not controller.is_ai_turn():
			_on_click(_hex_at_mouse())  # ドラッグしていない＝クリック
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and _press_on_empty:
		if not _dragging_pan and _press_pos.distance_to(get_viewport().get_mouse_position()) > DRAG_THRESHOLD:
			_dragging_pan = true
		if _dragging_pan:
			_board_cam.pan_by(event.relative)  # 空き地ドラッグ＝パン
		return
	# --- 盤操作（自ターンのみ）---
	if _locked or controller.is_ai_turn():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_cancel(false)  # 右クリック＝キャンセル・戻る
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel(true)
	elif event.is_action_pressed("ui_accept"):
		_deselect()
		SfxPlayer.play_event("map_turn_end")
		controller.end_turn()

## スクロール（2本指/ピンチ/ホイール）・全体表示を処理。消費したら true。
## Ctrl の有無で判別: 修飾なし＝パン、Ctrl付き＝ズーム（カーソル基点）。
func _handle_camera_scroll(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index >= MOUSE_BUTTON_WHEEL_UP and event.button_index <= MOUSE_BUTTON_WHEEL_RIGHT:
		# トラックパッドは1ノッチ未満の量を factor(小数)付きのイベント連打で送ってくる。
		# 固定量×連打だと敏感すぎるため factor に比例させる（マウスホイールは factor=1 相当）。
		var f: float = event.factor if event.factor > 0.0 else 1.0
		if event.ctrl_pressed:  # ピンチ＝ズーム
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_board_cam.zoom_at_point(pow(BoardCamera.ZOOM_STEP, f), get_viewport().get_mouse_position())
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_board_cam.zoom_at_point(pow(1.0 / BoardCamera.ZOOM_STEP, f), get_viewport().get_mouse_position())
		else:  # 2本指スクロール＝パン（上下左右）
			var step := BoardCamera.PAN_WHEEL_STEP * f
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP: _board_cam.pan_by(Vector2(0, step))
				MOUSE_BUTTON_WHEEL_DOWN: _board_cam.pan_by(Vector2(0, -step))
				MOUSE_BUTTON_WHEEL_LEFT: _board_cam.pan_by(Vector2(step, 0))
				MOUSE_BUTTON_WHEEL_RIGHT: _board_cam.pan_by(Vector2(-step, 0))
		return true
	if event is InputEventMagnifyGesture:
		_board_cam.zoom_at_point(event.factor, event.position)
		return true
	if event is InputEventPanGesture:
		_board_cam.pan_by(-event.delta * BoardCamera.PAN_GESTURE_SPEED)
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		fit_to_view()
		return true
	return false

## 盤全体が HUD を避けた表示領域に収まるよう距離と注視点を合わせる。
func fit_to_view() -> void:
	if state == null:
		return
	var b := _board_bounds()
	if b.size.x < 0.0:
		return
	_board_cam.fit_to_bounds(b.position, b.end, TILE, _vis_rect())

## AIターンで「次に動く主体(hex)」をカメラに収める（controller.focus_pace が各手の前に呼ぶ）。
## 敵の全行動を見せる＝いつの間にか位置が変わる事態を防ぐ（doc/gdd/uiux.md「敵ターンのカメラ」）。
func focus_camera_on(hex: Vector2i) -> void:
	if state == null:
		return
	var b := _board_bounds()
	if b.size.x >= 0.0:
		_board_cam.set_focus_bounds(b.position, b.end, TILE * 2.0)
	await _board_cam.focus_on(_hex_world(hex), _vis_rect())

## 盤の外周をピクセル座標（＝ワールド xz）の矩形で返す。盤が空なら size が負。
func _board_bounds() -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for col in state.cols:
		for row in state.rows:
			var p := Hex.to_pixel(Hex.offset_to_axial(col, row), TILE)
			mn = mn.min(p)
			mx = mx.max(p)
	if mn.x > mx.x:
		return Rect2()
	return Rect2(mn, mx - mn)

## 着弾の揺れ（盤ぶん）。
func shake(px: float = BoardCamera.SHAKE_PX) -> void:
	_board_cam.shake(px)

## HUD を避けた可視域を Rect2 で返す（fit / focus の共通パラメータ）。
func _vis_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var x := 16.0
	var y := 64.0
	var w := minf(vp.x, INFOPANEL_LEFT) - 32.0
	var h := vp.y - 96.0
	return Rect2(x, y, w, h)

# =========================================================================
# picking（マウスレイ ∩ 盤平面 y=0。物理・コリジョン不要）
# =========================================================================

## screen 直下・高さ y の水平面上の点。交差しない（水平線より上）なら Vector3.INF。
func _plane_point_at_y(screen: Vector2, y: float) -> Vector3:
	var o := _board_cam.camera.project_ray_origin(screen)
	var d := _board_cam.camera.project_ray_normal(screen)
	if absf(d.y) < 1e-6:
		return Vector3.INF
	var t := (y - o.y) / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t

## screen 直下の盤平面(y=0)上の点。カメラパン等が使う。
func _plane_point_at(screen: Vector2) -> Vector3:
	return _plane_point_at_y(screen, 0.0)

## screen 直下のヘックス。高い所にあるタイルが低い所を隠すので、高いほうから順に見て最初に
## 当たったものを返す。どれにも当たらなければ y=0 の素の hex。
##
## 高さの候補を1つずつ平面として試すのではなく、レイが通るヘックスを高いほうから拾って、
## そのヘックス自身の高さで当たるかを見る。盤が行と列の基準高さを持つと高さの種類は
## 行数×列数まで増えるので、種類ぶん回すとピッキングが種類数に比例して重くなる
## （14×11・52種で 0.78ms を実測）。この形なら高さの幅にしか比例しない。
func _hex_at_mouse() -> Vector2i:
	return _hex_at_screen(get_viewport().get_mouse_position())

## 画面座標の直下のヘックス（_hex_at_mouse の本体。検証から任意の点を投げられるように分けてある）。
func _hex_at_screen(screen: Vector2) -> Vector2i:
	var o := _board_cam.camera.project_ray_origin(screen)
	var d := _board_cam.camera.project_ray_normal(screen)
	if absf(d.y) < 1e-6:
		return INVALID_HEX
	var levels := _terrain_renderer.elev_levels()  # 高い順・0 を必ず含む
	var top: float = float(levels[0])
	var bottom: float = float(levels[levels.size() - 1])
	# 高さを Δ 下げるとレイの着地点は水平に Δ×|d.xz|/|d.y| ずれる。1マスを跨がない刻みで歩く。
	var horiz := Vector2(d.x, d.z).length()
	var step: float = TILE * 0.4 * absf(d.y) / maxf(horiz, 1e-6)
	var seen := {}
	var e := top
	while e >= bottom - 0.001:
		var hex := _hex_on_plane(o, d, e)
		if hex != INVALID_HEX and not seen.has(hex):
			seen[hex] = true
			if _on_board(hex) and _hex_on_plane(o, d, _terrain_renderer.elev(hex)) == hex:
				return hex
		e -= step
	var flat := _hex_on_plane(o, d, 0.0)
	return flat if flat != INVALID_HEX else INVALID_HEX

## レイと高さ y の水平面の交点が乗るヘックス。交差しなければ INVALID_HEX。
func _hex_on_plane(o: Vector3, d: Vector3, y: float) -> Vector2i:
	var t := (y - o.y) / d.y
	if t < 0.0:
		return INVALID_HEX
	var p := o + d * t
	return Hex.from_pixel(Vector2(p.x, p.z), TILE)

## hex が盤の中か（ホバー表示は盤上だけ）。
func _on_board(hex: Vector2i) -> bool:
	var o := Hex.axial_to_offset(hex)
	return o.x >= 0 and o.x < state.cols and o.y >= 0 and o.y < state.rows

# =========================================================================
# クリック→選択→移動→コマンドメニュー
# =========================================================================

func _on_click(hex: Vector2i) -> void:
	# 降車モード中: 降車先候補をクリック → 確認メニュー。
	if _unload_transport != -1:
		if _unload_cells.has(hex):
			_open_unload_menu(hex)
			return
		_clear_unload()
	# 出撃モード中: 出撃先候補をクリック → 出撃。それ以外は出撃モードを抜けて通常処理。
	if _deploy_base != INVALID_HEX:
		if _deploy_cells.has(hex):
			SfxPlayer.play_event("map_deploy")
			controller.execute_deploy(DeployCommand.new(_deploy_base, _deploy_index, hex))
			return
		_clear_deploy()
	# 陣形の着弾中心クリック待ち: 射程内なら発動、それ以外は中止。
	if _choosing_formation:
		if _formation_cells.has(hex):
			controller.execute_formation(FormationCommand.new(_formation_active, hex))
		else:
			_deselect()
		return
	# 攻撃対象クリック待ち: 対象なら攻撃、それ以外は中止。
	if _choosing_target:
		if _targets.has(hex):
			controller.execute_attack(AttackCommand.new(_selected_id, _targets[hex]))
		else:
			_deselect()
		return
	# 選択中に「自マス or 到達マス」をクリック → コマンドメニュー（移動は未確定のまま開く）。
	if _selected_id != -1:
		var sel := state.unit_by_id(_selected_id)
		if sel != null and (hex == sel.pos or (state.unit_at(hex) == null and _reachable.has(hex))):
			_open_command_menu(hex)
			return
		# 到達範囲内の「乗れる味方輸送」をクリック → 乗車メニュー。
		var occ := state.unit_at(hex)
		if sel != null and occ != null and _reachable.has(hex) and state.can_board(sel, occ):
			_open_board_menu(hex)
			return
	# 現ターンで操作可能なユニットをクリック → 選択。
	var clicked := state.unit_at(hex)
	if clicked != null and state.can_select(clicked.id):
		_select(clicked.id)
		return
	# 自軍の出撃可能な拠点をクリック → 拠点メニュー（出撃）。
	var b := state.base_at(hex)
	if b != null and b.team == state.current_team and not controller.deploy_cells_for(hex).is_empty():
		_open_base_menu(hex)
		return
	if clicked != null:
		_inspect_unit(clicked.id)  # 操作対象外（敵など）→ 選択せずステータスのみ表示
		return
	_deselect()
	if state.unit_at(hex) == null:
		tile_inspected.emit(hex)  # 空きマス＝地形（拠点なら控えも）を右パネルに表示

## 移動先（自マス含む）に対するコマンドメニューを開く。移動はまだ確定しない。
func _open_command_menu(dest: Vector2i) -> void:
	_pending_to = dest
	_menu_base = INVALID_HEX
	var can_attack := not controller.attack_targets_from(_selected_id, dest).is_empty()
	var sel := state.unit_by_id(_selected_id)
	var base := state.base_at(dest)
	var will_capture := sel != null and sel.can_capture and base != null and base.team != sel.team
	var can_enter := state.can_enter_base_at(_selected_id, dest)
	_menu.clear()
	_menu.add_item(tr("ui.board.attack"), MENU_ATTACK)
	_menu.set_item_disabled(_menu.get_item_index(MENU_ATTACK), not can_attack)
	_menu.add_item(tr("ui.board.capture") if will_capture else tr("ui.board.wait"), MENU_WAIT)
	if can_enter:
		_menu.add_item(tr("ui.board.enter"), MENU_ENTER)
	var pas := state.passengers(_selected_id)
	if not pas.is_empty():
		_menu.add_separator()
	for i in pas.size():
		var pu: Unit = pas[i]
		var sk := SkinCatalog.resolve(_skin_catalog, pu.skin_id, pu.type_id, pu.team)
		_menu.add_item(tr("ui.board.unload") % (tr("unit." + sk.skin_id + ".name") if sk != null else pu.type_id), UNLOAD_ID_BASE + i)
		if state.has_moved(pu.id):
			_menu.set_item_disabled(_menu.get_item_index(UNLOAD_ID_BASE + i), true)
	if sel != null and base != null and base.team == sel.team and not base.garrison.is_empty():
		_menu.add_separator()
		var no_cells := controller.deploy_cells_for(dest).is_empty()
		for i in base.garrison.size():
			var gu: Unit = base.garrison[i]
			var gsk := SkinCatalog.resolve(_skin_catalog, gu.skin_id, gu.type_id, state.current_team)
			_menu.add_item(tr("ui.board.deploy") % (tr("unit." + gsk.skin_id + ".name") if gsk != null else gu.type_id), DEPLOY_ID_BASE + i)
			if no_cells or not state.can_deploy_garrison(dest, i):
				_menu.set_item_disabled(_menu.get_item_index(DEPLOY_ID_BASE + i), true)
	# 発動者は移動してから撃てる＝成立も射程も「移動先 dest に居るものとして」見る。
	# 成立していないレシピは項目を出さない。成立していても撃てる先が無ければ、出したうえで
	# 無効化する（攻撃と同じ流儀＝できない操作は選べない → doc/gdd/uiux.md）。
	_formation_opts = []
	if sel != null:
		_formation_opts = Formation.available_for(state, sel, dest)
		if not _formation_opts.is_empty():
			_menu.add_separator()
			for i in _formation_opts.size():
				var o: Dictionary = _formation_opts[i]
				var label := tr("ui.board.unit_skill") if String(o.get("kind", "")) == "skill" else tr("ui.board.formation_skill")
				# レシピ名は規約キー（names.csv）で解決。RECIPES の name は開発用メモ
				var recipe_name := tr("recipe." + String(o["recipe"]) + ".name")
				_menu.add_item(tr("ui.board.recipe_item") % [label, recipe_name], FORMATION_ID_BASE + i)
				if Formation.targetable_cells(state, o, dest).is_empty() and bool(o["needs_target"]):
					_menu.set_item_disabled(_menu.get_item_index(FORMATION_ID_BASE + i), true)
	_menu.add_separator()
	_menu.add_item(tr("ui.board.cancel"), MENU_CANCEL)
	_menu_handled = false
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
	_menu.popup()
	_sync_overlay()  # 移動先プレビューを描く

func _on_menu_id(id: int) -> void:
	_menu_handled = true
	SfxPlayer.play_event("map_confirm" if id != MENU_CANCEL else "map_cancel")
	if _unload_to != INVALID_HEX:
		_handle_unload_menu(id)
		return
	if id >= FORMATION_ID_BASE:  # 300以上＝UNLOAD/DEPLOYより先に判定（範囲が重ならないよう最上位）
		var opt: Dictionary = _formation_opts[id - FORMATION_ID_BASE]
		# 陣形もユニットスキルも、先に移動を確定してから対象を選ぶ（射程は移動先から測る）。
		# 動かずに開いた場合は保留移動が無いので素通り。
		_commit_pending_move()
		_enter_formation(opt)
		return
	if id >= UNLOAD_ID_BASE:
		var tid := _selected_id
		_commit_pending_move()
		_enter_unload(tid, id - UNLOAD_ID_BASE)
		return
	if id >= DEPLOY_ID_BASE:
		_deploy_index = id - DEPLOY_ID_BASE
		var from := _menu_base
		if from == INVALID_HEX:
			from = _pending_to
			_commit_pending_move()
			_deselect()
		_enter_deploy(from)
		return
	match id:
		MENU_ATTACK:
			_commit_pending_move()
			_reachable.clear()
			_targets.clear()
			for tid in controller.attack_targets_for(_selected_id):
				var u := state.unit_by_id(tid)
				if u != null:
					_targets[u.pos] = tid
			_choosing_target = true
			_sync_overlay()
		MENU_WAIT:
			_commit_pending_move()
			controller.stand(_selected_id)
			_deselect()
		MENU_BOARD:
			if _pending_to != INVALID_HEX:
				controller.execute(MoveCommand.new(_selected_id, _pending_to))
			_deselect()
		MENU_ENTER:
			_commit_pending_move()
			controller.enter_base(_selected_id)
			_deselect()
		MENU_CANCEL:
			_deselect()

## 陣形スキルの着弾中心クリック待ちモードに入る。射程内hexをハイライトする。
## 対象を取らないバフ系（②）は即発動（クリック待ちに入らない）。
func _enter_formation(option: Dictionary) -> void:
	if not bool(option["needs_target"]):
		controller.execute_formation(FormationCommand.new(option, INVALID_HEX))
		return
	_commit_pending_move()  # 移動してから撃つ＝先に確定させる（自マスなら no-op）
	_reachable.clear()
	_targets.clear()
	_choosing_formation = true
	_formation_active = option
	_formation_cells.clear()
	# 移動は確定済み＝発動者は盤の上の実位置に居る（from_hex は渡さない）。
	for h in Formation.targetable_cells(state, option):
		_formation_cells[h] = true
	_sync_overlay()

## 陣形スキルが解決した＝選択を解く。着弾がある場合、盤の作り直しは play_formation_impact まで
## 保留する（撃たれる前の姿のまま置く）＝カットインの裏で駒が消えない。順番は main が持つ。
## 詳細 → doc/gdd/formations.md 発動の演出
func _on_formation_resolved(result: Dictionary) -> void:
	# 着弾（results）が無くても、光らせる面（cells）があれば保留する＝光ってから盤を作り直す
	# （スライムの複製は光の後に現れる。駒の居ない面への着弾も面を見せる）。
	_impact_renderer.set_pending(not (result.get("results", []) as Array).is_empty()
		or not (result.get("cells", []) as Array).is_empty())
	_deselect()
	if not _impact_renderer.is_impacting():
		_sync()

## 着弾を見せる（BoardImpactRenderer に委譲）。
func play_formation_impact(result: Dictionary) -> void:
	await _impact_renderer.play(result, _locked)

## 着弾演出が進行中か（盤が撃たれる前の姿を保持している間）。決着の告知はこれが終わるまで待つ。
func is_impacting() -> bool:
	return _impact_renderer.is_impacting()

## メニューが閉じた。id_pressed と popup_hide の発火順は環境差があるため、
## 判定を1フレーム遅らせ、項目選択（_on_menu_id）が先に処理されるようにする。
func _on_menu_closed() -> void:
	call_deferred("_after_menu_closed")

func _after_menu_closed() -> void:
	if not _menu_handled:
		_pending_to = INVALID_HEX
		_unload_to = INVALID_HEX
		_sync_overlay()

## 保留中の移動を確定（自マスのままなら移動しない）。
func _commit_pending_move() -> void:
	var sel := state.unit_by_id(_selected_id)
	if sel != null and _pending_to != INVALID_HEX and _pending_to != sel.pos:
		controller.execute(MoveCommand.new(_selected_id, _pending_to))
	_pending_to = INVALID_HEX

## 「戻る」。メニュー→選択→出撃モードの順に1段ずつ解除。
func _on_cancel(from_esc: bool) -> void:
	SfxPlayer.play_event("map_cancel")
	if _menu.visible:
		_menu.hide()
	elif _choosing_formation or _choosing_target or _selected_id != -1:
		_deselect()
	elif _unload_transport != -1:
		_clear_unload()
	elif _deploy_base != INVALID_HEX:
		_clear_deploy()
	elif _inspected_id != -1:
		_inspected_id = -1
		_inspect_reach.clear()
		selection_changed.emit(-1)
		_sync_overlay()
	elif from_esc:
		system_menu_requested.emit()

## 到達範囲内の味方輸送をクリック → 乗車メニュー（乗車／キャンセル）。
func _open_board_menu(dest: Vector2i) -> void:
	_pending_to = dest
	_menu_base = INVALID_HEX
	_menu.clear()
	_menu.add_item(tr("ui.board.embark"), MENU_BOARD)
	_menu.add_separator()
	_menu.add_item(tr("ui.board.cancel"), MENU_CANCEL)
	_menu_handled = false
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
	_menu.popup()
	_sync_overlay()

## 降車モードに入り、降車先候補をハイライトする。
func _enter_unload(transport_id: int, index: int) -> void:
	_deselect()
	var cells := controller.unload_cells_for(transport_id, index)
	if cells.is_empty():
		return
	_unload_transport = transport_id
	_unload_index = index
	_unload_cells.clear()
	for c in cells:
		_unload_cells[c] = true
	_sync_overlay()

## 降車先に対する確認メニュー（通常移動のコマンドメニューと同じ並び）。
func _open_unload_menu(dest: Vector2i) -> void:
	_unload_to = dest
	var p: Unit = state.passengers(_unload_transport)[_unload_index]
	var can_attack := not controller.unload_attack_targets_for(_unload_transport, _unload_index, dest).is_empty()
	var base := state.base_at(dest)
	var will_capture := p.can_capture and base != null and base.team != p.team
	_menu.clear()
	_menu.add_item(tr("ui.board.attack"), MENU_ATTACK)
	_menu.set_item_disabled(_menu.get_item_index(MENU_ATTACK), not can_attack)
	_menu.add_item(tr("ui.board.capture") if will_capture else tr("ui.board.wait"), MENU_WAIT)
	_menu.add_separator()
	_menu.add_item(tr("ui.board.cancel"), MENU_CANCEL)
	_menu_handled = false
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
	_menu.popup()
	_sync_overlay()

func _handle_unload_menu(id: int) -> void:
	var dest := _unload_to
	_unload_to = INVALID_HEX
	match id:
		MENU_ATTACK:
			var pid: int = state.passengers(_unload_transport)[_unload_index].id
			if controller.execute_unload(UnloadCommand.new(_unload_transport, _unload_index, dest)):
				_selected_id = pid
				_targets.clear()
				for tid in controller.attack_targets_for(pid):
					var u := state.unit_by_id(tid)
					if u != null:
						_targets[u.pos] = tid
				_choosing_target = true
				selection_changed.emit(pid)
				_sync()
		MENU_WAIT:
			var pid: int = state.passengers(_unload_transport)[_unload_index].id
			if controller.execute_unload(UnloadCommand.new(_unload_transport, _unload_index, dest)):
				controller.stand(pid)  # unit_stood → _sync（降車なので待つ移動アニメは無い）
		MENU_CANCEL:
			_clear_unload()

func _clear_unload() -> void:
	_unload_transport = -1
	_unload_cells.clear()
	_unload_to = INVALID_HEX
	_sync_overlay()

func _on_unit_unloaded(_unit_id: int, _transport_id: int, _to: Vector2i) -> void:
	_unload_transport = -1
	_unload_cells.clear()
	SfxPlayer.play_event("map_board")
	_sync()

## 自軍の出撃可能な拠点をクリック → 拠点メニュー。
func _open_base_menu(base_hex: Vector2i) -> void:
	_deselect()
	_menu_base = base_hex
	tile_inspected.emit(base_hex)
	_menu.clear()
	var b := state.base_at(base_hex)
	for i in b.garrison.size():
		var gu: Unit = b.garrison[i]
		var sk := SkinCatalog.resolve(_skin_catalog, gu.skin_id, gu.type_id, state.current_team)
		var nm := tr("unit." + sk.skin_id + ".name") if sk != null else gu.type_id
		_menu.add_item(tr("ui.board.deploy") % nm, DEPLOY_ID_BASE + i)
		if not state.can_deploy_garrison(base_hex, i):
			_menu.set_item_disabled(_menu.get_item_index(DEPLOY_ID_BASE + i), true)
	_menu.add_separator()
	_menu.add_item(tr("ui.board.cancel"), MENU_CANCEL)
	_menu_handled = false
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
	_menu.popup()

## 出撃モードに入り、出撃先候補をハイライトする。
func _enter_deploy(base_hex: Vector2i) -> void:
	var cells := controller.deploy_cells_for(base_hex, _deploy_index)
	if cells.is_empty():
		return
	_deploy_base = base_hex
	_deploy_cells.clear()
	for c in cells:
		_deploy_cells[c] = true
	_sync_overlay()

func _clear_deploy() -> void:
	_deploy_base = INVALID_HEX
	_deploy_cells.clear()
	_sync_overlay()

func _select(id: int) -> void:
	SfxPlayer.play_event("map_select")
	_selected_id = id
	_inspected_id = -1
	_inspect_reach.clear()
	_pending_to = INVALID_HEX
	_choosing_target = false
	_clear_formation()
	_reachable.clear()
	_targets.clear()
	if state.can_still_move(id):
		for h in controller.reachable_for(id):
			_reachable[h] = true
	selection_changed.emit(id)
	_sync_overlay()

func _deselect() -> void:
	var had := _selected_id
	_selected_id = -1
	_inspected_id = -1
	_inspect_reach.clear()
	_pending_to = INVALID_HEX
	_choosing_target = false
	_clear_formation()
	_reachable.clear()
	_targets.clear()
	if _menu != null and _menu.visible:
		_menu.hide()
	if had != -1:
		selection_changed.emit(-1)
	_sync_overlay()

## 陣形スキルの発動・着弾待ち状態を解除する。
func _clear_formation() -> void:
	_choosing_formation = false
	_formation_active = {}
	_formation_cells.clear()
	_formation_opts = []

## 敵など操作できないユニットを閲覧（選択状態にはしない）。移動範囲＝脅威範囲だけ別色で出す。
func _inspect_unit(id: int) -> void:
	_selected_id = -1
	_pending_to = INVALID_HEX
	_choosing_target = false
	_clear_formation()
	_reachable.clear()
	_targets.clear()
	_inspected_id = id
	_inspect_reach.clear()
	for h in controller.reachable_for(id):
		_inspect_reach[h] = true
	selection_changed.emit(id)
	_sync_overlay()

func _on_unit_moved(unit_id: int, _from: Vector2i, _to: Vector2i, path: Array[Vector2i]) -> void:
	_sync()  # 盤は真実（＝移動先）で作り直す
	# 乗車には専用のシグナルが無い。輸送のマスへ入った駒は盤から外れる＝作り直した後に
	# ノードが残っていなければ乗ったと分かる（降車は _on_unit_unloaded 側で鳴らす）。
	if not _unit_renderer.has_unit_node(unit_id):
		SfxPlayer.play_event("map_board")
	_animate_move(unit_id, path)

## 移動した駒を経路の起点へ戻し、マスを1つずつ辿らせる（見た目だけ後追い）。
## 盤の状態は既に移動先で確定しているので、アニメが途中で切れても嘘にはならない
## ＝別イベントの sync_units がノードごと作り直し、駒は真実の位置にスナップする
## （戦闘演出と同じ「状態は即確定・見た目は後追い」の流儀）。
func _animate_move(unit_id: int, path: Array[Vector2i]) -> void:
	var node: Node3D = _unit_renderer.get_unit_node(unit_id)
	# 経路なし＝アニメできない（乗車で盤から消えた／隣接特例の外）→ 従来どおり瞬間移動。
	if node == null or path.size() < 2:
		move_animation_finished.emit()
		return
	var steps := path.size() - 1
	var per_hex := minf(MOVE_ANIM_SEC_PER_HEX, MOVE_ANIM_MAX_SEC / float(steps))
	# map_move（doc/audio/sfx.md 移動音）。素材は移動タイプ＋スキンで決まり、未配置なら無音で進む。
	# 鳴らす頻度は素材ごとの最小間隔で決める。0＝1マス踏むごと（足音）、飛行は数マスに1回。
	# per_hex は経路が長いほど縮む＝マス数で間引くと長い経路で羽ばたきが速まるため、時間で見る。
	var move_sfx := _move_sfx_of(unit_id)
	var move_interval := SfxCatalog.move_interval_of(move_sfx)
	var last_sfx_sec := -1.0  # 直近に鳴らした時刻（アニメ開始から）。負＝まだ鳴らしていない
	node.position = _hex_world(path[0])
	var t := create_tween()  # 既定は等速（TRANS_LINEAR）＝マスを一定の速さで歩く
	for i in range(1, path.size()):
		var at_sec := per_hex * float(i - 1)  # このマスへ踏み出す時刻
		# 1マス目（last < 0）は間隔によらず必ず鳴らす＝短い移動でも無音にしない。
		if move_sfx != "" and (last_sfx_sec < 0.0 or at_sec - last_sfx_sec >= move_interval):
			last_sfx_sec = at_sec
			t.tween_callback(func() -> void: SfxPlayer.play_sfx(move_sfx))
		t.tween_property(node, "position", _hex_world(path[i]), per_hex)
	t.finished.connect(func() -> void:
		if _move_tween == t:
			_move_tween = null
		move_animation_finished.emit())
	_move_tween = t

## その駒の移動音の素材ID。スキンの指定（map_move_sfx）を優先し、無ければ移動タイプの既定。
## 飛行の飛び方の違い（羽ばたき／浮遊／プロペラ）はスキン側で分かれる（doc/audio/sfx.md 移動音）。
## 盤に居ない・移動タイプ不明なら ""＝無音。
func _move_sfx_of(unit_id: int) -> String:
	if state == null:
		return ""
	var u := state.unit_by_id(unit_id)
	if u == null:
		return ""
	var s: UnitSkin = SkinCatalog.resolve(_skin_catalog, u.skin_id, u.type_id, u.team)
	if s != null and s.map_move_sfx != "":
		return s.map_move_sfx
	return SfxCatalog.move_sfx_of(UnitCatalog.move_type_of(u.type_id))

## ヘックスの中心（ユニットの親ノードを置くワールド座標）。地形の標高ぶん持ち上げる。
func _hex_world(hex: Vector2i) -> Vector3:
	var p := Hex.to_pixel(hex, TILE)
	return Vector3(p.x, _terrain_renderer.elev(hex), p.y)

## 進行中の移動アニメを畳む。待っている側（AIターン）を取り残さないため完了を必ず知らせる。
func _kill_move_tween() -> void:
	if _move_tween == null:
		return
	var t := _move_tween
	_move_tween = null
	if t.is_valid():
		t.kill()
	move_animation_finished.emit()

## AIターンのテンポ制御（main が controller.move_pace に注入）：移動アニメ中なら歩き切るまで待つ。
func await_move_animation() -> void:
	if _move_tween != null and _move_tween.is_valid() and _move_tween.is_running():
		await move_animation_finished

func _on_unit_attacked(_attacker_id: int, _target_id: int, _damage: int, _killed: bool) -> void:
	_deselect()  # 攻撃したユニットは行動終了
	_sync()

func _on_unit_deployed(_unit_id: int, _base_hex: Vector2i, _to: Vector2i) -> void:
	_clear_deploy()
	_sync()

## 「待機」＝駒は動かないが行動終了の見た目（暗く）へ変える。
## 移動を伴う待機では直前に移動アニメが走っている＝sync_units はそれを畳むため、
## 歩き切るのを待ってから作り直す（待たないと駒が移動先へ飛ぶ）。
func _on_unit_stood(_unit_id: int) -> void:
	await await_move_animation()
	_sync()

## 占領成立。歩き切ってから鳴らす＝駒が拠点に着く前に音が出ない。
## 盤の描き直しは _on_unit_moved の _sync が済ませているので、ここは音だけ。
func _on_base_captured(_base_hex: Vector2i, _team: int) -> void:
	await await_move_animation()
	SfxPlayer.play_event("map_capture")

## 「入る」＝駒は拠点の中へ消える。待つ理由は待機と同じ（歩いてから入る）。
func _on_unit_entered_base(_unit_id: int, _base_hex: Vector2i) -> void:
	await await_move_animation()
	_sync()

func _on_turn_changed(_team: int, _turn_number: int) -> void:
	_deselect()
	_clear_deploy()
	_clear_unload()
	_sync()

func _on_battle_finished(_winner: int) -> void:
	_locked = true
	_impact_renderer.cancel_unlock()  # 決着中は解錠しない（陣形で決着＝着弾演出の途中で飛んでくる）
	_deselect()
	_clear_deploy()
	_clear_unload()

# =========================================================================
# 3D描画（タイル＝床のヘックスメッシュ / 駒＝ビルボード / オーバーレイ＝半透明マス）
# =========================================================================

## 盤の見た目を状態から作り直す。
func _sync() -> void:
	_sync_bases()
	_kill_move_tween()
	_unit_renderer.sync_units()
	_sync_overlay()

## 拠点の所属（六角の縁取り）と控え数。占領で変わるためイベントごとに作り直す。
func _sync_bases() -> void:
	_clear_children(_bases_root)
	if state == null:
		return
	_terrain_renderer.refresh_base_tiles()
	for b in state.bases():
		var col := COLOR_BASE_NEUTRAL
		if b.team >= 0:
			col = TEAM_COLORS[b.team % TEAM_COLORS.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = _hexring_mesh
		mi.material_override = BoardMeshFactory.overlay_material(col)
		var p := Hex.to_pixel(b.hex, TILE)
		var by := _terrain_renderer.elev(b.hex)
		mi.position = Vector3(p.x, by + 0.015, p.y)
		_bases_root.add_child(mi)
		# 控え数（出撃できる人数）。立ち絵の拠点は建物の頭上、平らなタイルの拠点はマス左上に小さく。
		if not b.garrison.is_empty():
			var text := "+%d" % b.garrison.size()
			var top = _terrain_renderer.standee_top(b.hex, _board_cam.cam_up)
			if top == null:
				_unit_renderer.add_count_label(text, Vector3(p.x, by, p.y), col, _bases_root)
			else:
				_unit_renderer.add_count_label(text, top, col, _bases_root,
						_board_cam.cam_up * LABEL_GAP, VERTICAL_ALIGNMENT_BOTTOM)

## hex が盤の矩形（offset col/row）の中にあるか。
func _in_board(hex: Vector2i) -> bool:
	if state == null:
		return false
	var c := Hex.axial_to_offset(hex)
	return c.x >= 0 and c.x < state.cols and c.y >= 0 and c.y < state.rows

## オーバーレイ（範囲・候補・プレビュー・選択・攻撃対象・ホバー）を作り直す。
## 種類ごとに高さをずらして重なりのZファイトを避ける。
func _sync_overlay() -> void:
	_clear_children(_overlay_root)
	_unit_renderer.clear_target_markers()  # 実体は _overlay_root の子＝いま消えた。参照を残すと _process が落ちる
	if state == null:
		return
	for h in _reachable:
		_add_cell(h, COLOR_REACH, 0.02)
	for h in _inspect_reach:
		_add_cell(h, COLOR_ENEMY_REACH, 0.02)
	for h in _deploy_cells:
		_add_cell(h, COLOR_DEPLOY, 0.02)
	for h in _unload_cells:
		_add_cell(h, COLOR_DEPLOY, 0.02)
	if _pending_to != INVALID_HEX:
		_add_cell(_pending_to, COLOR_PENDING, 0.03)
	if _unload_to != INVALID_HEX:
		_add_cell(_unload_to, COLOR_PENDING, 0.03)
	# 攻撃可能な敵＝頭上のマーカー（見つけるための記号）＋地面の赤リング（どのマスを押すかの補助）。
	# リングだけでは手前の地形に隠れて読めないが、クリック判定はマス単位なので位置の目印としては残す。
	for pos in _targets:
		var tp := Hex.to_pixel(pos, TILE)
		_unit_renderer.add_ring(Vector3(tp.x, _terrain_renderer.elev(pos), tp.y), TILE * 0.72, 0.06, COLOR_ATTACK_RING, 0.05, _overlay_root)
		_unit_renderer.add_target_marker(state.unit_by_id(int(_targets[pos])), _overlay_root)
	for h in _formation_cells:  # 陣形の着弾可能hex（射程内）
		_add_cell(h, COLOR_FORMATION_RANGE, 0.02)
	if _choosing_formation and _formation_cells.has(_hover):  # ホバー先の面プレビュー
		for h in Hex.within_range(_hover, int(_formation_active.get("radius", 0))):
			_add_cell(h, COLOR_FORMATION_BLAST, 0.035)
	var sel := state.unit_by_id(_selected_id) if _selected_id != -1 else null
	if sel != null:
		var sp := Hex.to_pixel(sel.pos, TILE)
		_unit_renderer.add_ring(Vector3(sp.x, _terrain_renderer.elev(sel.pos), sp.y), TILE * 0.70, 0.06, COLOR_SELECT_RING, 0.045, _overlay_root)
	var ins := state.unit_by_id(_inspected_id) if _inspected_id != -1 else null
	if ins != null:
		var ip := Hex.to_pixel(ins.pos, TILE)
		_unit_renderer.add_ring(Vector3(ip.x, _terrain_renderer.elev(ins.pos), ip.y), TILE * 0.70, 0.05, COLOR_INSPECT_RING, 0.045, _overlay_root)
		# 待機中の見張り（sight で起きる・未起動）を選んだら、検知域の外周を赤線でなぞる。
		if controller != null:
			var det: int = controller.detection_radius(ins)
			if det > 0:
				_add_sight_boundary(state.visible_hexes(ins.pos, det))
	if _hover != INVALID_HEX and _on_board(_hover):
		_add_cell(_hover, COLOR_HOVER, 0.04)

func _add_cell(hex: Vector2i, color: Color, y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _overlay_mesh
	mi.material_override = BoardMeshFactory.overlay_material(color)
	var p := Hex.to_pixel(hex, TILE)
	mi.position = Vector3(p.x, _terrain_renderer.elev(hex) + y, p.y)
	_overlay_root.add_child(mi)

## 辺 i（コーナー i→i+1）に対応する隣接方向（フラットトップ axial・BoardTerrainRenderer._add_skirt と同じ対応）。
const _EDGE_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]

## 検知域（visible な hex 集合）の外周だけを赤い太線でなぞる（塗らない＝移動範囲と紛れない）。
## 各 hex の6辺のうち、隣が visible でない辺だけを描く＝壁の影・森のへこみがそのまま輪郭に出る。
## 3D の線は太さが効かない（GPU依存）ので、各辺を幅つきの帯（三角形2枚）で描いて太さを持たせる。
func _add_sight_boundary(visible: Dictionary) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := TILE * SIGHT_EDGE_WIDTH * 0.5  # 帯の半幅
	for hex in visible:
		var p := Hex.to_pixel(hex, TILE)
		var sy := _terrain_renderer.elev(hex) + 0.05
		for i in 6:
			if visible.has(hex + _EDGE_DIRS[i]):
				continue  # 内側の辺は描かない（外周だけ）
			var a0 := deg_to_rad(60.0 * i)
			var a1 := deg_to_rad(60.0 * (i + 1))
			var v0 := Vector3(p.x + cos(a0) * TILE, sy, p.y + sin(a0) * TILE)
			var v1 := Vector3(p.x + cos(a1) * TILE, sy, p.y + sin(a1) * TILE)
			_add_thick_edge(im, v0, v1, hw)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COLOR_SIGHT_EDGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 上から見て裏面でも描く
	mi.material_override = m
	_overlay_root.add_child(mi)

## v0→v1 の辺を幅 2*hw の帯（三角形2枚）にして im に足す。端を hw ぶん伸ばして角の隙間を埋める。
func _add_thick_edge(im: ImmediateMesh, v0: Vector3, v1: Vector3, hw: float) -> void:
	var d := v1 - v0
	var l := d.length()
	if l < 0.00001:
		return
	d /= l
	var perp := Vector3(-d.z, 0.0, d.x) * hw
	var e0 := v0 - d * hw  # 角で隣の帯と重ねて隙間を消す
	var e1 := v1 + d * hw
	var a := e0 + perp
	var b := e0 - perp
	var c := e1 + perp
	var e := e1 - perp
	im.surface_add_vertex(a); im.surface_add_vertex(c); im.surface_add_vertex(b)
	im.surface_add_vertex(b); im.surface_add_vertex(c); im.surface_add_vertex(e)

func _clear_children(root: Node3D) -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.free()
