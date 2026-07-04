extends Node2D
class_name HexBoard
## ヘックス盤面とユニットの描画・入力。flat-top。
## Presentation 層: 状態(BattleState)は読むだけ。変更はコマンドを controller に渡し、
## 結果はシグナル(unit_moved/unit_attacked/turn_changed)を受けて再描画する。
##
## カメラ操作（doc/gdd/uiux.md 準拠）:
##   パン … 空き地から左ドラッグ（クリック/ドラッグはしきい値で判別。マウス・トラックパッド共通）。
##   ズーム … ホイール / ピンチ（カーソルか2本指中心を基点）。F … 全体表示。
##   ※Windows のトラックパッドは2本指スクロールがホイールと同一イベントのためズーム扱い（パンは左ドラッグで行う）。
##   盤自身の Node2D 変換(position/scale)で実現するため、HUD(兄弟ノード)には影響しない。
##   マウス判定は get_local_mouse_position() がノード変換を含むので、描画・入力側は変更不要。

## 選択中ユニットが変わったとき発行（id<0＝選択解除）。情報パネル等が購読する。
signal selection_changed(unit_id: int)
## ユニットのいない空きマスをクリックしたとき発行（地形・拠点情報を右パネルに出す）。
signal tile_inspected(hex: Vector2i)
## 戻る対象が無い最上位で Esc を押したとき発行（HUD がシステムメニューを開く）。
signal system_menu_requested

@export var hex_size: float = 36.0
@export var board_origin: Vector2 = Vector2(120, 100)
@export var min_zoom: float = 0.3
@export var max_zoom: float = 2.5

const ZOOM_STEP := 1.15
const INFOPANEL_LEFT := 800.0    # InfoPanel の左端（main.tscn の offset_left と一致）
const DRAG_THRESHOLD := 6.0      # この距離(px)を超えて動いたらクリックでなくパン
const PAN_GESTURE_SPEED := 24.0  # パンジェスチャ(macOS等の2本指)の感度
const PAN_WHEEL_STEP := 50.0     # 2本指スクロール1ノッチぶんのパン量(px)
var _press_pos := Vector2.ZERO   # 左ボタン押下位置（クリック/ドラッグ判別の起点・スクリーン座標）
var _press_on_empty := false     # 押下が空き地（ユニット無し）から始まったか＝パン許可
var _dragging_pan := false       # 左ドラッグでパン中

const COLOR_LINE := Color(0.78, 0.83, 0.90, 1.0)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.30)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_DEPLOY := Color(0.65, 0.45, 0.95, 0.40)  # 出撃先候補（移動の緑と区別）
const COLOR_SELECT_RING := Color(1.00, 0.85, 0.25)
const COLOR_ATTACK_RING := Color(0.95, 0.25, 0.25)
const COLOR_SURROUNDED := Color(0.95, 0.55, 0.15)
const TEAM_COLORS: Array[Color] = [Color(0.30, 0.55, 0.95), Color(0.92, 0.40, 0.35)]
const COLOR_BASE_NEUTRAL := Color(0.80, 0.80, 0.80)  # 未占領拠点の縁取り

const COLOR_UNIT_LABEL := Color(1, 1, 1, 0.95)

var state: BattleState
var controller: MatchController
var _terrain_tex := {}    # terrain_id(String) -> Texture2D（Terrain カタログから読み込み）
var _unit_tex := {}       # 画像パス(String) -> Texture2D（スキンの map スプライト・キャッシュ）
var _skin_catalog := {}   # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }（名前プレースホルダ用）

const INVALID_HEX := Vector2i(-9999, -9999)

var _hover := Vector2i(-9999, -9999)
var _selected_id := -1
var _reachable := {}  # Vector2i -> true
var _targets := {}    # Vector2i -> target_id（攻撃可能な敵の位置）
var _deploy_base := INVALID_HEX  # 出撃モード中の拠点（拠点メニューの「出撃」で入る）
var _deploy_cells := {}  # Vector2i -> true（出撃先候補）
var _locked := false  # 決着・AI手番中は入力を受けない

