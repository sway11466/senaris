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
const FOCUS_PAN_SEC := 0.25          # AIターンのカメラ追従＝1回のパンにかける秒数（なめらかに）
const FOCUS_MARGIN := 96.0           # 追従の安全域(デッドゾーン)＝可視域の内側マージン(px)。この内なら動かさない
const FOCUS_PULL_IN := 40.0          # 追従時は縁ちょうどでなく安全域の少し内側まで入れる（俯角の換算誤差・境界の揺れを吸収）
const SPRITE_FOOT_Z := TILE * 0.6  # 立ち絵の足元をヘックス中心から手前（下辺寄り）へ
## 立ち絵PNGの「キャンバス高さ」が何タイルぶんに当たるか。絵そのものではなくキャンバスを基準に
## するのは、大小関係を余白として焼き込んでいるため（小さい駒＝同じ枠で絵が小さい）。
## tools/gen_unit_map.ps1 の $Canvas / $BaseHeight と対で決まる＝どちらか変えたら両方直す。
## 384 / 200 × 1.95タイル ＝ 3.75（倍率1.0の駒が約1.95タイルの背丈になる）。
const UNIT_CANVAS_TILES := 3.75
const SKIRT_DEPTH := TILE * 0.45   # 盤外周の側面（ジオラマの島の厚み）
## 見た目の高さ（elevation）と立ち絵の沈み（sprite_sink）はスキン側のデータ＝terrain_skin.csv。
## 高さは段差辺に側面スカートを生やす（崖は台地より高い＝登れる高台と登れない絶壁を序列で見せる）。
## 沈めるのは立ち絵だけ（影・兵数バー・リングは上面のまま）＝盤の読み取りは従来どおり。
## 高さと同値の沈みにすると足元がまわりの地面と揃う＝背丈は平地の駒のまま、沈めたぶんだけ隠れる。
const SKIRT_DARKEN := 0.55         # 側面の暗さ（タイル平均色をこの割合で darkened）
const COLOR_SHADOW := Color(0, 0, 0, 0.28)     # 足元のブロブシャドウ
## ユニットスキルが効いている駒の足元の光。強化と弱体を色で分け、両方効いていれば両方出す
## （弱体＝内側の塗り／強化＝その外周の輪）。仕様 → doc/gdd/skills.md 共通ルール
const COLOR_SKILL_GLOW := Color(0.85, 1.00, 0.55)  # 強化（黄緑）
## 弱体（紫）。赤は敵陣営の色と紛れるので避ける。地形は明るい緑〜土色が多いので、
## 明度を落とした濃い紫にする＝淡い紫だと明るい地形に沈んで気づけない。
const COLOR_SKILL_DEBUFF := Color(0.42, 0.12, 0.68)
## どちらも輪にする。塗りにすると立ち絵の足元に隠れて前側の三日月しか見えない（実機で確認）。
## 弱体を内側・太く、強化を外側・細く＝重なっても互いを潰さず、面積の差で弱体のほうが目に付く。
const SKILL_DEBUFF_INNER := TILE * 0.46
const SKILL_DEBUFF_OUTER := TILE * 0.80
const SKILL_RING_INNER := TILE * 0.84
const SKILL_RING_OUTER := TILE * 1.02
const SKILL_GLOW_MIN := 0.35             # 明滅の下限アルファ（強化の輪＝加算合成）
const SKILL_GLOW_MAX := 0.85             # 同・上限
## 弱体の塗りは通常合成なので、加算の輪と同じ数字では薄く出る。下限を上げて常に読めるようにする。
const SKILL_DEBUFF_MIN := 0.55
const SKILL_DEBUFF_MAX := 0.92
const SKILL_GLOW_CYCLE := 1.6            # 明滅の周期（秒）
const CAM_PITCH_DEG := 52.0      # カメラ俯角（プローブで確認した見え方）
const CAM_FOV := 42.0
const MIN_DIST := 5.0            # ズーム＝カメラ距離の範囲
const MAX_DIST := 90.0
const ZOOM_STEP := 1.15
const INFOPANEL_LEFT := UiLayout.RIGHT_BOX_LEFT    # InfoPanel の左端（レイアウト定数は ui_layout.gd に集約）
const DRAG_THRESHOLD := 6.0      # この距離(px)を超えて動いたらクリックでなくパン
const PAN_GESTURE_SPEED := 24.0  # パンジェスチャ(macOS等の2本指)の感度
const PAN_WHEEL_STEP := 50.0     # 2本指スクロール1ノッチぶんのパン量(px)

const COLOR_LINE := Color(0.78, 0.83, 0.90, 0.45)
const COLOR_HOVER := Color(0.30, 0.62, 1.00, 0.30)
const COLOR_REACH := Color(0.25, 0.85, 0.55, 0.30)
const COLOR_DEPLOY := Color(0.65, 0.45, 0.95, 0.40)  # 出撃先候補（移動の緑と区別）
const COLOR_ENEMY_REACH := Color(0.95, 0.35, 0.30, 0.22)  # 敵の移動（脅威）範囲
const COLOR_SIGHT_EDGE := Color(0.95, 0.25, 0.25)  # 索敵の検知域の外周線（赤）＝待機中の見張りの視界。塗らず境界だけ
const SIGHT_EDGE_WIDTH := 0.16  # 検知域の外周線の太さ（TILE 比＝ヘックス幅の16%。実機で調整可）
const COLOR_FORMATION_RANGE := Color(0.55, 0.45, 0.95, 0.18)  # 陣形の着弾可能hex（射程内）
const COLOR_FORMATION_BLAST := Color(0.95, 0.35, 0.85, 0.34)  # 陣形の着弾プレビュー（面）
# 陣形スキルの着弾演出（→ doc/gdd/formations.md 発動の演出）。揺れ→面の光→被弾した駒を1体ずつ。
const COLOR_FORMATION_HIT := Color(1.00, 0.82, 0.40)  # 着弾した面の光（金）
const HIT_LEAD_SEC := 0.10        # 揺れてから面が光るまでの間（同時に出すと1つの衝撃に潰れる）
const HIT_CELL_RISE := 0.07       # 面の光の立ち上がり
const HIT_CELL_SETTLE := 0.18     # 立ち上がりから居座りの濃さへ落とすまで
const HIT_CELL_HOLD := 0.16       # 同・居座り（この間に駒の処理が進む）
const HIT_CELL_FADE := 0.32       # 同・引き
const HIT_CELL_ALPHA := 0.34      # 同・立ち上がりの濃さ（加算合成。これ以上は地形が白く飛ぶ）
const HIT_CELL_ALPHA_HOLD := 0.13 # 同・居座りの濃さ。駒に重ねるエフェクトを埋もれさせない
const HIT_STEP_SEC := 0.13        # 駒1体ぶんの間隔＝何体が受けたのかを数えられる範囲で詰める
const HIT_DROP_SEC := 0.16        # 駒に落とすエフェクトの落下時間（着弾＝ここで駒が反応する）
const HIT_DROP_FROM := TILE * 2.0 # 同・落とし始める高さ（駒の頭より上）
const HIT_BURST_SEC := 0.18       # 同・着弾して弾けて消えるまで
const HIT_BURST_TILES := 2.2      # 同・大きさの基準（scale 1.0 でヘックス幅の何倍か）
const HIT_BURST_OPEN := 1.35      # 同・着弾で開く倍率
const HIT_FLASH_SEC := 0.14       # 被弾フラッシュ（立ち絵を白く飛ばす）の片道
const HIT_FLASH_GAIN := 2.2       # 同・明るさの倍率
const HIT_FADE_SEC := 0.22        # 撃破された駒が消えるまで
const SHAKE_PX := 7.0             # 着弾の揺れ幅（画面px。盤と2D側で同じ量を使う）
const SHAKE_STEP := 0.05          # 同・1振りの秒数
const COLOR_PENDING := Color(1.00, 0.85, 0.25, 0.35)  # 移動先プレビュー（メニュー表示中）
const COLOR_SELECT_RING := Color(1.00, 0.85, 0.25)
const COLOR_ATTACK_RING := Color(0.95, 0.25, 0.25)
const COLOR_INSPECT_RING := Color(0.85, 0.90, 1.00)
const COLOR_SURROUNDED := Color(0.95, 0.55, 0.15)
const COLOR_BASE_NEUTRAL := Color(0.80, 0.80, 0.80)  # 未占領拠点の縁取り
const COLOR_TROOPS_BG := Color(0, 0, 0, 0.6)
const COLOR_TROOPS_FILL := Color(0.30, 0.90, 0.40)
const TEAM_COLORS: Array[Color] = [Color(0.30, 0.55, 0.95), Color(0.92, 0.40, 0.35)]
const COLOR_UNIT_LABEL := Color(1, 1, 1, 0.95)

## 攻撃対象マーカー＝対象の頭上に浮かぶ下向きの三角。深度判定を切って常に最前面に描く。
## 地面の輪だけでは読めないため。俯角52°では手前の地形が 高さ×0.78 ぶんの奥行を隠し
## （壁0.70＝ヘックスの奥行の3割強）、輪の奥側は対象の立ち絵が覆う＝前後から挟まれる。
## 立ち絵は足元が手前（SPRITE_FOOT_Z）に出て背も高いので、駒の高さに置けば地形に負けない。
## クリックの入口になる記号は地面に置かない（仕様 → doc/gdd/uiux.md 盤の表示記号）。
const COLOR_ATTACK_MARK := Color(0.98, 0.22, 0.20)
## 縁取りは黒。赤が主色の背景（火口・炎）が来ても輪郭が残るように、明度で分ける。
## 盤の現状（緑・灰・黒）では赤だけで足りるが、後から足すと絵の調整をやり直すことになる。
const COLOR_ATTACK_MARK_EDGE := Color(0.06, 0.03, 0.03)
const MARK_W := TILE * 0.42        # マーカーの横幅
const MARK_H := TILE * 0.38        # 同・高さ（下向きの先端までの深さ）
const MARK_EDGE := TILE * 0.035    # 縁取りの張り出し（全周で等距離）
const MARK_GAP := TILE * 0.16      # 頭のてっぺんから縁取りの先端までの隙間
const MARK_BOB := TILE * 0.06      # 上下の揺れ幅（止まっていると背景の模様に紛れる）
const MARK_BOB_CYCLE := 1.1        # 同・周期（秒）
## 引いた画角での最小の大きさ(px)。盤全体を映すと1ヘックスが39px まで縮み、素のままだと
## マーカーは8px＝探せない。これを下回るぶんだけ拡大する（寄った画角では等倍のまま）。
const MARK_MIN_PX := 18.0
const MARK_MAX_SCALE := 2.5        # 拡大の上限（際限なく大きくすると盤を覆う）

