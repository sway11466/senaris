extends Node3D
class_name BoardUnitRenderer
## 駒の描画（立ち絵・影・光・兵数バー・リング・マーカー）を担う。
## HexBoard3D が子ノードとして持ち、駒ノードの組み立て・周期アニメ（光の明滅・
## マーカー揺れ）・共用パーツ（リング・ラベル）を委譲する。
## 盤のゲーム状態には直接依存しない＝呼び出し側が setup で注入する。

# HexBoard3D.TILE と同値。盤全体で共有する「ヘックスの大きさ」の定数。
const TILE := 1.0
const SPRITE_FOOT_Z := TILE * 0.6  # 立ち絵の足元をヘックス中心から手前（下辺寄り）へ
## 立ち絵PNGの「キャンバス高さ」が何タイルぶんに当たるか。絵そのものではなくキャンバスを基準に
## するのは、大小関係を余白として焼き込んでいるため（小さい駒＝同じ枠で絵が小さい）。
const UNIT_CANVAS_TILES := 3.75
const COLOR_SHADOW := Color(0, 0, 0, 0.28)     # 足元のブロブシャドウ
## ユニットスキルが効いている駒の足元の光。強化と弱体を色で分ける
const COLOR_SKILL_GLOW := Color(0.85, 1.00, 0.55)  # 強化（黄緑）
const COLOR_SKILL_DEBUFF := Color(0.42, 0.12, 0.68) # 弱体（紫）
## どちらも輪にする。弱体を内側・太く、強化を外側・細く
const SKILL_DEBUFF_INNER := TILE * 0.46
const SKILL_DEBUFF_OUTER := TILE * 0.80
const SKILL_RING_INNER := TILE * 0.84
const SKILL_RING_OUTER := TILE * 1.02
const SKILL_GLOW_MIN := 0.35             # 明滅の下限アルファ
const SKILL_GLOW_MAX := 0.85             # 同・上限
const SKILL_DEBUFF_MIN := 0.55
const SKILL_DEBUFF_MAX := 0.92
const SKILL_GLOW_CYCLE := 1.6            # 明滅の周期（秒）
const COLOR_SURROUNDED := Color(0.95, 0.55, 0.15)
const COLOR_TROOPS_BG := Color(0, 0, 0, 0.6)
const COLOR_TROOPS_FILL := Color(0.30, 0.90, 0.40)
const COLOR_UNIT_LABEL := Color(1, 1, 1, 0.95)

## 攻撃対象マーカー＝対象の頭上に浮かぶ下向きの三角
const COLOR_ATTACK_MARK := Color(0.98, 0.22, 0.20)
const COLOR_ATTACK_MARK_EDGE := Color(0.06, 0.03, 0.03)
const MARK_W := TILE * 0.42        # マーカーの横幅
const MARK_H := TILE * 0.38        # 同・高さ
const MARK_EDGE := TILE * 0.035    # 縁取りの張り出し
const MARK_GAP := TILE * 0.16      # 頭のてっぺんから縁取りの先端までの隙間
const MARK_BOB := TILE * 0.06      # 上下の揺れ幅
const MARK_BOB_CYCLE := 1.1        # 同・周期（秒）
const MARK_MIN_PX := 18.0          # 引いた画角での最小の大きさ(px)
const MARK_MAX_SCALE := 2.5        # 拡大の上限

# --- 外部参照（setup で注入）---
var _board_cam: BoardCamera
var _state: BattleState
var _skin_catalog: Dictionary
var _elev_fn: Callable       # (hex: Vector2i) -> float（地形の見た目の高さ）
var _floor_fn: Callable      # (hex: Vector2i) -> float（駒の足元の高さ。立ち絵だけがここに立つ）

# --- メッシュ・材質（_ready で生成）---
var _shadow_mesh: ArrayMesh
var _glow_mesh: ArrayMesh
var _glow_ring_mesh: ArrayMesh
var _glow_mat: StandardMaterial3D
var _glow_mat_debuff: StandardMaterial3D
var _disc_mesh: CylinderMesh
var _mark_mesh: ArrayMesh
var _mark_edge_mesh: ArrayMesh
var _mark_mat: StandardMaterial3D
var _mark_mat_edge: StandardMaterial3D
var _mark_tip_drop := 0.0

# --- キャッシュ ---
var _ring_mesh := {}      # "半径|太さ" -> ArrayMesh（円環メッシュキャッシュ）
var _fig_height := {}     # Texture2D -> float（立ち絵の実体の背丈）
var _unit_tex := {}       # 画像パス(String) -> Texture2D

