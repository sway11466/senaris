extends Node3D
class_name HexBoard3D
## ヘックス盤面の3D表示（3Dハイブリッド実験・M1）。
## 傾けた Camera3D＋床に寝かせたヘックスタイル（地形テクスチャ流用）＋完全ビルボードの
## Sprite3D（ユニット立ち絵流用）。公開API・シグナルは2D版 hex_board.gd と同一＝
## main.tscn のノード差し替えだけで使える。
## インタラクション（選択→移動→コマンド・出撃・降車・乗車）は2D版から移植。
## 3D化したのは 描画 / picking（マウスレイ∩盤平面 y=0）/ カメラ（俯角固定リグ）のみ。
## M1の未実装（M2予定）: 兵数バー・+N・選択/攻撃/包囲リング（暫定でマス塗り）・拠点の縁取り。

## 選択中ユニットが変わったとき発行（id<0＝選択解除）。情報パネル等が購読する。
signal selection_changed(unit_id: int)
## ユニットのいない空きマスをクリックしたとき発行（地形・拠点情報を右パネルに出す）。
signal tile_inspected(hex: Vector2i)
## 戻る対象が無い最上位で Esc を押したとき発行（HUD がシステムメニューを開く）。
signal system_menu_requested

const TILE := 1.0                # ワールドでの hex サイズ（中心〜頂点）
const SPRITE_FOOT_Z := TILE * 0.6  # 立ち絵の足元をヘックス中心から手前（下辺寄り）へ。2D版の接地(0.75)と同じ狙い
const CAM_PITCH_DEG := 52.0      # カメラ俯角（プローブで確認した見え方）
const CAM_FOV := 42.0
const MIN_DIST := 5.0            # ズーム＝カメラ距離の範囲
const MAX_DIST := 90.0
const ZOOM_STEP := 1.15
const INFOPANEL_LEFT := 800.0    # InfoPanel の左端（main.tscn の offset_left と一致）
const DRAG_THRESHOLD := 6.0      # この距離(px)を超えて動いたらクリックでなくパン
const PAN_GESTURE_SPEED := 24.0  # パンジェスチャ(macOS等の2本指)の感度
const PAN_WHEEL_STEP := 50.0     # 2本指スクロール1ノッチぶんのパン量(px)

const COLOR_LINE := Color(0.78, 0.83, 0.90, 0.45)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.30)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_DEPLOY := Color(0.65, 0.45, 0.95, 0.40)  # 出撃先候補（移動の緑と区別）
const COLOR_ENEMY_REACH := Color(0.95, 0.35, 0.30, 0.22)  # 敵の移動（脅威）範囲
const COLOR_PENDING := Color(1.00, 0.85, 0.25, 0.35)  # 移動先プレビュー（メニュー表示中）
# M1はリングの代わりにマス塗りで選択/閲覧/攻撃対象を示す（リングはM2）。
const COLOR_SELECT_FILL := Color(1.00, 0.85, 0.25, 0.35)
const COLOR_INSPECT_FILL := Color(0.85, 0.90, 1.00, 0.30)
const COLOR_TARGET_FILL := Color(0.95, 0.25, 0.25, 0.40)
const TEAM_COLORS: Array[Color] = [Color(0.30, 0.55, 0.95), Color(0.92, 0.40, 0.35)]
const COLOR_UNIT_LABEL := Color(1, 1, 1, 0.95)

const INVALID_HEX := Vector2i(-9999, -9999)

var state: BattleState
var controller: MatchController
var _terrain_tex := {}    # skin_id(String) -> Array[Texture2D]（基本＋連番 variant）
var _terrain_skins := {}  # Vector2i -> skin_id（ステージの見た目差分）
var _unit_tex := {}       # 画像パス(String) -> Texture2D
var _skin_catalog := {}   # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }

# --- カメラリグ（俯角固定・注視点とdistだけ動かす）---
var _cam: Camera3D
var _cam_target := Vector3.ZERO
var _cam_dist := 20.0
var _press_pos := Vector2.ZERO   # 左ボタン押下位置（クリック/ドラッグ判別の起点・スクリーン座標）
var _press_on_empty := false     # 押下が空き地（ユニット無し）から始まったか＝パン許可
var _dragging_pan := false       # 左ドラッグでパン中