# コマンドメニュー（選択→移動先クリックで開く。移動は未確定＝キャンセルで戻せる）。
var _pending_to := INVALID_HEX  # メニュー表示中の移動先（未確定）
var _choosing_target := false   # 「攻撃」選択後＝攻撃対象クリック待ち
var _menu: PopupMenu = null     # 攻撃/待機/キャンセル のポップアップ
var _menu_handled := false      # 項目が選ばれたか（閉じただけ＝キャンセル判定用）
var _menu_base := INVALID_HEX   # 拠点メニュー中の対象拠点（出撃元）。コマンドメニュー時は無効値
var _deploy_index := 0          # 出撃する控え（garrison）の選択index
enum { MENU_ATTACK, MENU_WAIT, MENU_CANCEL, MENU_BOARD, MENU_ENTER }
const DEPLOY_ID_BASE := 100     # 拠点メニューの「出撃: 〈駒〉」項目の id。garrison index を加えて採番
const UNLOAD_ID_BASE := 200     # コマンドメニューの「降車: 〈駒〉」項目の id。搭乗 index を加えて採番

# 降車モード（輸送から駒を降ろす先を選んでいる状態）
var _unload_transport := -1     # 降車元の輸送ユニットid（-1=降車モードでない）
var _unload_index := 0          # 降ろす搭乗駒の index
var _unload_cells := {}         # Vector2i -> true（降車先候補）
var _unload_to := INVALID_HEX   # 降車確認メニュー中の降車先（未確定＝通常移動と同じ確認フロー）
const COLOR_PENDING := Color(1.00, 0.85, 0.25, 0.35)  # 移動先プレビュー（メニュー表示中）

func _ready() -> void:
	_menu = PopupMenu.new()  # ユニットコマンドメニュー（盤の子。Windowなのでカメラ変換の影響を受けない）
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu_id)
	_menu.popup_hide.connect(_on_menu_closed)

func bind(p_state: BattleState, p_controller: MatchController, p_skin_catalog: Dictionary = {}) -> void:
	state = p_state
	controller = p_controller
	_skin_catalog = p_skin_catalog
	if _terrain_tex.is_empty():  # タイル画像は1回だけ読む
		for id in Terrain.all_ids():
			_terrain_tex[id] = load(Terrain.image_path(id))
	_reset_interaction()  # ステージ再ロードに備え、選択・出撃・ロック状態を初期化
	controller.unit_moved.connect(_on_unit_moved)
	controller.unit_attacked.connect(_on_unit_attacked)
	controller.unit_deployed.connect(_on_unit_deployed)
	controller.unit_unloaded.connect(_on_unit_unloaded)
	controller.unit_entered_base.connect(func(_id: int, _hex: Vector2i) -> void: queue_redraw())
	controller.turn_changed.connect(_on_turn_changed)
	controller.battle_finished.connect(_on_battle_finished)
	fit_to_view()  # 新ステージの全体が画面に収まるよう初期ズーム/位置を合わせる
	queue_redraw()

## 選択・出撃モード・ロック・ホバーを初期状態へ（ステージ再ロード時に呼ぶ）。
func _reset_interaction() -> void:
	_selected_id = -1
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
	_hover = Vector2i(-9999, -9999)

func _process(_delta: float) -> void:
	if state == null:
		return
	var h := _hex_at_mouse()
	if h != _hover:
		_hover = h
		queue_redraw()

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
			position += event.relative  # 空き地ドラッグ＝パン
		return
	# --- 盤操作（自手番のみ）---
	if _locked or controller.is_ai_turn():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_cancel(false)  # 右クリック＝キャンセル・戻る（タッチは将来 長押し）
	elif event.is_action_pressed("ui_cancel"):  # Esc でキャンセル・戻る（最上位でシステムメニュー）
		_on_cancel(true)
	elif event.is_action_pressed("ui_accept"):  # Enter / Space で手番終了
		_deselect()
		controller.end_turn()