# --- ノード管理 ---
## unit_id -> Node3D（そのユニットの見た目一式の親）。sync_units が作り直す。
var _unit_nodes := {}
## 頭上マーカーのノード（_process が揺らす）。
var _target_markers: Array[Node3D] = []

func _ready() -> void:
	_shadow_mesh = BoardMeshFactory.make_disc_mesh(TILE * 0.55, 0.5)
	_glow_mesh = BoardMeshFactory.make_glow_ring_mesh(SKILL_DEBUFF_INNER, SKILL_DEBUFF_OUTER, 0.5)
	_glow_ring_mesh = BoardMeshFactory.make_glow_ring_mesh(SKILL_RING_INNER, SKILL_RING_OUTER, 0.5)
	_glow_mat = BoardMeshFactory.make_glow_material(COLOR_SKILL_GLOW)
	_glow_mat_debuff = BoardMeshFactory.make_glow_material(COLOR_SKILL_DEBUFF, false)
	var tri := BoardMeshFactory.tri_points(MARK_W, MARK_H)
	var tri_edge := BoardMeshFactory.outset_tri(tri, MARK_EDGE)
	_mark_mesh = BoardMeshFactory.make_tri_mesh(tri)
	_mark_edge_mesh = BoardMeshFactory.make_tri_mesh(tri_edge)
	_mark_tip_drop = -tri_edge[1].y
	_mark_mat = BoardMeshFactory.make_mark_material(COLOR_ATTACK_MARK, 4)
	_mark_mat_edge = BoardMeshFactory.make_mark_material(COLOR_ATTACK_MARK_EDGE, 3)
	_disc_mesh = CylinderMesh.new()
	_disc_mesh.top_radius = TILE * 0.55
	_disc_mesh.bottom_radius = TILE * 0.55
	_disc_mesh.height = 0.06

## 外部参照を注入する。bind（ステージ確定）のたびに呼ばれる。
func setup(board_cam: BoardCamera, p_state: BattleState, skin_catalog: Dictionary,
		elev_fn: Callable, floor_fn: Callable) -> void:
	_board_cam = board_cam
	_state = p_state
	_skin_catalog = skin_catalog
	_elev_fn = elev_fn
	_floor_fn = floor_fn

func _process(_delta: float) -> void:
	# 足元の光の明滅。位相は絶対時刻から出す＝sync_units でノードを作り直しても途切れない。
	if _glow_mat != null:
		var t := float(Time.get_ticks_msec()) * 0.001 / SKILL_GLOW_CYCLE
		var w := 0.5 - 0.5 * cos(t * TAU)  # 0..1 のなめらかな往復
		_glow_mat.albedo_color.a = lerpf(SKILL_GLOW_MIN, SKILL_GLOW_MAX, w)
		# 位相は共通（2つ出ても揃って呼吸する）。濃さの幅だけ合成方式に合わせて分ける。
		_glow_mat_debuff.albedo_color.a = lerpf(SKILL_DEBUFF_MIN, SKILL_DEBUFF_MAX, w)
	# 攻撃対象マーカーの上下の揺れ。
	if not _target_markers.is_empty() and _board_cam != null:
		var dy := sin(float(Time.get_ticks_msec()) * 0.001 / MARK_BOB_CYCLE * TAU) * MARK_BOB
		var s := _mark_scale()  # ズームで見失わないよう、引いた画角では拡大する
		for m in _target_markers:
			m.position = Vector3(m.get_meta("base_pos")) + _board_cam.cam_up * (dy * s)
			m.scale = Vector3(s, s, 1.0)

# =========================================================================
# 公開API
# =========================================================================

## 全ユニットの見た目を作り直す（数十体規模なので毎イベント作り直しで十分軽い）。
## 呼び出し前に移動アニメを止めるのは呼び出し側（HexBoard3D）の責務。
func sync_units() -> void:
	_clear_children()
	_unit_nodes.clear()
	if _state == null:
		return
	for u in _state.units():
		build_unit_node(u)