const INVALID_HEX := Vector2i(-9999, -9999)

var state: BattleState
var controller: MatchController
var _terrain_tex := {}    # skin_id(String) -> Array[Texture2D]（基本＋連番 variant）
var _terrain_skins := {}  # Vector2i -> skin_id（ステージの見た目差分。盤外＝外周のセルも書ける）
## Vector2i -> terrain_id（外周＝盤の外側1周ぶんの地形。作者が描いたもの）。
## 描かないし駒も入らない＝接続タイル（柵・道）が「盤の外に何があるか」を引くためだけのデータ。
## 空＝外周なしで、そのときだけ縁の推測（面は丸め込み／線は腕を伸ばす）に落ちる。
var _margin_terrain := {}
var _side_tex := {}           # skin_id -> Texture2D|null（側面画像。置いていなければ null）
var _tile_nodes := {}         # Vector2i -> MeshInstance3D（占領で拠点タイルを貼り替えるため）
var _elev_cache := {}         # Vector2i -> float（スキン解決の結果。_build_tiles で捨てる）
var _elev_levels_cache: Array = []  # 盤に実在する標高レベル（高い順）。同上
var _unit_tex := {}       # 画像パス(String) -> Texture2D
var _skin_catalog := {}   # type_id -> { ally:[UnitSkin], enemy:[UnitSkin] }

# --- カメラリグ（俯角固定・注視点とdistだけ動かす）---
var _cam: Camera3D
var _cam_target := Vector3.ZERO
var _cam_dist := 20.0
var _cam_up := Vector3.UP  # カメラの上方向（_update_camera が入れる）。頭上マーカーの持ち上げ向き
var _press_pos := Vector2.ZERO   # 左ボタン押下位置（クリック/ドラッグ判別の起点・スクリーン座標）
var _press_on_empty := false     # 押下が空き地（ユニット無し）から始まったか＝パン許可
var _dragging_pan := false       # 左ドラッグでパン中

# --- シーン構造（_ready で組む）---
var _tiles_root: Node3D    # 地形タイル＋グリッド線＋下地（bind ごとに作り直し）
var _bases_root: Node3D    # 拠点の縁取り・控え数（占領で変わるのでイベントごとに作り直し）
var _units_root: Node3D    # ユニット（イベントごとに作り直し）
var _overlay_root: Node3D  # 範囲・ホバー等の半透明マス（変化ごとに作り直し）
var _fx_root: Node3D       # 一時的な演出（着弾の光・駒に重ねるエフェクト）。オーバーレイの作り直しで消えない層
var _hex_mesh: ArrayMesh          # 床に寝かせたヘックス（タイル用・UVは外接矩形）
var _overlay_mesh: ArrayMesh      # オーバーレイ用（同形・材質だけ変える）
var _hexring_mesh: ArrayMesh      # 拠点の縁取り（六角の枠）
var _shadow_mesh: ArrayMesh       # 足元のブロブシャドウ（楕円）
var _glow_mesh: ArrayMesh         # 弱体の光（内側の太い輪）
var _glow_ring_mesh: ArrayMesh    # 強化の光（その外側の細い輪）
var _glow_mat: StandardMaterial3D # 強化の材質（加算合成）。明滅は _process が alpha を書き換える
var _glow_mat_debuff: StandardMaterial3D # 弱体の材質（同上・色だけ違う）
var _disc_mesh: CylinderMesh      # 画像なしユニットのプレースホルダ円盤
var _mark_mesh: ArrayMesh         # 攻撃対象マーカー（下向き三角）
var _mark_edge_mesh: ArrayMesh    # 同・その下に敷く縁取り（全周を等距離に押し出した三角）
var _mark_mat: StandardMaterial3D      # 同・本体の材質（深度切り＝常に最前面）
var _mark_mat_edge: StandardMaterial3D # 同・縁取りの材質（本体より1つ手前で描く）
var _mark_tip_drop := 0.0         # 同・縁取りの先端が本体より下へ伸びる量（隙間の補正）
var _overlay_mat := {}    # Color -> StandardMaterial3D（オーバーレイ材質キャッシュ）
var _bill_mat := {}       # Color -> StandardMaterial3D（ビルボード材質キャッシュ＝兵数バー用）
var _ring_mesh := {}      # "半径|太さ" -> ArrayMesh（円環メッシュキャッシュ）
var _fig_height := {}     # Texture2D -> float（立ち絵の実体の背丈＝マーカーを置く高さの基準）
var _avg_color := {}      # Texture2D -> Color（タイル平均色キャッシュ＝スカートの断面色）
var _skirt_tex: ImageTexture  # スカートの粒状ノイズ（べた塗り回避。_ready で1回生成）

# --- インタラクション状態 ---
var _hover := INVALID_HEX
var _selected_id := -1
var _inspected_id := -1  # 閲覧のみのユニット（敵など）。選択とは別＝移動範囲/コマンドは出さない
var _reachable := {}     # Vector2i -> true
var _inspect_reach := {} # Vector2i -> true（閲覧中の敵ユニットの移動範囲＝脅威範囲）
var _targets := {}       # Vector2i -> target_id（攻撃可能な敵の位置）
var _target_markers: Array[Node3D] = []  # 頭上マーカーのノード（_process が揺らす。_sync_overlay が作り直す）
var _deploy_base := INVALID_HEX
var _deploy_cells := {}  # Vector2i -> true（出撃先候補）
var _locked := false     # 決着・AIターン中は入力を受けない（カメラは見られる）
var _frozen := false     # 会話中フリーズ＝カメラ含む全入力を止める（set_input_locked で制御）
var _unit_nodes := {}    # unit_id -> Node3D（そのユニットの見た目一式の親。_sync_units が作り直す）
var _move_tween: Tween = null  # 進行中の移動アニメ（同時に1本＝次の _sync_units で必ず畳む）
var _cam_tween: Tween = null   # 進行中のカメラ追従パン（同時に1本＝新しい追従で差し替える）

var _pending_to := INVALID_HEX  # メニュー表示中の移動先（未確定）
var _choosing_target := false   # 「攻撃」選択後＝攻撃対象クリック待ち
var _choosing_formation := false  # 陣形スキルの着弾中心クリック待ち
var _formation_active := {}     # 発動中の陣形 option（着弾待ち）
var _formation_cells := {}      # Vector2i -> true（着弾可能な射程内hex）
var _formation_opts: Array = [] # 現メニューで提示中の陣形 option 一覧
var _impact_gen := 0            # 着弾演出の世代。ステージが変わったら増やす＝await の先で打ち切る
var _impact_pending := false    # 陣形の着弾待ち＝盤の作り直しを保留している（撃たれる前の姿のまま置く）
var _impact_lock := false       # 着弾演出の間だけ入力を止めた＝終わったら元へ戻す
var _effect_tex := {}           # effect_id -> Texture2D|null（駒に重ねるエフェクトの絵）
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
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	add_child(_cam)
	_update_camera()
	_cam.make_current()
	# 共有メッシュとコンテナ。
	_hex_mesh = _make_hex_mesh()
	_overlay_mesh = _make_hex_mesh()
	_hexring_mesh = _make_hexring_mesh()
	_shadow_mesh = _make_disc_mesh(TILE * 0.55, 0.5)  # 楕円（zを潰した円）＝立ち絵の足元影
	_glow_mesh = _make_glow_ring_mesh(SKILL_DEBUFF_INNER, SKILL_DEBUFF_OUTER, 0.5)
	_glow_ring_mesh = _make_glow_ring_mesh(SKILL_RING_INNER, SKILL_RING_OUTER, 0.5)
	_glow_mat = _make_glow_material(COLOR_SKILL_GLOW)
	_glow_mat_debuff = _make_glow_material(COLOR_SKILL_DEBUFF, false)
	var tri := _tri_points(MARK_W, MARK_H)
	var tri_edge := _outset_tri(tri, MARK_EDGE)
	_mark_mesh = _make_tri_mesh(tri)
	_mark_edge_mesh = _make_tri_mesh(tri_edge)
	# 等距離に押し出すと、鋭い先端は e より深く伸びる（先端の角度から e/sin(θ/2)）。
	# 隙間は見えている縁取りの先から測りたいので、その伸びぶんを持ち上げに足す。
	_mark_tip_drop = -tri_edge[1].y
	_mark_mat = _make_mark_material(COLOR_ATTACK_MARK, 4)
	_mark_mat_edge = _make_mark_material(COLOR_ATTACK_MARK_EDGE, 3)
	_skirt_tex = _make_skirt_texture()
	_disc_mesh = CylinderMesh.new()
	_disc_mesh.top_radius = TILE * 0.55
	_disc_mesh.bottom_radius = TILE * 0.55
	_disc_mesh.height = 0.06
	_tiles_root = Node3D.new(); add_child(_tiles_root)
	_bases_root = Node3D.new(); add_child(_bases_root)
	_units_root = Node3D.new(); add_child(_units_root)
	_overlay_root = Node3D.new(); add_child(_overlay_root)
	_fx_root = Node3D.new(); add_child(_fx_root)
	# コマンドメニュー（Window なのでカメラ変換の影響を受けない）。
	_menu = PopupMenu.new()
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu_id)
	_menu.popup_hide.connect(_on_menu_closed)