# --- シーン構造（_ready で組む）---
var _tiles_root: Node3D    # 地形タイル＋グリッド線＋下地（bind ごとに作り直し）
var _units_root: Node3D    # ユニット（イベントごとに作り直し）
var _overlay_root: Node3D  # 範囲・ホバー等の半透明マス（変化ごとに作り直し）
var _hex_mesh: ArrayMesh          # 床に寝かせたヘックス（タイル用・UVは外接矩形）
var _overlay_mesh: ArrayMesh      # オーバーレイ用（同形・材質だけ変える）
var _disc_mesh: CylinderMesh      # 画像なしユニットのプレースホルダ円盤
var _overlay_mat := {}    # Color -> StandardMaterial3D（オーバーレイ材質キャッシュ）
var _terrain_mat := {}    # Texture2D -> StandardMaterial3D（タイル材質キャッシュ）

# --- インタラクション状態（2D版から移植）---
var _hover := INVALID_HEX
var _selected_id := -1
var _inspected_id := -1  # 閲覧のみのユニット（敵など）。選択とは別＝移動範囲/コマンドは出さない
var _reachable := {}     # Vector2i -> true
var _inspect_reach := {} # Vector2i -> true（閲覧中の敵ユニットの移動範囲＝脅威範囲）
var _targets := {}       # Vector2i -> target_id（攻撃可能な敵の位置）
var _deploy_base := INVALID_HEX
var _deploy_cells := {}  # Vector2i -> true（出撃先候補）
var _locked := false     # 決着・AI手番中は入力を受けない

var _pending_to := INVALID_HEX  # メニュー表示中の移動先（未確定）
var _choosing_target := false   # 「攻撃」選択後＝攻撃対象クリック待ち
var _menu: PopupMenu = null
var _menu_handled := false
var _menu_base := INVALID_HEX
var _deploy_index := 0
enum { MENU_ATTACK, MENU_WAIT, MENU_CANCEL, MENU_BOARD, MENU_ENTER }
const DEPLOY_ID_BASE := 100
const UNLOAD_ID_BASE := 200

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
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	add_child(_cam)
	_update_camera()
	_cam.make_current()
	# 共有メッシュとコンテナ。
	_hex_mesh = _make_hex_mesh()
	_overlay_mesh = _make_hex_mesh()
	_disc_mesh = CylinderMesh.new()
	_disc_mesh.top_radius = TILE * 0.55
	_disc_mesh.bottom_radius = TILE * 0.55
	_disc_mesh.height = 0.06
	_tiles_root = Node3D.new(); add_child(_tiles_root)
	_units_root = Node3D.new(); add_child(_units_root)
	_overlay_root = Node3D.new(); add_child(_overlay_root)
	# コマンドメニュー（Window なのでカメラ変換の影響を受けない）。
	_menu = PopupMenu.new()
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu_id)
	_menu.popup_hide.connect(_on_menu_closed)

func bind(p_state: BattleState, p_controller: MatchController, p_skin_catalog: Dictionary = {}, p_terrain_skins: Dictionary = {}) -> void:
	state = p_state
	controller = p_controller
	_skin_catalog = p_skin_catalog
	_terrain_skins = p_terrain_skins
	_reset_interaction()
	controller.unit_moved.connect(_on_unit_moved)
	controller.unit_attacked.connect(_on_unit_attacked)
	controller.unit_deployed.connect(_on_unit_deployed)
	controller.unit_unloaded.connect(_on_unit_unloaded)
	controller.unit_entered_base.connect(func(_id: int, _hex: Vector2i) -> void: _sync())
	controller.turn_changed.connect(_on_turn_changed)
	controller.battle_finished.connect(_on_battle_finished)
	_build_tiles()
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
	_pending_to = INVALID_HEX
	_choosing_target = false
	if _menu != null and _menu.visible:
		_menu.hide()
	_dragging_pan = false
	_press_on_empty = false
	_hover = INVALID_HEX

## 会話中など盤の操作を一時ロックする（カメラ操作は可）。presentation の会話フローが使う。
func set_input_locked(v: bool) -> void:
	_locked = v