func _on_click(hex: Vector2i) -> void:
	# 降車モード中: 降車先候補をクリック → 確認メニュー（通常移動と同じ「選んで確定」フロー）。
	if _unload_transport != -1:
		if _unload_cells.has(hex):
			_open_unload_menu(hex)
			return
		_clear_unload()
	# 出撃モード中: 出撃先候補をクリック → 出撃。それ以外のクリックは出撃モードを抜けて通常処理。
	if _deploy_base != INVALID_HEX:
		if _deploy_cells.has(hex):
			controller.execute_deploy(DeployCommand.new(_deploy_base, _deploy_index, hex))
			return
		_clear_deploy()
	# 攻撃対象クリック待ち（メニューで「攻撃」を選んだ後）: 対象なら攻撃、それ以外は中止。
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
	# 現手番で操作可能なユニットをクリック → 選択（拠点上に駒がいれば駒選択を優先）。
	var clicked := state.unit_at(hex)
	if clicked != null and state.can_select(clicked.id):
		_select(clicked.id)
		return
	# 自軍の出撃可能な拠点をクリック → 拠点メニュー（出撃）。
	var b := state.base_at(hex)
	if b != null and b.team == state.current_team and not controller.deploy_cells_for(hex).is_empty():
		_open_base_menu(hex)
		return
	_deselect()
	if state.unit_at(hex) == null:
		tile_inspected.emit(hex)  # 空きマス＝地形（拠点なら控えも）を右パネルに表示

## 移動先（自マス含む）に対するコマンドメニューを開く。移動はまだ確定しない。
func _open_command_menu(dest: Vector2i) -> void:
	_pending_to = dest
	_menu_base = INVALID_HEX  # これはコマンドメニュー（拠点メニューではない）
	var can_attack := not controller.attack_targets_from(_selected_id, dest).is_empty()
	# 占領可ユニットが敵/中立の拠点へ進む移動先なら、待機の代わりに「占領」を見せる
	# （動作は待機と同じ＝移動確定で domain が自動占領する。ラベルだけ変える）。
	var sel := state.unit_by_id(_selected_id)
	var base := state.base_at(dest)
	var will_capture := sel != null and sel.can_capture and base != null and base.team != sel.team
	# 自軍所有の拠点が移動先なら「入る」（駐留＝回復）を出す。盤上最後の1体は入れない（暫定）。
	var can_enter := sel != null and base != null and base.team == sel.team \
			and state.team_unit_count(sel.team) > 1
	_menu.clear()
	_menu.add_item("攻撃", MENU_ATTACK)
	_menu.set_item_disabled(_menu.get_item_index(MENU_ATTACK), not can_attack)
	_menu.add_item("占領" if will_capture else "待機", MENU_WAIT)
	if can_enter:
		_menu.add_item("入る", MENU_ENTER)
	# 輸送で搭乗駒がいれば「降車: 〈駒〉」を並べる（乗車したターンの駒は無効表示）。
	# 駒自身の行動とは別グループなのでセパレーターで区切る。
	var pas := state.passengers(_selected_id)
	if not pas.is_empty():
		_menu.add_separator()
	for i in pas.size():
		var pu: Unit = pas[i]
		var sk := SkinCatalog.resolve(_skin_catalog, pu.skin_id, pu.type_id, pu.team)
		_menu.add_item("降車: %s" % (sk.name if sk != null else pu.type_id), UNLOAD_ID_BASE + i)
		if state.has_moved(pu.id):  # 乗車したターンは行動完了＝降りられない
			_menu.set_item_disabled(_menu.get_item_index(UNLOAD_ID_BASE + i), true)
	# 移動先が自軍所有の拠点で控え（garrison）がいれば「出撃: 〈駒〉」を並べる＝拠点の操作。
	# 上に駒が立っていても拠点の中の駒を出せる動線（出撃は garrison の行動＝降車と同じ扱い）。
	if sel != null and base != null and base.team == sel.team and not base.garrison.is_empty():
		_menu.add_separator()
		var no_cells := controller.deploy_cells_for(dest).is_empty()
		for i in base.garrison.size():
			var gu: Unit = base.garrison[i]
			var gsk := SkinCatalog.resolve(_skin_catalog, gu.skin_id, gu.type_id, state.current_team)
			_menu.add_item("出撃: %s" % (gsk.name if gsk != null else gu.type_id), DEPLOY_ID_BASE + i)
			if no_cells or not state.can_deploy_garrison(dest, i):  # 出口なし／閉じ込め＝無効表示
				_menu.set_item_disabled(_menu.get_item_index(DEPLOY_ID_BASE + i), true)
	_menu.add_separator()
	_menu.add_item("キャンセル", MENU_CANCEL)
	_menu_handled = false
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
	_menu.popup()
	queue_redraw()  # 移動先プレビューを描く