func bind(p_state: BattleState, p_controller: MatchController, p_skin_catalog: Dictionary = {}, p_terrain_skins: Dictionary = {}, p_margin_terrain: Dictionary = {}) -> void:
	state = p_state
	controller = p_controller
	_skin_catalog = p_skin_catalog
	_terrain_skins = p_terrain_skins
	_margin_terrain = p_margin_terrain
	_reset_interaction()
	controller.unit_moved.connect(_on_unit_moved)
	controller.unit_attacked.connect(_on_unit_attacked)
	controller.formation_resolved.connect(_on_formation_resolved)
	controller.unit_deployed.connect(_on_unit_deployed)
	controller.unit_unloaded.connect(_on_unit_unloaded)
	controller.unit_entered_base.connect(_on_unit_entered_base)
	controller.unit_stood.connect(_on_unit_stood)
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
	_frozen = false
	_pending_to = INVALID_HEX
	_choosing_target = false
	_clear_formation()
	_impact_gen += 1  # 進行中の着弾演出を打ち切る（await の先で盤に触らせない）
	_impact_pending = false
	_impact_lock = false
	if _fx_root != null:
		_clear_children(_fx_root)
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
	# 足元の光の明滅。位相は絶対時刻から出す＝_sync_units でノードを作り直しても途切れない。
	if _glow_mat != null:
		var t := float(Time.get_ticks_msec()) * 0.001 / SKILL_GLOW_CYCLE
		var w := 0.5 - 0.5 * cos(t * TAU)  # 0..1 のなめらかな往復
		_glow_mat.albedo_color.a = lerpf(SKILL_GLOW_MIN, SKILL_GLOW_MAX, w)
		# 位相は共通（2つ出ても揃って呼吸する）。濃さの幅だけ合成方式に合わせて分ける。
		_glow_mat_debuff.albedo_color.a = lerpf(SKILL_DEBUFF_MIN, SKILL_DEBUFF_MAX, w)
	# 攻撃対象マーカーの上下の揺れ。位相は足元の光と同じく絶対時刻から出す＝作り直しで途切れない。
	# 明滅ではなく動きにするのは、深度を切って最前面に描く記号は背景の模様に紛れるのを
	# 濃さで解けないため（薄くすると読めず、濃いままだと止まって見える）。
	if not _target_markers.is_empty():
		var dy := sin(float(Time.get_ticks_msec()) * 0.001 / MARK_BOB_CYCLE * TAU) * MARK_BOB
		var s := _mark_scale()  # ズームで見失わないよう、引いた画角では拡大する
		for m in _target_markers:
			m.position = Vector3(m.get_meta("base_pos")) + _cam_up * (dy * s)
			m.scale = Vector3(s, s, 1.0)
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
			_pan_by(event.relative)  # 空き地ドラッグ＝パン
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
	# ビルボードの「上」＝カメラの上方向。俯角固定なのでパン・ズームでは変わらない。
	# ワールドのYで持ち上げた点は遠近で画面中心から外へ倒れるが、ビルボードの立ち絵は倒れない
	# （常にカメラへ正対＝画面の縦に伸びる）。駒の頭に載せる物はこの向きで持ち上げる。
	_cam_up = Vector3(0.0, cos(pitch), -sin(pitch))

## 画面1pxがワールドで何mか（注視点の距離基準の近似）。パン・fit の換算に使う。
func _world_per_pixel() -> float:
	return 2.0 * _cam_dist * tan(deg_to_rad(CAM_FOV) * 0.5) / get_viewport().get_visible_rect().size.y

## マウス移動(px)ぶん盤が指に追随するよう注視点を動かす。
## 画面の縦は俯角で奥行きが sin(pitch) に縮むぶん割り戻す。
func _pan_by(px: Vector2) -> void:
	var wpp := _world_per_pixel()
	_cam_target.x -= px.x * wpp
	_cam_target.z -= px.y * wpp / sin(deg_to_rad(CAM_PITCH_DEG))
	_update_camera()

## screen の直下の盤上の点を固定したままズーム（＝カーソル基点）。
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

## 盤全体が HUD を避けた表示領域（上のターン板・右の InfoPanel を除く）に収まるよう距離と注視点を合わせる。
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
	var vis_h := vp.y - 96.0                          # 上のターン板の下から下端まで
	var d_h := half.x / (tanf * vis_w / vp.y)         # 横に収まる距離
	var d_v := half.y * sp / (tanf * vis_h / vp.y)    # 縦（奥行きは俯角で縮む）に収まる距離
	_cam_dist = clampf(maxf(d_h, d_v) * 1.05, MIN_DIST, MAX_DIST)
	# 盤中心が可視域の中心（画面中心より左・やや下）に来るよう注視点をずらす。
	var wpp := _world_per_pixel()
	var dx_px := vp.x * 0.5 - (16.0 + vis_w * 0.5)
	var dy_px := vp.y * 0.5 - (64.0 + vis_h * 0.5)
	_cam_target = Vector3(c.x + dx_px * wpp, 0.0, c.y + dy_px * wpp / sp)
	_update_camera()

## AIターンで「次に動く主体(hex)」をカメラに収める（controller.focus_pace が各手の前に呼ぶ）。
## 敵の全行動を見せる＝いつの間にか位置が変わる事態を防ぐ（doc/gdd/uiux.md「敵ターンのカメラ」）。
## ただし: すでに安全域(可視域の内側)に見えていれば動かさない＝近くの敵が続くとき無駄に揺らさない。
## 外／端にいるときだけ、その主体が安全域に入る最小限だけ なめらかにパンする。ズーム(距離)は変えない。
func focus_camera_on(hex: Vector2i) -> void:
	if state == null:
		return
	var w := _hex_world(hex)
	if _cam.is_position_behind(w):
		return  # 主体がカメラ背後（通常起きない）＝寄せようがない
	var sp := _cam.unproject_position(w)
	var vp := get_viewport().get_visible_rect().size
	# 安全域＝可視域（右の InfoPanel・上のターン板を除く）の、さらに内側 FOCUS_MARGIN。
	var left := 16.0 + FOCUS_MARGIN
	var right := INFOPANEL_LEFT - 16.0 - FOCUS_MARGIN
	var top := 96.0 + FOCUS_MARGIN
	var bottom := vp.y - FOCUS_MARGIN
	# はみ出し量(px)。判定の縁は [left,right]/[top,bottom]（内側なら 0＝動かさない＝デッドゾーン）。
	# 動かすときの目標は縁より FOCUS_PULL_IN 内側＝一度入れたら次はデッドゾーン内で安定（揺れない）。
	var dx := 0.0
	if sp.x < left:
		dx = sp.x - (left + FOCUS_PULL_IN)
	elif sp.x > right:
		dx = sp.x - (right - FOCUS_PULL_IN)
	var dy := 0.0
	if sp.y < top:
		dy = sp.y - (top + FOCUS_PULL_IN)
	elif sp.y > bottom:
		dy = sp.y - (bottom - FOCUS_PULL_IN)
	if is_zero_approx(dx) and is_zero_approx(dy):
		return  # 見えている＝カメラは動かさない
	# はみ出しぶんだけ注視点をずらす（画面の縦は俯角で奥行きが縮むぶん割り戻す・_pan_by と同じ換算）。
	var wpp := _world_per_pixel()
	var dest := _cam_target
	dest.x += dx * wpp
	dest.z += dy * wpp / sin(deg_to_rad(CAM_PITCH_DEG))
	await _pan_target_to(dest)

## 注視点を dest へ Tween でなめらかに移す（追従用）。完了まで待てる。
func _pan_target_to(dest: Vector3) -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()  # 前の追従が残っていれば差し替える（同時に1本）
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_cam_target, _cam_target, dest, FOCUS_PAN_SEC)
	_cam_tween = t
	await t.finished

func _set_cam_target(p: Vector3) -> void:
	_cam_target = p
	_update_camera()

# =========================================================================
# picking（マウスレイ ∩ 盤平面 y=0。物理・コリジョン不要）
# =========================================================================

## screen 直下・高さ y の水平面上の点。交差しない（水平線より上）なら Vector3.INF。
func _plane_point_at_y(screen: Vector2, y: float) -> Vector3:
	var o := _cam.project_ray_origin(screen)
	var d := _cam.project_ray_normal(screen)
	if absf(d.y) < 1e-6:
		return Vector3.INF
	var t := (y - o.y) / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t

## screen 直下の盤平面(y=0)上の点。カメラパン等が使う。
func _plane_point_at(screen: Vector2) -> Vector3:
	return _plane_point_at_y(screen, 0.0)

## screen 直下のヘックス。標高対応＝高い標高の平面から順に判定し、実際にその高さのタイルを指す
## 最初の hex を返す（上のタイルが下を隠す）。どの標高にも当たらなければ y=0 の素の hex。
func _hex_at_mouse() -> Vector2i:
	var screen := get_viewport().get_mouse_position()
	for e in _elev_levels():
		var p := _plane_point_at_y(screen, e)
		if not p.is_finite():
			continue
		var hex := Hex.from_pixel(Vector2(p.x, p.z), TILE)
		if _on_board(hex) and is_equal_approx(_elev(hex), e):
			return hex
	var p0 := _plane_point_at_y(screen, 0.0)
	if not p0.is_finite():
		return INVALID_HEX
	return Hex.from_pixel(Vector2(p0.x, p0.z), TILE)

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
				var label := "ユニットスキル" if String(o.get("kind", "")) == "skill" else "陣形"
				_menu.add_item("%s: %s" % [label, String(o["name"])], FORMATION_ID_BASE + i)
				if Formation.targetable_cells(state, o, dest).is_empty() and bool(o["needs_target"]):
					_menu.set_item_disabled(_menu.get_item_index(FORMATION_ID_BASE + i), true)
	_menu.add_separator()
	_menu.add_item("キャンセル", MENU_CANCEL)
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
	_impact_pending = not (result.get("results", []) as Array).is_empty()
	_deselect()
	if not _impact_pending:
		_sync()