func _process(_delta: float) -> void:
	if state == null:
		return
	var h := _hex_at_mouse()
	if h != _hover:
		_hover = h
		_sync_overlay()

# =========================================================================
# 入力（2D版から移植。パン/ズームだけ3Dカメラ流儀）
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	# --- カメラ（パン/ズーム/全体表示）。AI手番・決着後も見渡せるよう常時受ける。---
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
			_pan_by(event.relative)  # 空き地ドラッグ＝パン
		return
	# --- 盤操作（自手番のみ）---
	if _locked or controller.is_ai_turn():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_cancel(false)  # 右クリック＝キャンセル・戻る
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel(true)
	elif event.is_action_pressed("ui_accept"):
		_deselect()
		controller.end_turn()

## スクロール（2本指/ピンチ/ホイール）・全体表示を処理。消費したら true。
## Ctrl の有無で判別: 修飾なし＝パン、Ctrl付き＝ズーム（カーソル基点）。2D版と同じ操作系。
func _handle_camera_scroll(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index >= MOUSE_BUTTON_WHEEL_UP and event.button_index <= MOUSE_BUTTON_WHEEL_RIGHT:
		# トラックパッドは1ノッチ未満の量を factor(小数)付きのイベント連打で送ってくる。
		# 固定量×連打だと敏感すぎるため factor に比例させる（マウスホイールは factor=1 相当）。
		var f: float = event.factor if event.factor > 0.0 else 1.0
		if event.ctrl_pressed:  # ピンチ＝ズーム
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at_point(pow(ZOOM_STEP, f), get_viewport().get_mouse_position())
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at_point(pow(1.0 / ZOOM_STEP, f), get_viewport().get_mouse_position())
		else:  # 2本指スクロール＝パン（上下左右）
			var step := PAN_WHEEL_STEP * f
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP: _pan_by(Vector2(0, step))
				MOUSE_BUTTON_WHEEL_DOWN: _pan_by(Vector2(0, -step))
				MOUSE_BUTTON_WHEEL_LEFT: _pan_by(Vector2(step, 0))
				MOUSE_BUTTON_WHEEL_RIGHT: _pan_by(Vector2(-step, 0))
		return true
	if event is InputEventMagnifyGesture:
		_zoom_at_point(event.factor, event.position)
		return true
	if event is InputEventPanGesture:
		_pan_by(-event.delta * PAN_GESTURE_SPEED)
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		fit_to_view()
		return true
	return false

# =========================================================================
# カメラリグ（俯角固定。注視点 _cam_target と距離 _cam_dist だけ動かす）
# =========================================================================

func _update_camera() -> void:
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	_cam.position = _cam_target + Vector3(0.0, sin(pitch), cos(pitch)) * _cam_dist
	_cam.look_at(_cam_target, Vector3.UP)

## 画面1pxがワールドで何mか（注視点の距離基準の近似）。パン・fit の換算に使う。
func _world_per_pixel() -> float:
	return 2.0 * _cam_dist * tan(deg_to_rad(CAM_FOV) * 0.5) / get_viewport().get_visible_rect().size.y

## マウス移動(px)ぶん盤が指に追随するよう注視点を動かす（2D版のパンと同じ操作感）。
## 画面の縦は俯角で奥行きが sin(pitch) に縮むぶん割り戻す。
func _pan_by(px: Vector2) -> void:
	var wpp := _world_per_pixel()
	_cam_target.x -= px.x * wpp
	_cam_target.z -= px.y * wpp / sin(deg_to_rad(CAM_PITCH_DEG))
	_update_camera()

## screen の直下の盤上の点を固定したままズーム（＝カーソル基点。2D版 _zoom_at_point と同義）。
func _zoom_at_point(factor: float, screen: Vector2) -> void:
	var nd := clampf(_cam_dist / factor, MIN_DIST, MAX_DIST)  # ズームイン＝距離を縮める
	if is_equal_approx(nd, _cam_dist):
		return
	var before := _plane_point_at(screen)
	_cam_dist = nd
	_update_camera()
	var after := _plane_point_at(screen)
	if before.is_finite() and after.is_finite():
		_cam_target += Vector3(before.x - after.x, 0.0, before.z - after.z)
		_update_camera()

## 盤全体が HUD を避けた表示領域（上の Title・右の InfoPanel を除く）に収まるよう距離と注視点を合わせる。
func fit_to_view() -> void:
	if state == null:
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for col in state.cols:
		for row in state.rows:
			var p := Hex.to_pixel(Hex.offset_to_axial(col, row), TILE)
			mn = mn.min(p)
			mx = mx.max(p)
	if mn.x > mx.x:
		return
	var c := (mn + mx) * 0.5
	var half := (mx - mn) * 0.5 + Vector2(TILE * 1.5, TILE * 1.5)
	var vp := get_viewport().get_visible_rect().size
	var tanf := tan(deg_to_rad(CAM_FOV) * 0.5)
	var sp := sin(deg_to_rad(CAM_PITCH_DEG))
	var vis_w := minf(vp.x, INFOPANEL_LEFT) - 32.0   # 可視域（右の InfoPanel・左右マージンを除く）
	var vis_h := vp.y - 96.0                          # 上の Title 下から下端まで
	var d_h := half.x / (tanf * vis_w / vp.y)         # 横に収まる距離
	var d_v := half.y * sp / (tanf * vis_h / vp.y)    # 縦（奥行きは俯角で縮む）に収まる距離
	_cam_dist = clampf(maxf(d_h, d_v) * 1.05, MIN_DIST, MAX_DIST)
	# 盤中心が可視域の中心（画面中心より左・やや下）に来るよう注視点をずらす。
	var wpp := _world_per_pixel()
	var dx_px := vp.x * 0.5 - (16.0 + vis_w * 0.5)
	var dy_px := vp.y * 0.5 - (64.0 + vis_h * 0.5)
	_cam_target = Vector3(c.x + dx_px * wpp, 0.0, c.y + dy_px * wpp / sp)
	_update_camera()

# =========================================================================
# picking（マウスレイ ∩ 盤平面 y=0。物理・コリジョン不要）
# =========================================================================

## screen 直下の盤平面(y=0)上の点。交差しない（水平線より上）なら Vector3.INF。
func _plane_point_at(screen: Vector2) -> Vector3:
	var o := _cam.project_ray_origin(screen)
	var d := _cam.project_ray_normal(screen)
	if absf(d.y) < 1e-6:
		return Vector3.INF
	var t := -o.y / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t

func _hex_at_mouse() -> Vector2i:
	var p := _plane_point_at(get_viewport().get_mouse_position())
	if not p.is_finite():
		return INVALID_HEX
	return Hex.from_pixel(Vector2(p.x, p.z), TILE)

## hex が盤の中か（ホバー表示は盤上だけ）。
func _on_board(hex: Vector2i) -> bool:
	var o := Hex.axial_to_offset(hex)
	return o.x >= 0 and o.x < state.cols and o.y >= 0 and o.y < state.rows

# =========================================================================
# クリック→選択→移動→コマンドメニュー（2D版から移植。描画呼び出しのみ _sync に置換）
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
			controller.execute_deploy(DeployCommand.new(_deploy_base, _deploy_index, hex))
			return
		_clear_deploy()
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
	# 現手番で操作可能なユニットをクリック → 選択。
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
	_menu.add_item("攻撃", MENU_ATTACK)
	_menu.set_item_disabled(_menu.get_item_index(MENU_ATTACK), not can_attack)
	_menu.add_item("占領" if will_capture else "待機", MENU_WAIT)
	if can_enter:
		_menu.add_item("入る", MENU_ENTER)
	var pas := state.passengers(_selected_id)
	if not pas.is_empty():
		_menu.add_separator()
	for i in pas.size():
		var pu: Unit = pas[i]
		var sk := SkinCatalog.resolve(_skin_catalog, pu.skin_id, pu.type_id, pu.team)
		_menu.add_item("降車: %s" % (sk.name if sk != null else pu.type_id), UNLOAD_ID_BASE + i)
		if state.has_moved(pu.id):
			_menu.set_item_disabled(_menu.get_item_index(UNLOAD_ID_BASE + i), true)
	if sel != null and base != null and base.team == sel.team and not base.garrison.is_empty():
		_menu.add_separator()
		var no_cells := controller.deploy_cells_for(dest).is_empty()
		for i in base.garrison.size():
			var gu: Unit = base.garrison[i]
			var gsk := SkinCatalog.resolve(_skin_catalog, gu.skin_id, gu.type_id, state.current_team)
			_menu.add_item("出撃: %s" % (gsk.name if gsk != null else gu.type_id), DEPLOY_ID_BASE + i)
			if no_cells or not state.can_deploy_garrison(dest, i):
				_menu.set_item_disabled(_menu.get_item_index(DEPLOY_ID_BASE + i), true)
	_menu.add_separator()
	_menu.add_item("キャンセル", MENU_CANCEL)
	_menu_handled = false
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
	_menu.popup()
	_sync_overlay()  # 移動先プレビューを描く

func _on_menu_id(id: int) -> void:
	_menu_handled = true
	if _unload_to != INVALID_HEX:
		_handle_unload_menu(id)
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
	if _menu.visible:
		_menu.hide()
	elif _choosing_target or _selected_id != -1:
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
	_menu.add_item("乗車", MENU_BOARD)
	_menu.add_separator()
	_menu.add_item("キャンセル", MENU_CANCEL)
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
	_menu.add_item("攻撃", MENU_ATTACK)
	_menu.set_item_disabled(_menu.get_item_index(MENU_ATTACK), not can_attack)
	_menu.add_item("占領" if will_capture else "待機", MENU_WAIT)
	_menu.add_separator()
	_menu.add_item("キャンセル", MENU_CANCEL)
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
				controller.stand(pid)
				_sync()
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
		var nm := sk.name if sk != null else gu.type_id
		_menu.add_item("出撃: %s" % nm, DEPLOY_ID_BASE + i)
		if not state.can_deploy_garrison(base_hex, i):
			_menu.set_item_disabled(_menu.get_item_index(DEPLOY_ID_BASE + i), true)
	_menu.add_separator()
	_menu.add_item("キャンセル", MENU_CANCEL)
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
	_selected_id = id
	_inspected_id = -1
	_inspect_reach.clear()
	_pending_to = INVALID_HEX
	_choosing_target = false
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
	_reachable.clear()
	_targets.clear()
	if _menu != null and _menu.visible:
		_menu.hide()
	if had != -1:
		selection_changed.emit(-1)
	_sync_overlay()

## 敵など操作できないユニットを閲覧（選択状態にはしない）。移動範囲＝脅威範囲だけ別色で出す。
func _inspect_unit(id: int) -> void:
	_selected_id = -1
	_pending_to = INVALID_HEX
	_choosing_target = false
	_reachable.clear()
	_targets.clear()
	_inspected_id = id
	_inspect_reach.clear()
	for h in controller.reachable_for(id):
		_inspect_reach[h] = true
	selection_changed.emit(id)
	_sync_overlay()

func _on_unit_moved(_unit_id: int, _from: Vector2i, _to: Vector2i) -> void:
	_sync()

func _on_unit_attacked(_attacker_id: int, _target_id: int, _damage: int, _killed: bool) -> void:
	_deselect()  # 攻撃したユニットは行動終了
	_sync()

func _on_unit_deployed(_unit_id: int, _base_hex: Vector2i, _to: Vector2i) -> void:
	_clear_deploy()
	_sync()

func _on_turn_changed(_team: int, _turn_number: int) -> void:
	_deselect()
	_clear_deploy()
	_clear_unload()
	_sync()

func _on_battle_finished(_winner: int) -> void:
	_locked = true
	_deselect()
	_clear_deploy()
	_clear_unload()

# =========================================================================
# 3D描画（タイル＝床のヘックスメッシュ / 駒＝ビルボード / オーバーレイ＝半透明マス）
# =========================================================================

## 盤の見た目を状態から作り直す（2D版の queue_redraw 相当）。
func _sync() -> void:
	_sync_units()
	_sync_overlay()

## 地形タイル・グリッド線・下地。bind（ステージ確定）ごとに作り直す。
func _build_tiles() -> void:
	_clear_children(_tiles_root)
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			_add_tile(hex)
	_add_grid()
	_add_ground()

func _add_tile(hex: Vector2i) -> void:
	var tid: String = state.terrain_at(hex)
	var skin := TerrainSkinCatalog.resolve(_terrain_skins.get(hex, ""), tid)
	if skin == null:
		return
	var variants: Array = _terrain_tex.get(skin.skin_id, [])
	if variants.is_empty() and not _terrain_tex.has(skin.skin_id):
		variants = _load_terrain_variants(skin.image_path())
		_terrain_tex[skin.skin_id] = variants
	if variants.is_empty():
		return
	var tex: Texture2D = variants[_terrain_variant(hex, variants.size())]
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_mesh
	mi.material_override = _terrain_material(tex)
	var p := Hex.to_pixel(hex, TILE)
	mi.position = Vector3(p.x, 0.0, p.y)
	if skin.orientable:
		# 向きは座標ハッシュから決定的に選ぶ（2D版と同じ流儀）＝盤は毎回同じ。
		var o := absi(hash(Vector2i(hex.y, hex.x)))
		mi.rotation.y = float(o % 6) * (PI / 3.0)
		if (o / 6) % 2 == 1:
			mi.scale = Vector3(-1.0, 1.0, 1.0)  # 左右反転（cull無効なので裏面でも描ける）
	_tiles_root.add_child(mi)

## ヘックスの輪郭線（セルの読み取り用・2D版の draw_polyline 相当）。全マスまとめて1メッシュ。
func _add_grid() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for col in state.cols:
		for row in state.rows:
			var p := Hex.to_pixel(Hex.offset_to_axial(col, row), TILE)
			for i in 6:
				var a0 := deg_to_rad(60.0 * i)
				var a1 := deg_to_rad(60.0 * (i + 1))
				im.surface_add_vertex(Vector3(p.x + cos(a0) * TILE, 0.01, p.y + sin(a0) * TILE))
				im.surface_add_vertex(Vector3(p.x + cos(a1) * TILE, 0.01, p.y + sin(a1) * TILE))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COLOR_LINE
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	_tiles_root.add_child(mi)

## 盤の下地（虚空に浮かないための大きな平面）。
func _add_ground() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for col in state.cols:
		for row in state.rows:
			var p := Hex.to_pixel(Hex.offset_to_axial(col, row), TILE)
			mn = mn.min(p)
			mx = mx.max(p)
	var c := (mn + mx) * 0.5
	var pm := PlaneMesh.new()
	pm.size = (mx - mn) + Vector2(60.0, 60.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.36, 0.40, 0.27)
	mi.material_override = m
	mi.position = Vector3(c.x, -0.02, c.y)
	_tiles_root.add_child(mi)

## 全ユニットの見た目を作り直す（数十体規模なので毎イベント作り直しで十分軽い）。
func _sync_units() -> void:
	_clear_children(_units_root)
	if state == null:
		return
	for u in state.units():
		var p := Hex.to_pixel(u.pos, TILE)
		var wpos := Vector3(p.x, 0.0, p.y)
		var done := state.is_done(u.id)
		var tex := _unit_texture(u)
		if tex != null:
			var spr := Sprite3D.new()
			spr.texture = tex
			spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 常にカメラへ正対＝立ち姿のまま
			spr.shaded = false
			spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD    # 半透明ソート回避（手前/奥が常に正しい）
			spr.pixel_size = (2.5 * TILE) / float(tex.get_height())  # 高さ ~2.5 タイル（2D版と同比率）
			spr.offset = Vector2(0, tex.get_height() * 0.5)   # 原点＝足元（接地・回転軸）
			spr.position = wpos + Vector3(0, 0.02, SPRITE_FOOT_Z)  # 足元は下辺寄り＝マスの中に立って見える
			if done:
				spr.modulate = Color(0.55, 0.55, 0.55)  # 行動終了は暗く
			_units_root.add_child(spr)
		else:
			_add_unit_placeholder(u, wpos, done)

## 画像なしユニットのプレースホルダ（チーム色の円盤＋スキン名ラベル。2D版の円＋文字と同義）。
func _add_unit_placeholder(u: Unit, wpos: Vector3, done: bool) -> void:
	var col: Color = TEAM_COLORS[u.team % TEAM_COLORS.size()]
	if done:
		col = col.darkened(0.45)
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.position = wpos + Vector3(0, 0.05, 0)
	_units_root.add_child(mi)
	var s: UnitSkin = SkinCatalog.resolve(_skin_catalog, u.skin_id, u.type_id, u.team)
	var label := s.map_label() if s != null else u.type_id.substr(0, 2)
	if label.is_empty():
		return
	var l := Label3D.new()
	l.text = label
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.pixel_size = 0.01
	l.modulate = COLOR_UNIT_LABEL
	l.position = wpos + Vector3(0, 0.6, 0)
	_units_root.add_child(l)

## オーバーレイ（範囲・候補・プレビュー・選択・攻撃対象・ホバー）を作り直す。
## 種類ごとに高さをずらして重なりのZファイトを避ける。
func _sync_overlay() -> void:
	_clear_children(_overlay_root)
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
	for pos in _targets:
		_add_cell(pos, COLOR_TARGET_FILL, 0.03)
	var sel := state.unit_by_id(_selected_id) if _selected_id != -1 else null
	if sel != null:
		_add_cell(sel.pos, COLOR_SELECT_FILL, 0.035)
	var ins := state.unit_by_id(_inspected_id) if _inspected_id != -1 else null
	if ins != null:
		_add_cell(ins.pos, COLOR_INSPECT_FILL, 0.035)
	if _hover != INVALID_HEX and _on_board(_hover):
		_add_cell(_hover, COLOR_HOVER, 0.04)

func _add_cell(hex: Vector2i, color: Color, y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _overlay_mesh
	mi.material_override = _overlay_material(color)
	var p := Hex.to_pixel(hex, TILE)
	mi.position = Vector3(p.x, y, p.y)
	_overlay_root.add_child(mi)

# --- メッシュ・材質・テクスチャのヘルパー ---

## 床(XZ)に寝かせたフラットトップ六角メッシュ（中心ファン）。UVはテクスチャの外接矩形。
func _make_hex_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a0 := deg_to_rad(60.0 * i)
		var a1 := deg_to_rad(60.0 * (i + 1))
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)); st.add_vertex(Vector3(cos(a0) * TILE, 0.0, sin(a0) * TILE))
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)); st.add_vertex(Vector3(cos(a1) * TILE, 0.0, sin(a1) * TILE))
	return st.commit()