## 駒1体ぶんの見た目一式（立ち絵・影・光・兵数バー）を組んでこのノードに足す。
## 1体だけ作り直せるように切り出してある（着弾で兵数だけ書き換わる駒）。
func build_unit_node(u: Unit) -> Node3D:
	var p := Hex.to_pixel(u.pos, TILE)
	var root := Node3D.new()
	root.position = Vector3(p.x, _elev_fn.call(u.pos), p.y)
	add_child(root)
	_unit_nodes[u.id] = root
	# 暗く落とすのは「このターンの行動を終えた駒」だけ。
	var done := _state.is_done(u.id)
	var tex := _unit_texture(u)
	if tex != null:
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 常にカメラへ正対
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD    # 半透明ソート回避
		spr.pixel_size = (UNIT_CANVAS_TILES * TILE) / float(tex.get_height())
		spr.offset = Vector2(0, tex.get_height() * 0.5)   # 原点＝足元
		# 根ノードはタイル上面（elev）。立ち絵だけ floor へずらす＝影・バー・リングは上面のまま。
		spr.position = Vector3(0, 0.02 + _floor_fn.call(u.pos) - _elev_fn.call(u.pos), SPRITE_FOOT_Z)
		if done:
			spr.modulate = Color(0.55, 0.55, 0.55)  # 行動終了は暗く
		root.add_child(spr)
		# 足元のブロブシャドウ（接地感）。
		var sh := MeshInstance3D.new()
		sh.mesh = _shadow_mesh
		sh.material_override = BoardMeshFactory.overlay_material(COLOR_SHADOW)
		sh.position = Vector3(0, 0.032, SPRITE_FOOT_Z + 0.08)
		root.add_child(sh)
	else:
		_add_unit_placeholder(u, done, root)
	_add_skill_glow(u, root)  # 絵の有無によらず出す
	# 包囲中（攻防に係数<1.0）を明示。
	if Surround.factor(_state, u) < 1.0:
		add_ring(Vector3.ZERO, TILE * 0.86, 0.05, COLOR_SURROUNDED, 0.05, root)
	# 兵数バー（残存兵数/満員）。駒の足元に置く。
	_add_troops_bar(u, root)
	# 輸送の搭載数を左上に小さく。
	var pcount := _state.passengers(u.id).size()
	if pcount > 0:
		add_count_label("+%d" % pcount, Vector3.ZERO, COLOR_UNIT_LABEL, root)
	return root

## 駒ノードを返す（着弾演出・移動アニメ用）。居なければ null。
func get_unit_node(uid: int) -> Node3D:
	return _unit_nodes.get(uid)

## 駒ノードが存在するか（乗車判定に使う）。
func has_unit_node(uid: int) -> bool:
	return _unit_nodes.has(uid)

## 追跡辞書から除く（シーンからは消さない）。着弾でフェードアウトする駒に使う。
func forget_unit(uid: int) -> void:
	_unit_nodes.erase(uid)

## 追跡辞書から除き、シーンからも消す。着弾で兵数が変わった駒を作り直す前に呼ぶ。
func remove_unit(uid: int) -> void:
	var node: Node3D = _unit_nodes.get(uid)
	if node != null:
		remove_child(node)
		node.queue_free()
	_unit_nodes.erase(uid)

## 地面に寝かせた円環（選択/攻撃/閲覧/包囲リング）。radius|width でメッシュをキャッシュ。
## y は wpos からの上乗せ＝タイル上面からの浮かせ量。
func add_ring(wpos: Vector3, radius: float, width: float, color: Color, y: float, root: Node3D) -> void:
	var key := "%.3f|%.3f" % [radius, width]
	if not _ring_mesh.has(key):
		_ring_mesh[key] = BoardMeshFactory.make_ring_mesh(radius, width)
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh[key]
	mi.material_override = BoardMeshFactory.overlay_material(color)
	mi.position = Vector3(wpos.x, wpos.y + y, wpos.z)
	root.add_child(mi)

## 「+N」の小ラベル（輸送の搭載数・拠点の控え数）。既定はマス左上で、置き場を変えたい呼び側
## （立ち絵の頭上に出す拠点）は offset を渡す。
func add_count_label(text: String, wpos: Vector3, color: Color, root: Node3D,
		offset := Vector3(-TILE * 0.55, 0.8, -TILE * 0.3),
		valign := VERTICAL_ALIGNMENT_CENTER) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.pixel_size = 0.01
	l.modulate = color
	l.vertical_alignment = valign  # 頭上に出す呼び側は BOTTOM＝原点より上に字が出る
	l.outline_size = 16  # 淡い地形の上でも読めるように
	l.no_depth_test = true
	l.render_priority = 2
	l.outline_render_priority = 1
	l.position = wpos + offset
	root.add_child(l)

## 攻撃対象マーカー（頭上の下向き三角）を1体ぶん置く。parent はオーバーレイ層。
func add_target_marker(u: Unit, parent: Node3D) -> void:
	if u == null:
		return
	var n := Node3D.new()
	var base := _unit_head_pos(u) + _board_cam.cam_up * (MARK_GAP + _mark_tip_drop)
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
	parent.add_child(n)
	_target_markers.append(n)