## 着弾を見せる：面の光 → 被弾した駒を1体ずつ（エフェクト→フラッシュ→兵数、撃破はフェード）。
## 画面全体の揺れは main が持つ（盤だけを揺らしても画面全体にはならない）。
## 着弾が無いもの（バフ・解除）は光らせず盤を更新するだけ＝呼び出し側で分岐しなくていい。
func play_formation_impact(result: Dictionary) -> void:
	if not _impact_pending:
		return  # 着弾の無いもの（バフ・解除）＝盤は解決した時点で更新済み
	var hits: Array = result.get("results", [])
	if hits.is_empty():
		_end_impact()
		_sync()
		return
	var gen := _impact_gen
	_impact_lock = not _locked
	_locked = true  # 演出中に盤を触らせない（別の作り直しが割り込むと消えかけの駒が飛ぶ）
	await _wait(HIT_LEAD_SEC)  # 揺れと同時に光らせない＝1つの衝撃に潰れる
	if gen != _impact_gen:
		_end_impact()
		return
	var center := Vector2i(result.get("center", Vector2i.ZERO))
	# 面の光は駒の処理が終わるまで保たせる＝どの範囲の中で起きているのかが見えたまま進む。
	_flash_cells(result.get("cells", []), HIT_CELL_HOLD + HIT_DROP_SEC + HIT_STEP_SEC * float(hits.size()))
	var eff := _impact_effect(result)
	# 着弾中心に近い駒から外へ。同距離は id 順＝毎回同じ順で出る（見え方が揺れない）。
	var order: Array = hits.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := Hex.distance(Vector2i(a["hex"]), center)
		var db := Hex.distance(Vector2i(b["hex"]), center)
		return da < db if da != db else int(a["target_id"]) < int(b["target_id"]))
	for i in order.size():
		_hit_unit(order[i], eff)
		# 最後の1発は落ちて当たって消えるまで待ってから盤を作り直す（消えかけの駒を飛ばさない）。
		await _wait(HIT_STEP_SEC if i < order.size() - 1 else HIT_DROP_SEC + maxf(HIT_BURST_SEC, HIT_FADE_SEC))
		if gen != _impact_gen:
			_end_impact()
			return
	_end_impact()
	_sync()

## 着弾演出の後始末＝保留を解き、止めた入力を戻し、待っている側（main）へ知らせる。
## 決着が割り込んだ場合は _impact_lock が下りている＝解錠しない。
func _end_impact() -> void:
	_impact_pending = false
	if _impact_lock:
		_locked = false
		_impact_lock = false
	formation_impact_finished.emit()

## 着弾演出が進行中か（盤が撃たれる前の姿を保持している間）。決着の告知はこれが終わるまで待つ。
func is_impacting() -> bool:
	return _impact_pending

## 被弾した駒1体ぶん。エフェクトが上から落ちきった瞬間に駒が反応する
## （撃破ならその場でフェードアウト、生き残りは新しい兵数で組み直して光らせる）。
func _hit_unit(hit: Dictionary, eff: CombatEffect) -> void:
	var gen := _impact_gen
	_spawn_burst(Vector2i(hit["hex"]), eff, func() -> void:
		if gen == _impact_gen:
			_land_hit(hit))

func _land_hit(hit: Dictionary) -> void:
	var uid := int(hit["target_id"])
	var node: Node3D = _unit_nodes.get(uid)
	if node == null:
		return
	_unit_nodes.erase(uid)
	if bool(hit["killed"]):
		_fade_out_unit(node)
		return
	# 兵数バーは組み立て時に焼くので、減った値を出すには組み直すのが早い（state は解決済み）。
	_units_root.remove_child(node)
	node.queue_free()
	var u := state.unit_by_id(uid)
	if u != null:
		_flash_unit(_build_unit_node(u))

## 被弾フラッシュ＝立ち絵を一瞬白く飛ばして戻す。行動終了の暗さ（modulate）を基準に掛ける。
func _flash_unit(node: Node3D) -> void:
	for c in node.get_children():
		if not (c is Sprite3D):
			continue
		var spr := c as Sprite3D
		var base := spr.modulate
		var hot := Color(base.r * HIT_FLASH_GAIN, base.g * HIT_FLASH_GAIN, base.b * HIT_FLASH_GAIN, base.a)
		var tw := create_tween()
		tw.tween_property(spr, "modulate", hot, HIT_FLASH_SEC)
		tw.tween_property(spr, "modulate", base, HIT_FLASH_SEC)

## 撃破された駒を消す。立ち絵は薄くして消し、影・バー・輪は共有材質なので隠すだけにする
## （材質のアルファを触ると、同じ色を使う他の駒まで一緒に薄くなる）。
func _fade_out_unit(node: Node3D) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	for c in node.get_children():
		if c is Sprite3D:
			var spr := c as Sprite3D
			spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED  # discard のままでは薄くならない
			tw.tween_property(spr, "modulate:a", 0.0, HIT_FADE_SEC)
		elif c is Label3D:
			tw.tween_property(c, "modulate:a", 0.0, HIT_FADE_SEC)
		elif c is Node3D:
			(c as Node3D).hide()
	tw.chain().tween_callback(node.queue_free)