func _on_menu_id(id: int) -> void:
	_menu_handled = true
	if _unload_to != INVALID_HEX:  # 降車確認メニュー（攻撃/占領・待機/キャンセル）
		_handle_unload_menu(id)
		return
	if id >= UNLOAD_ID_BASE:  # 「降車: 〈駒〉」（id に搭乗 index を埋め込み）
		var tid := _selected_id
		_commit_pending_move()  # 保留中の移動があれば確定（移動してから降ろす）
		_enter_unload(tid, id - UNLOAD_ID_BASE)
		return
	if id >= DEPLOY_ID_BASE:  # 「出撃: 〈駒〉」（id に garrison index を埋め込み）
		_deploy_index = id - DEPLOY_ID_BASE
		var from := _menu_base  # 拠点メニュー経由＝拠点そのもの
		if from == INVALID_HEX:  # コマンドメニュー経由（拠点の上の駒／拠点へ移動中の駒）
			from = _pending_to
			_commit_pending_move()  # 保留中の移動があれば確定してから出す
			_deselect()
		_enter_deploy(from)  # 出撃モードへ（候補マスをハイライト）
		return
	match id:
		MENU_ATTACK:
			_commit_pending_move()
			_reachable.clear()
			_targets.clear()
			for tid in controller.attack_targets_for(_selected_id):  # 移動後の位置から狙える敵
				var u := state.unit_by_id(tid)
				if u != null:
					_targets[u.pos] = tid
			_choosing_target = true
			queue_redraw()
		MENU_WAIT:
			_commit_pending_move()
			controller.stand(_selected_id)  # 移動だけ／動かず＝この駒の行動を終了
			_deselect()
		MENU_BOARD:
			# 乗車: 輸送のマスへの移動を確定（domain 側で搭乗処理される）。乗った駒は行動完了。
			if _pending_to != INVALID_HEX:
				controller.execute(MoveCommand.new(_selected_id, _pending_to))
			_deselect()
		MENU_ENTER:
			# 入る（駐留）: 移動を確定してから拠点の中へ＝盤上から消えて garrison になる。
			_commit_pending_move()
			controller.enter_base(_selected_id)
			_deselect()
		MENU_CANCEL:
			_deselect()  # 移動そのものを取りやめ＝選択解除（別マスを選ぶだけなら直接そのマスをクリック）

## メニューが閉じた。id_pressed と popup_hide の発火順は環境差があるため、
## 判定を1フレーム遅らせ、項目選択（_on_menu_id）が先に処理されるようにする。
func _on_menu_closed() -> void:
	call_deferred("_after_menu_closed")

## 項目を選ばず閉じた（外側クリック / Esc）＝キャンセル扱いで選択状態へ戻す。
## 降車確認中なら降車先だけ解除（降車モードは維持＝候補から選び直せる）。
func _after_menu_closed() -> void:
	if not _menu_handled:
		_pending_to = INVALID_HEX
		_unload_to = INVALID_HEX
		queue_redraw()

## 保留中の移動を確定（自マスのままなら移動しない）。
func _commit_pending_move() -> void:
	var sel := state.unit_by_id(_selected_id)
	if sel != null and _pending_to != INVALID_HEX and _pending_to != sel.pos:
		controller.execute(MoveCommand.new(_selected_id, _pending_to))
	_pending_to = INVALID_HEX

## 「戻る」。メニュー→選択→出撃モードの順に1段ずつ解除。
## 戻る対象が無く from_esc なら最上位＝システムメニューを開く（右クリックでは開かない）。
func _on_cancel(from_esc: bool) -> void:
	if _menu.visible:
		_menu.hide()  # popup_hide がキャンセル処理する
	elif _choosing_target or _selected_id != -1:
		_deselect()
	elif _unload_transport != -1:
		_clear_unload()
	elif _deploy_base != INVALID_HEX:
		_clear_deploy()
	elif from_esc:
		system_menu_requested.emit()