## マーカーの追跡リストをクリアする。実体は親（_overlay_root）の子なので、
## 親を消すと実体も消える＝ここでは参照だけ。
func clear_target_markers() -> void:
	_target_markers.clear()

# =========================================================================
# 内部
# =========================================================================

## ユニットスキルが効いている駒の足元を光らせる。
func _add_skill_glow(u: Unit, root: Node3D) -> void:
	var buffed := false
	var debuffed := false
	for m in _state.status_mods_for(u):
		if String(m.get("fx", "")).is_empty():
			continue
		if StatusMod.is_debuff(m):
			debuffed = true
		else:
			buffed = true
	var at := Vector3(0, 0.034, SPRITE_FOOT_Z + 0.08)
	if debuffed:
		var g := MeshInstance3D.new()
		g.mesh = _glow_mesh
		g.material_override = _glow_mat_debuff
		g.position = at
		root.add_child(g)
	if buffed:
		var r := MeshInstance3D.new()
		r.mesh = _glow_ring_mesh
		r.material_override = _glow_mat
		r.position = at
		root.add_child(r)

## 画像なしユニットのプレースホルダ（チーム色の円盤＋スキン名ラベル）。
func _add_unit_placeholder(u: Unit, done: bool, root: Node3D) -> void:
	var col: Color = HexBoard3D.TEAM_COLORS[u.team % HexBoard3D.TEAM_COLORS.size()]
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
	var label := tr("unit." + s.skin_id + ".name").substr(0, 2) if s != null else u.type_id.substr(0, 2)
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

## 兵数バー（背景＋残存率ぶんの緑）。ビルボードの小さなクアッド2枚を足元に置く。
func _add_troops_bar(u: Unit, root: Node3D) -> void:
	var w := TILE * 1.0
	var h := TILE * 0.13
	var base_pos := Vector3(0, 0.10, SPRITE_FOOT_Z + 0.15)  # 立ち絵より手前
	var bg := MeshInstance3D.new()
	var bgq := QuadMesh.new()
	bgq.size = Vector2(w, h)
	bg.mesh = bgq
	bg.material_override = BoardMeshFactory.bill_material(COLOR_TROOPS_BG)
	bg.position = base_pos
	root.add_child(bg)
	var ratio := clampf(float(u.troops) / float(u.max_troops), 0.0, 1.0)
	if ratio <= 0.0:
		return
	var fill := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(w * ratio, h * 0.8)
	fq.center_offset = Vector3(-w * (1.0 - ratio) * 0.5, 0.0, 0.0)
	fill.mesh = fq
	fill.material_override = BoardMeshFactory.bill_material(COLOR_TROOPS_FILL)
	fill.position = base_pos + Vector3(0, 0, 0.01)
	root.add_child(fill)

## 頭上マーカーの倍率。画面上で MARK_MIN_PX を割り込むぶんだけ拡大する。
func _mark_scale() -> float:
	var px := MARK_W / _board_cam.world_per_pixel()
	if px >= MARK_MIN_PX:
		return 1.0
	return minf(MARK_MIN_PX / px, MARK_MAX_SCALE)

## 駒の頭のてっぺんのワールド位置。足元からカメラの上方向へ背丈ぶん進めた点。
func _unit_head_pos(u: Unit) -> Vector3:
	var p := Hex.to_pixel(u.pos, TILE)
	var foot := Vector3(p.x, _floor_fn.call(u.pos) + 0.02, p.y + SPRITE_FOOT_Z)
	var tex := _unit_texture(u)
	if tex == null:
		return foot + _board_cam.cam_up * (TILE * 0.35)
	return foot + _board_cam.cam_up * _figure_height(tex)

## 立ち絵PNGの「実体」の背丈（ワールド単位）。非透過部分の上端で測る。テクスチャごとにキャッシュ。
func _figure_height(tex: Texture2D) -> float:
	if _fig_height.has(tex):
		return _fig_height[tex]
	var canvas := UNIT_CANVAS_TILES * TILE
	var h := canvas  # 読めなければキャンバス全高
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img = img.duplicate()
		if img.decompress() != OK:
			img = null
	if img != null:
		var used := img.get_used_rect()
		if used.size.y > 0:
			h = float(tex.get_height() - used.position.y) * canvas / float(tex.get_height())
	_fig_height[tex] = h
	return h

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

func _clear_children() -> void:
	for c in get_children():
		remove_child(c)