## 着弾した面を光らせる。駒の居ない空ヘックスも光らせる＝面の広さが伝わる。
## 盤の外へはみ出したヘックスは出さない。材質は1枚ごとに作る（アルファを個別に動かすため）。
func _flash_cells(cells: Array, hold: float) -> void:
	for c in cells:
		var hex := Vector2i(c)
		if not _in_board(hex):
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(COLOR_FORMATION_HIT, 0.0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # 地形の上に載せる（塗り潰さない）
		var mi := MeshInstance3D.new()
		mi.mesh = _overlay_mesh
		mi.material_override = m
		var p := Hex.to_pixel(hex, TILE)
		mi.position = Vector3(p.x, _elev(hex) + 0.05, p.y)
		_fx_root.add_child(mi)
		# 立ち上がりで一度強く光らせ、駒を処理している間は薄く居座らせる（面は見えたまま・
		# 駒に重ねるエフェクトは埋もれない）。最後に引く。
		var tw := create_tween()
		tw.tween_property(m, "albedo_color:a", HIT_CELL_ALPHA, HIT_CELL_RISE)
		tw.tween_property(m, "albedo_color:a", HIT_CELL_ALPHA_HOLD, HIT_CELL_SETTLE)
		tw.tween_interval(hold)
		tw.tween_property(m, "albedo_color:a", 0.0, HIT_CELL_FADE)
		tw.tween_callback(mi.queue_free)

## 駒に当てるエフェクト1発。戦闘演出シーンと同じカタログの絵を使い、盤では kind によらず
## 真上から落として当てる。盤には左右の向きが無い（右から撃つこともある）ので、絵の
## 「右へ向かう一撃」をそのまま重ねると流れる向きが嘘になる＝90度回して落とす向きに使う。
## 落ちきった時点で on_land を呼ぶ＝駒の反応（フラッシュ・兵数・撃破）はそこに揃う。
## 絵が引けないときは、そのヘックスだけを濃く光らせる＝穴が開かない。
func _spawn_burst(hex: Vector2i, eff: CombatEffect, on_land: Callable) -> void:
	var tex := _effect_texture(eff)
	if tex == null:
		_flash_cells([hex], HIT_BURST_SEC)
		on_land.call()
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.no_depth_test = true      # 駒より手前に出す（足元の地形や後列に潜り込ませない）
	spr.render_priority = 6
	# 大きさの基準は長辺（縦長の斬撃と横長の矢が釣り合う）。倍率はカタログの scale。
	var longest := float(maxi(tex.get_width(), tex.get_height()))
	spr.pixel_size = (HIT_BURST_TILES * TILE * eff.scale) / maxf(longest, 1.0)
	var at := _hex_world(hex)
	var land := Vector3(at.x, at.y + TILE * 0.9, at.z + SPRITE_FOOT_Z)
	spr.position = land + Vector3(0, HIT_DROP_FROM, 0)
	_fx_root.add_child(spr)
	var tw := create_tween()
	tw.tween_property(spr, "position", land, HIT_DROP_SEC).set_ease(Tween.EASE_IN)  # 落下＝加速
	tw.tween_callback(on_land)
	tw.set_parallel(true)  # 着弾＝開きながら消える
	tw.tween_property(spr, "scale", Vector3.ONE * HIT_BURST_OPEN, HIT_BURST_SEC)
	tw.tween_property(spr, "modulate:a", 0.0, HIT_BURST_SEC)
	tw.chain().tween_callback(spr.queue_free)

## 着弾に使うエフェクト。レシピの combat_effect を優先し、空なら発動者スキンの combat_effect へ
## 落ちる（ユニットスキルの演出と同じ規約 → doc/gdd/skills.md）。どちらも無ければ null。
func _impact_effect(result: Dictionary) -> CombatEffect:
	var id := String(result.get("combat_effect", ""))
	if id.is_empty():
		var leader := state.unit_by_id(int(result.get("leader_id", -1))) if state != null else null
		if leader != null:
			var s: UnitSkin = SkinCatalog.resolve(_skin_catalog, leader.skin_id, leader.type_id, leader.team)
			if s != null:
				id = s.combat_effect
	return CombatEffectCatalog.by_id(id)

## エフェクトの絵（キャッシュ）。カタログの絵は「右へ向かう一撃」なので、盤で使うぶんは
## 時計回りに90度回して「下へ向かう一撃」にする（→ _spawn_burst）。ビルボードは回転を
## 打ち消すので、ノードではなく画像そのものを回す。未定義・未配置は null。
func _effect_texture(eff: CombatEffect) -> Texture2D:
	if eff == null:
		return null
	if _effect_tex.has(eff.effect_id):
		return _effect_tex[eff.effect_id]
	var p := eff.image_path()
	var src := load(p) as Texture2D if p != "" and ResourceLoader.exists(p) else null
	var tex: Texture2D = null
	if src != null:
		var img := src.get_image()
		img.rotate_90(CLOCKWISE)
		tex = ImageTexture.create_from_image(img)
	_effect_tex[eff.effect_id] = tex
	return tex

## 着弾の揺れ（盤ぶん）。カメラの frustum をずらす＝注視点を動かさないので、
## 揺れ終わりに位置が残らない。2D側（UI）の揺れは main が同じ量で掛ける。
func shake(px: float = SHAKE_PX) -> void:
	if _cam == null:
		return
	var d := px * _world_per_pixel()
	var tw := create_tween()
	tw.tween_method(_set_cam_shake, Vector2.ZERO, Vector2(-d, d * 0.5), SHAKE_STEP)
	tw.tween_method(_set_cam_shake, Vector2(-d, d * 0.5), Vector2(d * 0.8, -d * 0.3), SHAKE_STEP)
	tw.tween_method(_set_cam_shake, Vector2(d * 0.8, -d * 0.3), Vector2(-d * 0.4, -d * 0.2), SHAKE_STEP)
	tw.tween_method(_set_cam_shake, Vector2(-d * 0.4, -d * 0.2), Vector2.ZERO, SHAKE_STEP)

func _set_cam_shake(v: Vector2) -> void:
	if _cam == null:
		return
	_cam.h_offset = v.x
	_cam.v_offset = v.y

func _wait(sec: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(sec).timeout

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
	if not _unit_nodes.has(unit_id):
		SfxPlayer.play_event("map_board")
	_animate_move(unit_id, path)

## 移動した駒を経路の起点へ戻し、マスを1つずつ辿らせる（見た目だけ後追い）。
## 盤の状態は既に移動先で確定しているので、アニメが途中で切れても嘘にはならない
## ＝別イベントの _sync_units がノードごと作り直し、駒は真実の位置にスナップする
## （戦闘演出と同じ「状態は即確定・見た目は後追い」の流儀）。
func _animate_move(unit_id: int, path: Array[Vector2i]) -> void:
	var node: Node3D = _unit_nodes.get(unit_id)
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
	return Vector3(p.x, _elev(hex), p.y)

## そのヘックスの見た目のスキン（ステージの差分指定を優先・無ければ地形の既定）。無ければ null。
func _skin_at(hex: Vector2i) -> TerrainSkin:
	if state == null:
		return null
	return TerrainSkinCatalog.resolve(_terrain_skins.get(hex, ""), state.terrain_at(hex))

## スキンの側面画像（置いてあれば）。無ければ null＝既定の粒ノイズ＋断面色。スキン単位でキャッシュ。
func _side_texture(skin: TerrainSkin) -> Texture2D:
	if skin == null:
		return null
	if _side_tex.has(skin.skin_id):
		return _side_tex[skin.skin_id]
	var p := skin.side_image_path()
	var tex := load(p) as Texture2D if ResourceLoader.exists(p) else null
	_side_tex[skin.skin_id] = tex
	return tex

## そのヘックスの見た目の標高（スキン別・既定0）。ピッキング/配置/スカートで使う。
## 毎フレームのピッキングから何度も引かれるので、盤を組み直すまでキャッシュする。
func _elev(hex: Vector2i) -> float:
	if _elev_cache.has(hex):
		return _elev_cache[hex]
	var skin := _skin_at(hex)
	var e: float = skin.elevation if skin != null else 0.0
	_elev_cache[hex] = e
	return e

## 立ち絵をタイル上面より沈める量（植生の厚み・既定0）。足元が下草・樹冠に隠れる量。
func _sprite_sink(hex: Vector2i) -> float:
	var skin := _skin_at(hex)
	return skin.sprite_sink if skin != null else 0.0

## 盤に存在する標高レベルを高い順で（ピッキングで上のタイルを先に判定）。0 を必ず含む。
## スキンはセルごとに違いうるので、定数表ではなく実際に敷かれた高さから集める。
func _elev_levels() -> Array:
	if not _elev_levels_cache.is_empty():
		return _elev_levels_cache
	var s := { 0.0: true }
	if state != null:
		for col in state.cols:
			for row in state.rows:
				s[_elev(Hex.offset_to_axial(col, row))] = true
	var arr := s.keys()
	arr.sort()
	arr.reverse()
	_elev_levels_cache = arr
	return arr

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
## 移動を伴う待機では直前に移動アニメが走っている＝_sync_units はそれを畳むため、
## 歩き切るのを待ってから作り直す（待たないと駒が移動先へ飛ぶ）。
func _on_unit_stood(_unit_id: int) -> void:
	await await_move_animation()
	_sync()

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
	_impact_lock = false  # 決着中は解錠しない（陣形で決着＝着弾演出の途中で飛んでくる）
	_deselect()
	_clear_deploy()
	_clear_unload()

# =========================================================================
# 3D描画（タイル＝床のヘックスメッシュ / 駒＝ビルボード / オーバーレイ＝半透明マス）
# =========================================================================

## 盤の見た目を状態から作り直す。
func _sync() -> void:
	_sync_bases()
	_sync_units()
	_sync_overlay()

## 拠点の所属（六角の縁取り）と控え数。占領で変わるためイベントごとに作り直す。
func _sync_bases() -> void:
	_clear_children(_bases_root)
	if state == null:
		return
	_refresh_base_tiles()
	for b in state.bases():
		var col := COLOR_BASE_NEUTRAL
		if b.team >= 0:
			col = TEAM_COLORS[b.team % TEAM_COLORS.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = _hexring_mesh
		mi.material_override = _overlay_material(col)
		var p := Hex.to_pixel(b.hex, TILE)
		var by := _elev(b.hex)
		mi.position = Vector3(p.x, by + 0.015, p.y)
		_bases_root.add_child(mi)
		# 控え数（出撃できる人数）を左上に小さく。
		if not b.garrison.is_empty():
			_add_count_label("+%d" % b.garrison.size(), Vector3(p.x, by, p.y), col, _bases_root)

## 地形タイル・グリッド線・下地。bind（ステージ確定）ごとに作り直す。
func _build_tiles() -> void:
	_clear_children(_tiles_root)
	_tile_nodes.clear()          # 破棄したノードを指したままにしない
	_elev_cache.clear()          # スキン解決のキャッシュはステージごとに捨てる
	_elev_levels_cache.clear()
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			_add_tile(hex)
	_add_grid()
	_add_skirt()
	_add_ground()

## hex の地形タイルのテクスチャ（skin 解決＋variant 敷き分け＋キャッシュ）。無ければ null。
## map_ground を持つスキン（地面を絵に焼き込んでいない柵など）は、下地を敷いてから重ねる。
## 下地の variant もこのヘックスで選ぶので、柵のマスだけ地面が固定される、ということにならない。
func _tile_texture(hex: Vector2i) -> Texture2D:
	var skin := _skin_at(hex)
	if skin == null:
		return null
	var over := _variant_texture(_tile_image_path(skin, hex), hex)
	var ground_id := skin.map_ground_id()
	if ground_id.is_empty():
		return over
	var ground := TerrainSkinCatalog.resolve(ground_id, "")
	if ground == null:
		return over
	return TerrainTiles.composited(_variant_texture(ground.image_path(), hex), over)

## パスの variant を読み、このヘックスぶんの1枚を返す（読み込みはパスごとに1回）。
func _variant_texture(path: String, hex: Vector2i) -> Texture2D:
	var variants: Array = _terrain_tex.get(path, [])
	if variants.is_empty() and not _terrain_tex.has(path):
		variants = _load_terrain_variants(path)
		_terrain_tex[path] = variants
	if variants.is_empty():
		return null
	return variants[_terrain_variant(hex, variants.size())]

## そのヘックスに敷く画像の基準パス。占領されている拠点は、所有チーム別の絵があればそれを使う。
## assets/terrain/{skin_id}_team{N}.png を置けば切り替わり、置かなければ中立の絵のまま（コード不変）。
## 線地形（connect＝柵・道）は、隣り合う同スキンの向きの組み合わせで絵を選ぶ。
func _tile_image_path(skin: TerrainSkin, hex: Vector2i) -> String:
	var team := _base_team_at(hex)
	if team >= 0:
		var p := "res://assets/terrain/%s_team%d.png" % [skin.skin_id, team]
		if ResourceLoader.exists(p):
			return p
	if skin.connects():
		var cp := skin.connected_image_path(_connected_dirs(skin, hex))
		if ResourceLoader.exists(cp):
			return cp
	return skin.image_path()

## hex の6近傍が同じスキンか（Hex.DIRECTIONS 順）。盤外の隣をどう埋めるかを3段で決める。
## 1) 外周(margin)が描いてあれば、そのマスの地形をそのまま読む＝作者の指定が最優先。線も面も同じ扱い
##    で、on_board も真にする＝腕を伸ばす補正は効かせない（描いてある以上、推測する必要がない）。
## 2) 外周が無い面(area＝道)は「縁のマスがそのまま続いている」として引く＝座標を盤に丸めて読む。
##    縁で帯が輪郭付きの蓋にならず、まっすぐ盤の外へ抜ける。
## 3) 外周が無い線(line＝柵)は丸めない。端が縁に来たときだけ、その先へ腕を伸ばす（extend_off_board）。
## 6近傍だけでは出せない絵（縁の2マス先の事情で変わる形）があるので、1) を用意している。
func _connected_dirs(skin: TerrainSkin, hex: Vector2i) -> Array:
	var area := skin.connects_as_area()
	var connected: Array = []
	var on_board: Array = []
	for d in Hex.DIRECTIONS:
		var n := hex + d
		var s: TerrainSkin = null
		var covered := true
		if _in_board(n):
			s = _skin_at(n)
		elif _margin_terrain.has(n):
			# 外周のセル。見た目差分(terrain_skins)は盤外の座標でも書けるので盤内と同じ引き方をする。
			s = TerrainSkinCatalog.resolve(_terrain_skins.get(n, ""), String(_margin_terrain[n]))
		elif area:
			s = _skin_at(_clamp_to_board(n))
		else:
			covered = false
		connected.append(s != null and s.skin_id == skin.skin_id)
		on_board.append(covered)
	if area:
		return connected
	return TerrainSkin.extend_off_board(connected, on_board)

## 盤の矩形（offset col/row）へ丸め込む。盤内はそのまま返る。
func _clamp_to_board(hex: Vector2i) -> Vector2i:
	if state == null:
		return hex
	var c := Hex.axial_to_offset(hex)
	return Hex.offset_to_axial(clampi(c.x, 0, state.cols - 1), clampi(c.y, 0, state.rows - 1))

## hex が盤の矩形（offset col/row）の中にあるか。
func _in_board(hex: Vector2i) -> bool:
	if state == null:
		return false
	var c := Hex.axial_to_offset(hex)
	return c.x >= 0 and c.x < state.cols and c.y >= 0 and c.y < state.rows

## そのヘックスにある拠点の所属チーム。拠点でない/中立なら -1。拠点は数個なので線形で足りる。
func _base_team_at(hex: Vector2i) -> int:
	if state == null:
		return -1
	for b in state.bases():
		if b.hex == hex:
			return b.team
	return -1

## 拠点タイルを現在の所有チームの絵に貼り替える。占領で色が変わるので _sync_bases から毎回呼ぶ。
func _refresh_base_tiles() -> void:
	for b in state.bases():
		var mi: MeshInstance3D = _tile_nodes.get(b.hex)
		if mi == null:
			continue
		var tex := _tile_texture(b.hex)
		if tex != null:
			mi.material_override = _terrain_material(tex)

## タイルの平均色（中央付近を5点サンプル・透過は除外）。スカートの断面色に使う。
func _tile_avg_color(tex: Texture2D) -> Color:
	if _avg_color.has(tex):
		return _avg_color[tex]
	var col := Color(0.35, 0.30, 0.22)  # 読めない場合のフォールバック（土色）
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var sum := Vector3.ZERO
		var cnt := 0
		for off: Vector2 in [Vector2(0.5, 0.5), Vector2(0.3, 0.35), Vector2(0.7, 0.35), Vector2(0.3, 0.65), Vector2(0.7, 0.65)]:
			var c := img.get_pixel(int(w * off.x), int(h * off.y))
			if c.a > 0.5:
				sum += Vector3(c.r, c.g, c.b)
				cnt += 1
		if cnt > 0:
			col = Color(sum.x / cnt, sum.y / cnt, sum.z / cnt)
	_avg_color[tex] = col
	return col

func _add_tile(hex: Vector2i) -> void:
	var tex := _tile_texture(hex)
	if tex == null:
		return
	var skin := _skin_at(hex)
	var mi := MeshInstance3D.new()
	mi.mesh = _hex_mesh
	mi.material_override = _terrain_material(tex)
	var p := Hex.to_pixel(hex, TILE)
	mi.position = Vector3(p.x, _elev(hex), p.y)
	if skin != null and skin.orients():
		TerrainTiles.orient(mi, hex, skin.rotates())  # 向きは座標ハッシュから決定的に選ぶ＝盤は毎回同じ
	_tile_nodes[hex] = mi  # 占領でタイルを貼り替えるため、ヘックスから引けるようにしておく
	_tiles_root.add_child(mi)

## ヘックスの輪郭線（セルの読み取り用）。全マスまとめて1メッシュ。
## スキンが grid=false のマスは引かない＝駒が入れない地形が枠で刻まれず、一つの塊として読める。
func _add_grid() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var skin := _skin_at(hex)
			if skin != null and not skin.grid:
				continue
			var p := Hex.to_pixel(hex, TILE)
			var gy := _elev(hex) + 0.01
			for i in 6:
				var a0 := deg_to_rad(60.0 * i)
				var a1 := deg_to_rad(60.0 * (i + 1))
				im.surface_add_vertex(Vector3(p.x + cos(a0) * TILE, gy, p.y + sin(a0) * TILE))
				im.surface_add_vertex(Vector3(p.x + cos(a1) * TILE, gy, p.y + sin(a1) * TILE))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COLOR_LINE
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	_tiles_root.add_child(mi)

## 盤外周の側面（スカート）。盤外に接する辺だけ下へ伸ばし、ジオラマの「島」に見せる。
## 側面画像（assets/terrain/{skin_id}_side.png）を持つスキンは、その画像を貼った別メッシュにまとめる。
## 画像ごとにマテリアルが要るので、テクスチャ単位でメッシュを分ける（アンライトなので法線は不問）。
func _add_skirt() -> void:
	# 辺 i（コーナー i→i+1・辺中点の方位 60i+30°）に対応する隣接方向（フラットトップ axial）。
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
	]
	var tools := {}  # Texture2D|null -> SurfaceTool（null＝既定の粒ノイズ＋断面色）
	for col in state.cols:
		for row in state.rows:
			var hex := Hex.offset_to_axial(col, row)
			var p := Hex.to_pixel(hex, TILE)
			var side := _side_texture(_skin_at(hex))
			var top_c: Color
			var bot_c: Color
			if side != null:
				# 側面画像はそれ自体が岩肌＝タイルの平均色で染めない。上端→下端の減光だけ掛ける。
				top_c = Color(1, 1, 1)
				bot_c = Color(0.8, 0.8, 0.8)
			else:
				# 断面色＝そのタイルの平均色（草の下は緑土・砂の下は砂色＝地続きに見える）。
				# べた塗り回避: 上端は明るめ→下端ほど暗い頂点グラデ＋粒状ノイズテクスチャを重ねる。
				var tex := _tile_texture(hex)
				var base := _tile_avg_color(tex) if tex != null else Color(0.35, 0.30, 0.22)
				top_c = base.darkened(SKIRT_DARKEN - 0.20)
				bot_c = base.darkened(SKIRT_DARKEN + 0.20)
			var st: SurfaceTool = tools.get(side)
			if st == null:
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[side] = st
			var top := _elev(hex)
			for i in 6:
				var nb := hex + dirs[i]
				var bottom: float
				if not _on_board(nb):
					bottom = -SKIRT_DEPTH         # 盤外＝ジオラマの縁（島の厚み）
				elif _elev(nb) < top - 0.001:
					bottom = _elev(nb)            # 低い隣接＝台地の崖面（段差ぶんだけ下ろす）
				else:
					continue                      # 同高 or 高い隣にはスカート不要
				var a0 := deg_to_rad(60.0 * i)
				var a1 := deg_to_rad(60.0 * (i + 1))
				var c0 := Vector3(p.x + cos(a0) * TILE, top, p.y + sin(a0) * TILE)
				var c1 := Vector3(p.x + cos(a1) * TILE, top, p.y + sin(a1) * TILE)
				var d0 := Vector3(c0.x, bottom, c0.z)
				var d1 := Vector3(c1.x, bottom, c1.z)
				# UVのuはコーナーのワールド座標から取る＝隣り合う辺と連続（継ぎ目が出ない）。
				var u0 := (c0.x * 0.31 + c0.z * 0.53) * 0.8
				var u1 := (c1.x * 0.31 + c1.z * 0.53) * 0.8
				st.set_color(top_c); st.set_uv(Vector2(u0, 0.05)); st.set_normal(Vector3.UP); st.add_vertex(c0)
				st.set_color(top_c); st.set_uv(Vector2(u1, 0.05)); st.set_normal(Vector3.UP); st.add_vertex(c1)
				st.set_color(bot_c); st.set_uv(Vector2(u0, 0.95)); st.set_normal(Vector3.UP); st.add_vertex(d0)
				st.set_color(bot_c); st.set_uv(Vector2(u1, 0.95)); st.set_normal(Vector3.UP); st.add_vertex(d1)
				st.set_color(bot_c); st.set_uv(Vector2(u0, 0.95)); st.set_normal(Vector3.UP); st.add_vertex(d0)
				st.set_color(top_c); st.set_uv(Vector2(u1, 0.05)); st.set_normal(Vector3.UP); st.add_vertex(c1)
	for side in tools:
		var mi := MeshInstance3D.new()
		mi.mesh = tools[side].commit()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true  # 断面色/減光（頂点カラー）× テクスチャの積
		m.albedo_texture = side if side != null else _skirt_tex
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 三角形の向きを気にしない（内外どちらからも見える）
		mi.material_override = m
		_tiles_root.add_child(mi)

## 盤の下地（虚空に浮かないための大きな平面）。スカートの下端より深くに置き、盤を「島」として浮かせる。
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
	m.albedo_color = Color(0.22, 0.24, 0.18)  # 盤より暗く＝盤が浮き立つ
	mi.material_override = m
	mi.position = Vector3(c.x, -SKIRT_DEPTH - 0.35, c.y)
	_tiles_root.add_child(mi)

## 全ユニットの見た目を作り直す（数十体規模なので毎イベント作り直しで十分軽い）。
## 1体＝1つの親ノード（_unit_nodes に id で登録）。立ち絵・影・兵数バー・リングはすべてその子＝
## 親を動かせば一式が付いてくる（移動アニメ）。子の位置は親からの相対で置く。
func _sync_units() -> void:
	_kill_move_tween()  # 作り直す＝アニメ中のノードは消える。先に畳んで真実の位置から始める
	_clear_children(_units_root)
	_unit_nodes.clear()
	if state == null:
		return
	for u in state.units():
		_build_unit_node(u)

## 駒1体ぶんの見た目一式（立ち絵・影・光・兵数バー）を組んで _units_root に足す。
## 1体だけ作り直せるように切り出してある（着弾で兵数だけ書き換わる駒＝play_formation_impact）。
func _build_unit_node(u: Unit) -> Node3D:
	var p := Hex.to_pixel(u.pos, TILE)
	var root := Node3D.new()
	root.position = Vector3(p.x, _elev(u.pos), p.y)
	_units_root.add_child(root)
	_unit_nodes[u.id] = root
	# 暗く落とすのは「このターンの行動を終えた駒」だけ。行ける先が無いだけの駒も、ターンでない
	# 側の陣営も落とさない（どちらの陣営のターンかはターン板で示す → doc/gdd/uiux.md）。
	var done := state.is_done(u.id)
	var tex := _unit_texture(u)
	if tex != null:
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 常にカメラへ正対＝立ち姿のまま
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD    # 半透明ソート回避（手前/奥が常に正しい）
		spr.pixel_size = (UNIT_CANVAS_TILES * TILE) / float(tex.get_height())
		spr.offset = Vector2(0, tex.get_height() * 0.5)   # 原点＝足元（接地・回転軸）
		# 足元は下辺寄り＝マスの中に立って見える。植生地形はそのぶん沈めて足元を隠す。
		spr.position = Vector3(0, 0.02 - _sprite_sink(u.pos), SPRITE_FOOT_Z)
		if done:
			spr.modulate = Color(0.55, 0.55, 0.55)  # 行動終了は暗く
		root.add_child(spr)
		# 足元のブロブシャドウ（接地感）。範囲塗りの上・リングの下の高さ。
		var sh := MeshInstance3D.new()
		sh.mesh = _shadow_mesh
		sh.material_override = _overlay_material(COLOR_SHADOW)
		sh.position = Vector3(0, 0.032, SPRITE_FOOT_Z + 0.08)  # 台座の少し手前まで出す
		root.add_child(sh)
	else:
		_add_unit_placeholder(u, done, root)
	_add_skill_glow(u, root)  # 絵の有無によらず出す（プレースホルダの駒でも掛かりは見える）
	# 包囲中（攻防に係数<1.0）を明示。
	if Surround.factor(state, u) < 1.0:
		_add_ring(Vector3.ZERO, TILE * 0.86, 0.05, COLOR_SURROUNDED, 0.05, root)
	# 兵数バー（残存兵数/満員）。駒の足元に置く。
	_add_troops_bar(u, root)
	# 輸送の搭載数を左上に小さく（拠点の garrison 表示と同じ流儀）。
	var pcount := state.passengers(u.id).size()
	if pcount > 0:
		_add_count_label("+%d" % pcount, Vector3.ZERO, COLOR_UNIT_LABEL, root)
	return root

## ユニットスキルが効いている駒の足元を光らせる。見た目を宣言した補正（fx）だけを見る＝
## 陣営全体バフ（ホーリーアリア等）では光らない。強化と弱体は別に数え、両方あれば両方出す
## （弱体＝内側の塗り／強化＝その外周の輪）。詳細 → doc/gdd/skills.md 共通ルール
func _add_skill_glow(u: Unit, root: Node3D) -> void:
	var buffed := false
	var debuffed := false
	for m in state.status_mods_for(u):
		if String(m.get("fx", "")).is_empty():
			continue
		if StatusMod.is_debuff(m):
			debuffed = true
		else:
			buffed = true
	# 影の上（影の黒に打ち消されない高さ）。2つの輪は半径が重ならないので同じ高さでよい。
	var at := Vector3(0, 0.034, SPRITE_FOOT_Z + 0.08)
	if debuffed:
		var g := MeshInstance3D.new()
		g.mesh = _glow_mesh
		g.material_override = _glow_mat_debuff  # 共有＝全員が同じ位相で明滅する
		g.position = at
		root.add_child(g)
	if buffed:
		var r := MeshInstance3D.new()
		r.mesh = _glow_ring_mesh
		r.material_override = _glow_mat
		r.position = at
		root.add_child(r)

## 画像なしユニットのプレースホルダ（チーム色の円盤＋スキン名ラベル）。
## root＝そのユニットの親ノード（位置は相対）。
func _add_unit_placeholder(u: Unit, done: bool, root: Node3D) -> void:
	var col: Color = TEAM_COLORS[u.team % TEAM_COLORS.size()]
	if done:
		col = col.darkened(0.45)
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.position = Vector3(0, 0.05, 0)
	root.add_child(mi)
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
	l.position = Vector3(0, 0.6, 0)
	root.add_child(l)

## オーバーレイ（範囲・候補・プレビュー・選択・攻撃対象・ホバー）を作り直す。
## 種類ごとに高さをずらして重なりのZファイトを避ける。
func _sync_overlay() -> void:
	_clear_children(_overlay_root)
	_target_markers.clear()  # 実体は _overlay_root の子＝いま消えた。参照を残すと _process が落ちる
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
		_add_ring(Vector3(tp.x, _elev(pos), tp.y), TILE * 0.72, 0.06, COLOR_ATTACK_RING, 0.05, _overlay_root)
		_add_target_marker(state.unit_by_id(int(_targets[pos])))
	for h in _formation_cells:  # 陣形の着弾可能hex（射程内）
		_add_cell(h, COLOR_FORMATION_RANGE, 0.02)
	if _choosing_formation and _formation_cells.has(_hover):  # ホバー先の面プレビュー
		for h in Hex.within_range(_hover, int(_formation_active.get("radius", 0))):
			_add_cell(h, COLOR_FORMATION_BLAST, 0.035)
	var sel := state.unit_by_id(_selected_id) if _selected_id != -1 else null
	if sel != null:
		var sp := Hex.to_pixel(sel.pos, TILE)
		_add_ring(Vector3(sp.x, _elev(sel.pos), sp.y), TILE * 0.70, 0.06, COLOR_SELECT_RING, 0.045, _overlay_root)
	var ins := state.unit_by_id(_inspected_id) if _inspected_id != -1 else null
	if ins != null:
		var ip := Hex.to_pixel(ins.pos, TILE)
		_add_ring(Vector3(ip.x, _elev(ins.pos), ip.y), TILE * 0.70, 0.05, COLOR_INSPECT_RING, 0.045, _overlay_root)
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
	mi.material_override = _overlay_material(color)
	var p := Hex.to_pixel(hex, TILE)
	mi.position = Vector3(p.x, _elev(hex) + y, p.y)
	_overlay_root.add_child(mi)

## 辺 i（コーナー i→i+1）に対応する隣接方向（フラットトップ axial・_add_skirt と同じ対応）。
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
		var sy := _elev(hex) + 0.05
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

# --- 兵数バー・ラベル・リングのヘルパー ---

## 兵数バー（背景＋残存率ぶんの緑）。ビルボードの小さなクアッド2枚を足元に置く。
## root＝そのユニットの親ノード（位置は相対）。
func _add_troops_bar(u: Unit, root: Node3D) -> void:
	var w := TILE * 1.0
	var h := TILE * 0.13
	var base_pos := Vector3(0, 0.10, SPRITE_FOOT_Z + 0.15)  # 立ち絵より手前＝隠れない
	var bg := MeshInstance3D.new()
	var bgq := QuadMesh.new()
	bgq.size = Vector2(w, h)
	bg.mesh = bgq
	bg.material_override = _bill_material(COLOR_TROOPS_BG)
	bg.position = base_pos
	root.add_child(bg)
	var ratio := clampf(float(u.troops) / float(u.max_troops), 0.0, 1.0)
	if ratio <= 0.0:
		return
	var fill := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(w * ratio, h * 0.8)
	fq.center_offset = Vector3(-w * (1.0 - ratio) * 0.5, 0.0, 0.0)  # 左詰め（ビルボードでも左端固定）
	fill.mesh = fq
	fill.material_override = _bill_material(COLOR_TROOPS_FILL)
	fill.position = base_pos + Vector3(0, 0, 0.01)
	root.add_child(fill)

## 「+N」の小ラベル（輸送の搭載数・拠点の控え数）。マス左上に置く。
## root＝追加先（拠点は _bases_root・ユニットは _units_root。別コンテナなのはクリア周期が違うため）。
func _add_count_label(text: String, wpos: Vector3, color: Color, root: Node3D) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 16  # 淡い地形の上でも読めるように
	# 重なり順は 縁取りリング → タイルの絵 → この数字。リングもリング状の半透明なので、
	# 深度だけに任せると数字がリングの下に潜る。深度判定を切り、最後に描かせて最前面に固定する。
	l.no_depth_test = true
	l.render_priority = 2
	l.outline_render_priority = 1
	l.position = wpos + Vector3(-TILE * 0.55, 0.8, -TILE * 0.3)
	root.add_child(l)

## 地面に寝かせた円環（選択/攻撃/閲覧/包囲リング）。radius|width でメッシュをキャッシュ。
## y は wpos からの上乗せ＝タイル上面からの浮かせ量。wpos.y を無視して絶対高さに置くと、
## 標高を持つスキン（森・台地・崖・壁）の上に立つ駒の輪がタイルの中に埋まって見えなくなる。
## 駒に付ける輪は親ノードが標高に乗っているので wpos.y=0 で呼ばれる（相対座標のまま効く）。
func _add_ring(wpos: Vector3, radius: float, width: float, color: Color, y: float, root: Node3D) -> void:
	var key := "%.3f|%.3f" % [radius, width]
	if not _ring_mesh.has(key):
		_ring_mesh[key] = _make_ring_mesh(radius, width)
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh[key]
	mi.material_override = _overlay_material(color)
	mi.position = Vector3(wpos.x, wpos.y + y, wpos.z)
	root.add_child(mi)

## 攻撃対象マーカー（頭上の下向き三角）を1体ぶん置く。縁取り→本体の順に重ねる。
## 揺れの基準位置は meta に持たせる＝_process はノードを1周するだけで済む。
func _add_target_marker(u: Unit) -> void:
	if u == null:
		return
	var n := Node3D.new()
	var base := _unit_head_pos(u) + _cam_up * (MARK_GAP + _mark_tip_drop)
	n.position = base
	n.set_meta("base_pos", base)
	var edge := MeshInstance3D.new()
	edge.mesh = _mark_edge_mesh
	edge.material_override = _mark_mat_edge
	n.add_child(edge)
	var fill := MeshInstance3D.new()
	fill.mesh = _mark_mesh
	fill.material_override = _mark_mat
	n.add_child(fill)
	_overlay_root.add_child(n)
	_target_markers.append(n)

## 頭上マーカーの倍率。画面上で MARK_MIN_PX を割り込むぶんだけ拡大する（寄っていれば等倍）。
## 盤の駒と一緒に縮んでよい記号ではない＝探すための印なので、下限は画面のpxで持つ。
func _mark_scale() -> float:
	var px := MARK_W / _world_per_pixel()
	if px >= MARK_MIN_PX:
		return 1.0
	return minf(MARK_MIN_PX / px, MARK_MAX_SCALE)

## 駒の頭のてっぺんのワールド位置。足元（立ち絵の原点）から、ビルボードが伸びる向き
## ＝カメラの上方向へ背丈ぶん進めた点。立ち絵は沈み（植生の厚み）も受けるのでそれも引く。
func _unit_head_pos(u: Unit) -> Vector3:
	var p := Hex.to_pixel(u.pos, TILE)
	# 足元は立ち絵と同じ置き方（z を手前へ SPRITE_FOOT_Z ぶん出す）。
	var foot := Vector3(p.x, _elev(u.pos) + 0.02 - _sprite_sink(u.pos), p.y + SPRITE_FOOT_Z)
	var tex := _unit_texture(u)
	if tex == null:
		return foot + _cam_up * (TILE * 0.35)  # プレースホルダの円盤＝背丈を持たないので固定
	return foot + _cam_up * _figure_height(tex)

## 立ち絵PNGの「実体」の背丈（ワールド単位）。キャンバス全高ではなく非透過部分の上端で測る。
## 大小関係はキャンバスに焼き込んだ余白で表しているので（→ doc/art/units.md 3.1）、キャンバス
## 全高を使うとハーフリングの頭上マーカーがドラゴンと同じ高さに浮く。テクスチャごとにキャッシュ。
func _figure_height(tex: Texture2D) -> float:
	if _fig_height.has(tex):
		return _fig_height[tex]
	var canvas := UNIT_CANVAS_TILES * TILE
	var h := canvas  # 読めなければキャンバス全高＝高めに浮く（駒に食い込むより害が小さい）
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img = img.duplicate()  # キャッシュ済みの Image を書き換えない
		if img.decompress() != OK:
			img = null
	if img != null:
		var used := img.get_used_rect()
		if used.size.y > 0:
			# 立ち絵は原点＝足元・上へ canvas ぶん伸びる。テクスチャの行 r はワールド
			# (tex_h - r) × pixel_size の高さに来るので、実体の上端は最上行から出る。
			h = float(tex.get_height() - used.position.y) * canvas / float(tex.get_height())
	_fig_height[tex] = h
	return h

## 床(XZ)の円環メッシュ（32分割の帯）。
func _make_ring_mesh(radius: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var r0 := radius - width * 0.5
	var r1 := radius + width * 0.5
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var o0 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
		var o1 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		var i0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var i1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		st.set_normal(Vector3.UP); st.add_vertex(o0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(i1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
	return st.commit()

## スカート用の粒状ノイズ（グレースケール・シームレス）。頂点カラーに乗算されて土の質感になる。
## 変化幅は控えめ（0.78〜1.0倍）＝べた塗り感だけ消し、色は頂点グラデに任せる。
## ユニットスキル中の足元の光の材質（加算合成・中心が濃く外へ消える）。
## 明滅は共有の1材質を _process が書き換える＝掛かっている駒が同じ位相で光る。
## 足元の光の材質。add＝地形の上に載せる（暗くしない）＝強化の輪はこちら。
## 弱体の塗りは mix にする＝加算だと明るい地形の上で白へ飽和し、紫に見えない（平地で実測）。
func _make_glow_material(color: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true  # 中心→外周のアルファ落ちは頂点カラーで作る
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## 足元の光の円盤。中心が不透明・外周が透明の頂点カラーを持つ（_make_disc_mesh は UV も
## 頂点カラーも持たないので、テクスチャを貼っても一様に透明になる＝こちらを使う）。
func _make_glow_mesh(radius: float, z_ratio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		st.set_color(Color(1, 1, 1, 1)); st.set_normal(Vector3.UP); st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1, 1, 1, 0)); st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a0) * radius, 0.0, sin(a0) * radius * z_ratio))
		st.set_color(Color(1, 1, 1, 0)); st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a1) * radius, 0.0, sin(a1) * radius * z_ratio))
	return st.commit()