## 到達範囲内の味方輸送をクリック → 乗車メニュー（乗車／キャンセル）。移動は未確定のまま開く。
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
	queue_redraw()  # 移動先（輸送のマス）プレビュー

## 降車モードに入り、降車先候補（搭乗駒が自力で動ける空きhex）をハイライトする。
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
	queue_redraw()

## 降車先に対する確認メニュー（通常移動のコマンドメニューと同じ並び）。降車はまだ確定しない。
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
	queue_redraw()  # 降車先プレビュー

## 降車確認メニューの選択。攻撃＝降車を確定して対象選び、占領/待機＝確定して行動終了、
## キャンセル＝降車を取りやめ（乗ったまま）。
func _handle_unload_menu(id: int) -> void:
	var dest := _unload_to
	_unload_to = INVALID_HEX
	match id:
		MENU_ATTACK:
			var pid: int = state.passengers(_unload_transport)[_unload_index].id
			if controller.execute_unload(UnloadCommand.new(_unload_transport, _unload_index, dest)):
				_selected_id = pid  # 降りた駒で攻撃対象選びへ（通常の 移動→攻撃 と同じ流れ）
				_targets.clear()
				for tid in controller.attack_targets_for(pid):
					var u := state.unit_by_id(tid)
					if u != null:
						_targets[u.pos] = tid
				_choosing_target = true
				selection_changed.emit(pid)
				queue_redraw()
		MENU_WAIT:
			var pid: int = state.passengers(_unload_transport)[_unload_index].id
			if controller.execute_unload(UnloadCommand.new(_unload_transport, _unload_index, dest)):
				controller.stand(pid)  # 降りるだけ＝行動終了（占領は進入した時点で済んでいる）
				queue_redraw()
		MENU_CANCEL:
			_clear_unload()  # 降車を取りやめ＝乗ったまま

func _clear_unload() -> void:
	_unload_transport = -1
	_unload_cells.clear()
	_unload_to = INVALID_HEX
	queue_redraw()

func _on_unit_unloaded(_unit_id: int, _transport_id: int, _to: Vector2i) -> void:
	# 確定した降車のあと、候補ハイライトを消す（攻撃対象選びの状態は _handle_unload_menu が組む）。
	_unload_transport = -1
	_unload_cells.clear()
	queue_redraw()

## 自軍の出撃可能な拠点をクリック → 拠点メニュー（控えを1体ずつ並べる＋キャンセル）。
func _open_base_menu(base_hex: Vector2i) -> void:
	_deselect()  # 選択状態は解いて拠点メニューへ移る
	_menu_base = base_hex
	tile_inspected.emit(base_hex)
	_menu.clear()
	var b := state.base_at(base_hex)
	for i in b.garrison.size():  # 出撃させる駒を選ばせる（id に garrison index を埋め込む）
		var gu: Unit = b.garrison[i]
		var sk := SkinCatalog.resolve(_skin_catalog, gu.skin_id, gu.type_id, state.current_team)
		var nm := sk.name if sk != null else gu.type_id
		_menu.add_item("出撃: %s" % nm, DEPLOY_ID_BASE + i)
		if not state.can_deploy_garrison(base_hex, i):  # native不一致＝閉じ込め（奪還されるまで出せない）
			_menu.set_item_disabled(_menu.get_item_index(DEPLOY_ID_BASE + i), true)
	_menu.add_separator()
	_menu.add_item("キャンセル", MENU_CANCEL)
	_menu_handled = false
	_menu.reset_size()
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
	_menu.popup()

## 出撃モードに入り、出撃先候補（拠点の隣接空き＋その駒が乗れる輸送のマス）をハイライトする。
func _enter_deploy(base_hex: Vector2i) -> void:
	var cells := controller.deploy_cells_for(base_hex, _deploy_index)
	if cells.is_empty():
		return
	_deploy_base = base_hex
	_deploy_cells.clear()
	for c in cells:
		_deploy_cells[c] = true
	queue_redraw()

func _clear_deploy() -> void:
	_deploy_base = INVALID_HEX
	_deploy_cells.clear()
	queue_redraw()