## タイル材質（アンライト＝2D canvas と同じ発色）。テクスチャごとにキャッシュ。
func _terrain_material(tex: Texture2D) -> StandardMaterial3D:
	if _terrain_mat.has(tex):
		return _terrain_mat[tex]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 左右反転タイル（scale.x=-1）でも描けるように
	_terrain_mat[tex] = m
	return m

## オーバーレイ材質（半透明・アンライト）。色ごとにキャッシュ。
func _overlay_material(color: Color) -> StandardMaterial3D:
	if _overlay_mat.has(color):
		return _overlay_mat[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay_mat[color] = m
	return m

## スキンの map 画像テクスチャ（キャッシュ）。未設定/未配置は null＝プレースホルダ描画。
func _unit_texture(u: Unit) -> Texture2D:
	var s: UnitSkin = SkinCatalog.resolve(_skin_catalog, u.skin_id, u.type_id, u.team)
	if s == null:
		return null
	var p := s.image("map")
	if p == "":
		return null
	if not _unit_tex.has(p):
		_unit_tex[p] = load(p)
	return _unit_tex[p]

## 地形タイルを読む。基本 {name}.png ＋連番 variant（2D版と同一ロジック）。
func _load_terrain_variants(base_path: String) -> Array:
	var texs: Array = []
	var base := load(base_path) as Texture2D
	if base != null:
		texs.append(base)
	var stem := base_path.trim_suffix(".png")
	var n := 2
	while true:
		var p := "%s_%d.png" % [stem, n]
		if not ResourceLoader.exists(p):
			break
		var t := load(p) as Texture2D
		if t != null:
			texs.append(t)
		n += 1
	return texs

## ヘックス座標から決定的に variant を選ぶ（盤の再構築でも不変）。
func _terrain_variant(hex: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	return absi(hash(hex)) % count

func _clear_children(root: Node3D) -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.free()