## 足元の光の輪。内周と外周が透明・その中間が不透明の帯（_make_glow_mesh と同じ頂点カラー方式）。
## 塗りの外側に置くので、弱体の塗りと強化の輪が同じ足元に出ても互いを潰さない。
func _make_glow_ring_mesh(r_in: float, r_out: float, z_ratio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var r_mid := (r_in + r_out) * 0.5
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		# 内周→中間→外周の2段の帯。中間だけ不透明にして、両端へなだらかに消す。
		for band in [[r_in, 0.0, r_mid, 1.0], [r_mid, 1.0, r_out, 0.0]]:
			var ri: float = band[0]
			var ai: float = band[1]
			var ro: float = band[2]
			var ao: float = band[3]
			var p0 := Vector3(cos(a0) * ri, 0.0, sin(a0) * ri * z_ratio)
			var p1 := Vector3(cos(a1) * ri, 0.0, sin(a1) * ri * z_ratio)
			var q0 := Vector3(cos(a0) * ro, 0.0, sin(a0) * ro * z_ratio)
			var q1 := Vector3(cos(a1) * ro, 0.0, sin(a1) * ro * z_ratio)
			st.set_color(Color(1, 1, 1, ai)); st.set_normal(Vector3.UP); st.add_vertex(p0)
			st.set_color(Color(1, 1, 1, ai)); st.set_normal(Vector3.UP); st.add_vertex(p1)
			st.set_color(Color(1, 1, 1, ao)); st.set_normal(Vector3.UP); st.add_vertex(q0)
			st.set_color(Color(1, 1, 1, ao)); st.set_normal(Vector3.UP); st.add_vertex(q0)
			st.set_color(Color(1, 1, 1, ai)); st.set_normal(Vector3.UP); st.add_vertex(p1)
			st.set_color(Color(1, 1, 1, ao)); st.set_normal(Vector3.UP); st.add_vertex(q1)
	return st.commit()

func _make_skirt_texture() -> ImageTexture:
	var fn := FastNoiseLite.new()
	fn.seed = 7  # 決定的（毎回同じ見た目）
	fn.frequency = 0.05
	fn.fractal_octaves = 4
	var img := fn.get_seamless_image(256, 256)
	for y in 256:
		for x in 256:
			var v := img.get_pixel(x, y).r          # ノイズ値 0..1
			var g := 0.78 + v * 0.22                 # 控えめな明暗に圧縮
			img.set_pixel(x, y, Color(g, g, g))
	return ImageTexture.create_from_image(img)

## 床(XZ)の楕円メッシュ（ブロブシャドウ用。z_ratio でつぶす）。
func _make_disc_mesh(radius: float, z_ratio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP); st.add_vertex(Vector3(cos(a0) * radius, 0.0, sin(a0) * radius * z_ratio))
		st.set_normal(Vector3.UP); st.add_vertex(Vector3(cos(a1) * radius, 0.0, sin(a1) * radius * z_ratio))
	return st.commit()

## 拠点の縁取り＝六角の枠メッシュ（タイルの外側に張り出す帯）。
## 内側へ食い込ませるとタイルの絵を隠す（町スキンは六角いっぱいに描かれている）。
## 帯をヘックスの外へ出し、隣のタイルの上に乗せることで、絵を欠かさず所属を示す。
func _make_hexring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_out := TILE * 1.10
	var r_in := TILE * 1.00
	for i in 6:
		var a0 := deg_to_rad(60.0 * i)
		var a1 := deg_to_rad(60.0 * (i + 1))
		var o0 := Vector3(cos(a0) * r_out, 0.0, sin(a0) * r_out)
		var o1 := Vector3(cos(a1) * r_out, 0.0, sin(a1) * r_out)
		var i0 := Vector3(cos(a0) * r_in, 0.0, sin(a0) * r_in)
		var i1 := Vector3(cos(a1) * r_in, 0.0, sin(a1) * r_in)
		st.set_normal(Vector3.UP); st.add_vertex(o0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(i1)
		st.set_normal(Vector3.UP); st.add_vertex(i0)
		st.set_normal(Vector3.UP); st.add_vertex(o1)
	return st.commit()

## 下向き三角の頂点（XY平面・原点＝下の先端）。ビルボード材質と組んで頭上マーカーにする。
func _tri_points(w: float, h: float) -> Array[Vector2]:
	return [Vector2(-w * 0.5, h), Vector2(0.0, 0.0), Vector2(w * 0.5, h)]

## 三角形の3辺すべてを外へ e だけ等距離に押し出した三角形（＝縁取りの下敷き）。
## 幅と高さを増やしただけの相似形では、上辺と斜辺で張り出しが2倍ちがう（上辺0.045に対し
## 斜辺0.022＝実測）ので、輪郭ではなく上辺の帽子に見える。内接円の半径が r→r+e に増えた
## 相似形＝内心を中心に (r+e)/r 倍すれば、どの辺からも距離 e で揃う。
func _outset_tri(p: Array[Vector2], e: float) -> Array[Vector2]:
	var a := p[1].distance_to(p[2])  # 各頂点の対辺の長さ（内心の重み）
	var b := p[2].distance_to(p[0])
	var c := p[0].distance_to(p[1])
	var per := a + b + c
	var area := absf((p[1] - p[0]).cross(p[2] - p[0])) * 0.5
	if per <= 0.0 or area <= 0.0:
		return p
	var incenter := (p[0] * a + p[1] * b + p[2] * c) / per
	var r := area / (per * 0.5)  # 内接円の半径
	var k := (r + e) / r
	return [
		incenter + (p[0] - incenter) * k,
		incenter + (p[1] - incenter) * k,
		incenter + (p[2] - incenter) * k,
	]

## 頂点3つ（XY平面）を三角のメッシュにする。裏面も描く前提で巻き順は問わない。
func _make_tri_mesh(p: Array[Vector2]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in p:
		st.set_normal(Vector3.BACK); st.add_vertex(Vector3(v.x, v.y, 0.0))
	return st.commit()

## 頭上マーカーの材質。深度判定を切って常に最前面に描く＝地形にも他の駒にも隠れない
## （+N ラベルと同じ手）。重なり順は render_priority だけで決まるので、縁取り→本体の順に上げる。
func _make_mark_material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = priority
	return m

## ビルボード材質（兵数バー用・アンライト・半透明可）。色ごとにキャッシュ。
func _bill_material(color: Color) -> StandardMaterial3D:
	if _bill_mat.has(color):
		return _bill_mat[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	_bill_mat[color] = m
	return m

# --- メッシュ・材質・テクスチャのヘルパー ---

## 床(XZ)に寝かせたフラットトップ六角メッシュ（中心ファン）。UVはテクスチャの外接矩形。
func _make_hex_mesh() -> ArrayMesh:
	return TerrainTiles.hex_mesh(TILE)  # 戦闘演出の地面と共有（同じ絵・同じ発色で敷く）

## タイル材質（アンライト＝2D canvas と同じ発色）。テクスチャごとにキャッシュ。
func _terrain_material(tex: Texture2D) -> StandardMaterial3D:
	return TerrainTiles.material(tex)

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

## 地形タイルを読む。基本 {name}.png ＋連番 variant。
func _load_terrain_variants(base_path: String) -> Array:
	return TerrainTiles.variants(base_path)

## ヘックス座標から決定的に variant を選ぶ（盤の再構築でも不変）。
func _terrain_variant(hex: Vector2i, count: int) -> int:
	return TerrainTiles.variant_index(hex, count)

func _clear_children(root: Node3D) -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.free()