func _select(id: int) -> void:
	_selected_id = id
	_pending_to = INVALID_HEX
	_choosing_target = false
	_reachable.clear()
	_targets.clear()
	if state.can_still_move(id):  # まだ動けるなら（残り移動力ぶん）移動範囲を出す
		for h in controller.reachable_for(id):
			_reachable[h] = true
	selection_changed.emit(id)  # 攻撃対象はコマンドメニューの「攻撃」選択後に表示する
	queue_redraw()

func _deselect() -> void:
	var had := _selected_id
	_selected_id = -1
	_pending_to = INVALID_HEX
	_choosing_target = false
	_reachable.clear()
	_targets.clear()
	if _menu != null and _menu.visible:
		_menu.hide()
	if had != -1:
		selection_changed.emit(-1)
	queue_redraw()

func _on_unit_moved(_unit_id: int, _from: Vector2i, _to: Vector2i) -> void:
	# 移動はコマンドメニュー側が駆動するため、ここは再描画のみ（選択遷移は明示的に行う）。
	queue_redraw()

func _on_unit_attacked(_attacker_id: int, _target_id: int, _damage: int, _killed: bool) -> void:
	_deselect()  # 攻撃したユニットは行動終了

func _on_unit_deployed(_unit_id: int, _base_hex: Vector2i, _to: Vector2i) -> void:
	# 1体出撃したら出撃モードを抜ける。続けて出すなら拠点を再クリックして駒を選び直す。
	_clear_deploy()

func _on_turn_changed(_team: int, _turn_number: int) -> void:
	_deselect()
	_clear_deploy()
	_clear_unload()

func _on_battle_finished(_winner: int) -> void:
	_locked = true
	_deselect()
	_clear_deploy()
	_clear_unload()

func _hex_at_mouse() -> Vector2i:
	return Hex.from_pixel(get_local_mouse_position() - board_origin, hex_size)

# --- カメラ（パン/ズーム/全体表示）。盤の Node2D 変換を直接動かす。HUD は兄弟なので無影響。---
# 左ドラッグのパンは _unhandled_input 側でクリック判別と一体で扱う。ここはスクロール/ジェスチャ。

## スクロール（2本指/ピンチ/ホイール）・全体表示を処理。消費したら true。
## Windows のトラックパッドでは「ピンチ＝Ctrl＋ホイール」「2本指スクロール＝修飾なしホイール」で届く。
## この Ctrl の有無で判別: 修飾なし＝パン、Ctrl付き＝ズーム（カーソル基点）。
func _handle_camera_scroll(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index >= MOUSE_BUTTON_WHEEL_UP and event.button_index <= MOUSE_BUTTON_WHEEL_RIGHT:
		if event.ctrl_pressed:  # ピンチ＝ズーム
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at_point(ZOOM_STEP, get_viewport().get_mouse_position())
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at_point(1.0 / ZOOM_STEP, get_viewport().get_mouse_position())
		else:  # 2本指スクロール＝パン（上下左右）
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP: position.y += PAN_WHEEL_STEP
				MOUSE_BUTTON_WHEEL_DOWN: position.y -= PAN_WHEEL_STEP
				MOUSE_BUTTON_WHEEL_LEFT: position.x += PAN_WHEEL_STEP
				MOUSE_BUTTON_WHEEL_RIGHT: position.x -= PAN_WHEEL_STEP
		return true
	if event is InputEventMagnifyGesture:  # macOS等のピンチ（Windowsでは通常来ない）
		_zoom_at_point(event.factor, event.position)
		return true
	if event is InputEventPanGesture:  # macOS等の2本指パン（Windowsでは通常来ない）
		position -= event.delta * PAN_GESTURE_SPEED
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		fit_to_view()
		return true
	return false

## pivot（親座標）を基点に拡大率を factor 倍する（pivot 下のワールド点を固定）。
func _zoom_at_point(factor: float, pivot: Vector2) -> void:
	var old := scale.x
	var ns := clampf(old * factor, min_zoom, max_zoom)
	if is_equal_approx(ns, old):
		return
	position = pivot - (pivot - position) * (ns / old)  # pivot 下の点を動かさないよう補正
	scale = Vector2(ns, ns)

## 盤全体が HUD を避けた表示領域に収まるよう scale/position を合わせる（読み込み時・F キー）。
func fit_to_view() -> void:
	if state == null:
		return
	var content := _content_bounds_local()
	if content.size.x <= 0.0 or content.size.y <= 0.0:
		return
	var view := _view_rect()
	var s := minf(view.size.x / content.size.x, view.size.y / content.size.y)
	s = clampf(s, min_zoom, 1.0)  # 拡大は等倍まで（小マップを巨大化しない）
	scale = Vector2(s, s)
	position = view.get_center() - content.get_center() * s

## 盤の描画範囲（ローカル座標・等倍）。全ヘックス中心の外接矩形を1ヘックスぶん広げて返す。
func _content_bounds_local() -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for col in state.cols:
		for row in state.rows:
			var c := board_origin + Hex.to_pixel(Hex.offset_to_axial(col, row), hex_size)
			mn.x = minf(mn.x, c.x); mn.y = minf(mn.y, c.y)
			mx.x = maxf(mx.x, c.x); mx.y = maxf(mx.y, c.y)
	var ext := Vector2(hex_size, hex_size * Hex.SQRT3 * 0.5)  # ヘックス半幅・半高
	return Rect2(mn - ext, (mx - mn) + ext * 2.0)

## 盤を表示してよい画面領域（HUD: 上の Title と右の InfoPanel を避ける）。
func _view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var right := minf(vp.x, INFOPANEL_LEFT)
	var margin := 16.0
	var top := 64.0  # Title の下
	return Rect2(margin, top, maxf(right - margin * 2.0, 1.0), maxf(vp.y - top - margin, 1.0))

func _draw() -> void:
	if state == null:
		return
	for col in state.cols:
		for row in state.rows:
			_draw_tile(Hex.offset_to_axial(col, row))
	for b in state.bases():
		_draw_base(b)
	for u in _units_in_draw_order():
		_draw_unit(u)

## 駒の重なり順：offset の row→col 昇順で描く＝row/col が大きい駒ほど後で描かれ手前に来る。
## row（縦）が重なりを支配するので主キー、col は同 row 内のタイブレーク。
## ドメインの _units は不変（描画用にコピーを並べ替えるだけ）。
func _units_in_draw_order() -> Array:
	var us := state.units().duplicate()
	us.sort_custom(func(a: Unit, b: Unit) -> bool:
		var oa := Hex.axial_to_offset(a.pos)
		var ob := Hex.axial_to_offset(b.pos)
		if oa.y != ob.y:
			return oa.y < ob.y
		return oa.x < ob.x
	)
	return us

## 拠点の所属（縁取りの色）と控え数（garrison）を描く。地形タイルの上・ユニットの下。
func _draw_base(b: Base) -> void:
	var center := board_origin + Hex.to_pixel(b.hex, hex_size)
	var col := COLOR_BASE_NEUTRAL
	if b.team >= 0:
		col = TEAM_COLORS[b.team % TEAM_COLORS.size()]
	# 所属を示す六角の縁取り（地形タイルの淵に沿わせる）。
	var ring := _corners(center)
	ring.append(ring[0])
	draw_polyline(ring, col, 3.0, true)
	# 控え数（出撃できる人数）を左上に小さく。
	if not b.garrison.is_empty():
		var font := ThemeDB.fallback_font
		var fs := int(hex_size * 0.42)
		var pos := center + Vector2(-hex_size * 0.5, -hex_size * 0.30)
		draw_string(font, pos, "+%d" % b.garrison.size(), HORIZONTAL_ALIGNMENT_LEFT, hex_size, fs, col)

func _draw_tile(hex: Vector2i) -> void:
	var center := board_origin + Hex.to_pixel(hex, hex_size)
	var pts := _corners(center)
	_draw_terrain(hex, center)  # 地形タイル（一番下）
	if _reachable.has(hex):
		draw_colored_polygon(pts, COLOR_REACH)
	if _deploy_cells.has(hex) or _unload_cells.has(hex):
		draw_colored_polygon(pts, COLOR_DEPLOY)  # 出撃・降車の候補は同系色（紫）
	if hex == _pending_to or hex == _unload_to:
		draw_colored_polygon(pts, COLOR_PENDING)  # メニュー表示中の移動先/降車先プレビュー
	if hex == _hover:
		draw_colored_polygon(pts, COLOR_HOVER)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, COLOR_LINE, 1.5, true)

## hex の地形タイル画像を、ヘックス寸法にフィットさせて描く。
func _draw_terrain(hex: Vector2i, center: Vector2) -> void:
	var tex: Texture2D = _terrain_tex.get(state.terrain_at(hex))
	if tex == null:
		return
	var w := hex_size * 2.0          # 頂点〜頂点
	var h := hex_size * Hex.SQRT3     # 上下の平辺間
	draw_texture_rect(tex, Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)), false)

func _draw_unit(u: Unit) -> void:
	var center := board_origin + Hex.to_pixel(u.pos, hex_size)
	var col: Color = TEAM_COLORS[u.team % TEAM_COLORS.size()]
	if state.is_done(u.id):
		col = col.darkened(0.45)  # 行動終了は暗く
	if Surround.factor(state, u) < 1.0:  # 包囲中（攻防に係数<1.0）を明示
		draw_arc(center, hex_size * 0.86, 0.0, TAU, 24, COLOR_SURROUNDED, 2.5)
	var tex := _unit_texture(u)
	if tex != null:
		_draw_unit_sprite(tex, center, state.is_done(u.id))
	else:
		draw_circle(center, hex_size * 0.55, col)
		_draw_unit_label(u, center)
	# 輸送の搭載数（乗っている駒の数）を左上に小さく（拠点の garrison 表示と同じ流儀）。
	var pcount := state.passengers(u.id).size()
	if pcount > 0:
		var pfont := ThemeDB.fallback_font
		var pfs := int(hex_size * 0.42)
		var ppos := center + Vector2(-hex_size * 0.5, -hex_size * 0.30)
		draw_string(pfont, ppos, "+%d" % pcount, HORIZONTAL_ALIGNMENT_LEFT, hex_size, pfs, COLOR_UNIT_LABEL)
	if u.id == _selected_id:
		draw_arc(center, hex_size * 0.70, 0.0, TAU, 32, COLOR_SELECT_RING, 3.0)
	if _targets.has(u.pos):
		draw_arc(center, hex_size * 0.72, 0.0, TAU, 32, COLOR_ATTACK_RING, 3.0)
	_draw_troops_bar(u, center)

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

## map スプライト（256セル）を描く。足元をヘックス下辺付近に接地。行動終了は暗く。
func _draw_unit_sprite(tex: Texture2D, center: Vector2, done: bool) -> void:
	var s := hex_size * 2.5                       # セル画像の画面上サイズ（256px四方→この正方形）
	var bottom_y := center.y + hex_size * 0.75    # セル下辺（＝足元）＝ヘックス下辺付近に接地
	var rect := Rect2(center.x - s * 0.5, bottom_y - s, s, s)
	var mod: Color = Color(0.55, 0.55, 0.55) if done else Color.WHITE
	draw_texture_rect(tex, rect, false, mod)

## ユニットのマップ表示プレースホルダ（スキン名の先頭2文字）。画像が来たら差し替え予定。
func _draw_unit_label(u: Unit, center: Vector2) -> void:
	var s: UnitSkin = SkinCatalog.resolve(_skin_catalog, u.skin_id, u.type_id, u.team)
	var label := s.map_label() if s != null else u.type_id.substr(0, 2)
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fs := int(hex_size * 0.5)
	var w := hex_size * 1.6
	var pos := center + Vector2(-w * 0.5, fs * 0.36)  # ざっくり中央寄せ
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, w, fs, COLOR_UNIT_LABEL)

func _draw_troops_bar(u: Unit, center: Vector2) -> void:
	# 兵数バー（残存兵数 / 満員）。駒の足元（ヘックス下辺付近）に置く。
	var w := hex_size
	var h := 5.0
	var top_left := Vector2(center.x - w * 0.5, center.y + hex_size * 0.72)
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0, 0, 0, 0.6))
	var ratio := clampf(float(u.troops) / float(u.max_troops), 0.0, 1.0)
	draw_rect(Rect2(top_left, Vector2(w * ratio, h)), Color(0.30, 0.90, 0.40))

func _corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
	return pts
